import GnocchiCore
import SwiftUI

struct MealChangeView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: MealSlot
    let onSave: () -> Void
    @State private var move = true
    @State private var date: Date
    @State private var meal: Meal
    @State private var preview: PlanChangePreview?
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?
    @State private var choseInitialTarget = false

    init(slot: MealSlot, onSave: @escaping () -> Void) {
        self.slot = slot
        self.onSave = onSave
        _date = State(initialValue: BerlinDay.date(for: BerlinDay.adding(1, to: slot.date)) ?? .now)
        _meal = State(initialValue: slot.meal)
    }

    var body: some View {
        let target = MealSlot(date: BerlinDay.key(for: date), meal: meal)
        let change: PlanChange = move ? .move(slot, target) : .out(slot)
        Form {
            Section {
                Picker("Änderung", selection: $move) {
                    Text("Verschieben").tag(true)
                    Text("Auswärts essen").tag(false)
                }
                if move {
                    DatePicker("Neuer Tag", selection: $date, in: BerlinDay.calendar.startOfDay(for: .now)..., displayedComponents: .date)
                        .environment(\.timeZone, BerlinDay.calendar.timeZone)
                    Picker("Mahlzeit", selection: $meal) {
                        ForEach(Meal.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            }
            Section("Was ändert sich?") {
                if loading { ProgressView("Vorschau wird geladen") }
                else if let preview, preview.change == change {
                    ForEach(preview.lines.indices, id: \.self) { Text(preview.lines[$0]) }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Wochenplan ändern")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Übernehmen", systemImage: "checkmark") { Task { await save(change) } }
                    .labelStyle(.iconOnly)
                    .disabled(loading || saving || preview?.change != change)
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .onAppear {
            guard !choseInitialTarget else { return }
            choseInitialTarget = true
            let candidates = BerlinDay.days(from: BerlinDay.adding(1, to: slot.date))
            if let day = candidates.first(where: { day in
                !store.plan.contains {
                    $0.date == day && $0.meal == slot.meal && ($0.recipeID != nil || $0.leftoverOf != nil)
                }
            }), let preferred = BerlinDay.date(for: day) {
                date = preferred
            }
        }
        .task(id: change) { await loadPreview(change) }
    }

    private func loadPreview(_ change: PlanChange, needsConfirmation: Bool = false) async {
        loading = true
        preview = nil
        message = nil
        do {
            let updated = try await AssistantActions.previewChange(change, household: store)
            guard !Task.isCancelled else { return }
            preview = updated
            if needsConfirmation { message = "Der Plan wurde aktualisiert. Prüfe die Vorschau und bestätige erneut." }
        } catch {
            guard !Task.isCancelled else { return }
            message = (error as? AssistantFailure)?.errorDescription ?? "Die Vorschau konnte nicht geladen werden."
        }
        loading = false
    }

    private func save(_ change: PlanChange) async {
        guard !saving, let approved = preview, approved.change == change else { return }
        saving = true
        message = nil
        defer { saving = false }
        do {
            let current = try await AssistantActions.previewChange(change, household: store)
            guard approved.matches(current) else {
                preview = current
                message = "Der Plan wurde aktualisiert. Prüfe die Vorschau und bestätige erneut."
                return
            }
            try await AssistantActions.applyPlanChange(approved, household: store)
            onSave()
        } catch AssistantFailure.planChanged {
            await loadPreview(change, needsConfirmation: true)
        } catch {
            message = (error as? AssistantFailure)?.errorDescription ?? "Die Änderung konnte nicht gespeichert werden."
        }
    }
}
