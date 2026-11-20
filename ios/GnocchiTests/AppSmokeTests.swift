import Foundation
import Supabase
import Testing
import GnocchiCore
@testable import Gnocchi

@Suite("App")
struct AppSmokeTests {
    @MainActor
    @Test("Die Schnellaktion bleibt während der Rezeptansicht ausgeblendet")
    func recipeDetailKeepsQuickActionHidden() {
        let chrome = NavigationChrome()
        let detail = UUID()
        chrome.setRecipeDetailVisible(true, id: detail)

        chrome.showActions(addCookbook: nil)
        #expect(chrome.actionsSuppressed)

        chrome.setRecipeDetailVisible(false, id: detail)
        #expect(!chrome.actionsSuppressed)
    }

    @Test("Backend zeigt auf das Projekt der Web-App")
    func backend() {
        #expect(Backend.url.host() == "xamzkxjjiwyrraavlgxw.supabase.co")
    }

    @Test("Die Einkaufsliste rechnet mit dem Rezept aus dem geladenen Wochenplan")
    func shoppingUsesEmbeddedRecipe() throws {
        let payload = Data("""
        [
          {"id":"meal","date":"2026-11-16","meal":"mittag","status":"geplant","recipe_id":"new-recipe",
           "servings_override":4,"recipe":{"title":"Kürbisrisotto","servings":2,"ep_recipe_ingredients":[
             {"id":"ingredient","name":"Kürbis","position":0,"amount":"150.5","unit":"g","aisle":"Obst und Gemüse"}
           ]}},
          {"id":"leftover","date":"2026-11-16","meal":"abend","status":"geplant","leftover_of":"meal","recipe":null}
        ]
        """.utf8)
        let rows = try JSONDecoder().decode([ShoppingPlanRow].self, from: payload)
        let recipe = try #require(rows.first?.recipe)
        let result = Shopping.calculate(plan: rows.map(\.entry), recipes: ["new-recipe": recipe],
                                        members: [], attendance: [], pantry: [], purchases: [],
                                        today: "2026-11-16", now: .now)

        #expect(rows.last?.recipe == nil)
        #expect(recipe.ingredients.first?.quantity?.amount == 150.5)
        #expect(result.open.count == 1)
        #expect(result.open.first?.recipeTitles == ["Kürbisrisotto"])
        #expect(result.open.first?.parts.first?.amount == 300)
    }

    @MainActor
    @Test("Ein Wochenupdate lädt neue Rezepte und Quellen von Resten gezielt nach")
    func weekDiscoversRecipes() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeekFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let backend = SupabaseClient(supabaseURL: URL(string: "https://week-fixture.invalid")!, supabaseKey: "fixture",
                                     options: .init(global: .init(session: session)))
        let store = HouseholdStore(client: backend)
        await store.load()
        #expect(store.recipes.map(\.id) == ["known"])

        await store.loadWeek(from: "2026-11-16")

