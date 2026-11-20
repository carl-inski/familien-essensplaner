import GnocchiCore
import SwiftUI

struct LongNotCookedView: View {
    @Environment(HouseholdStore.self) private var store
    @State private var diet: String?
    @State private var book: String?
    @State private var planning: Recipe?

    var body: some View {
        let summary = CookingSummary.from(store.cookingHistory)
        let filtered = store.recipes.filter { (diet == nil || $0.diet == diet) && (book == nil || $0.cookbookID == book) }
        let cooked = RecipeOrder.oldest.sorted(filtered.filter { summary[$0.id] != nil }, history: summary)
        let never = RecipeOrder.alphabetical.sorted(filtered.filter { summary[$0.id] == nil }, history: summary)
        List {
            if !cooked.isEmpty {
                Section("Zuletzt gekocht") {
                    ForEach(cooked) { recipe in row(recipe, summary: summary[recipe.id]) }
                }
            }
            if !never.isEmpty {
                Section("Noch nie gekocht") {
                    ForEach(never) { recipe in row(recipe, summary: nil) }
                }
            }
            if cooked.isEmpty && never.isEmpty {
                ContentUnavailableView("Keine passenden Rezepte", systemImage: "clock.arrow.circlepath")
            }
        }
        .navigationTitle("Lange nicht gegessen")
        .gnScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Ernährung", selection: $diet) {
                        Text("Alle").tag(nil as String?)
                        Text("Vegetarisch").tag(Optional("vegetarisch"))
                        Text("Fisch").tag(Optional("fisch"))
                        Text("Fleisch").tag(Optional("fleisch"))
                    }
                    if !store.cookbooks.isEmpty {
                        Picker("Kochbuch", selection: $book) {
                            Text("Alle").tag(nil as String?)
                            ForEach(store.cookbooks) { Text($0.title).tag(Optional($0.id)) }
                        }
                    }
                } label: { Label("Filtern", systemImage: "line.3.horizontal.decrease") }
            }
        }
        .refreshable { await store.refreshCookingHistory() }
        .sheet(item: $planning) { recipe in
            NavigationStack { RecipeScheduleView(recipe: recipe) }
                .compactRecipeSheet()
        }
    }

    private func row(_ recipe: Recipe, summary: CookingSummary?) -> some View {
        NavigationLink {
            RecipeDetailView(recipe: recipe)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                RecipeRow(recipe: recipe)
                if let summary {
                    let date = BerlinDay.date(for: summary.latest)
                    let days = date.flatMap { BerlinDay.calendar.dateComponents([.day], from: $0, to: BerlinDay.calendar.startOfDay(for: .now)).day }
                    Text("\(cookingDateLabel(summary.latest)) · \(summary.count)×" + (days.map { " · vor \($0) Tagen" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Einplanen", systemImage: "calendar.badge.plus") { planning = recipe }
                .tint(.accentColor)
        }
        .contextMenu {
            Button("Einplanen", systemImage: "calendar.badge.plus") { planning = recipe }
        }
    }
}

struct RecipeScheduleView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let fixedDay: String?
    private let choosesRecipe: Bool
    private let onEdit: ((MealSlot) -> Void)?
    private let onAskAssistant: ((MealSlot) -> Void)?
    private let onSaved: () -> Void
    private let title: String?
    private let onSchedule: ((Recipe, MealSlot, MealPlanEntry?) async -> String?)?
    @State private var recipe: Recipe?
    @State private var day: Date
    @State private var meal: Meal
    @State private var choosingRecipe = false
    @State private var choosingLeftover = false
    @State private var leftover: MealPlanEntry?
    @State private var plan: DayPlan?
    @State private var checking = false
    @State private var replacement: MealPlanEntry?
    @State private var error: String?

    private struct DayPlan {
        let day: String
        let entries: [MealPlanEntry]?
    }

    init(
        recipe: Recipe? = nil, fixedDay: String? = nil, initialDay: String? = nil, meal: Meal = .dinner,
        title: String? = nil,
        onSchedule: ((Recipe, MealSlot, MealPlanEntry?) async -> String?)? = nil,
        onEdit: ((MealSlot) -> Void)? = nil, onAskAssistant: ((MealSlot) -> Void)? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        self.fixedDay = fixedDay
        self.choosesRecipe = recipe == nil
        self.onEdit = onEdit
        self.onAskAssistant = onAskAssistant
        self.onSaved = onSaved
        self.title = title
        self.onSchedule = onSchedule
        _recipe = State(initialValue: recipe)
        _meal = State(initialValue: meal)
        let requested = (fixedDay ?? initialDay).flatMap(BerlinDay.date(for:))
        _day = State(initialValue: requested ?? BerlinDay.calendar.startOfDay(for: .now))
    }

    static func detents(fixedDay: Bool = false, choosesRecipe: Bool = true) -> Set<PresentationDetent> {
        if fixedDay { return [.height(365), .large] }
        return choosesRecipe ? [.fraction(0.6), .large] : [.medium, .large]
    }

    private var today: String { BerlinDay.today() }
    private var tomorrow: String { BerlinDay.adding(1, to: today) }
    private var selectedDay: String { fixedDay ?? max(today, BerlinDay.key(for: day)) }
    private var selectedSlot: MealSlot { MealSlot(date: selectedDay, meal: meal) }

    private var scheduleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if choosesRecipe {
                    recipeChoice
                    if onSchedule == nil { leftoverChoice }
                } else if let recipe {
                    Text(recipe.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                if fixedDay == nil { dayPicker }
                MealChoiceGrid(selection: $meal, detail: mealStatus)
                if fixedDay != nil { scheduleButton }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if fixedDay == nil {
                scheduleButton
                    .padding(.horizontal, Theme.gutter)
                    .padding(.vertical, 8)
                    .background(Theme.paper)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    var body: some View {
        scheduleContent
        .navigationTitle(title ?? (choosesRecipe ? "Gericht einplanen" : "Datum und Mahlzeit"))
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .disabled(checking || store.saving)
            }
            if onEdit != nil || onAskAssistant != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Weitere Aktionen", systemImage: "ellipsis") {
                        if let onEdit {
                            Button("Mahlzeit bearbeiten", systemImage: "slider.horizontal.3") {
                                onEdit(selectedSlot)
                                dismiss()
                            }
                        }
                        if let onAskAssistant {
                            Button("KI nach einem Gericht fragen", systemImage: "sparkles") {
                                onAskAssistant(selectedSlot)
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $choosingRecipe) {
            RecipePicker(selection: Binding<String?>.constant(nil),
                         context: fixedDay.flatMap(BerlinDay.date(for:)).map(formattedDay),
                         onChoose: { selected in
                             leftover = nil
                             recipe = selected
                             choosingRecipe = false
                         })
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $choosingLeftover) {
            LeftoverSourcePicker(target: selectedSlot) { source in
                leftover = source
                recipe = nil
                choosingLeftover = false
            }
        }
        .task(id: selectedDay) { await loadDay(selectedDay) }
        .disabled(checking || store.saving)
        .interactiveDismissDisabled(checking || store.saving)
        .confirmationDialog("Geplanten Termin ersetzen?", isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }
        ), titleVisibility: .visible, presenting: replacement) { entry in
            Button("Termin ersetzen", role: .destructive) {
                Task {
                    checking = true
                    defer { checking = false }
                    await schedule(at: entry.slot, expected: entry)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { entry in
            if let title = slotTitle(entry), let selectionTitle {
                Text("Aktuell steht „\(title)“ im Plan. Möchtest du stattdessen „\(selectionTitle)“ einplanen?")
            }
        }
        .alert("Einplanen", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var scheduleButton: some View {
        Button {
            Task { await checkSlot(selectedSlot) }
        } label: {
            if checking { ProgressView().accessibilityLabel("Termin wird geprüft") }
            else { Text(leftover == nil ? "Einplanen" : "Reste einplanen") }
        }
        .buttonStyle(.ink)
        .disabled(recipe == nil && leftover == nil)
    }

    private var selectionTitle: String? {
        if let leftover, let source = store.recipeForMeal(recipeID: leftover.recipeID, leftoverOf: nil) {
            return "Reste von \(source.title)"
        }
        return recipe?.title
    }

    private var leftoverChoice: some View {
        Button {
            choosingLeftover = true
        } label: {
            HStack(spacing: 10) {
                Label("Reste / Meal Prep", systemImage: "takeoutbag.and.cup.and.straw")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .gnCard(padding: 0, radius: Theme.radiusControl)
        }
        .buttonStyle(.plain)
    }

    private var recipeChoice: some View {
        Button {
            choosingRecipe = true
        } label: {
            HStack(spacing: 11) {
                if let chosen = recipe ?? store.recipeForMeal(recipeID: leftover?.recipeID, leftoverOf: nil) {
                    RecipeThumbnail(recipe: chosen)
                } else {
                    Image(systemName: "book")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(Theme.well, in: .rect(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectionTitle ?? "Rezept auswählen").font(.subheadline.weight(.semibold))
                    if let date = fixedDay.flatMap(BerlinDay.date(for:)) {
                        Text(formattedDay(date)).font(.caption).foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.ink)
            .gnCard(padding: 10, radius: Theme.radiusControl)
        }
        .buttonStyle(.plain)
    }

    private func formattedDay(_ date: Date) -> String {
        var style = Date.FormatStyle().weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))
        style.timeZone = BerlinDay.calendar.timeZone
        return date.formatted(style)
    }

    private var dayPicker: some View {
        VStack(spacing: 0) {
            dayButton("Heute", icon: "calendar", date: today)
            Divider().padding(.leading, 15)
            dayButton("Morgen", icon: "calendar", date: tomorrow)
            Divider().padding(.leading, 15)
            DatePicker(selection: $day, in: BerlinDay.calendar.startOfDay(for: .now)..., displayedComponents: .date) {
                Label("Datum wählen", systemImage: "calendar.badge.clock")
                    .font(.subheadline)
            }
            .datePickerStyle(.compact)
            .environment(\.calendar, BerlinDay.calendar)
            .environment(\.timeZone, BerlinDay.calendar.timeZone)
            .environment(\.locale, Locale(identifier: "de_DE"))
            .frame(minHeight: 44)
            .padding(.horizontal, 13)
        }
        .gnCard(padding: 0, radius: Theme.radiusControl)
    }

    private func dayButton(_ title: String, icon: String, date: String) -> some View {
        let selected = selectedDay == date
        return Button {
            if let value = BerlinDay.date(for: date) { day = value }
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func mealStatus(_ option: Meal) -> String {
        let entry = plan?.day == selectedDay ? plan?.entries?.first(where: { $0.meal == option }) : nil
        if plan?.day != selectedDay { return "Wird geladen" }
        if plan?.entries == nil { return "Plan wird beim Einplanen geprüft" }
        return slotTitle(entry) ?? "Frei"
    }

    private func slotTitle(_ entry: MealPlanEntry?) -> String? {
        guard let entry else { return nil }
        if entry.status == .cancelled {
            return entry.note.flatMap { $0.isEmpty ? nil : "Fällt aus · \($0)" } ?? "Fällt aus"
        }
        if let recipe = store.recipeForMeal(recipeID: entry.recipeID, leftoverOf: entry.leftoverOf) {
            return entry.leftoverOf == nil ? recipe.title : "Reste von \(recipe.title)"
        }
        if entry.leftoverOf != nil { return "Reste" }
        if let note = entry.note, !note.isEmpty { return note }
        if entry.status == .cooked, entry.recipeID == nil { return "Gekocht" }
        return entry.recipeID == nil ? nil : "Gericht eingeplant"
    }

    private func loadDay(_ day: String) async {
        let entries = try? await store.plannedMeals(from: day, through: day)
        guard !Task.isCancelled, day == selectedDay else { return }
        plan = DayPlan(day: day, entries: entries)
    }

    private func checkSlot(_ slot: MealSlot) async {
        guard !checking, !store.saving, recipe != nil || leftover != nil else { return }
        checking = true
        defer { checking = false }
        do {
            let entries = try await store.plannedMeals(from: slot.date, through: slot.date)
            let expected = entries.first { $0.slot == slot }
            let matchesSelection = leftover.map { expected?.leftoverOf == $0.id && expected?.status == .planned }
                ?? (recipe.map { expected?.alreadyPlansRecipe($0.id) == true } ?? false)
            if let expected, !expected.allowsSuggestion, !matchesSelection {
                replacement = expected
            } else {
                await schedule(at: slot, expected: expected)
            }
        } catch {
            self.error = "Der Wochenplan konnte nicht geprüft werden."
        }
    }

    private func schedule(at slot: MealSlot, expected: MealPlanEntry?) async {
        let failure: String?
        if let leftover {
            do {
                try await store.scheduleLeftover(from: leftover, at: slot, expected: expected)
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
        } else if let recipe {
            if let onSchedule {
                failure = await onSchedule(recipe, slot, expected)
            } else {
                let saved = await store.scheduleRecipe(recipe.id, at: slot, expected: expected)
                failure = saved ? nil : store.error ?? "Der Termin wurde inzwischen geändert. Bitte wähle ihn erneut."
                store.error = nil
            }
        } else {
            return
        }
        if let failure {
            await loadDay(selectedDay)
            error = failure
        } else {
            onSaved()
            dismiss()
        }
    }
}

struct RecipeCookingHistory: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    let recipe: Recipe
    let servings: Int?
    let sheetColorScheme: ColorScheme
    @State private var enteringDate = false
    @State private var busy = false
    @State private var error = false
    @State private var deleting: CookingRecord?

    private var history: [CookingRecord] {
        store.cookingHistory.filter { $0.recipe_id == recipe.id }.sorted { $0.cooked_on > $1.cooked_on }
    }

    private var alreadyLoggedToday: Bool {
        history.contains { $0.cooked_on == BerlinDay.today() && $0.source == .manual }
    }

    var body: some View {
        RecipePanel("Kochhistorie") {
            if let latest = history.first {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Zuletzt am \(cookingDateLabel(latest.cooked_on))")
                    Spacer(minLength: 0)
                    Text("\(history.count)× gekocht").monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(Theme.recipeSecondary)
                DisclosureGroup("Alle Einträge") {
                    ForEach(history) { entry in historyRow(entry) }
                }
            } else {
                Text("Noch nie gekocht").foregroundStyle(Theme.recipeSecondary)
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                historyButton(
                    alreadyLoggedToday ? "Heute erfasst" : "Außerhalb des Plans gekocht",
                    icon: alreadyLoggedToday ? "checkmark.circle.fill" : "checkmark.circle",
                    active: !alreadyLoggedToday
                ) {
                    Task { await logToday() }
                }
                .disabled(alreadyLoggedToday)
                historyButton("Nachtragen", icon: "calendar.badge.plus", active: true) {
                    enteringDate = true
                }
            }
        }
        .disabled(busy)
        .sheet(isPresented: $enteringDate) {
            NavigationStack {
                CookingDateForm(title: recipe.title) { date, meal in
                    try await store.addCookingRecord(recipeID: recipe.id, day: date, servings: servings,
                                                     source: .backdated, meal: meal)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(\.colorScheme, sheetColorScheme)
            .tint(Theme.accent)
        }
        .confirmationDialog("Eintrag löschen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), presenting: deleting) { record in
            Button("Eintrag löschen", role: .destructive) {
                Task {
                    busy = true
                    defer { busy = false }
                    do { try await store.deleteCookingRecord(record) }
                    catch { self.error = true }
                }
            }
        }
        .alert("Die Kochhistorie konnte nicht geändert werden.", isPresented: $error) { Button("OK", role: .cancel) {} }
    }

    private func historyButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.body.weight(.semibold)).accessibilityHidden(true)
                Text(title).font(.footnote.weight(.semibold))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, 6)
            .foregroundStyle(active ? Color.white : Theme.recipeSecondary)
            .background(Theme.recipeHighlight, in: .rect(cornerRadius: Theme.radiusControl))
            .contentShape(.rect(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func historyRow(_ entry: CookingRecord) -> some View {
        let date = cookingDateLabel(entry.cooked_on)
        let cook = store.members.first { $0.id == entry.cook_id }?.name
        let portions = entry.servings.map { $0 == 1 ? "1 Portion" : "\($0) Portionen" }
        let details = [entry.meal?.label, entry.source.label, cook, portions].compactMap { $0 }.joined(separator: " · ")
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(date).font(.subheadline.weight(.semibold))
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 2)
            if entry.source != .plan {
                Button(role: .destructive) {
                    deleting = entry
                } label: {
                    Label("Eintrag vom \(date) löschen", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func logToday() async {
        guard !busy, !alreadyLoggedToday else { return }
        error = false
        busy = true
        defer { busy = false }
        do { try await store.addCookingRecord(recipeID: recipe.id, day: BerlinDay.today(), servings: servings, source: .manual) }
        catch { self.error = true }
    }
}

private struct CookingDateForm: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let save: (String, Meal) async throws -> Void
    @State private var date = BerlinDay.calendar.startOfDay(for: .now)
    @State private var meal: Meal = .dinner
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    dateOption("Heute", day: BerlinDay.today())
                    Divider().padding(.leading, 13)
                    dateOption("Gestern", day: BerlinDay.adding(-1, to: BerlinDay.today()))
                    Divider().padding(.leading, 13)
                    DatePicker("Datum wählen", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .environment(\.timeZone, BerlinDay.calendar.timeZone)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                        .font(.subheadline)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                }
                .gnCard(padding: 0, radius: Theme.radiusControl)
                MealChoiceGrid(selection: $meal)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await submit() }
            } label: {
                if busy { ProgressView().accessibilityLabel("Speichert …") }
                else { Text("Nachtragen") }
            }
            .buttonStyle(.ink)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)
            .background(Theme.paper)
        }
        .navigationTitle("Gekocht nachtragen")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).disabled(busy)
            }
        }
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .alert("Der Eintrag konnte nicht gespeichert werden.", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        }
    }

    private func dateOption(_ title: String, day: String) -> some View {
        let selected = BerlinDay.key(for: date) == day
        return Button {
            if let value = BerlinDay.date(for: day) { date = value }
        } label: {
            HStack {
                Label(title, systemImage: "calendar")
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func submit() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await save(BerlinDay.key(for: date), meal)
            dismiss()
        } catch {
            failed = true
        }
    }
}

func cookingDateLabel(_ day: String) -> String {
    guard let date = BerlinDay.date(for: day) else { return day }
    var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: "de_DE"))
    style.timeZone = BerlinDay.calendar.timeZone
    return date.formatted(style)
}
