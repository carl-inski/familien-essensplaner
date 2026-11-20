import CoreTransferable
import GnocchiCore
import Supabase
import SwiftUI
import UniformTypeIdentifiers

struct WeekView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var preferences
    let onAskAssistant: (MealSlot) -> Void
    @ScaledMetric(relativeTo: .subheadline) private var dayRingSize: CGFloat = 33
    @State private var today = BerlinDay.today()
    @State private var start = Self.monday(containing: BerlinDay.today())
    @State private var calendarTapCount = 0
    @State private var pendingScrollDay: String?
    @State private var slot: MealSlot?
    @State private var previewSlot: MealSlot?
    @State private var nextRecipe: Recipe?
    @State private var openedRecipe: Recipe?
    @State private var attendanceSlot: MealSlot?
    @State private var planningSlot: MealSlot?
    @State private var nextEditorSlot: MealSlot?
    @State private var nextEditorStartsWithRecipe = false
    @State private var editorStartsWithRecipe = false
    @State private var nextAssistantSlot: MealSlot?
    @State private var suggesting: MealSlot?
    @State private var noSuggestion = false
    @State private var slotChanged = false
    @State private var confirmedMealCount = 0
    @State private var moveInProgress = false
    @State private var moveConfirmation: PlannedMealMove?
    @State private var moveError: String?
    @State private var hoverWeekOffset: Int?
    @State private var calendarTop: CGFloat = 0
    @State private var accessibleMoveSlot: MealSlot?

    private var days: [String] { BerlinDay.days(from: start) }
    private var canNavigateWeeks: Bool { !store.saving && !moveInProgress && suggesting == nil }
    private var mealCounts: [String: Int] {
        guard store.weekStart == start else { return [:] }
        let end = BerlinDay.adding(6, to: start)
        return store.plan.reduce(into: [:]) { counts, entry in
            guard entry.date >= start, entry.date <= end,
                  entry.status != .cancelled, entry.recipeID != nil || entry.leftoverOf != nil else { return }
            counts[entry.date, default: 0] += 1
        }
    }

    var body: some View {
        let counts = mealCounts
        ScrollViewReader { scroll in
            let calendar = calendarStrip(counts: counts) { day in
                calendarTapCount += 1
                scrollToDay(day, using: scroll)
            } showToday: {
                let todayWeek = Self.monday(containing: today)
                if start == todayWeek, store.weekStart == todayWeek {
                    scrollToDay(today, using: scroll)
                } else {
                    pendingScrollDay = today
                    start = todayWeek
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    greeting.id("week-top")
                    calendar.hidden().accessibilityHidden(true)
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            max(0, geometry.frame(in: .named("week-scroll")).minY)
                        } action: { calendarTop = $0 }
                    if store.weekStart == start {
                        WeekFoodWidgets(start: start, plannedDays: counts.count,
                                        plannedMeals: counts.values.reduce(0, +))
                        ForEach(days, id: \.self) { day in
                            daySection(day).id(day)
                        }
                    } else {
                        ProgressView("Wochenplan wird geladen")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 20)
            }
            .coordinateSpace(.named("week-scroll"))
            .overlay(alignment: .top) {
                calendar
                    .padding(.horizontal, Theme.gutter)
                    .background(Theme.paper)
                    .offset(y: calendarTop)
            }
            .onChange(of: start) { scroll.scrollTo("week-top", anchor: .top) }
            .onChange(of: store.weekStart) {
                if store.weekStart == start, let day = pendingScrollDay {
                    pendingScrollDay = nil
                    scrollToDay(day, using: scroll)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 22).onEnded { drag in
                let x = drag.translation.width
                let y = drag.translation.height
                guard abs(x) > 70, abs(x) > abs(y) * 1.6 else { return }
                changeWeek(by: x < 0 ? 7 : -7)
            })
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .task(id: start) { await store.watchWeek(from: start) }
        .task {
            updateToday()
            while let midnight = BerlinDay.calendar.dateInterval(of: .day, for: .now)?.end {
                do { try await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSinceNow))) }
                catch { return }
                updateToday()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                let currentWeek = start
                updateToday()
                if start == currentWeek {
                    Task { await store.loadWeek(from: currentWeek) }
                }
            }
        }
        .refreshable { await store.loadWeek(from: start) }
        .sensoryFeedback(.success, trigger: confirmedMealCount) { _, _ in preferences.hapticsEnabled }
        .sensoryFeedback(.selection, trigger: calendarTapCount) { _, _ in preferences.hapticsEnabled }
        .alert("Kein passender Vorschlag", isPresented: $noSuggestion) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Für diese Mahlzeit ist gerade kein passendes Rezept verfügbar.")
        }
        .alert("Die Mahlzeit wurde inzwischen geändert.", isPresented: $slotChanged) {
            Button("OK", role: .cancel) {}
        }
        .task(id: hoverWeekOffset) {
            guard let offset = hoverWeekOffset else { return }
            do { try await Task.sleep(for: .milliseconds(650)) }
            catch { return }
            guard hoverWeekOffset == offset else { return }
            hoverWeekOffset = nil
            changeWeek(by: offset)
        }
        .confirmationDialog("Gerichte tauschen?", isPresented: Binding(
            get: { moveConfirmation != nil }, set: { if !$0 { moveConfirmation = nil } }
        ), titleVisibility: .visible, presenting: moveConfirmation) { proposal in
            Button("Gerichte tauschen") { Task { await commitMove(proposal) } }
        } message: { proposal in
            Text("Am \(shortDate(proposal.target.date)) ist für \(proposal.target.meal.label) schon ein Gericht eingeplant.")
        }
        .alert("Gericht verschieben", isPresented: Binding(
            get: { moveError != nil }, set: { if !$0 { moveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(moveError ?? "") }
        .sheet(item: $accessibleMoveSlot) { source in
            NavigationStack {
                MealChangeView(slot: source) { accessibleMoveSlot = nil }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $slot) { slot in
            NavigationStack {
                MealEditor(slot: slot, openRecipePicker: editorStartsWithRecipe)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $previewSlot, onDismiss: openDeferredAction) { target in
            NavigationStack {
                mealOverview(target)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: Binding(
            get: { openedRecipe != nil },
            set: { if !$0 { openedRecipe = nil } }
        )) {
            if let openedRecipe { RecipeDetailView(recipe: openedRecipe) }
        }
        .sheet(item: $attendanceSlot) { slot in
            NavigationStack {
                MealAttendanceSheet(slot: slot, day: shortDate(slot.date))
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $planningSlot, onDismiss: openDeferredAction) { target in
            NavigationStack {
                RecipeScheduleView(
                    fixedDay: target.date,
                    meal: target.meal,
                    onEdit: { nextEditorStartsWithRecipe = false; nextEditorSlot = $0 },
                    onAskAssistant: { nextAssistantSlot = $0 },
                    onSaved: { confirmedMealCount += 1 }
                )
            }
            .presentationDetents(RecipeScheduleView.detents(fixedDay: true))
            .presentationContentInteraction(.resizes)
            .presentationDragIndicator(.visible)
        }
    }

    private func openDeferredAction() {
        if let nextRecipe {
            self.nextRecipe = nil
            openedRecipe = nextRecipe
        }
        if let nextEditorSlot {
            self.nextEditorSlot = nil
            editorStartsWithRecipe = nextEditorStartsWithRecipe
            nextEditorStartsWithRecipe = false
            slot = nextEditorSlot
        }
        if let nextAssistantSlot {
            self.nextAssistantSlot = nil
            onAskAssistant(nextAssistantSlot)
        }
    }

    private func calendarStrip(
        counts: [String: Int], select: @escaping (String) -> Void, showToday: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                if let first = BerlinDay.date(for: start),
                   let last = days.last.flatMap(BerlinDay.date(for:)) {
                    Text(Self.weekDates.string(from: first, to: last))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 4)
                Button(action: showToday) {
                    Text("Heute")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.card, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(!canNavigateWeeks)
                weekButton("Vorherige Woche", icon: "chevron.left", offset: -7)
                weekButton("Nächste Woche", icon: "chevron.right", offset: 7)
            }
            ViewThatFits(in: .horizontal) {
                dayButtons(counts: counts, select: select)
                ScrollView(.horizontal) {
                    dayButtons(counts: counts, select: select)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func dayButtons(counts: [String: Int], select: @escaping (String) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { day in
                dayChip(day, count: counts[day, default: 0]) { select(day) }
            }
        }
    }

    private func weekButton(_ title: String, icon: String, offset: Int) -> some View {
        Button {
            changeWeek(by: offset)
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(hoverWeekOffset == offset ? Theme.blush : Theme.card).frame(width: 32, height: 32)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(title)
        .disabled(!canNavigateWeeks)
        .accessibilityHint("Gericht hier halten, um die Woche zu wechseln")
        .onDrop(of: [.json], delegate: WeekArrowDropDelegate { hovering in
            if hovering, canNavigateWeeks { hoverWeekOffset = offset }
            else if hoverWeekOffset == offset { hoverWeekOffset = nil }
        })
    }

    private func changeWeek(by offset: Int) {
        guard canNavigateWeeks else { return }
        pendingScrollDay = nil
        start = BerlinDay.adding(offset, to: start)
    }

    private func scrollToDay(_ day: String, using scroll: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : Theme.spring) {
            scroll.scrollTo(day, anchor: .center)
        }
    }

    private func updateToday() {
        let date = BerlinDay.today()
        let wasShowingCurrentWeek = start == Self.monday(containing: today)
        today = date
        if wasShowingCurrentWeek {
            start = Self.monday(containing: date)
        }
    }

    private static func monday(containing key: String) -> String {
        guard let date = BerlinDay.date(for: key),
              let monday = BerlinDay.calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return key }
        return BerlinDay.key(for: monday)
    }

    private var greeting: some View {
        let hour = BerlinDay.calendar.component(.hour, from: Date())
        let hello = (5..<11).contains(hour) ? "Guten Morgen" : (11..<17).contains(hour) ? "Hallo" : "Guten Abend"
        let name = store.members.first { $0.id == store.household?.memberID }?.name

        return Text(name.map { "\(hello), \($0)." } ?? "\(hello).")
            .font(Theme.display(34))
            .tracking(-0.6)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }

    private func dayChip(_ day: String, count: Int, select: @escaping () -> Void) -> some View {
        let date = BerlinDay.date(for: day)
        let isToday = day == today
        let style = Date.FormatStyle().locale(Locale(identifier: "de_DE")).configuredForBerlin
        let ringColor = isToday ? Theme.onInk : Theme.ink
        let weekday = date?.formatted(style.weekday(.abbreviated)).prefix(2) ?? ""

        return Button(action: select) {
            VStack(spacing: 5) {
                Text(weekday)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? Theme.onInk : Theme.inkSecondary)
                Text(date?.formatted(style.day()) ?? "")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ringColor)
                    .frame(width: dayRingSize, height: dayRingSize)
                    .background {
                        Circle()
                            .strokeBorder(ringColor.opacity(count > 0 ? 1 : 0.15), lineWidth: 2)
                    }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 44, maxWidth: .infinity)
            .background(isToday ? Theme.ink : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(store.weekStart != start)
        .accessibilityLabel(date?.formatted(style.weekday(.wide).day().month(.wide)) ?? day)
        .accessibilityValue(count == 1 ? "1 Mahlzeit geplant" : "\(count) Mahlzeiten geplant")
        .accessibilityHint(isToday ? "Heute" : "")
        .accessibilityAddTraits(isToday ? .isSelected : [])
        .dropDestination(for: PlannedMealDrag.self) { items, _ in
            guard let item = items.first else { return false }
            return acceptMealDrop(item, at: MealSlot(date: day, meal: item.slot.meal))
        }
    }

    private func daySection(_ day: String) -> some View {
        let meals = Planning.configuredMeals(on: day, plan: store.plan, attendance: store.attendance)
        let available = Meal.allCases.first { !meals.contains($0) }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(day == today ? "Heute, \(shortDate(day))" : shortDate(day))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 2)
                if let available, day >= today {
                    Button {
                        planningSlot = MealSlot(date: day, meal: available)
                    } label: {
                        Label("Mahlzeit hinzufügen", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .background {
                                Circle().fill(Theme.well).frame(width: 34, height: 34)
                            }
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Mahlzeit hinzufügen für \(shortDate(day))")
                    .disabled(store.saving || suggesting != nil)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
            .dropDestination(for: PlannedMealDrag.self) { items, _ in
                guard let item = items.first else { return false }
                return acceptMealDrop(item, at: MealSlot(date: day, meal: item.slot.meal))
            }

            if meals.isEmpty {
                Text("Noch nichts geplant")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gnCard(padding: 14, radius: Theme.radiusControl)
                    .dropDestination(for: PlannedMealDrag.self) { items, _ in
                        guard let item = items.first else { return false }
                        return acceptMealDrop(item, at: MealSlot(date: day, meal: item.slot.meal))
                    }
            } else {
                VStack(spacing: 0) {
                    ForEach(meals, id: \.self) { meal in
                        if meal != meals.first { Divider().padding(.leading, textSize.isAccessibilitySize ? 12 : 66) }
                        mealRow(MealSlot(date: day, meal: meal))
                    }
                }
                .gnCard(padding: 0, radius: Theme.radiusControl)
            }
        }
    }

    private func openMeal(_ target: MealSlot) {
        let entry = store.plan.first { $0.slot == target }
        let eaters = Planning.eaters(at: target, members: store.members, attendance: store.attendance, familyGuests: entry?.familyGuests)
        if let entry, entry.status != .cancelled, entry.recipeID != nil || entry.leftoverOf != nil {
            previewSlot = target
        } else if target.date >= today, eaters > 0, entry?.allowsSuggestion ?? true {
            planningSlot = target
        } else {
            editorStartsWithRecipe = false
            slot = target
        }
    }

    private func mealOverview(_ target: MealSlot) -> some View {
        PlannedMealOverview(slot: target, day: shortDate(target.date)) { recipe in
            nextRecipe = recipe
            previewSlot = nil
        } onEdit: {
            nextEditorStartsWithRecipe = true
            nextEditorSlot = target
            previewSlot = nil
        }
    }

    private static let weekDates: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = BerlinDay.calendar.timeZone
        formatter.dateTemplate = "dMMMy"
        return formatter
    }()

    private func mealRow(_ slot: MealSlot) -> some View {
        let entry = store.plan.first { $0.slot == slot }
        let recipe = store.recipeForMeal(recipeID: entry?.recipeID, leftoverOf: entry?.leftoverOf)
        let count = Planning.eaters(at: slot, members: store.members, attendance: store.attendance, familyGuests: entry?.familyGuests)
        let present = store.members.filter {
            Planning.effectiveStatus(for: $0, at: slot, attendance: store.attendance).status == .present
        }
        let cooks = store.members.filter { $0.id == entry?.cookID }
        let cookMissing = cooks.contains {
            Planning.effectiveStatus(for: $0, at: slot, attendance: store.attendance).status == .away
        }

        let canSuggest = slot.date >= BerlinDay.today() && count > 0 && (entry?.allowsSuggestion ?? true)
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            : AnyLayout(HStackLayout(spacing: 6))

        return layout {
            let mealButton = Button {
                openMeal(slot)
            } label: {
                HStack(spacing: 10) {
                    if !textSize.isAccessibilitySize {
                        mealThumbnail(for: slot.meal, recipe: entry?.status == .cancelled ? nil : recipe)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.meal.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Text(mealTitle(entry, recipe: recipe, people: count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(textSize.isAccessibilitySize ? nil : 2)
                        if entry?.status != .cancelled {
                            if let detail = mealDetail(recipe: recipe, leftoverOf: entry?.leftoverOf) {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                            }
                            if entry?.leftoverOf != nil || entry.map({ store.isMealPrepSource($0.id) }) == true {
                                Label(entry?.leftoverOf == nil ? "Meal Prep · Kochtag" : "Reste",
                                      systemImage: entry?.leftoverOf == nil ? "frying.pan" : "arrow.turn.down.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Theme.blush, in: .capsule)
                            }
                            if !cooks.isEmpty {
                                Label(cookMissing ? "Koch fehlt" : cooks.map(\.name).joined(separator: " und "),
                                      systemImage: cookMissing ? "exclamationmark.circle" : "person")
                                    .font(.caption2)
                                    .foregroundStyle(cookMissing ? Theme.accent : Theme.inkSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if entry?.status == .cooked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                            .accessibilityLabel("Gekocht")
                    } else if entry?.status == .planned, entry?.shoppedAt != nil {
                        Image(systemName: "basket.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.success)
                            .accessibilityLabel("Eingekauft")
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)

            if let entry, let family = store.household, slot.date >= today,
               entry.status == .planned, entry.recipeID != nil || entry.leftoverOf != nil {
                mealButton
                    .draggable(PlannedMealDrag(householdID: family.id, slot: slot, id: entry.id,
                                               recipeID: entry.recipeID, leftoverOf: entry.leftoverOf))
                    .accessibilityAction(named: Text("Gericht verschieben")) { accessibleMoveSlot = slot }
            } else {
                mealButton
            }

            HStack(spacing: 0) {
                if canSuggest {
                    Button {
                        Task { await suggest(at: slot) }
                    } label: {
                        suggestionLabel(for: slot)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(suggesting != nil || store.saving)
                    .accessibilityLabel("Gericht für \(shortDate(slot.date)) \(slot.meal.label) vorschlagen")
                }
                attendanceButton(for: slot, count: count, present: present)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .dropDestination(for: PlannedMealDrag.self) { items, _ in
            guard let item = items.first else { return false }
            return acceptMealDrop(item, at: slot)
        }
    }

    private func acceptMealDrop(_ item: PlannedMealDrag, at target: MealSlot) -> Bool {
        guard !moveInProgress, !store.saving, moveConfirmation == nil,
              item.householdID == store.household?.id, item.slot != target else { return false }
        hoverWeekOffset = nil
        if target.date < BerlinDay.today() {
            moveError = "In die Vergangenheit lässt sich kein Gericht verschieben."
            return false
        }
        moveInProgress = true
        Task {
            defer { moveInProgress = false }
            do {
                let proposal = try await store.prepareMealMove(from: item.slot, to: target, expectedID: item.id,
                                                               recipeID: item.recipeID, leftoverOf: item.leftoverOf)
                if proposal.needsConfirmation { moveConfirmation = proposal }
                else { try await store.movePlannedMeal(proposal); confirmedMealCount += 1 }
            } catch let error as PostgrestError {
                moveError = error.message
            } catch {
                moveError = error.localizedDescription
            }
        }
        return true
    }

    private func commitMove(_ proposal: PlannedMealMove) async {
        guard !moveInProgress else { return }
        moveInProgress = true
        defer { moveInProgress = false }
        do {
            try await store.movePlannedMeal(proposal)
            confirmedMealCount += 1
        } catch let error as PostgrestError {
            moveError = error.message
        } catch {
            moveError = error.localizedDescription
        }
    }

    private func mealTitle(_ entry: MealPlanEntry?, recipe: Recipe?, people: Int) -> String {
        if entry?.status == .cancelled {
            return entry?.note.flatMap { $0.isEmpty ? nil : "Fällt aus · \($0)" } ?? "Fällt aus"
        }
        if let recipe {
            return recipe.title
        }
        if entry?.leftoverOf != nil { return "Reste" }
        if entry?.recipeID != nil { return "Gericht eingeplant" }
        if let note = entry?.note, !note.isEmpty { return note }
        return people == 0 ? "Niemand da" : "Gericht planen"
    }

    private func mealThumbnail(for meal: Meal, recipe: Recipe?) -> some View {
        CatalogImage(url: recipe?.imageURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Theme.well.overlay {
                Image(systemName: meal.icon)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(width: 48, height: 64)
        .clipShape(.rect(cornerRadius: Theme.radiusControl / 2))
        .accessibilityHidden(true)
    }

    private func attendanceButton(for slot: MealSlot, count: Int, present: [Member]) -> some View {
        Button {
            attendanceSlot = slot
        } label: {
            HStack(spacing: 4) {
                if present.isEmpty {
                    Image(systemName: "person.2").accessibilityHidden(true)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(19), spacing: 1), count: min(5, present.count)),
                              alignment: .trailing, spacing: 2) {
                        ForEach(present) { member in
                            MealMemberAvatar(member: member, size: 19)
                        }
                    }
                    .frame(width: CGFloat(min(5, present.count) * 20 - 1))
                }
                Text(count, format: .number).monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Anwesenheit für \(shortDate(slot.date)) \(slot.meal.label)")
        .accessibilityValue(attendanceDescription(count: count, present: present))
    }

    private func mealDetail(recipe: Recipe?, leftoverOf: String?) -> String? {
        if let leftoverOf {
            guard let source = store.leftoverSource(leftoverOf) else { return nil }
            let day = source.date == BerlinDay.today() ? "heute" : shortDate(source.date)
            return "Von \(day) · \(source.meal.label)"
        }
        if let recipe, let book = store.cookbooks.first(where: { $0.id == recipe.cookbookID }) {
            return recipe.cookbookPage.map { "\(book.title), S. \($0)" } ?? book.title
        }
        return recipe?.timeText
    }

    private func attendanceDescription(count: Int, present: [Member]) -> String {
        let total = count == 1 ? "1 Person isst mit" : "\(count) Personen essen mit"
        guard !present.isEmpty else { return total }
        return "\(total). \(present.map(\.name).formatted(.list(type: .and)))"
    }

    @ViewBuilder
    private func suggestionLabel(for slot: MealSlot) -> some View {
        if textSize.isAccessibilitySize {
            if suggesting == slot {
                ProgressView("Vorschlag wird gesucht")
            } else {
                Label("Gericht vorschlagen", systemImage: "sparkles")
                    .multilineTextAlignment(.leading)
            }
        } else if suggesting == slot {
            ProgressView()
        } else {
            Image(systemName: "sparkles")
        }
    }

    private func suggest(at target: MealSlot) async {
        guard suggesting == nil, !store.saving, store.weekStart == start else { return }
        let requestedStart = start
        suggesting = target
        defer { suggesting = nil }
        guard let recipe = store.suggestedRecipe(at: target) else {
            noSuggestion = true
            return
        }
        if await store.saveMeal(at: target, changes: ["recipe_id": .string(recipe.id), "shopped_at": .null], condition: .unplanned) {
            confirmedMealCount += 1
            await store.recordMealSuggestion(recipeID: recipe.id, slot: target)
        } else if requestedStart == start, store.plan.first(where: { $0.slot == target })?.allowsSuggestion == false {
            slotChanged = true
        }
    }

    private func shortDate(_ key: String) -> String {
        guard let day = BerlinDay.date(for: key) else { return key }
        return day.formatted(
            Date.FormatStyle()
                .weekday(.wide).day().month(.abbreviated)
                .locale(Locale(identifier: "de_DE"))
                .configuredForBerlin
        )
    }
}

struct MealMemberAvatar: View {
    let member: Member
    let size: CGFloat

    var body: some View {
        AsyncImage(url: member.avatarURL.flatMap { URL(string: $0) }) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                let initials = member.name.split(whereSeparator: \.isWhitespace).prefix(2)
                    .compactMap(\.first).map(String.init).joined().uppercased()
                Color.accentColor.opacity(0.13).background(.background).overlay {
                    if initials.isEmpty {
                        Image(systemName: "person.fill")
                    } else {
                        Text(initials)
                    }
                }
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.background, lineWidth: 1.5) }
        .accessibilityHidden(true)
    }
}

private struct MealAttendanceSheet: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let slot: MealSlot
    let day: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(day) · \(slot.meal.label)")
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                MealAttendanceControls(slot: slot)
                    .gnCard(padding: 14)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 8)
        }
        .navigationTitle("Wer isst mit?")
        .gnScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig", systemImage: "checkmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .disabled(store.saving)
            }
        }
        .interactiveDismissDisabled(store.saving)
    }
}

struct MealAttendanceControls: View {
    @Environment(HouseholdStore.self) private var store
    let slot: MealSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MealProfileChoices(actionName: "Teilnahme", isSelected: { member in
                Planning.effectiveStatus(for: member, at: slot, attendance: store.attendance).status == .present
            }) { member in
                Task { await store.toggleAttendance(for: member, at: slot) }
            }
            Divider()
            let count = store.familyGuestCount(at: slot)
            Stepper(value: Binding(
                get: { store.familyGuestCount(at: slot) },
                set: { count in Task { await store.setFamilyGuestCount(count, at: slot) } }
            ), in: 0...max(99, count)) {
                LabeledContent("Gäste", value: String(count))
            }
            .accessibilityLabel("Gäste")
            .accessibilityValue(String(count))
        }
        .disabled(store.saving)
    }
}

private struct MealProfileChoices: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    let actionName: String
    let isSelected: (Member) -> Bool
    let action: (Member) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 100 : 62), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(store.members) { member in
                let selected = isSelected(member)
                Button { action(member) } label: {
                    VStack(spacing: 4) {
                        MealMemberAvatar(member: member, size: 42)
                            .padding(3)
                            .overlay { Circle().strokeBorder(selected ? Theme.success : Theme.hairline, lineWidth: 2) }
                            .overlay(alignment: .bottomTrailing) {
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Theme.success)
                                        .background(Theme.card, in: .circle)
                                        .accessibilityHidden(true)
                                }
                            }
                        Text(member.name).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(actionName): \(member.name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private struct PlannedMealOverview: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    let slot: MealSlot
    let day: String
    let onRecipe: (Recipe) -> Void
    let onEdit: () -> Void
    @State private var error: String?
    @State private var confirmingRemoval = false

    private var entry: MealPlanEntry? { store.plan.first { $0.slot == slot } }
    private var recipe: Recipe? { store.recipeForMeal(recipeID: entry?.recipeID, leftoverOf: entry?.leftoverOf) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let recipe {
                    Button { onRecipe(recipe) } label: {
                        Label("Rezept öffnen", systemImage: "book")
                    }
                    .buttonStyle(.ink)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wer isst mit?").font(.headline)
                    MealAttendanceControls(slot: slot)
                }
                .gnCard(padding: 14)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kochdienst").font(.headline)
                    MealProfileChoices(actionName: "Kochdienst", isSelected: { $0.id == entry?.cookID }) { member in
                        Task { await saveCook(member) }
                    }
                }
                .gnCard(padding: 14)
                Button(action: onEdit) { Label("Gericht ändern", systemImage: "pencil") }
                    .buttonStyle(.soft)
                Button("Gericht entfernen", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .disabled(store.saving)
        .navigationTitle(slot.meal.fullLabel)
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig", systemImage: "checkmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .disabled(store.saving)
            }
        }
        .interactiveDismissDisabled(store.saving)
        .confirmationDialog("Gericht aus dem Wochenplan entfernen?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Gericht entfernen", role: .destructive) { Task { await remove() } }
        }
        .alert("Mahlzeit", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            CatalogImage(url: recipe?.imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.well.overlay { Image(systemName: slot.meal.icon).foregroundStyle(Theme.inkSecondary) }
            }
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.map { entry?.leftoverOf == nil ? $0.title : "Reste von \($0.title)" } ?? "Gericht eingeplant")
                    .font(.headline)
                Text(day).font(.caption).foregroundStyle(Theme.inkSecondary)
                if let note = entry?.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private func saveCook(_ member: Member) async {
        guard !store.saving, let expected = entry else { return }
        let cookID = member.id == expected.cookID ? nil : member.id
        if !(await store.saveMeal(at: slot, changes: ["cook_id": cookID.map(AnyJSON.string) ?? .null, "cook2_id": .null],
                                 condition: .unchanged(expected, includingDetails: true))) {
            showSaveError()
        }
    }

    private func remove() async {
        guard let expected = entry, !store.saving else { return }
        do {
            try await store.clearPlannedMeal(expected)
            dismiss()
        } catch let failure as PostgrestError {
            error = failure.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func showSaveError() {
        error = store.error ?? "Die Mahlzeit wurde inzwischen geändert. Bitte öffne sie erneut."
        store.error = nil
    }
}

private struct WeekArrowDropDelegate: DropDelegate {
    let onHover: (Bool) -> Void

    func dropEntered(info: DropInfo) { onHover(true) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { onHover(false) }

    func performDrop(info: DropInfo) -> Bool {
        onHover(false)
        return false
    }
}

private struct PlannedMealDrag: Codable, Transferable {
    let householdID: String
    let slot: MealSlot
    let id: String
    let recipeID: String?
    let leftoverOf: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json).visibility(.ownProcess)
    }
}

private extension Date.FormatStyle {
    var configuredForBerlin: Self {
        var style = self
        style.timeZone = BerlinDay.calendar.timeZone
        return style
    }
}

extension Meal {
    var label: String {
        switch self {
        case .breakfast: "Frühstück"
        case .lunch: "Mittag"
        case .dinner: "Abend"
        case .snack: "Snack"
        }
    }

    var fullLabel: String {
        switch self {
        case .lunch: "Mittagessen"
        case .dinner: "Abendessen"
        case .breakfast, .snack: label
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }
}

extension PlanStatus {
    var label: String {
        switch self {
        case .planned: "Geplant"
        case .cooked: "Gekocht"
        case .cancelled: "Ausgefallen"
        }
    }
}
