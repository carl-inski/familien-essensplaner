import GnocchiCore
import Supabase
import SwiftUI

struct MealEditor: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: MealSlot
    var openRecipePicker = false
    @State private var showingRecipePicker = false
    @State private var openedInitialPicker = false
    @State private var chosenLeftover: MealPlanEntry?
    @State private var draft = MealDraft()
    @State private var initial: MealDraft?
    @State private var initialEntry: MealPlanEntry?
    @State private var conflict = false
    @State private var reloading = false
    @State private var saveError: String?
    @State private var changeShown = false
    @State private var suggestionsSeen: Set<String> = []
    @State private var suggestedID: String?
    @State private var noSuggestion = false

    private var automaticServings: Int {
        let entry = MealPlanEntry(id: store.plan.first { $0.slot == slot }?.id ?? UUID().uuidString,
                                  date: slot.date, meal: slot.meal,
                                  familyGuests: store.plan.first { $0.slot == slot }?.familyGuests)
        return Planning.servings(for: entry, in: store.plan, members: store.members, attendance: store.attendance)
    }

    var body: some View {
        Form {
            Section("Gericht") {
                if let recipe = store.recipeForMeal(recipeID: draft.recipeID ?? chosenLeftover?.recipeID, leftoverOf: draft.leftoverOf) {
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            RecipeRow(recipe: recipe)
                            if draft.leftoverOf != nil {
                                Text("Rezept zum Resteessen")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if let book = store.cookbooks.first(where: { $0.id == recipe.cookbookID }) {
                                Text(recipe.cookbookPage.map { "\(book.title), S. \($0)" } ?? book.title)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button {
                    showingRecipePicker = true
                } label: {
                    Label(draft.recipeID == nil && draft.leftoverOf == nil ? "Rezept auswählen" : "Rezept ändern", systemImage: "book")
                }
                TextField("Notiz", text: $draft.note, axis: .vertical)
                if slot.date >= BerlinDay.today() {
                    Button(suggestedID == nil ? "Gericht vorschlagen" : "Anderen Vorschlag suchen", systemImage: "sparkles") {
                        suggest()
                    }
                    .disabled(store.saving)
                    if Meal.planned.contains(slot.meal) {
                        NavigationLink {
                            DecideView(suggestedSlot: slot)
                        } label: {
                            Label("Gericht ausspielen", systemImage: "dice")
                        }
                    }
                }
                Picker("Status", selection: $draft.status) {
                    ForEach(PlanStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(status)
                    }
                }
                if slot.date >= BerlinDay.today(), initial?.recipeID != nil || initial?.leftoverOf != nil {
                    Button("Gericht verschieben oder ausfallen lassen", systemImage: "calendar.badge.clock") {
                        changeShown = true
                    }
                    .disabled(initial.map { !draft.changes(from: $0).isEmpty } ?? true)
                }
            }

            if draft.recipeID != nil {
                Section("Portionen") {
                    Toggle("Automatisch", isOn: Binding(
                        get: { draft.servings == nil },
                        set: { draft.servings = $0 ? nil : max(1, min(40, automaticServings)) }
                    ))
                    if draft.servings == nil {
                        LabeledContent("Portionen", value: automaticServings.formatted())
                    } else {
                        Stepper(value: Binding(get: { draft.servings ?? 1 }, set: { draft.servings = $0 }), in: 1...40) {
                            LabeledContent("Portionen", value: (draft.servings ?? 1).formatted())
                        }
                    }
                }
            }
            if draft.recipeID != nil || draft.leftoverOf != nil {
                Section("Kochdienst") {
                    MealCookPicker(slot: slot, cookID: Binding(get: { draft.cookID }, set: { member in
                        if draft.cookID != member {
                            draft.cookID = member
                            draft.secondCookID = nil
                        }
                    }))
                }
            }

            Section("Wer isst mit?") {
                MealAttendanceControls(slot: slot)
            }
        }
        .disabled(store.saving || reloading)
        .navigationTitle(slot.meal.label)
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }.disabled(store.saving || reloading)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    Task { await save() }
                }
                .disabled(store.saving || reloading || initial == nil)
            }
        }
        .interactiveDismissDisabled(store.saving || reloading)
        .alert("Mahlzeit wurde geändert", isPresented: $conflict) {
            Button("Aktuellen Stand laden", role: .destructive) { Task { await reloadDraft() } }
            Button("Entwurf behalten", role: .cancel) {}
        } message: {
            Text("Jemand hat diesen Termin geändert. Wenn du den aktuellen Stand lädst, verwirfst du deine ungespeicherten Eingaben.")
        }
        .alert("Mahlzeit bearbeiten", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .alert("Kein passender Vorschlag", isPresented: $noSuggestion) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Für diese Mahlzeit ist gerade kein passendes Rezept verfügbar.")
        }
        .sheet(isPresented: $changeShown) {
            NavigationStack {
                MealChangeView(slot: slot) {
                    changeShown = false
                    dismiss()
                }
            }
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showingRecipePicker) {
            RecipePicker(selection: Binding(get: { draft.recipeID }, set: { selectRecipe($0) }),
                         leftoverTarget: slot, onLeftover: { source in
                             selectRecipe(nil)
                             chosenLeftover = source
                             draft.leftoverOf = source.id
                             showingRecipePicker = false
                         })
        }
        .onAppear {
            prepareDraft()
            if openRecipePicker, !openedInitialPicker {
                openedInitialPicker = true
                showingRecipePicker = true
            }
        }
    }

    @MainActor
    private func save() async {
        guard let initial, !store.saving, !reloading else { return }
        if let chosenLeftover {
            do {
                try await store.validateLeftoverSource(chosenLeftover, for: slot)
            } catch {
                saveError = error.localizedDescription
                return
            }
        }
        guard await store.saveMeal(at: slot, changes: draft.changes(from: initial),
                                   condition: .unchanged(initialEntry, includingDetails: true)) else {
            if let message = store.error {
                store.error = nil
                saveError = message
            } else {
                conflict = true
            }
            return
        }
        if let suggestedID, suggestedID == draft.recipeID, suggestedID != initial.recipeID,
           draft.status != .cancelled, draft.leftoverOf == nil {
            await store.recordMealSuggestion(recipeID: suggestedID, slot: slot)
        }
        dismiss()
    }

    private func selectRecipe(_ id: String?) {
        chosenLeftover = nil
        suggestedID = nil
        draft.recipeID = id
        draft.leftoverOf = nil
        draft.status = .planned
        if id == nil { draft.servings = nil }
    }

    private func suggest() {
        var excluded = suggestionsSeen
        if let id = draft.recipeID { excluded.insert(id) }
        guard let pick = store.suggestedRecipe(at: slot, avoiding: excluded) else {
            noSuggestion = true
            return
        }
        selectRecipe(pick.id)
        suggestedID = pick.id
        suggestionsSeen.insert(pick.id)
    }

    private func prepareDraft() {
        guard initial == nil else { return }
        setDraft(from: store.plan.first(where: { $0.slot == slot }))
    }

    private func setDraft(from entry: MealPlanEntry?) {
        if let entry {
            draft = MealDraft(recipeID: entry.recipeID, leftoverOf: entry.leftoverOf, note: entry.note ?? "",
                              status: entry.status, servings: entry.servingsOverride,
                              cookID: entry.cookID, secondCookID: entry.secondCookID)
        } else {
            draft = MealDraft()
        }
        initialEntry = entry
        initial = draft
        suggestedID = nil
        suggestionsSeen = []
    }

    private func reloadDraft() async {
        guard !reloading else { return }
        reloading = true
        defer { reloading = false }
        do {
            let entries = try await store.plannedMeals(from: slot.date, through: slot.date)
            setDraft(from: entries.first { $0.slot == slot })
        } catch {
            saveError = "Der aktuelle Termin konnte nicht geladen werden."
        }
    }



}