        #expect(store.error == nil)
        #expect(store.plan.map(\.id) == ["new-slot", "leftover"])
        #expect(Set(store.recipes.map(\.id)) == ["known", "new", "previous"])
        #expect(store.recipeForMeal(recipeID: "new", leftoverOf: nil)?.ingredients.first?.name == "Kürbis")
        #expect(store.recipeForMeal(recipeID: nil, leftoverOf: "source")?.title == "Linsensuppe")
    }

    @MainActor
    @Test("Rezeptplanung ersetzt nur den bestätigten Stand und lässt eine späte Belegung bestehen")
    func recipeSchedulingChecksSlot() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeekFixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let backend = SupabaseClient(supabaseURL: URL(string: "https://week-fixture.invalid")!, supabaseKey: "fixture",
                                     options: .init(global: .init(session: session)))
        let store = HouseholdStore(client: backend)
        await store.load()
        let day = "2026-11-16"
        let slot = MealSlot(date: day, meal: .lunch)

        #expect(!(await store.scheduleRecipe("known", at: slot, expected: nil)))
        #expect(store.error == nil)
        let stale = MealPlanEntry(id: "new-slot", date: day, meal: .lunch, recipeID: "new",
                                  note: "Mit Freunden, (zu Hause)")
        #expect(!(await store.scheduleRecipe("known", at: slot, expected: stale)))
        #expect(store.error == nil)

        let entries = try await store.plannedMeals(from: day, through: day)
        let current = try #require(entries.first { $0.slot == slot })
        #expect(await store.scheduleRecipe("known", at: slot, expected: current))
        #expect(store.plan.first { $0.slot == slot }?.recipeID == "known")
    }

    @MainActor
    @Test("Anwesenheit und Gäste ändern den Bedarf mit eingeplanten Resten")
    func attendanceUpdatesMealAndShopping() async throws {
        let store = HouseholdStore.demo()
        let meal = try #require(store.plan.first { $0.recipeID == "gnocchi" })
        let cook = try #require(store.members.first { $0.id == meal.cookID })
        let recipes = Dictionary(uniqueKeysWithValues: store.recipes.map { ($0.id, $0.shoppingRecipe) })
        func gnocchiAmount() -> Double? {
            Shopping.calculate(plan: store.plan, recipes: recipes, members: store.members, attendance: store.attendance,
                               pantry: [], purchases: [], today: meal.date, now: .now)
                .open.first { $0.name == "Gnocchi" }?.parts.first?.amount
        }

        #expect(gnocchiAmount() == 900)
        await store.setAttendance(for: cook, at: meal.slot, status: .away, guests: 0)
        #expect(Planning.eaters(at: meal.slot, members: store.members, attendance: store.attendance) == 2)
        #expect(gnocchiAmount() == 750)
        await store.setAttendance(for: cook, at: meal.slot, status: .present, guests: 2)
        #expect(Planning.eaters(at: meal.slot, members: store.members, attendance: store.attendance) == 5)
        #expect(gnocchiAmount() == 1200)
    }

    @MainActor
    @Test("Reste wählen einen gekochten Ursprung und werden pro Mahlzeit verknüpft")
    func leftoversUseRecentCookedMeal() async throws {
        let store = HouseholdStore.demo()
        let today = BerlinDay.today()
        let yesterday = MealSlot(date: BerlinDay.adding(-1, to: today), meal: .dinner)
        let first = MealSlot(date: BerlinDay.adding(1, to: today), meal: .dinner)
        let second = MealSlot(date: BerlinDay.adding(3, to: today), meal: .lunch)
        #expect(await store.saveMeal(at: yesterday, changes: [
            "recipe_id": .string("gnocchi"), "status": .string(PlanStatus.cooked.rawValue)
        ]))

        let choices = try await store.recentLeftoverSources(before: first)
        let source = try #require(choices.first { $0.slot == yesterday })
        #expect(choices.contains { $0.slot == yesterday })
        #expect(choices.contains { $0.date == today && $0.status == .planned })
        #expect(choices.allSatisfy { $0.leftoverOf == nil })
        try await store.scheduleLeftover(from: source, at: first, expected: nil)
        try await store.scheduleLeftover(from: source, at: second, expected: nil)

        let leftovers = store.plan.filter { $0.leftoverOf == source.id }
        #expect(leftovers.map(\.slot) == [first, second])
        #expect(leftovers.allSatisfy { $0.recipeID == nil && !Shopping.isShoppable($0, today: today) })
        #expect(store.plan.first { $0.id == source.id }?.status == .cooked)
    }

    @MainActor
    @Test("Familiengäste bleiben beim Abwählen da und das Entfernen räumt den Termin auf")
    func familyGuestsAndClearMeal() async throws {
        let store = HouseholdStore.demo()
        let slot = MealSlot(date: BerlinDay.adding(8, to: BerlinDay.today()), meal: .snack)
        let person = try #require(store.members.first)
        #expect(await store.scheduleRecipe("gnocchi", at: slot, expected: nil))
        await store.setFamilyGuestCount(2, at: slot)
        await store.toggleAttendance(for: person, at: slot)
        let planned = try #require(store.plan.first(where: { $0.slot == slot }))
        #expect(planned.familyGuests == 2)
        #expect(store.familyGuestCount(at: slot) == 2)
        #expect(Planning.eaters(at: slot, members: store.members, attendance: store.attendance, familyGuests: planned.familyGuests) == store.members.count + 1)

        let nextWeek = MealSlot(date: BerlinDay.adding(7, to: slot.date), meal: .snack)
        let movement = try await store.prepareMealMove(from: slot, to: nextWeek, expectedID: planned.id,
                                                      recipeID: planned.recipeID, leftoverOf: nil)
        try await store.movePlannedMeal(movement)
        #expect(store.plan.first { $0.slot == nextWeek }?.recipeID == "gnocchi")
        #expect(store.familyGuestCount(at: slot) == 2)
        let shifted = try #require(store.plan.first { $0.slot == nextWeek })
        await store.setFamilyGuestCount(3, at: nextWeek)
        await store.toggleAttendance(for: person, at: nextWeek)
        let updated = try #require(store.plan.first { $0.id == shifted.id })
        try await store.clearPlannedMeal(updated)
        #expect(!store.plan.contains { $0.slot == nextWeek })
        #expect(!store.attendance.contains { $0.date == nextWeek.date && $0.meal == nextWeek.meal })
        #expect(Planning.configuredMeals(on: nextWeek.date, plan: store.plan, attendance: store.attendance).isEmpty)
    }

    @Test("Zubereitung erkennt Zutaten im Wortlaut und lässt Wortteile unangetastet")
    func preparationFindsWholeIngredientMentions() throws {
        let data = Data(#"[{"id":"1","name":"Salz","position":0},{"id":"2","name":"Ei","position":1},{"id":"3","name":"Olivenöl","position":2}]"#.utf8)
        let ingredients = try JSONDecoder().decode([Recipe.Ingredient].self, from: data)
        let text = "Eier mit der Hälfte des Salzes mischen und in Öl anbraten. Salzwasser erhitzen."
        let matches = IngredientMentions(ingredients: ingredients).matches(in: text)
        #expect(matches.map { String(text[$0.range]) } == ["Eier", "Salzes", "Öl"])
        #expect(matches.map { $0.ingredient.id } == ["2", "1", "3"])
    }

    @Test("Sommerrollen erkennen Kurzformen, zusammengesetzte Namen und beide Alternativen")
    func preparationFindsSummerRollIngredients() throws {
        let data = Data("""
        [
          {"id":"paper","name":"Reispapierblätter (22 cm Ø)","position":0},
          {"id":"noodles","name":"Reisbandnudeln (dünn)","position":1},
          {"id":"protein","name":"Garnelen (gekocht) oder Hähnchenbrust","position":2},
          {"id":"salad","name":"Eisbergsalat oder Butterlatich","position":3},
          {"id":"mint","name":"Frische Minze","position":4},
          {"id":"coriander","name":"Frischer Koriander","position":5},
          {"id":"rice","name":"Basmati-Reis","position":6}
        ]
        """.utf8)
        let ingredients = try JSONDecoder().decode([Recipe.Ingredient].self, from: data)
        let text = "Reisnudeln einweichen. Salat schneiden. Garnelen oder Hähnchen dazugeben. "
            + "Reispapierblatt in Wasser legen. Reispapier und Nudeln abtropfen. "
            + "Reis-Papier-Blatt füllen. Mit Minze und Koriander servieren. Reis separat kochen. "
            + "Ein Blatt in lauwarmes Wasser legen. Papier kurz anfeuchten. Minzblätter zupfen."
        let matches = IngredientMentions(ingredients: ingredients).matches(in: text)
        #expect(matches.map { String(text[$0.range]) } == [
            "Reisnudeln", "Salat", "Garnelen", "Hähnchen", "Reispapierblatt", "Reispapier", "Nudeln",
            "Reis-Papier-Blatt", "Minze", "Koriander", "Reis", "Blatt", "Papier", "Minzblätter"
        ])
        #expect(matches.map { $0.ingredient.id } == [
            "noodles", "salad", "protein", "protein", "paper", "paper", "noodles",
            "paper", "mint", "coriander", "rice", "paper", "paper", "mint"
        ])
        #expect(matches.filter { $0.ingredient.id == "protein" }.map(\.iconName) == ["garnelen", "hähnchenbrust"])

        let onlyPaper = IngredientMentions(ingredients: ingredients.filter { $0.id == "paper" })
        #expect(onlyPaper.matches(in: "Reis kochen. Ein Blatt Salat zupfen. Küchenpapier bereitlegen.").isEmpty)
    }

    @Test("Rezeptbereiche ergänzen alte Sortierungen und behalten geprüfte Zutatenbegriffe")
    func recipeSectionsAndReviewedMentions() throws {
        let order = RecipeSection.ordered("notes,ingredients,notes,nicht-vorhanden")
        #expect(Array(order.prefix(2)) == [.notes, .ingredients])
        #expect(order.count == RecipeSection.allCases.count)
        let payload = Data(#"[{"id":"1","name":"Tofu","position":0}]"#.utf8)
        let ingredients = try JSONDecoder().decode([Recipe.Ingredient].self, from: payload)
        let text = "Sojawürfel in der Pfanne braten."
        let mentions = IngredientMentions(ingredients: ingredients, reviewedAliases: ["tofu": ["Sojawürfel"]])
        #expect(mentions.matches(in: text).map { String(text[$0.range]) } == ["Sojawürfel"])
    }

    @MainActor
    @Test("Rezeptwahl kombiniert Zutaten und Kochhistorie")
    func recipePickerScopes() throws {
        let store = HouseholdStore.demo()
        let recipes = Array(store.recipes.reversed())
        let history = CookingSummary.from(store.cookingHistory)
        #expect(RecipePickerScope.all.results(recipes, history: history, query: "Basilikum").map(\.id) == ["gnocchi"])
        #expect(RecipePickerScope.oldest.results(recipes, history: history, query: "").map(\.id) == ["gnocchi", "lachs"])
    }

    @MainActor
    @Test("Der Mahlzeitenentwurf schützt auch Kochdienst und Portionsänderungen")
    func mealEditorChecksPlanningDetails() async throws {
        let store = HouseholdStore.demo()
        let before = try #require(store.plan.first { $0.recipeID == "gnocchi" })
        #expect(await store.saveMeal(at: before.slot, changes: [
            "servings_override": .integer(5), "cook_id": .string("toni")
        ]))
        let draft = ["note": AnyJSON.string("Mehr Basilikum")]
        #expect(!(await store.saveMeal(at: before.slot, changes: draft, condition: .unchanged(before, includingDetails: true))))
        let latest = try #require(store.plan.first { $0.slot == before.slot })
        #expect(latest.note == before.note)
        #expect(latest.servingsOverride == 5)
        #expect(latest.cookID == "toni")
        #expect(await store.saveMeal(at: before.slot, changes: draft, condition: .unchanged(latest, includingDetails: true)))
        let saved = try #require(store.plan.first { $0.slot == before.slot })
        #expect(saved.note == "Mehr Basilikum")
        #expect(saved.servingsOverride == 5)
        #expect(saved.cookID == "toni")
    }

    @MainActor
    @Test("Eine Verschiebung verlangt nach einer weiteren Terminänderung erneut eine Bestätigung")
    func moveChecksChangesNotShownInPreview() async throws {
        let store = HouseholdStore.demo()
        let before = try #require(store.plan.first { $0.recipeID == "gnocchi" })
        let target = MealSlot(date: before.date, meal: .breakfast)
        #expect(await store.saveMeal(at: target, changes: ["note": .string("Vorläufig frei")]))
        let change = PlanChange.move(before.slot, target)
        let approved = try await AssistantActions.previewChange(change, household: store)
        #expect(await store.saveMeal(at: target, changes: ["note": .string("Besuch kommt später")]))
        let updated = try await AssistantActions.previewChange(change, household: store)

        #expect(approved.lines == updated.lines)
        #expect(!approved.matches(updated))
        do {
            try await AssistantActions.applyPlanChange(approved, household: store)
            Issue.record("Die veraltete Vorschau wurde übernommen.")
        } catch AssistantFailure.planChanged {}
        #expect(store.plan.first { $0.id == before.id }?.recipeID == "gnocchi")

        try await AssistantActions.applyPlanChange(updated, household: store)
        #expect(store.plan.first { $0.slot == target }?.recipeID == "gnocchi")
        #expect(store.plan.first { $0.slot == target }?.note == "Besuch kommt später")
    }

    @MainActor
    @Test("Ein Gewinnergericht bleibt offen, wenn sich der geprüfte Termin ändert")
    func winnerScheduleDetectsChangedSlot() async throws {
        let household = HouseholdStore.demo()
        let family = try #require(household.household)
        let decide = DecideStore()
        let slot = MealSlot(date: BerlinDay.adding(2, to: BerlinDay.today()), meal: .dinner)
        await decide.create(game: .swipe, family: family, recipes: household.recipes,
                            folder: nil, slot: slot, demo: true)
        await decide.start(family: family, demo: true)
        let playing = try #require(decide.session)
        let winner = try #require(playing.state.deck?.first)
        await decide.submit(.counts([winner: 2]), for: playing.round, family: family, demo: true)

        #expect(await household.saveMeal(at: slot, changes: ["note": .string("Mit Gästen")]))
        #expect(!(await decide.schedule(slot, expected: nil, family: family, household: household)))
        #expect(decide.session?.date == nil)
        let updated = try #require(household.plan.first { $0.slot == slot })
        #expect(updated.recipeID == nil)
        #expect(updated.note == "Mit Gästen")

        #expect(await decide.schedule(slot, expected: updated, family: family, household: household))
        #expect(decide.session?.date == slot.date)
        #expect(household.plan.first { $0.slot == slot }?.recipeID == winner)
    }

    @MainActor
    @Test("Das schon eingeplante Gewinnergericht bleibt als eingekauft markiert")
    func winnerScheduleKeepsShoppingMarker() async throws {
        let household = HouseholdStore.demo()
        let family = try #require(household.household)
        let planned = try #require(household.plan.first { $0.recipeID == "gnocchi" })
        let date = "2026-11-15T08:00:00Z"
        household.setDemoShoppingMarker(mealIDs: [planned.id], timestamp: date)
        let expected = try #require(household.plan.first { $0.id == planned.id })
        let decide = DecideStore()

        await decide.create(game: .swipe, family: family, recipes: household.recipes,
                            folder: nil, slot: planned.slot, demo: true)
        await decide.start(family: family, demo: true)
        await decide.submit(.counts(["gnocchi": 2]), for: 0, family: family, demo: true)

        #expect(await decide.schedule(planned.slot, expected: expected, family: family, household: household))
        #expect(decide.session?.date == planned.date)
        #expect(household.plan.first { $0.id == planned.id }?.shoppedAt == date)
    }

    @Test("KI-Status versteht abgeschaltete KI und Verbrauch über dem Monatsbudget")
    func assistantStatusResponse() throws {
        let data = Data("""
        {"enabled":false,"reason":"Die KI ist ausgeschaltet.","provider":"off","models":null,
         "limits":{"dailyCallsPerMember":50,"monthlyBudgetEur":5},
         "usage":{"month_calls":32,"month_cache_hits":4,"month_cost_eur":5.2,"my_calls_today":2}}
        """.utf8)
        let result = try JSONDecoder().decode(AssistantStatus.self, from: data)
        #expect(result.enabled == false)
        #expect(result.models == nil)
        #expect(result.reason == "Die KI ist ausgeschaltet.")
        #expect(result.usage.monthCalls == 32)
        #expect(result.usage.monthCacheHits == 4)
        #expect(result.budgetShare == 1)
    }

    @Test("Der Bildnachweis ist gebündelt und bleibt nach dem Umbenennen eines Rezepts sichtbar")
    func photographCredit() throws {
        let photo = try #require(RecipePhotoCredit.credit(title: "  Tomaten-GNOCCHI  ", imagePath: nil))
        let path = try #require(photo.src)
        #expect(path == "/images/rezepte/tomaten-gnocchi.jpg")
        #expect(photo.author == "Lil Vienna")
        #expect(RecipePhotoCredit.credit(title: "Gnocchi mit Burrata", imagePath: path)?.sourceUrl == photo.sourceUrl)
        #expect(RecipePhotoCredit.credit(title: photo.title, imagePath: "https://example.com/privat.jpg") == nil)
    }

    @Test("Der Kochbuchkatalog beschriftet eindeutige Ausgaben und lässt unsichere ISBN offen")
    func cookbookCatalog() {
        let known = Cookbook(id: "1", title: "Jerusalem", authors: ["Eigene Angabe"], publisher: nil,
                             year: nil, isbn: nil, coverPath: nil, notes: nil)
        let shown = known.presented
        #expect(shown.id == known.id)
        #expect(shown.authors == known.authors)
        #expect(shown.isbn == "978-3-8310-2333-2")
        #expect(shown.isbnSource == "Deutsche Nationalbibliografie")
        #expect(shown.coverURL?.path == "/images/kochbuecher/jerusalem.jpg")
        #expect(known.isbn == nil)

        let ambiguous = Cookbook(id: "2", title: "Ottolenghi Test Kitchen", authors: [], publisher: nil,
                                 year: nil, isbn: nil, coverPath: nil, notes: nil).presented
        #expect(ambiguous.isbn == nil)
        #expect(ambiguous.isbnSource == nil)
        #expect(ambiguous.notes != nil)

        let ownEdition = Cookbook(id: "3", title: "Jerusalem", authors: [], publisher: nil, year: nil,
                                  isbn: "978-1-60774-394-1", coverPath: "https://example.com/cover.jpg", notes: nil).presented
        #expect(ownEdition.isbn == "978-1-60774-394-1")
        #expect(ownEdition.isbnSource == nil)
        #expect(ownEdition.coverSource == nil)
    }

    #if DEBUG
    @MainActor
    @Test("Ein unsicherer Einkaufsabschluss verwendet nach einem Neustart denselben Auftrag")
    func shoppingCompletionKeepsRequestAfterTimeout() async throws {
        let household = HouseholdStore.demo()
        let family = try #require(household.household)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "shopping.json")
        var requests: [ShoppingStore.CompletionRequest] = []
        let original = ShoppingStore(completeShopping: { request in
            requests.append(request)
            throw URLError(.timedOut)
        })
        original.restoreLocalChanges(from: file)
        await original.addExtra("Milch", family: family, demo: true)
        let extra = try #require(original.extras.first)
        let meal = try #require(household.plan.first)
        let recipes = Dictionary(uniqueKeysWithValues: household.recipes.map { ($0.id, $0.shoppingRecipe) })
        let lines = Shopping.calculate(plan: household.plan, recipes: recipes, members: household.members,
                                       attendance: household.attendance, pantry: [], purchases: [],
                                       today: BerlinDay.today(), now: .now, including: [meal.id]).open
        #expect(!lines.isEmpty)
        #expect(!(await original.finish(lines: lines, mealIDs: [meal.id], extraIDs: [extra.id], household: household)))
        #expect(original.hasPendingCompletion)
        #expect(!original.canUndoCompletion)
        #expect(original.error == nil)

        let restarted = ShoppingStore(completeShopping: { request in
            requests.append(request)
            return ShoppingStore.Receipt(timestamp: Date.now.ISO8601Format(), meal_ids: request.p_meals,
                                         purchase_ids: request.p_purchases.map(\.client_id), extras: [])
        })
        restarted.restoreLocalChanges(from: file)
        #expect(restarted.hasPendingCompletion)
        #expect(!(await restarted.finish(lines: [], mealIDs: [], extraIDs: [extra.id], household: household)))
        #expect(await restarted.retryCompletion(household: household))
        #expect(requests.count == 2)
        #expect(requests.first == requests.last)
        #expect(!restarted.hasPendingCompletion)
        #expect(restarted.canUndoCompletion)
        let confirmed = ShoppingStore()
        confirmed.restoreLocalChanges(from: file)
        #expect(!confirmed.hasPendingCompletion)
    }

    @MainActor
    @Test("Haken und Rücknahme bleiben offline sichtbar und werden in derselben Reihenfolge gesichert")
    func shoppingChecksSyncAfterReconnect() async throws {
        let household = HouseholdStore.demo()
        let family = try #require(household.household)
        var attempts: [ShoppingStore.PurchaseChange] = []
        let store = ShoppingStore(writePurchaseChange: { change, householdID in
            #expect(householdID == family.id)
            attempts.append(change)
            if attempts.count <= 2 { throw URLError(.notConnectedToInternet) }
        })
        await store.addExtra("Milch", family: family, demo: true)
        let extra = try #require(store.extras.first)
        await store.toggleExtra(extra, family: family, demo: false)
        await store.syncPurchases(family: family)
        let purchase = try #require(store.purchases.first)
        #expect(store.purchaseSyncState == .waiting)

        await store.undo([purchase.id], family: family, demo: false)
        await store.syncPurchases(family: family)
        #expect(store.purchases.isEmpty)
        #expect(store.hasPendingPurchases)

        await store.syncPurchases(family: family)
        #expect(store.purchaseSyncState == .current)
        #expect(!store.hasPendingPurchases)
        #expect(store.purchases.isEmpty)
        let history = attempts.map { change in
            switch change {
            case let .buy(rows, _): rows.map(\.client_id)
            case let .undo(ids): ids.sorted()
            }
        }
        #expect(history == [[purchase.id], [purchase.id], [purchase.id], [purchase.id]])
        guard case .undo? = attempts.last else { Issue.record("Die Rücknahme muss zuletzt gesichert werden."); return }
    }

    @MainActor
    @Test("Neustart lädt wartende Haken mit identischen IDs und nur für das aktive Familienmitglied")
    func shoppingChecksSurviveRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let householdID = UUID().uuidString
        let family = Membership(householdID: householdID, name: "Test", memberID: UUID().uuidString, active: true)
        let other = Membership(householdID: householdID, name: "Test", memberID: UUID().uuidString, active: true)
        let file = try #require(ShoppingStore.queueFile(for: family, in: directory))
        let otherFile = try #require(ShoppingStore.queueFile(for: other, in: directory))

        let original = ShoppingStore(writePurchaseChange: { _, _ in
            Issue.record("Ausstehende Haken werden durch den Synchronisierer gesendet.")
        })
        original.restoreLocalChanges(from: file)
        await original.addExtra("Milch", family: family, demo: true)
        let extra = try #require(original.extras.first)
        await original.toggleExtra(extra, family: family, demo: false)
        let id = try #require(original.purchases.first?.id)

        let restarted = ShoppingStore()
        restarted.restoreLocalChanges(from: file)
        #expect(restarted.purchaseSyncState == .waiting)
        #expect(restarted.purchases.first?.id == id)
        await restarted.undo([id], family: family, demo: false)

        let differentMember = ShoppingStore()
        differentMember.restoreLocalChanges(from: otherFile)
        #expect(!differentMember.hasPendingPurchases)

        var replayed: [String] = []
        let online = ShoppingStore(writePurchaseChange: { change, id in
            #expect(id == family.id)
            switch change {
            case let .buy(rows, _): replayed += rows.map(\.client_id)
            case let .undo(ids): replayed += ids.sorted()
            }
        })
        online.restoreLocalChanges(from: file)
        #expect(online.hasPendingPurchases)
        #expect(online.purchases.isEmpty)
        await online.syncPurchases(family: family)
        #expect(replayed == [id, id])

        let synced = ShoppingStore()
        synced.restoreLocalChanges(from: file)
        #expect(!synced.hasPendingPurchases)
    }

    @MainActor
    @Test("Fünf Fotos gehen in ihrer Reihenfolge als separate Bildteile an den KI-Stream")
    func assistantSendsFivePhotos() async {
        let photos = (1...5).map { Data([UInt8($0)]) }
        var receivedPhotos: [String] = []
        let store = AssistantStore { messages, _, _ in
            receivedPhotos = messages.last?.parts
                .filter { $0["type"]?.stringValue == "file" && $0["mediaType"]?.stringValue == "image/jpeg" }
                .compactMap { $0["url"]?.stringValue } ?? []
        }
        await store.send("", photos: photos, recipe: nil, demo: false)
        #expect(receivedPhotos == photos.map { "data:image/jpeg;base64," + $0.base64EncodedString() })
        #expect(store.messages.first?.parts.first?["text"]?.stringValue == "Was siehst du auf den Fotos?")
    }

    @MainActor
    @Test("Ein gestoppter KI-Stream behält Text und verwirft unvollständige Vorschläge")
    func stopAssistantResponse() async {
        let (receiving, ready) = AsyncStream<Void>.makeStream()
        let store = AssistantStore { _, _, receive in
            receive(["type": .string("text-delta"), "id": .string("text"), "delta": .string("Erste Antwort")])
            receive(["type": .string("tool-input-available"), "toolName": .string("einplanen"),
                     "toolCallId": .string("plan"), "input": .object([:])])
            ready.yield(())
            ready.finish()
            try await Task.sleep(for: .seconds(5))
        }
        let sending = Task { await store.send("Was kochen wir?", photo: nil, recipe: nil, demo: false) }
        for await _ in receiving { break }

        #expect(store.busy)
        #expect(store.showsComposer)
        store.stop()
        await sending.value

        #expect(!store.busy)
        #expect(store.showsComposer)
        #expect(store.error == nil)
        #expect(store.messages.last?.parts.count == 1)
        #expect(store.messages.last?.parts.first?["text"]?.stringValue == "Erste Antwort")
    }

    @MainActor
    @Test("Ein Schnellvorschlag ersetzt weder ein Gericht noch eine Notiz oder Absage")
    func quickSuggestionKeepsExistingPlans() async throws {
        let store = HouseholdStore.demo()
        let existing = try #require(store.plan.first { $0.recipeID == "gnocchi" })
        let next = BerlinDay.adding(3, to: existing.date)
        let noted = MealSlot(date: next, meal: .lunch)
        let cancelled = MealSlot(date: next, meal: .dinner)
        let free = MealSlot(date: BerlinDay.adding(1, to: next), meal: .dinner)
        #expect(await store.saveMeal(at: noted, changes: ["note": .string("Auswärts")]))
        #expect(await store.saveMeal(at: cancelled, changes: ["status": .string("ausgefallen")]))

        for slot in [existing.slot, noted, cancelled] {
            #expect(!(await store.saveMeal(at: slot, changes: ["recipe_id": .string("lachs")], condition: .unplanned)))
        }
        #expect(await store.saveMeal(at: free, changes: ["recipe_id": .string("lachs")], condition: .unplanned))
        #expect(store.plan.first { $0.slot == existing.slot }?.recipeID == "gnocchi")
        #expect(store.plan.first { $0.slot == noted }?.note == "Auswärts")
        #expect(store.plan.first { $0.slot == cancelled }?.status == .cancelled)
        #expect(store.plan.first { $0.slot == free }?.recipeID == "lachs")
    }

    @MainActor
    @Test("Direktes Ordnen ändert die Rezeptfassung und erhält Zutaten und Titel")
    func organizeRecipe() async throws {
        let store = HouseholdStore.demo()
        let original = try #require(store.recipes.first { $0.id == "gnocchi" })

        try await store.organizeRecipe(id: original.id, folderID: nil, tags: ["für-gäste"])

        let updated = try #require(store.recipes.first { $0.id == original.id })
        #expect(updated.folderID == nil)
        #expect(updated.tags == ["für-gäste"])
        #expect(updated.updatedAt != original.updatedAt)
        #expect(updated.title == original.title)
        #expect(updated.ingredients.map(\.id) == original.ingredients.map(\.id))
    }

    @MainActor
    @Test("Einkaufsabschluss und Zurückholen betreffen nur die gewählten Gerichte und Extras")
    func finishAndReturnShopping() async throws {
        let household = HouseholdStore.demo()
        let family = try #require(household.household)
        let store = ShoppingStore()
        let meal = try #require(household.plan.first { $0.recipeID == "gnocchi" })
        await store.addExtra("Milch", family: family, demo: true)
        await store.addExtra("Brot", family: family, demo: true)
        let milk = try #require(store.extras.first)
        await store.toggleExtra(milk, family: family, demo: true)
        func shopping() -> ShoppingResult {
            Shopping.calculate(plan: household.plan,
                               recipes: Dictionary(uniqueKeysWithValues: household.recipes.map { ($0.id, $0.shoppingRecipe) }),
                               members: household.members, attendance: household.attendance, pantry: [], purchases: store.purchases,
                               today: BerlinDay.today(), now: .now, including: [meal.id])
        }
        #expect(await store.finish(lines: [], mealIDs: [], extraIDs: [milk.id], household: household))
        #expect(store.extras.map(\.text) == ["Brot"])
        #expect(!shopping().open.isEmpty)
        #expect(await store.undoCompletion(household: household))
        #expect(Set(store.extras.map(\.text)) == ["Milch", "Brot"])
        #expect(await store.finish(lines: [], mealIDs: [], extraIDs: [milk.id], household: household))
        #expect(await household.saveMeal(at: meal.slot, changes: ["servings_override": .integer(3)]))
        #expect(await store.finish(lines: shopping().open, mealIDs: [meal.id], extraIDs: [], household: household))
        #expect(shopping().covered.contains(meal.id))
        let firstMarker = try #require(household.plan.first { $0.id == meal.id }?.shoppedAt)
        #expect(await household.saveMeal(at: meal.slot, changes: ["servings_override": .integer(4)]))
        let topUp = shopping().open
        #expect(topUp.map(\.text).sorted() == ["100 g Tomaten", "150 g Gnocchi"])
        #expect(await store.finish(lines: topUp, mealIDs: [meal.id], extraIDs: [], household: household))
        #expect(shopping().covered.contains(meal.id))
        #expect(household.plan.first { $0.id == meal.id }?.shoppedAt == firstMarker)
        #expect(await store.undoCompletion(household: household))
        #expect(shopping().open.map(\.text) == topUp.map(\.text))
        #expect(household.plan.first { $0.id == meal.id }?.shoppedAt == firstMarker)
        #expect(await store.returnMeal(meal, household: household))
        #expect(await store.finish(lines: shopping().open, mealIDs: [meal.id], extraIDs: [], household: household))
        #expect(await store.undoCompletion(household: household))
        #expect(!shopping().open.isEmpty)
        #expect(household.plan.first { $0.id == meal.id }?.shoppedAt == nil)
        #expect(await store.finish(lines: shopping().open, mealIDs: [meal.id], extraIDs: [], household: household))
        #expect(await store.returnMeal(meal, household: household))
        #expect(!shopping().open.isEmpty)
        #expect(household.plan.first { $0.id == meal.id }?.shoppedAt == nil)
        #expect(store.extras.map(\.text) == ["Brot"])
    }

    @MainActor
    @Test("Ein Resteessen öffnet das Rezept seiner ursprünglichen Mahlzeit")
    func recipeFromLeftoverMeal() throws {
        let store = HouseholdStore.demo()
        let leftover = try #require(store.plan.first { $0.leftoverOf != nil })
        let original = try #require(store.leftoverSource(leftover.leftoverOf))
        #expect(store.recipeForMeal(recipeID: leftover.recipeID, leftoverOf: leftover.leftoverOf)?.id == original.recipeID)
        #expect(store.recipeForMeal(recipeID: nil, leftoverOf: "unbekannt") == nil)
    }

    @MainActor
    @Test("Nährwerte lassen sich nach einem Import ändern und aus einem Rezept entfernen")
    func editImportedNutrition() async throws {
        let store = HouseholdStore.demo()
        let original = try #require(store.recipes.first { $0.id == "gnocchi" })
        var imported = RecipeMarkdown(title: original.title)
        imported.nutrition = "500 kcal | Eiweiß 42 g"
        var draft = ImportedRecipe(markdown: imported).draft(books: store.cookbooks, replacing: original)
        #expect(draft.nutritionText == "500 kcal | Eiweiß 42 g")
        draft.nutritionText = "442 kcal | Fett 23,7 g | Eiweiß 30 g"
        draft.nutritionEstimated = true
        try await store.saveRecipe(id: original.id, expectedRevision: original.updatedAt, draft: draft, replacingIngredients: false)

        let saved = try #require(store.recipes.first { $0.id == original.id })
        #expect(saved.nutrition?["kcal"] == "442")
        #expect(saved.nutrition?["Fett"] == "23,7 g")
        #expect(saved.nutrition?["Eiweiß"] == "30 g")
        #expect(saved.nutritionEstimated == true)
        var edit = RecipeDraft(recipe: saved)
        #expect(edit.recipeFields["nutrition"] == nil)
        #expect(edit.recipeFields["nutrition_estimated"] == nil)
        edit.nutritionText = " "
        try await store.saveRecipe(id: saved.id, expectedRevision: saved.updatedAt, draft: edit, replacingIngredients: false)
        let cleared = try #require(store.recipes.first { $0.id == original.id })
        #expect(cleared.nutrition == nil)
        #expect(cleared.nutritionEstimated == false)
    }

    @MainActor
    @Test("Markdown-Aktualisierung erhält Rezept-ID, Ordner und Foto und erkennt eine veraltete Fassung")
    func replaceRecipeFromMarkdown() async throws {
        let store = HouseholdStore.demo()
        let original = try #require(store.recipes.first { $0.id == "gnocchi" })
        let source = """
        ## Tomaten-Gnocchi mit Burrata

        ### Zutaten
        | Gnocchi | 500 g |
        | Tomaten | 400 g |
        ### Zubereitung
        1. Zusammen garen.
        **Nährwerte pro Portion:** 500 kcal
        """
        let imported = try #require(RecipeMarkdown.parseCollection(source).first)
        let draft = ImportedRecipe(markdown: imported).draft(books: store.cookbooks, replacing: original)
        try await store.saveRecipe(id: original.id, expectedRevision: original.updatedAt, draft: draft, replacingIngredients: true)
        let updated = try #require(store.recipes.first { $0.id == original.id })
        #expect(store.recipes.count == 2)
        #expect(updated.folderID == original.folderID)
        #expect(updated.imagePath == original.imagePath)
        #expect(updated.ingredients.first?.amount == 500)
        #expect(updated.nutrition?["kcal"] == "500")
        #expect(store.recipeNotes[updated.id]?.count == 1)
        await #expect(throws: RecipeSaveFailure.stale) {
            try await store.saveRecipe(id: original.id, expectedRevision: original.updatedAt, draft: draft, replacingIngredients: true)
        }
    }

    @MainActor
    @Test("Markdown-Import übernimmt Buch und Seite und legt ein fehlendes Kochbuch nur einmal an")
    func importCookbook() async throws {
        let store = HouseholdStore.demo()
        let source = """
        ## Polenta
        **Kochbuch:** Alpenküche, S. 12

        ---

        ## Risotto
        **Kochbuch:** Alpenküche, S. 24
        """
        let pending = try RecipeMarkdown.parseCollection(source).map { ImportedRecipe(markdown: $0).draft(books: store.cookbooks) }
        #expect(pending.count == 2)
        #expect(store.cookbooks.allSatisfy { $0.title != "Alpenküche" })
        for draft in pending {
            try await store.saveRecipe(id: UUID().uuidString, expectedRevision: nil, draft: draft, replacingIngredients: true)
        }
        let books = store.cookbooks.filter { $0.title == "Alpenküche" }
        let book = try #require(books.first)
        #expect(books.count == 1)
        let saved = store.recipes.filter { $0.cookbookID == book.id }
        #expect(saved.compactMap(\.cookbookPage).sorted() == [12, 24])
        #expect(saved.allSatisfy { $0.bookConfirmed == false })
    }

    @MainActor
    @Test("Eine veraltete Kochbuch-Verknüpfung kann eine neue Seitenzahl nicht überschreiben")
    func cookbookPageUpdateChecksCurrentLink() async throws {
        let store = HouseholdStore.demo()
        let original = try #require(store.recipes.first { $0.id == "gnocchi" })
        let book = try #require(store.cookbooks.first { $0.id == original.cookbookID })

        try await store.linkRecipe(original, to: book, page: 18)
        await #expect(throws: CookbookError.linkChanged) {
            try await store.linkRecipe(original, to: nil, page: nil)
        }
        let updated = try #require(store.recipes.first { $0.id == original.id })
        #expect(updated.cookbookPage == 18)

        try await store.linkRecipe(updated, to: nil, page: nil)
        let unlinked = try #require(store.recipes.first { $0.id == original.id })
        #expect(unlinked.cookbookID == nil)
        #expect(unlinked.cookbookPage == nil)
        #expect(unlinked.ingredients.map(\.id) == original.ingredients.map(\.id))
    }

    @MainActor
    @Test("Einladungslink übernimmt den Code ohne Familienwechsel")
    func inviteLink() async throws {
        let session = SessionStore()
        let url = try #require(URL(string: "gnocchi://beitreten?code=abcd-2345"))
        await session.open(url)
        #expect(session.inviteCode == "ABCD2345")
        #expect(session.state == .loading)
    }

    @MainActor
    @Test("Standardwoche beeinflusst Anwesenheit und behält explizite Einträge")
    func defaultWeekChangesAttendance() async throws {
        let store = HouseholdStore.demo()
        let original = try #require(store.members.first)
        let saturday = MealSlot(date: "2026-11-14", meal: .dinner)
        let settings = StandardWeek.updating(original.defaultWeek, day: "sat", meal: .dinner, present: false)
        try await store.saveStandardWeek(settings, memberID: original.id)
        let member = try #require(store.members.first { $0.id == original.id })
        #expect(Planning.effectiveStatus(for: member, at: saturday, attendance: []).status == .away)
        await store.setAttendance(for: member, at: saturday, status: .present, guests: 1)
        let actual = Planning.effectiveStatus(for: member, at: saturday, attendance: store.attendance)
        #expect(actual.status == .present)
        #expect(actual.guests == 1)
        try await store.saveStandardWeek(StandardWeek.updating(settings, day: "sat", meal: .dinner, present: true),
                                         memberID: member.id)
        #expect(store.members.first { $0.id == member.id }?.defaultWeek["sat"] == nil)
    }

    @MainActor
    @Test("Assistent plant erst nach Übernehmen")
    func assistantConfirmation() async throws {
        let household = HouseholdStore.demo()
        let assistant = AssistantStore()
        let slot = MealSlot(date: BerlinDay.today(), meal: .lunch)
        #expect(await household.saveMeal(at: slot, changes: ["recipe_id": .string("lachs")]))
        await assistant.send("Was kochen wir?", photo: nil, recipe: nil, demo: true)
        let card = try #require(assistant.messages.last?.parts.first { AssistantTool(part: $0) == .plan })
        let id = try #require(card["toolCallId"]?.stringValue)
        #expect(household.plan.first { $0.slot == slot }?.recipeID == "lachs")
        #expect(!assistant.showsComposer)
        await assistant.respond(id: id, approve: false, household: household, recipe: nil, openDraft: { _ in })
        #expect(assistant.showsComposer)
        #expect(household.plan.first { $0.slot == slot }?.recipeID == "lachs")

        await assistant.send("Plane Gnocchi ein.", photo: nil, recipe: nil, demo: true)
        let stalePart = try #require(assistant.messages.last?.parts.first { AssistantTool(part: $0) == .plan })
        let staleID = try #require(stalePart["toolCallId"]?.stringValue)
        let staleInput = try #require(stalePart["input"]?.objectValue)
        let stalePreview = try await assistant.preview(id: staleID, household: household)
        #expect(await household.saveMeal(at: slot, changes: ["note": .string("Mit Gästen")]))
        let updatedPreview = try await AssistantActions.preview(.plan, input: staleInput, household: household)
        #expect(stalePreview.lines == updatedPreview.lines)
        let reopened = try await assistant.preview(id: staleID, household: household)
        #expect(reopened.assignments[slot]?.entry?.note == nil)
        await assistant.respond(id: staleID, approve: true, household: household, recipe: nil, openDraft: { _ in })
        #expect(household.plan.first { $0.slot == slot }?.recipeID == "lachs")
        #expect(assistant.messages.last?.parts.last?["output"]?.objectValue?["ok"]?.boolValue == false)

        await assistant.send("Plane Gnocchi ein.", photo: nil, recipe: nil, demo: true)
        let proposal = try #require(assistant.messages.last?.parts.first { AssistantTool(part: $0) == .plan })
        let acceptedID = try #require(proposal["toolCallId"]?.stringValue)
        _ = try await assistant.preview(id: acceptedID, household: household)
        await assistant.respond(id: acceptedID, approve: true, household: household, recipe: nil, openDraft: { _ in })
        #expect(household.plan.first { $0.slot == slot }?.recipeID == "gnocchi")
        #expect(assistant.messages.last?.parts.last?["output"]?.objectValue?["ok"]?.boolValue == true)
    }

    @MainActor
    @Test("Die KI-Anfrage aus der Woche behält den ausgewählten Termin und einen offenen Vorschlag")
    func assistantUsesMealFromWeek() async throws {
        let household = HouseholdStore.demo()
        let assistant = AssistantStore()
        let first = MealSlot(date: BerlinDay.adding(3, to: BerlinDay.today()), meal: .dinner)
        let second = MealSlot(date: BerlinDay.adding(4, to: BerlinDay.today()), meal: .lunch)
        await assistant.askAboutMeal(first, demo: true)
        let proposed = try #require(assistant.messages.last?.parts.first { AssistantTool(part: $0) == .plan })
        let id = try #require(proposed["toolCallId"]?.stringValue)
        let preview = try await assistant.preview(id: id, household: household)
        #expect(preview.assignments[first]?.recipeID == "gnocchi")
        #expect(household.plan.first { $0.slot == first }?.recipeID == nil)

        await assistant.askAboutMeal(second, demo: true)
        #expect(assistant.pendingMealQuestion == second)
        #expect(assistant.messages.count == 2)
        await assistant.respond(id: id, approve: true, household: household, recipe: nil, openDraft: { _ in })
        #expect(household.plan.first { $0.slot == first }?.recipeID == "gnocchi")
        #expect(household.plan.first { $0.slot == second }?.recipeID == nil)

        await assistant.askAboutMeal(second, demo: true)
        #expect(assistant.pendingMealQuestion == nil)
        let next = try #require(assistant.messages.last?.parts.first { AssistantTool(part: $0) == .plan })
        let nextID = try #require(next["toolCallId"]?.stringValue)
        let nextPreview = try await assistant.preview(id: nextID, household: household)
        #expect(nextPreview.assignments[second]?.recipeID == "gnocchi")
    }

    @MainActor
    @Test("Ein KI-Wochenvorschlag speichert bei Konflikten nur nach erneuter Auswahl")
    func assistantBatchRejectsChangedSelection() async throws {
        let household = HouseholdStore.demo()
        let slots = [2, 3].map { MealSlot(date: BerlinDay.adding($0, to: BerlinDay.today()), meal: .dinner) }
        let rows: [AnyJSON] = slots.map {
            .object(["datum": .string($0.date), "mahlzeit": .string($0.meal.rawValue), "rezept_id": .string("gnocchi")])
        }
        let batch: JSONObject = ["eintraege": .array(rows)]
        let preview = try await AssistantActions.preview(.batch, input: batch, household: household)
        #expect(await household.saveMeal(at: slots[1], changes: ["recipe_id": .string("lachs")]))

        var conflict: AssistantFailure?
        do {
            _ = try await AssistantActions.apply(.batch, input: batch, household: household, confirmed: preview)
        } catch let failure as AssistantFailure {
            conflict = failure
        }
        #expect(conflict?.errorDescription?.contains("Wochenplan hat sich geändert") == true)
        #expect(household.plan.first { $0.slot == slots[0] } == nil)
        #expect(household.plan.first { $0.slot == slots[1] }?.recipeID == "lachs")

        _ = try await AssistantActions.apply(.batch, input: ["eintraege": .array([rows[0]])],
                                             household: household, confirmed: preview)
        #expect(household.plan.first { $0.slot == slots[0] }?.recipeID == "gnocchi")
        #expect(household.plan.first { $0.slot == slots[1] }?.recipeID == "lachs")
    }

    @MainActor
    @Test("Rezeptnotizen behalten beim Bearbeiten ihren Autor und werden bei Wiederholung nicht dupliziert")
    func recipeNotesRoundTrip() async throws {
        let store = HouseholdStore.demo()
        let previous = try #require(store.recipeNotes["gnocchi"]?.first)
        try await store.saveRecipeNote(id: previous.id, recipeID: "gnocchi",
                                       body: "Erst am Tisch dazugeben.", editing: previous)
        let edited = try #require(store.recipeNotes["gnocchi"]?.first)
        #expect(edited.member_id == previous.member_id)
        #expect(edited.created_at == previous.created_at)
        #expect(edited.body == "Erst am Tisch dazugeben.")
        #expect(edited.createdAt != nil)

        try await store.saveRecipeNote(id: "new", recipeID: "gnocchi", body: "  Mehr Basilikum.  ")
        try await store.saveRecipeNote(id: "new", recipeID: "gnocchi", body: "Mehr Basilikum.")
        let inserted = try #require(store.recipeNotes["gnocchi"]?.first)
        #expect(inserted.body == "Mehr Basilikum.")
        #expect(inserted.member_id == store.household?.memberID)
        #expect(store.recipeNotes["gnocchi"]?.count == 2)
        try await store.deleteRecipeNote(inserted, recipeID: "gnocchi")
        #expect(store.recipeNotes["gnocchi"]?.map(\.id) == [previous.id])
    }

    @MainActor
    @Test("Nach dem Tageswechsel zählt jedes vergangene Hauptrezept nur einmal")
    func cookingHistoryRollover() async throws {
        let store = HouseholdStore.demo()
        let today = BerlinDay.today()
        let tomorrow = BerlinDay.adding(1, to: today)
        let before = Set(store.cookingHistory.map(\.id))
        await store.refreshCookingHistory(today: today)
        #expect(Set(store.cookingHistory.map(\.id)) == before)

        await store.refreshCookingHistory(today: BerlinDay.adding(2, to: today))
        let rolled = store.cookingHistory.filter { $0.meal_plan_id != nil }
        #expect(Set(rolled.map(\.recipe_id)) == ["gnocchi", "lachs"])
        #expect(rolled.count == 2)
        #expect(rolled.allSatisfy { $0.cooked_on == today })
        #expect(store.plan.first { $0.date == tomorrow }?.leftoverOf != nil)
        #expect(store.plan.first { $0.date == tomorrow }?.status == .planned)
        await store.refreshCookingHistory(today: BerlinDay.adding(2, to: today))
        #expect(Set(store.cookingHistory.map(\.id)) == before.union(rolled.map(\.id)))
    }

    @MainActor
    @Test("Kochhistorie zeigt Herkunft und Portionen und der Kochdienst folgt den Einträgen")
    func cookingHistoryFollowsPlanAndManualRecords() async throws {
        let store = HouseholdStore.demo()
        let meal = try #require(store.plan.first { $0.recipeID == "gnocchi" })
        let cook = try #require(meal.cookID)
        #expect(store.cookCounts[cook, default: 0] == 0)

        #expect(await store.saveMeal(at: meal.slot, changes: ["status": .string("gekocht"), "servings_override": .integer(4)]))
        let planned = try #require(store.cookingHistory.first { $0.meal_plan_id == meal.id })
        #expect(planned.source == .plan)
        #expect(planned.servings == 4)
        #expect(store.cookCounts[cook] == 1)
        do {
            try await store.deleteCookingRecord(planned)
            Issue.record("Ein vom Wochenplan verwalteter Eintrag wurde gelöscht.")
        } catch HouseholdEditError.unavailable {}

        try await store.addCookingRecord(recipeID: "gnocchi", day: meal.date, servings: 2, source: .backdated)
        let added = try #require(store.cookingHistory.first { $0.recipe_id == "gnocchi" && $0.source == .backdated })
        #expect(added.servings == 2)
        #expect(store.cookCounts[cook] == 2)
        try await store.deleteCookingRecord(added)
        #expect(store.cookCounts[cook] == 1)

        #expect(await store.saveMeal(at: meal.slot, changes: ["status": .string("geplant")]))
        #expect(!store.cookingHistory.contains { $0.meal_plan_id == meal.id })
        #expect(store.cookCounts[cook, default: 0] == 0)
    }

    @MainActor
    @Test("Direktes Abhaken zählt pro Rezept und Tag nur einmal und Nachtragen speichert den Snack")
    func directCookingLogDeduplicatesAndKeepsMeal() async throws {
        let store = HouseholdStore.demo()
        let recipeID = "gnocchi"
        let today = BerlinDay.today()
        for _ in 0..<2 {
            try await store.addCookingRecord(recipeID: recipeID, day: today, servings: 2, source: .manual)
        }
        try await store.addCookingRecord(recipeID: recipeID, day: today, servings: 2, source: .backdated, meal: .snack)
        let records = store.cookingHistory.filter { $0.recipe_id == recipeID && $0.cooked_on == today }
        #expect(records.filter { $0.source == .manual }.count == 1)
        #expect(records.first { $0.source == .backdated }?.meal == .snack)
    }

    @MainActor
    @Test("Rezept löschen entfernt Notizen und Verlauf und behält den Platz im Wochenplan")
    func recipeDeletion() async throws {
        let store = HouseholdStore.demo()
        let recipe = try #require(store.recipes.first { $0.id == "gnocchi" })
        let slot = try #require(store.plan.first { $0.recipeID == recipe.id })
        try await store.addCookingRecord(recipeID: recipe.id, day: slot.date, servings: 4, source: .manual)
        #expect(store.recipeNotes[recipe.id]?.count == 1)
        #expect(store.cookingHistory.contains { $0.recipe_id == recipe.id })

        try await store.deleteRecipe(recipe)
        #expect(!store.recipes.contains { $0.id == recipe.id })
        #expect(store.recipeNotes[recipe.id] == nil)
        #expect(!store.cookingHistory.contains { $0.recipe_id == recipe.id })
        let unlinked = try #require(store.plan.first { $0.id == slot.id })
        #expect(unlinked.recipeID == nil)
        #expect(unlinked.slot == slot.slot)
        #expect(store.plan.contains { $0.leftoverOf == slot.id })
    }

    @MainActor
    @Test("Buch aus dem Regal entfernen erhält das verknüpfte Rezept und seine Zutaten")
    func cookbookRoundTrip() async throws {
        let store = HouseholdStore.demo()
        let original = try #require(store.recipes.first { $0.id == "gnocchi" })
        let book = Cookbook(id: "summer", title: "Sommerküche", authors: ["Lin"], publisher: nil,
                            year: 2026, isbn: "9780000000002", coverPath: nil, notes: nil)
        try await store.saveCookbook(book, existing: false)
        try await store.linkRecipe(original, to: book, page: 24)
        let linked = try #require(store.recipes.first { $0.id == original.id })
        #expect(linked.cookbookID == book.id)
        #expect(linked.cookbookPage == 24)
        #expect(linked.bookConfirmed == true)

        let revised = Cookbook(id: book.id, title: "La cucina", authors: book.authors,
                               publisher: nil, year: nil, isbn: nil, coverPath: nil, notes: nil)
        try await store.saveCookbook(revised, existing: true)
        #expect(store.cookbooks.first { $0.id == book.id }?.title == "La cucina")
        #expect(store.cookbooks.first { $0.id == book.id }?.isbn == nil)
        try await store.removeCookbook(revised)
        #expect(!store.cookbooks.contains { $0.id == book.id })
        let unlinked = try #require(store.recipes.first { $0.id == original.id })
        #expect(unlinked.cookbookID == nil)
        #expect(unlinked.ingredients.map(\.id) == original.ingredients.map(\.id))
    }

    @MainActor
    @Test("Rezept anlegen und bearbeiten erhält Menge und Kochbuchzuordnung")
    func recipeRoundTrip() async throws {
        let store = HouseholdStore.demo()
        var draft = RecipeDraft()
        draft.title = "Risotto mit Pilzen"
        draft.cookbookID = "kochbuch"
        var ingredient = RecipeDraft.Ingredient()
        ingredient.name = "Pilze"
        ingredient.amount = "250 g"
        draft.ingredients = [ingredient]

        try await store.saveRecipe(id: "risotto", expectedRevision: nil, draft: draft, replacingIngredients: true)
        let created = try #require(store.recipes.first { $0.id == "risotto" })
        #expect(created.title == "Risotto mit Pilzen")
        #expect(created.ingredients.first?.amount == 250)

        var next = RecipeDraft(recipe: created)
        next.title = "Pilzrisotto"
        try await store.saveRecipe(id: created.id, expectedRevision: created.updatedAt, draft: next, replacingIngredients: false)
        let edited = try #require(store.recipes.first { $0.id == "risotto" })
        #expect(edited.title == "Pilzrisotto")
        #expect(edited.ingredients.first?.amount == 250)
        #expect(edited.cookbookID == "kochbuch")
    }
    #endif
}

