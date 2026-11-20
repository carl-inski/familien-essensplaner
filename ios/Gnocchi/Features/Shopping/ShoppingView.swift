import GnocchiCore
import SwiftUI

/// Offene Posten nacheinander im Shop suchen und in den Warenkorb legen. REWE und Knuspr
/// erlauben fremden Apps keinen Warenkorb-Zugriff; die Suche pro Posten klappt immer.
private struct DeliveryHandoff: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var inCart: Set<Int> = []
    @State private var copied = false
    @State private var openFailed = false
    let shop: Delivery.Shop
    let lines: [String]

    var body: some View {
        List {
            if shop == .knuspr {
                Section {
                    Button("Alles per Claude", systemImage: "sparkles") { openAssistant(.claude) }
                    Button("Alles per ChatGPT", systemImage: "sparkles") { openAssistant(.chatGPT) }
                    Button(copied ? "Auftrag kopiert" : "Auftrag kopieren", systemImage: copied ? "checkmark" : "document.on.document") {
                        UIPasteboard.general.string = Knuspr.prompt(lines: lines)
                        copied = true
                    }
                } header: {
                    Text("Schneller mit KI")
                } footer: {
                    Text("Mit dem Knuspr-Konnektor in Claude oder ChatGPT legt die KI alle Posten in deinen Warenkorb. Einmalig dort „Knuspr“ verbinden.")
                }
            }
            Section {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    row(index: index, line: line)
                }
            } header: {
                Text("\(inCart.count) von \(lines.count) im Warenkorb")
            } footer: {
                Text("Tippe einen Posten an: Die \(shop.name)-Suche öffnet sich, du legst das passende Produkt in den Warenkorb. Bestellt und bezahlt wird bei \(shop.name).")
            }
            Section {
                Button("Zum \(shop.name)-Warenkorb", systemImage: "cart") { open(shop.home) }
            }
        }
        .navigationTitle(shop.name)
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
        }
        .alert("\(shop.name) konnte nicht geöffnet werden.", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func row(index: Int, line: String) -> some View {
        let done = inCart.contains(index)
        let term = Delivery.searchTerm(line)
        return HStack(spacing: 12) {
            Button {
                toggle(index)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Theme.accent : Theme.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "\(line): aus dem Warenkorb nehmen" : "\(line): als im Warenkorb markieren")
            Button {
                inCart.insert(index)
                if let url = Delivery.searchURL(shop, name: line) { open(url) } else { openFailed = true }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line)
                            .strikethrough(done)
                            .foregroundStyle(done ? Theme.inkSecondary : .primary)
                        if term != line {
                            Text("Suche: \(term)").font(.caption).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(Theme.inkSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet die \(shop.name)-Suche")
        }
    }

    private func toggle(_ index: Int) {
        if inCart.contains(index) { inCart.remove(index) } else { inCart.insert(index) }
    }

    private func openAssistant(_ assistant: Knuspr.Assistant) {
        guard let url = Knuspr.link(for: assistant, prompt: Knuspr.prompt(lines: lines)) else {
            openFailed = true
            return
        }
        open(url)
    }

    private func open(_ url: URL) {
        openURL(url) { accepted in
            if !accepted { openFailed = true }
        }
    }
}

private struct DeliveryServicesSheet: View {
    @Environment(HouseholdStore.self) private var household
    @Environment(ShoppingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let lines: [ShoppingLine]
    let extras: [ShoppingExtra]
    let exportLines: [String]
    let today: String

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                NavigationLink {
                    DeliveryHandoff(shop: .knuspr, lines: exportLines)
                } label: {
                    serviceLabel("knuspr.de", detail: "Posten suchen und in den Warenkorb legen", logo: "DeliveryKnuspr", background: 0xFFECD5, ink: 0x542B0D)
                }
                NavigationLink {
                    DeliveryHandoff(shop: .rewe, lines: exportLines)
                } label: {
                    serviceLabel("REWE", detail: "Posten suchen und in den Warenkorb legen", logo: "DeliveryRewe", background: 0xFDE9EB, ink: 0x731323)
                }
                Button {
                    shareWithBring()
                } label: {
                    serviceLabel("Bring!", detail: "Offene Artikel in deine Liste übernehmen", logo: "DeliveryBring", background: 0x075C53, ink: 0xFFFFFF)
                }
                .disabled(store.saving || household.isDemo || household.household == nil)
                if household.isDemo {
                    Text("Bring! ist mit deinem Familienkonto verfügbar.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)
        }
        .navigationTitle("Lieferdienste")
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
            }
        }
        .alert("Bring!", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }

    private func serviceLabel(_ title: String, detail: String, logo: String,
                              background: UInt32, ink: UInt32) -> some View {
        HStack(spacing: 14) {
            Image(logo)
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 42)
                .padding(6)
                .background(logo == "DeliveryBring" ? Color.clear : .white, in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)
            Text(detail)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color(light: ink, dark: ink))
        .padding(14)
        .background(Color(light: background, dark: background), in: .rect(cornerRadius: Theme.radiusControl))
        .contentShape(.rect(cornerRadius: Theme.radiusControl))
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func shareWithBring() {
        guard let family = household.household, !household.isDemo else { return }
        Task {
            if let url = await store.bringURL(for: lines, extras: extras, family: family, today: today) {
                openURL(url)
            }
        }
    }
}

struct ShoppingView: View {
    @Environment(HouseholdStore.self) private var household
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var preferences
    @Environment(ShoppingStore.self) private var store
    let accountEmail: String
    @State private var adding = false
    @State private var lastDay: String?
    @State private var excludedMeals: Set<String> = []
    @State private var confirmationCount = 0
    @State private var celebration: Celebration?
    @State private var finishOpen = false
    @State private var copyFeedback = 0
    @State private var didCopyList = false
    @State private var showingDeliveryServices = false
    @State private var openedRecipeID: String?
    @State private var pendingChecks: [String: PendingCheck] = [:]
    @State private var returnCandidate: MealPlanEntry?
    @State private var lastCompletion: Double = 0
    @State private var previousCompletion: Double = 0

    private struct PendingCheck {
        let line: ShoppingLine?
        let position: Int
        let removal: Task<Void, Never>
    }

    private struct ShoppingScope: Equatable {
        let day: String
        let memberIDs: [String]
    }

    private var today: String { BerlinDay.today() }
    private var plan: [MealPlanEntry] { household.isDemo ? household.plan : store.plan }
    private var recipes: [String: ShoppingRecipe] {
        household.isDemo ? Dictionary(uniqueKeysWithValues: household.recipes.map { ($0.id, $0.shoppingRecipe) }) : store.recipes
    }

    private func result(including ids: Set<String>? = nil, now: Date) -> ShoppingResult {
        Shopping.calculate(plan: plan, recipes: recipes, members: household.members,
                           attendance: attendance, pantry: store.pantry, purchases: store.purchases,
                           today: today, now: now, including: ids)
    }

    private var attendance: [Attendance] { household.isDemo ? household.attendance : store.attendance }

    private var dishes: [(entry: MealPlanEntry, recipe: ShoppingRecipe)] {
        let recipes = recipes
        return plan.filter { Shopping.isShoppable($0, today: today) }
            .sorted { ($0.date, $0.meal.displayOrder) < ($1.date, $1.meal.displayOrder) }
            .compactMap { entry in
                guard let id = entry.recipeID, let recipe = recipes[id] else { return nil }
                return (entry, recipe)
            }
    }

    var body: some View {
        let now = Date.now
        let overall = result(now: now)
        let dishes = dishes
        let openDishes = dishes.filter { !overall.covered.contains($0.entry.id) }
        let coveredDishes = dishes.filter { overall.covered.contains($0.entry.id) }
        let included = Set(openDishes.map(\.entry).filter { includes($0) }.map(\.id))

        let result = included.count == openDishes.count ? overall : result(including: included, now: now)
        let boughtKeys = Set(store.purchases.map(\.key))
        let openExtras = store.extras.filter { !boughtKeys.contains($0.key) }
        let visibleOpenExtras = store.extras.filter { item in
            pendingChecks[item.key] != nil || !boughtKeys.contains(item.key)
        }
        let visibleCheckedExtras = store.extras.filter { item in
            pendingChecks[item.key] == nil && boughtKeys.contains(item.key)
        }
        let exportLines = openExtras.map(\.text) + result.open.map(\.text)
        let openCount = result.open.count + openExtras.count
        let visiblePurchaseIDs = Set(store.purchases.filter { $0.boughtAt.timeIntervalSince1970 > lastCompletion }.map(\.id))
        let checkedLines = result.bought.filter { !$0.purchaseIDs.allSatisfy { !visiblePurchaseIDs.contains($0) } }
        let animatingChecks = checkedLines.filter { pendingChecks[$0.id] != nil }
        let animatingIDs = Set(animatingChecks.map(\.id))
        let coveredIDs = Set(coveredDishes.filter { $0.entry.shoppedAt == nil && includes($0.entry) }.map(\.entry.id))
        List {
            Text("Einkauf (\(openCount))")
                .font(Theme.display(34))
                .tracking(-1)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
            if store.purchaseSyncState == .waiting {
                Section {
                    Label("Haken werden bei Verbindung gesichert", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }
            } else if store.purchaseSyncState == .sending {
                Section { ProgressView("Haken werden gesichert") }
            }
            if store.hasPendingCompletion {
                Section {
                    if store.saving {
                        ProgressView("Einkaufsabschluss wird geprüft")
                    } else {
                        Label("Einkaufsabschluss ausstehend", systemImage: "clock")
                        Button("Erneut prüfen", systemImage: "arrow.clockwise") {
                            submitCompletion { await store.retryCompletion(household: household) }
                        }
                        .disabled(store.hasPendingPurchases)
                    }
                }
            } else if store.canUndoCompletion {
                Section {
                    let layout = textSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout())
                    layout {
                        Label("Einkauf erledigt", systemImage: "checkmark.circle.fill")
                        if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
                        Button("Rückgängig") { undoCompletion() }
                            .buttonStyle(.borderless)
                            .disabled(store.saving || store.hasPendingPurchases)
                    }
                }
            }
            if !openDishes.isEmpty {
                dishPicker(openDishes, selectedCount: included.count)
            }
            Section {
                Button("Artikel hinzufügen", systemImage: "plus") { adding = true }
                    .foregroundStyle(Theme.accent)
                    .disabled(store.saving)
            }
            shoppingLines(result.open, animatingIDs: animatingIDs)
            if !visibleOpenExtras.isEmpty {
                Section("Weitere Artikel (\(openExtras.count))") {
                    ForEach(visibleOpenExtras) { item in
                        extraRow(item, bought: boughtKeys.contains(item.key))
                    }
                }
            }
            let visibleChecks = checkedLines.filter { !animatingIDs.contains($0.id) }
            if !visibleChecks.isEmpty || !visibleCheckedExtras.isEmpty {
                Section("Abgehakt") {
                    ForEach(visibleChecks) { line in
                        Button {
                            undo(line)
                        } label: {
                            ShoppingIngredientRow(line: line, note: checkedOrigin(line), check: .bought)
                        }
                        .accessibilityHint("Haken entfernen")
                        .disabled(store.saving)
                    }
                    ForEach(visibleCheckedExtras) { item in
                        extraRow(item, bought: true)
                    }
                }
            }
            if !coveredDishes.isEmpty {
                Section("Schon eingekauft") {
                    ForEach(coveredDishes, id: \.entry.id) { dish in
                        Button {
                            returnCandidate = dish.entry
                        } label: {
                            HStack(spacing: 12) {
                                coveredDishPhoto(imageURL(for: dish.entry))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(dish.recipe.title).font(.subheadline.weight(.semibold))
                                    Text(mealDate(dish.entry)).font(.caption).foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(Theme.ink)
                        .accessibilityHint("Zurück auf die Einkaufsliste")
                        .disabled(store.saving || store.hasPendingPurchases)
                        .contextMenu {
                            Button("Rezept öffnen", systemImage: "book") { openedRecipeID = dish.entry.recipeID }
                        }
                        .accessibilityAction(named: Text("Rezept öffnen")) { openedRecipeID = dish.entry.recipeID }
                    }
                }
            }
            if !included.isEmpty || !coveredIDs.isEmpty || !store.extras.isEmpty {
                Section {
                    Button("Einkauf erledigt", systemImage: "checkmark") {
                        if result.open.isEmpty && openExtras.isEmpty {
                            finish(lines: [], meals: included.union(coveredIDs), extras: Set(store.extras.map(\.id)))
                        } else { finishOpen = true }
                    }
                    .buttonStyle(.ink)
                    .disabled(store.saving || store.hasPendingPurchases || store.hasPendingCompletion)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            if (store.loaded || household.isDemo) && result.open.isEmpty && store.extras.isEmpty
                && result.stock.isEmpty && checkedLines.isEmpty && coveredDishes.isEmpty {
                ContentUnavailableView {
                    Label(openDishes.isEmpty || !included.isEmpty ? "Alles da" : "Keine Gerichte ausgewählt",
                          systemImage: openDishes.isEmpty || !included.isEmpty ? "checkmark.circle" : "cart")
                } description: {
                    Text(openDishes.isEmpty ? "Zutaten für geplante Gerichte erscheinen hier." :
                         included.isEmpty ? "Wähle oben aus, wofür du einkaufen möchtest." :
                         "Für die ausgewählten Gerichte fehlen keine Artikel.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listSectionSpacing(14)
        .contentMargins(.top, 6, for: .scrollContent)
        .overlay {
            if !store.loaded && !household.isDemo && store.error == nil {
                AppLoadingView(label: "Einkaufsliste wird geladen")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Menu {
                    Button("Alle kommenden Gerichte") { lastDay = nil }
                    ForEach(daysWithMeals, id: \.self) { day in
                        Button("Bis \(dateLabel(day))") { lastDay = day }
                    }
                } label: {
                    Label(lastDay.map { "Bis \(dateLabel($0))" } ?? "Zeitraum", systemImage: "line.3.horizontal.decrease")
                }
                if let family = household.household {
                    NavigationLink {
                        PantrySettings(family: family)
                    } label: {
                        Label("Vorrat", systemImage: "cabinet")
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !exportLines.isEmpty {
                    Menu {
                        Button("Liste als Text kopieren", systemImage: "document.on.document") {
                            UIPasteboard.general.string = AppShareText.withFooter(exportLines.joined(separator: "\n"))
                            didCopyList = true
                            copyFeedback += 1
                            AccessibilityNotification.Announcement("Einkaufsliste kopiert").post()
                        }
                        ShareLink(item: AppShareText.withFooter(exportLines.joined(separator: "\n"))) {
                            Label("Liste als Text teilen", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label(didCopyList ? "Einkaufsliste kopiert" : "Einkaufsliste teilen",
                              systemImage: didCopyList ? "checkmark" : "square.and.arrow.up")
                    }
                    Button("Lieferdienste und Bring!", systemImage: "truck.box") {
                        showingDeliveryServices = true
                    }
                }
                AccountToolbarLink(email: accountEmail)
            }
        }
        .navigationDestination(item: $openedRecipeID) { id in
            ShoppingRecipeDestination(id: id)
        }
        .onDisappear(perform: clearPendingChecks)
        .onChange(of: reduceMotion) {
            if reduceMotion { clearPendingChecks() }
        }
        .onChange(of: lastDay) { clearPendingChecks() }
        .onChange(of: excludedMeals) { clearPendingChecks() }
        .task(id: ShoppingScope(day: today, memberIDs: household.members.map(\.id))) {
            guard let family = household.household, !household.isDemo else { return }
            await store.watch(family: family, members: household.members, today: today)
        }
        .task(id: household.household?.id) {
            if let family = household.household, !household.isDemo {
                lastCompletion = UserDefaults.standard.double(forKey: "gnocchi.shopping.lastCompletion.\(family.id)")
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await reload() } }
        }
        .refreshable {
            if let family = household.household, !household.isDemo { await store.syncPurchases(family: family) }
            await reload()
        }
        .sensoryFeedback(.success, trigger: confirmationCount) { _, _ in preferences.hapticsEnabled }
        .celebration($celebration)
        .task(id: copyFeedback) {
            guard didCopyList else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            didCopyList = false
        }
        .sheet(isPresented: $showingDeliveryServices) {
            NavigationStack {
                DeliveryServicesSheet(lines: result.open, extras: openExtras, exportLines: exportLines, today: today)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $finishOpen) {
            NavigationStack {
                List {
                    if !exportLines.isEmpty {
                        Section(exportLines.count == 1 ? "Noch 1 Posten offen" : "Noch \(exportLines.count) Posten offen") {
                            ForEach(Array(exportLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                            }
                        }
                    }
                    Section {
                        if !exportLines.isEmpty {
                            Button("Fehlendes auf der Liste lassen", systemImage: "cart") {
                                finishOpen = false
                                let extras = Set(store.extras.map(\.id)).subtracting(openExtras.map(\.id))
                                finish(lines: [], meals: coveredIDs, extras: extras)
                            }
                        }
                        Button(exportLines.isEmpty ? "Einkauf abschließen" : "Alles bekommen", systemImage: "checkmark.circle") {
                            finishOpen = false
                            finish(lines: result.open, meals: included.union(coveredIDs), extras: Set(store.extras.map(\.id)))
                        }
                    }
                    .disabled(store.saving || store.hasPendingPurchases || store.hasPendingCompletion)
                }
                .navigationTitle("Einkauf abschließen")
                .gnScreen()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen", systemImage: "xmark") { finishOpen = false }
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Gericht zurück auf die Liste?", isPresented: Binding(
            get: { returnCandidate != nil }, set: { if !$0 { returnCandidate = nil } }
        ), titleVisibility: .visible, presenting: returnCandidate) { entry in
            Button("Zurück auf die Liste") {
                Task {
                    if await store.returnMeal(entry, household: household) {
                        excludedMeals.remove(entry.id)
                        if let lastDay, entry.date > lastDay { self.lastDay = nil }
                        confirmationCount += 1
                    }
                    await reload()
                }
            }
        } message: { _ in
            Text("Die gespeicherten Käufe für dieses Gericht werden zurückgesetzt.")
        }
        .sheet(isPresented: $adding) {
            NavigationStack { ShoppingAddArticleSheet() }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Einkauf", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }

    private func shoppingLines(_ lines: [ShoppingLine], animatingIDs: Set<String>) -> some View {
        let groups = grouped(lines)
        let keptChecks = pendingChecks.values.compactMap { check -> (line: ShoppingLine, position: Int)? in
            guard let line = check.line, animatingIDs.contains(line.id) else { return nil }
            return (line, check.position)
        }
        let aisles = Set(groups.map(\.aisle)).union(keptChecks.map(\.line.aisle))
            .sorted { Aisles.rank($0) < Aisles.rank($1) }
        return ForEach(aisles, id: \.self) { aisle in
            let open = groups.first { $0.aisle == aisle }?.lines ?? []
            let displayed = displayedLines(open, adding: keptChecks.filter { $0.line.aisle == aisle })
            Section("\(aisle) (\(open.count))") {
                ForEach(Array(displayed.enumerated()), id: \.element.id) { index, line in
                    let checking = animatingIDs.contains(line.id)
                    Button {
                        buy(line, position: index)
                    } label: {
                        ShoppingIngredientRow(line: line, note: line.usesStock ? "Vorrat angerechnet" : nil,
                                              check: checking ? .bought : .open)
                    }
                    .accessibilityHint(checking ? "Abgehakt" : "Als gekauft abhaken")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Immer zu Hause", systemImage: "cabinet") {
                            changePantry(Pantry.entriesToAdd(line.name), adding: true)
                        }.tint(Theme.success)
                    }
                    .contextMenu {
                        Button("Immer zu Hause", systemImage: "cabinet") {
                            changePantry(Pantry.entriesToAdd(line.name), adding: true)
                        }
                    }
                    .disabled(store.saving || pendingChecks[line.id] != nil)
                }
            }
        }
    }

    private func displayedLines(
        _ lines: [ShoppingLine], adding checks: [(line: ShoppingLine, position: Int)]
    ) -> [ShoppingLine] {
        var displayed = lines
        for check in checks.sorted(by: { $0.position < $1.position }) {
            displayed.insert(check.line, at: min(check.position, displayed.count))
        }
        return displayed
    }

    private func extraRow(_ item: ShoppingExtra, bought: Bool) -> some View {
        Button {
            guard let family = household.household else { return }
            Task {
                await store.toggleExtra(item, family: family, demo: household.isDemo)
                if !bought, store.purchases.contains(where: { $0.key == item.key }) {
                    holdCheck(id: item.key)
                }
                await reload()
            }
        } label: {
            ShoppingIngredientRow(name: item.text, check: bought ? .bought : .open)
        }
        .accessibilityHint(bought ? "Haken entfernen" : "Als gekauft abhaken")
        .disabled(store.saving || pendingChecks[item.key] != nil)
        .swipeActions {
            Button("Entfernen", systemImage: "trash", role: .destructive) {
                guard let family = household.household else { return }
                Task { await store.deleteExtra(item, family: family, demo: household.isDemo) }
            }
            .disabled(store.hasPendingPurchases)
        }
    }

    private func coveredDishPhoto(_ url: URL?) -> some View {
        CatalogImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Theme.well.overlay {
                Image(systemName: "fork.knife").foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: Theme.radiusControl))
        .accessibilityHidden(true)
    }

    private func dishPicker(_ dishes: [(entry: MealPlanEntry, recipe: ShoppingRecipe)], selectedCount: Int) -> some View {
        Section {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(dishes, id: \.entry.id) { dish in
                        let entry = dish.entry
                        let selected = includes(entry)
                        let outsidePeriod = lastDay.map { entry.date > $0 } ?? false
                        let count = Planning.servings(for: entry, in: plan, members: household.members, attendance: attendance)
                        let portions = count == 1 ? "1 Portion" : "\(count) Portionen"
                        Button {
                            if selected { excludedMeals.insert(entry.id) }
                            else { excludedMeals.remove(entry.id) }
                        } label: {
                            ShoppingDishTile(
                                title: dish.recipe.title,
                                date: mealDate(entry),
                                detail: dish.recipe.ingredients.isEmpty ? "Ohne Zutaten" : portions,
                                url: imageURL(for: entry),
                                selected: selected
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selected ? "Ausgewählt" : "Abgewählt")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .disabled(outsidePeriod)
                        .opacity(outsidePeriod ? 0.5 : 1)
                        .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.radiusCard))
                        .contextMenu {
                            Button("Rezept öffnen", systemImage: "book") { openedRecipeID = entry.recipeID }
                        }
                        .accessibilityAction(named: Text("Rezept öffnen")) { openedRecipeID = entry.recipeID }
                    }
                }
                .padding(1)
            }
            .scrollIndicators(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            HStack {
                Text("Gerichte").accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(selectedCount) von \(dishes.count) ausgewählt")
                    .monospacedDigit()
            }
            .textCase(nil)
        }
    }

    private func imageURL(for entry: MealPlanEntry) -> URL? {
        guard let id = entry.recipeID else { return nil }
        return store.recipeImages[id] ?? household.recipes.first(where: { $0.id == id })?.imageURL
    }

    private func mealDate(_ entry: MealPlanEntry) -> String {
        "\(entry.date == today ? "Heute" : dateLabel(entry.date)) · \(entry.meal.label)"
    }

    private var daysWithMeals: [String] {
        Set(dishes.map(\.entry.date)).sorted()
    }

    private func includes(_ entry: MealPlanEntry) -> Bool {
        !excludedMeals.contains(entry.id) && (lastDay.map { entry.date <= $0 } ?? true)
    }

    private func changePantry(_ names: Set<String>, adding: Bool) {
        guard let family = household.household else { return }
        Task {
            if await store.changePantry(names, adding: adding, family: family, demo: household.isDemo) {
                confirmationCount += 1
            }
            await reload()
        }
    }

    private func finish(lines: [ShoppingLine], meals: Set<String>, extras: Set<String>) {
        let expected = store.completionExpectation(for: meals)
        submitCompletion { await store.finish(lines: lines, mealIDs: meals, extraIDs: extras, household: household, expected: expected) }
    }

    private func submitCompletion(_ operation: @escaping @MainActor () async -> Bool) {
        guard let family = household.household else { return }
        Task {
            if await operation() {
                previousCompletion = lastCompletion
                setLastCompletion(Date.now.timeIntervalSince1970, familyID: family.id)
                lastDay = nil
                excludedMeals.removeAll()
                celebration = Celebration(title: "Einkauf erledigt!", detail: "Alles im Korb. Jetzt wird gekocht.")
            }
            await reload()
        }
    }

    private func undoCompletion() {
        guard let family = household.household else { return }
        Task {
            if await store.undoCompletion(household: household) {
                setLastCompletion(previousCompletion, familyID: family.id)
                confirmationCount += 1
            }
            await reload()
        }
    }

    private func setLastCompletion(_ timestamp: Double, familyID: String) {
        lastCompletion = timestamp
        if !household.isDemo {
            UserDefaults.standard.set(timestamp, forKey: "gnocchi.shopping.lastCompletion.\(familyID)")
        }
    }

    private func checkedOrigin(_ line: ShoppingLine) -> String? {
        var details: [String] = []
        if line.fromStock { details.append("War noch da") }
        if let memberID = line.boughtBy, memberID != household.household?.memberID {
            let name = household.members.first { $0.id == memberID }?.name
            details.append(name.map { "Abgehakt von \($0)" } ?? "Von einem Familienmitglied abgehakt")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private func grouped(_ lines: [ShoppingLine]) -> [(aisle: String, lines: [ShoppingLine])] {
        Dictionary(grouping: lines, by: \.aisle).map { ($0.key, $0.value) }
            .sorted { Aisles.rank($0.aisle) < Aisles.rank($1.aisle) }
    }

    private func dateLabel(_ date: String) -> String {
        guard let value = BerlinDay.date(for: date) else { return date }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "de_DE"))
        style.timeZone = BerlinDay.calendar.timeZone
        return value.formatted(style)
    }

    private func buy(_ line: ShoppingLine, position: Int) {
        guard !store.saving, pendingChecks[line.id] == nil, let family = household.household else { return }
        let includedIDs = Set(plan.filter { includes($0) }.map(\.id))
        guard let current = result(including: includedIDs, now: .now).open.first(where: { $0.id == line.id }),
              store.buy(current, family: family, fromStock: false, demo: household.isDemo) else { return }
        confirmationCount += 1
        holdCheck(id: line.id, line: line, position: position)
        Task { await reload() }
    }

    private func holdCheck(id: String, line: ShoppingLine? = nil, position: Int = 0) {
        guard !reduceMotion else { return }
        // Der Kauf ist schon vorgemerkt. Die Zeile bleibt kurz für die Haken-Animation stehen.
        let removal = Task {
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            pendingChecks[id] = nil
        }
        pendingChecks[id] = PendingCheck(line: line, position: position, removal: removal)
    }

    private func clearPendingChecks() {
        for check in pendingChecks.values { check.removal.cancel() }
        pendingChecks.removeAll()
    }

    private func undo(_ line: ShoppingLine) {
        guard let family = household.household else { return }
        Task { await store.undo(line.purchaseIDs, family: family, demo: household.isDemo); await reload() }
    }

    private func reload() async {
        guard let family = household.household, !household.isDemo else { return }
        if store.purchaseSyncState != .waiting {
            await store.load(family: family, members: household.members, today: today)
        }
    }
}

struct ShoppingAddArticleSheet: View {
    enum Target {
        case shopping, pantry
        var title: String { self == .pantry ? "Vorrat hinzufügen" : "Artikel hinzufügen" }
        var historyKey: String { self == .pantry ? "recentPantryArticles" : "recentArticles" }
    }

    @Environment(HouseholdStore.self) private var household
    @Environment(ShoppingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var target: Target = .shopping
    @State private var query = ""
    @State private var recent: [String] = []
    @State private var error: String?
    @State private var adding = false

    private static let common = [
        "Milch", "Eier", "Brot", "Butter", "Bananen", "Äpfel", "Tomaten", "Joghurt",
        "Gurken", "Kartoffeln", "Karotten", "Zwiebeln", "Paprika", "Zitronen", "Knoblauch",
        "Hafermilch", "Käse", "Feta", "Reis", "Nudeln", "Haferflocken", "Mehl",
        "Tomatenmark", "Passierte Tomaten", "Olivenöl", "Salz", "Kaffee", "Mineralwasser"
    ]

    private var text: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchKey: String { Self.key(text) }

    private var recentMatches: [String] {
        let extras = target == .shopping ? store.extras.reversed().map(\.text) : []
        let previous = unique(recent + extras)
        return Array(matches(previous).prefix(4))
    }

    private func suggestions(excluding recentRows: [String]) -> [String] {
        let ingredients = household.recipes.flatMap(\.ingredients)
            .map { IngredientName.display($0.name) }
        let counts = Dictionary(grouping: ingredients, by: Self.key)
        let frequent = counts.values.sorted { left, right in
            if left.count != right.count { return left.count > right.count }
            return (left.first ?? "").localizedStandardCompare(right.first ?? "") == .orderedAscending
        }.compactMap(\.first)
        let recentKeys = Set(recentRows.map(Self.key))
        let available = unique(frequent + Self.common).filter { !recentKeys.contains(Self.key($0)) }
        return Array(matches(available).prefix(text.isEmpty ? 4 : 10))
    }

    var body: some View {
        let recentRows = recentMatches
        let suggestionRows = suggestions(excluding: recentRows)
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.inkSecondary)
                        .accessibilityHidden(true)
                    TextField("Artikel suchen", text: $query)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit { add(text) }
                    if !query.isEmpty {
                        Button("Suche leeren", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
            if text.isEmpty || !recentRows.isEmpty {
                Section("Zuletzt benutzt") {
                    if recentRows.isEmpty {
                        Text("Hier erscheinen deine zuletzt hinzugefügten Artikel.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    ForEach(recentRows, id: \.self) { articleRow($0) }
                }
            }
            if !suggestionRows.isEmpty {
                Section("Vorschläge") {
                    ForEach(suggestionRows, id: \.self) { articleRow($0) }
                }
            }
        }
        .gnScreen()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(target.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .disabled(adding)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Hinzufügen") { add(text) }
                    .disabled(!canAdd(text))
            }
        }
        .interactiveDismissDisabled(adding)
        .task(id: household.household?.id) {
            recent = household.household.flatMap {
                UserDefaults.standard.stringArray(forKey: recentKey(family: $0))
            } ?? []
        }
        .alert(target.title, isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func articleRow(_ name: String) -> some View {
        Button {
            add(name)
        } label: {
            HStack(spacing: 12) {
                ShoppingIngredientRow(name: name)
                Image(systemName: "plus.circle")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint(target == .pantry ? "Zu Immer zu Hause hinzufügen" : "Zur Einkaufsliste hinzufügen")
        .disabled(!canAdd(name))
    }

    private func canAdd(_ name: String) -> Bool {
        guard household.household != nil, !adding, !store.saving, !name.isEmpty, name.count <= 200 else { return false }
        if target == .pantry {
            let entries = Pantry.entriesFromInput(name)
            return !entries.isEmpty && entries.allSatisfy { $0.unicodeScalars.count <= 80 }
                && !entries.isSubset(of: store.pantry)
        }
        return true
    }

    private func add(_ name: String) {
        guard canAdd(name), let family = household.household else { return }
        adding = true
        Task {
            defer { adding = false }
            let saved = switch target {
            case .shopping:
                await store.addExtra(name, family: family, demo: household.isDemo)
            case .pantry:
                await store.changePantry(Pantry.entriesFromInput(name), adding: true, family: family, demo: household.isDemo)
            }
            if saved {
                let updated = Array(unique([name] + recent).prefix(16))
                UserDefaults.standard.set(updated, forKey: recentKey(family: family))
                dismiss()
            } else {
                error = store.error ?? "Der Eintrag konnte nicht hinzugefügt werden."
                store.error = nil
            }
        }
    }

    private func recentKey(family: Membership) -> String {
        "gnocchi.shopping.\(target.historyKey).\(family.id)"
    }

    private func unique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 200 && seen.insert(Self.key($0)).inserted }
    }

    private func matches(_ names: [String]) -> [String] {
        let query = searchKey
        guard !query.isEmpty else { return names }
        let matching = names.filter { Self.key($0).contains(query) }
        return matching.filter { Self.key($0).hasPrefix(query) }
            + matching.filter { !Self.key($0).hasPrefix(query) }
    }

    private static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct ShoppingRecipeDestination: View {
    @Environment(HouseholdStore.self) private var household
    @Environment(ShoppingStore.self) private var store
    @State private var recipe: Recipe?
    @State private var failed = false
    @State private var attempt = 0
    let id: String

    private var availableRecipe: Recipe? { household.recipes.first { $0.id == id } ?? recipe }

    var body: some View {
        Group {
            if let availableRecipe {
                RecipeDetailView(recipe: availableRecipe)
            } else if failed {
                ContentUnavailableView {
                    Label("Rezept nicht verfügbar", systemImage: "book.closed")
                } actions: {
                    if !household.isDemo {
                        Button("Erneut versuchen") {
                            failed = false
                            attempt += 1
                        }
                    }
                }
                .gnScreen()
            } else {
                AppLoadingView(label: "Rezept wird geladen")
                    .gnScreen()
            }
        }
        .task(id: attempt) {
            guard availableRecipe == nil else { return }
            guard let family = household.household, !household.isDemo else {
                failed = true
                return
            }
            do {
                recipe = try await store.loadRecipe(id, householdID: family.id)
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }
}

private struct ShoppingDishTile: View {
    @Environment(\.dynamicTypeSize) private var textSize

    let title: String
    let date: String
    let detail: String
    let url: URL?
    let selected: Bool

    var body: some View {
        let width: CGFloat = textSize.isAccessibilitySize ? 234 : 126
        PhotoCard(url: url, title: title, metadata: date, aspectRatio: 126.0 / 160.0, compact: true)
            .frame(width: width)
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(selected ? Theme.assistantButton : .white)
                    .background(selected ? .white : .black.opacity(0.36), in: .circle)
                    .padding(8)
                    .accessibilityHidden(true)
            }
            .opacity(selected ? 1 : 0.67)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(title), \(date), \(detail)"))
    }
}

struct ShoppingIngredientRow: View {
    enum Check: Equatable { case open, bought }

    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var iconWidth = 34.0

    let name: String
    var quantity: String?
    var aisle: String?
    var note: String?
    var check: Check?

    init(name: String, check: Check? = nil) {
        self.name = name
        self.check = check
    }

    init(line: ShoppingLine, note: String? = nil, check: Check? = nil) {
        if line.text.hasSuffix(" " + line.name) {
            name = line.name
            quantity = String(line.text.dropLast(line.name.count + 1))
        } else {
            name = line.text
        }
        aisle = line.aisle
        self.note = note
        self.check = check
    }

    var body: some View {
        HStack(spacing: 10) {
            IngredientIcon(name: name, aisle: aisle)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(check == .bought ? Theme.inkSecondary : Theme.ink)
                    .strikethrough(check == .bought)
                if textSize.isAccessibilitySize, let quantity { quantityLabel(quantity) }
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !textSize.isAccessibilitySize, let quantity {
                quantityLabel(quantity)
                    .layoutPriority(1)
            }
            if let check {
                Image(systemName: check == .bought ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(check == .bought ? Theme.success : Theme.inkSecondary)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 39)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: check)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func quantityLabel(_ quantity: String) -> some View {
        Text(quantity)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSecondary)
            .monospacedDigit()
            .strikethrough(check == .bought)
    }
}