private struct MealCookPicker: View {
    @Environment(HouseholdStore.self) private var store
    let slot: MealSlot
    @Binding var cookID: String?

    private var availableCooks: [Member] {
        store.members.filter {
            Planning.effectiveStatus(for: $0, at: slot, attendance: store.attendance).status == .present
        }
    }

    var body: some View {
        Picker("Wer kocht?", selection: $cookID) {
            Text("Niemand").tag(nil as String?)
            ForEach(availableCooks) { member in
                Text(member.name).tag(Optional(member.id))
            }
            if let cookID, !availableCooks.contains(where: { $0.id == cookID }) {
                Text("Koch fehlt").tag(Optional(cookID))
            }
        }
    }
}

extension HouseholdStore {
    var suggestionPlan: [MealSuggestion.Planned] {
        let days = Set(BerlinDay.days(from: weekStart ?? BerlinDay.today()))
        return plan.compactMap { entry in
            guard days.contains(entry.date), entry.status != .cancelled,
                  let id = entry.recipeID else { return nil }
            return MealSuggestion.Planned(slot: entry.slot, recipeID: id)
        }
    }

    func suggestedRecipe(at slot: MealSlot, avoiding excluded: Set<String> = []) -> MealSuggestion.Candidate? {
        let history = CookingSummary.from(cookingHistory).mapValues(\.latest)
        return MealSuggestion.pick(from: recipes.map(\.suggestionCandidate), lastCooked: history,
                                   plan: suggestionPlan, slot: slot, today: BerlinDay.today(),
                                   avoiding: excluded, random: .random(in: 0..<1))
    }
}

private extension Recipe {
    var suggestionCandidate: MealSuggestion.Candidate {
        .init(id: id, cookbookID: cookbookID, tags: tags ?? [], categories: categories ?? [])
    }
}

private struct MealDraft {
    var recipeID: String?
    var leftoverOf: String?
    var note = ""
    var status: PlanStatus = .planned
    var servings: Int?
    var cookID: String?
    var secondCookID: String?

    func changes(from old: Self) -> [String: AnyJSON] {
        var fields: [String: AnyJSON] = [:]
        if recipeID != old.recipeID { fields["recipe_id"] = recipeID.map(AnyJSON.string) ?? .null }
        if leftoverOf != old.leftoverOf { fields["leftover_of"] = leftoverOf.map(AnyJSON.string) ?? .null }
        if note != old.note { fields["note"] = note.isEmpty ? .null : .string(note) }
        if status != old.status { fields["status"] = .string(status.rawValue) }
        if servings != old.servings { fields["servings_override"] = servings.map(AnyJSON.integer) ?? .null }
        if cookID != old.cookID { fields["cook_id"] = cookID.map(AnyJSON.string) ?? .null }
        let second = cookID == nil ? nil : secondCookID
        if second != old.secondCookID { fields["cook2_id"] = second.map(AnyJSON.string) ?? .null }
        return fields
    }
}