private final class WeekFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "week-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = parts.queryItems ?? []
        let ids = query.first { $0.name == "id" }?.value
        let household = query.first { $0.name == "household_id" }?.value
        let (status, body): (Int, String) = switch url.path {
        case "/rest/v1/rpc/ep_my_memberships":
            (200, #"[{"household_id":"family","household_name":"Testfamilie","member_id":"me","active":true}]"#)
        case "/rest/v1/ep_households":
            (200, #"{"invite_code":null}"#)
        case "/rest/v1/ep_members", "/rest/v1/ep_cookbooks", "/rest/v1/ep_recipe_folders":
            (200, "[]")
        case "/rest/v1/ep_meal_plan" where request.httpMethod == "POST":
            (request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=ignore-duplicates") == true ? 200 : 400, "[]")
        case "/rest/v1/ep_meal_plan" where request.httpMethod == "PATCH" && household == "eq.family" && ids == "eq.new-slot":
            slotUpdateResponse(query)
        case "/rest/v1/ep_meal_plan" where request.httpMethod == "GET" && household == "eq.family" && ids == nil:
            (200, """
            [{"id":"new-slot","date":"2026-11-16","meal":"mittag","status":"geplant","recipe_id":"new"},
             {"id":"leftover","date":"2026-11-16","meal":"abend","status":"geplant","leftover_of":"source"}]
            """)
        case "/rest/v1/ep_meal_plan" where household == "eq.family" && ids == "in.(source)":
            (200, #"[{"id":"source","date":"2026-11-15","meal":"abend","status":"geplant","recipe_id":"previous"}]"#)
        case "/rest/v1/ep_recipes" where household == "eq.family" && ids == nil:
            (200, #"[{"id":"known","title":"Pasta","steps":[],"public_slug":"pasta","ep_recipe_ingredients":[]}]"#)
        case "/rest/v1/ep_recipes" where household == "eq.family" && ids == "in.(new,previous)":
            (200, """
            [{"id":"new","title":"Kürbisrisotto","steps":[],"public_slug":"risotto","ep_recipe_ingredients":[
                {"id":"pumpkin","name":"Kürbis","position":0,"amount":150,"unit":"g"}]},
             {"id":"previous","title":"Linsensuppe","steps":[],"public_slug":"linsen","ep_recipe_ingredients":[]}]
            """)
        default:
            (400, #"{"code":"unexpected_request","message":"Unexpected request in week fixture"}"#)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func slotUpdateResponse(_ query: [URLQueryItem]) -> (Int, String) {
        let values = Dictionary(uniqueKeysWithValues: query.compactMap { item in item.value.map { (item.name, $0) } })
        guard values["date"] == "eq.2026-11-16", values["meal"] == "eq.mittag", values["status"] == "eq.geplant",
              values["recipe_id"] == "eq.new", values["leftover_of"]?.lowercased() == "is.null",
              values["shopped_at"]?.lowercased() == "is.null" else {
            return (400, #"{"code":"unexpected_filters","message":"Missing slot comparison"}"#)
        }
        switch values["note"] {
        case #"in.("Mit Freunden, (zu Hause)")"#:
            return (200, "[]")
        case "is.NULL", "is.null":
            return (200, #"[{"id":"new-slot","date":"2026-11-16","meal":"mittag","status":"geplant","recipe_id":"known"}]"#)
        default:
            return (400, #"{"code":"unexpected_note","message":"Missing note comparison"}"#)
        }
    }
}
