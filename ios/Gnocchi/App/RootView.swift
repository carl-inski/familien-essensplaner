import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var onboardingFinished = OnboardingState.finished
    @State private var startRegistering = false

    var body: some View {
        switch session.state {
        case .loading:
            AppLoadingView(label: "Gnocchi lädt")
        case .signedOut:
            // Wer über einen Einladungslink kommt, soll direkt zum Konto
            if onboardingFinished || session.inviteCode != nil {
                LoginView(startRegistering: startRegistering)
                    .transition(.opacity)
            } else {
                OnboardingFlow { register in
                    startRegistering = register
                    withAnimation(Theme.spring) { onboardingFinished = true }
                }
            }
        case let .signedIn(id, email):
            if session.recovering {
                NavigationStack { PasswordForm(recovery: true) }
            } else {
                HouseholdTabs(email: email).id(id)
            }
        }
    }
}

struct HouseholdTabs: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: HouseholdStore
    let email: String

    init(email: String, store: HouseholdStore = HouseholdStore()) {
        self.email = email
        _store = State(initialValue: store)
    }

    var body: some View {
        Group {
            if !store.loaded && (store.loading || !store.loadAttempted) {
                AppLoadingView(label: "Familie wird geladen")
            } else if let household = store.household {
                FamilyNavigation(email: email)
                    .id(household.memberID)
                    .task(id: household.id) { await store.watchCookingHistory() }
                    .task(id: scenePhase) {
                        if scenePhase == .active { await store.refreshCookingHistory() }
                    }
            } else if store.loaded && store.memberships.isEmpty {
                FamilyOnboarding(email: email)
            } else {
                NavigationStack {
                    AccountView(email: email)
                }
            }
        }
        .environment(store)
        .task(id: scenePhase) {
            if scenePhase == .active { await store.load() }
        }
        .sheet(isPresented: Binding(
            get: { session.inviteCode != nil && store.loaded },
            set: { if !$0 { session.inviteCode = nil } }
        )) {
            NavigationStack { FamilyForm(creating: false, initialCode: session.inviteCode ?? "") }
                .presentationDragIndicator(.visible)
        }
        .alert("Gnocchi", isPresented: Binding(
            get: { store.error != nil },
            set: { if !$0 { store.error = nil } }
        )) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }
}

private struct FamilyOnboarding: View {
    @Environment(SessionStore.self) private var session
    @Environment(HouseholdStore.self) private var store
    let email: String
    @State private var action: FamilyAction?

    private enum FamilyAction: String, Identifiable {
        case create, join
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mit wem sitzt du am Tisch?")
                            .font(Theme.display(32))
                            .tracking(-0.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Wochenplan, Rezepte und Einkaufsliste gehören einer Familie. Lege eine an oder tritt einer bei.")
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        step("checkmark.circle.fill", "Konto erstellt", done: true)
                        Divider().padding(.leading, 42)
                        step("person.2", "Familie anlegen oder beitreten", done: false)
                        Divider().padding(.leading, 42)
                        step("fork.knife", "Erstes Gericht einplanen", done: false)
                    }
                    .gnCard(padding: 16)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 10) {
                createButton.buttonStyle(.ink)
                joinButton.buttonStyle(.soft)
                HStack(spacing: 6) {
                    if !email.isEmpty {
                        Text(email).foregroundStyle(Theme.inkSecondary).lineLimit(1).truncationMode(.middle)
                    }
                    Button("Abmelden") { Task { await session.signOut() } }
                        .disabled(store.isDemo)
                }
                .font(.footnote)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background { PaperBackground() }
        .sheet(item: $action) { action in
            NavigationStack { FamilyForm(creating: action == .create) }
                .presentationDragIndicator(.visible)
        }
    }

    private func step(_ symbol: String, _ text: String, done: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(done ? Theme.success : Theme.inkSecondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body.weight(done ? .regular : .medium))
                .foregroundStyle(done ? Theme.inkSecondary : Theme.ink)
                .strikethrough(done, color: Theme.inkSecondary)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Erledigt" : "Offen")
    }

    private var createButton: some View {
        Button { action = .create } label: {
            Label("Familie anlegen", systemImage: "person.2.badge.plus")
        }
    }

    private var joinButton: some View {
        Button { action = .join } label: {
            Label("Einladungscode eingeben", systemImage: "key")
        }
    }
}

private struct FamilyNavigation: View {
    private enum QuickAdd: String, Identifiable {
        case meal, recipe, ingredient
        var id: Self { self }

        var label: String {
            switch self {
            case .meal: "Gericht einplanen"
            case .recipe: "Rezept hinzufügen"
            case .ingredient: "Artikel hinzufügen"
            }
        }
    }

    private enum Destination: Hashable {
        case week, recipes, shopping, games, quickAction

        static let mainTabs: [Self] = [.week, .recipes, .shopping, .games]

        var title: String {
            switch self {
            case .week: "Woche"
            case .recipes: "Rezepte"
            case .shopping: "Einkauf"
            case .games: "Spielen"
            case .quickAction: "KI"
            }
        }

        var iconAsset: String {
            switch self {
            case .week: "GnocchiTabWeek"
            case .recipes: "GnocchiTabRecipes"
            case .shopping: "GnocchiTabShopping"
            case .games: "GnocchiTabGames"
            case .quickAction: "GnocchiActionAssistant"
            }
        }
    }

    let email: String
    @Environment(HouseholdStore.self) private var household
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var keyboardVisible = false
    @State private var assistant = AssistantStore()
    @State private var assistantDraft = AssistantDraft()
    @State private var shopping = ShoppingStore()
    @State private var decide = DecideStore()
    @State private var selectedTab: Destination = .week
    @State private var dismissedInvitation: String?
    @State private var prefersQuickAdd = true
    @State private var presentedQuickAdd: QuickAdd?
    @State private var showingAssistant = false
    @State private var showingQuickActionOptions = false
    @State private var navigationChrome = NavigationChrome()
    @State private var iconProgress: CGFloat = 0
    @State private var iconDirection: CGFloat = 1
    @State private var incomingPlus = false
    @State private var iconTransition = 0

    private var quickAdd: QuickAdd? {
        switch selectedTab {
        case .week: .meal
        case .recipes: .recipe
        case .shopping: .ingredient
        case .games, .quickAction: nil
        }
    }

    private var addsCookbook: Bool { selectedTab == .recipes && navigationChrome.addCookbook != nil }
    private var canSwapQuickAction: Bool { quickAdd != nil && !addsCookbook }
    private var showsQuickAdd: Bool { addsCookbook || (quickAdd != nil && prefersQuickAdd) }

    private var usesTrailingTab: Bool {
        if #available(iOS 26, *) { return horizontalSizeClass == .compact }
        return false
    }

    private var showsTrailingQuickAction: Bool {
        usesTrailingTab && !navigationChrome.actionsSuppressed && !keyboardVisible
    }

    private var tabSelection: Binding<Destination> {
        Binding(get: { selectedTab }, set: { destination in
            if destination == .quickAction {
                if canSwapQuickAction && (UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning) {
                    showingQuickActionOptions = true
                } else {
                    openQuickAction()
                }
            } else {
                selectedTab = destination
            }
        })
    }

    private var invitation: GameSession? {
        guard let memberID = household.household?.memberID,
              let lobby = decide.invitation(for: memberID),
              dismissedInvitation != lobby.id else { return nil }
        if selectedTab == .games, decide.session?.id == lobby.id { return nil }
        return lobby
    }

    var body: some View {
        tabs
        .sheet(item: $presentedQuickAdd) { action in
            NavigationStack {
                switch action {
                case .meal: RecipeScheduleView()
                case .recipe: RecipeAddSheet()
                case .ingredient: ShoppingAddArticleSheet()
                }
            }
            .presentationDetents(action == .meal ? RecipeScheduleView.detents() : action == .recipe ? [.medium] : [.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.resizes)
        }
        .fullScreenCover(isPresented: $showingAssistant) {
            NavigationStack {
                AssistantView(store: assistant, accountEmail: email, draft: assistantDraft)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("KI schließen", systemImage: "xmark") { showingAssistant = false }
                                .labelStyle(.iconOnly)
                        }
                    }
            }
        }
        .confirmationDialog("Schnellaktion", isPresented: $showingQuickActionOptions) {
            Button(quickActionTitle) { openQuickAction() }
            Button(quickActionSwitchTitle) { toggleQuickAction() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .environment(assistant)
        .environment(shopping)
        .environment(decide)
        .environment(navigationChrome)
        .task(id: scenePhase) {
            guard scenePhase == .active, let family = household.household else { return }
            await decide.follow(family: family, demo: household.isDemo)
        }
        .task(id: household.household?.memberID) {
            if let family = household.household, !household.isDemo {
                shopping.restoreLocalChanges(for: family)
            }
        }
        .task(id: scenePhase == .active && shopping.hasPendingPurchases) {
            guard scenePhase == .active, shopping.hasPendingPurchases,
                  let family = household.household, !household.isDemo else { return }
            while shopping.hasPendingPurchases, !Task.isCancelled {
                await shopping.syncPurchases(family: family)
                guard shopping.hasPendingPurchases else { break }
                do { try await Task.sleep(for: .seconds(8)) }
                catch { break }
            }
        }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 26, *) {
            modernTabs
                .tabBarMinimizeBehavior(.never)
                .overlay(alignment: .bottomTrailing) {
                    if showsTrailingQuickAction {
                        quickActionButton
                            .frame(width: 64, height: 60)
                            // The compact system tab sits just below the content safe area.
                            .padding(.trailing, Theme.gutter)
                            .offset(y: 12)
                    }
                }
        } else if #available(iOS 18, *) {
            modernTabs
        } else {
            TabView(selection: $selectedTab) {
                ForEach(Destination.mainTabs, id: \.self) { destination in
                    tabRoot(destination)
                        .tabItem { tabLabel(destination) }
                        .badge(destination == .games && invitation != nil ? 1 : 0)
                        .tag(destination)
                }
            }
            .tint(Theme.ink)
        }
    }

    @available(iOS 18, *)
    private var modernTabs: some View {
        TabView(selection: tabSelection) {
            ForEach(Destination.mainTabs, id: \.self) { destination in
                Tab(value: destination) {
                    tabRoot(destination)
                } label: {
                    tabLabel(destination)
                }
                .badge(destination == .games && invitation != nil ? 1 : 0)
            }
            if usesTrailingTab {
                if #available(iOS 27, *) {
                    trailingTab(role: .prominent)
                } else {
                    trailingTab(role: .search)
                }
            }
        }
        .tint(Theme.ink)
    }

    @available(iOS 18, *)
    private func trailingTab(role: TabRole) -> some TabContent<Destination> {
        Tab(value: .quickAction, role: role) {
            Color.clear
        } label: {
            Label(quickActionTitle, image: quickActionAsset)
        }
    }

    private func tabLabel(_ destination: Destination) -> some View {
        Label {
            Text(destination.title)
        } icon: {
            if let source = UIImage(named: destination.iconAsset) {
                Image(uiImage: source.withTintColor(
                    selectedTab == destination ? .label : .systemGray,
                    renderingMode: .alwaysOriginal
                ))
            }
        }
    }

    private func tabRoot(_ destination: Destination) -> some View {
        NavigationStack {
            tabContent(destination)
                .safeAreaInset(edge: .bottom, spacing: 0) { tabActions }
                .navigationActionSurface()
        }
        .tint(Theme.ink)
    }

    @ViewBuilder private func tabContent(_ destination: Destination) -> some View {
        switch destination {
        case .week:
            WeekView { slot in
                showingAssistant = true
                Task { await assistant.askAboutMeal(slot, demo: household.isDemo, recipes: household.recipes) }
            }
            .toolbar { accountButton }
        case .recipes:
            RecipesView(accountEmail: email)
        case .shopping:
            ShoppingView(accountEmail: email)
        case .games:
            DecideView()
                .toolbar { accountButton }
        case .quickAction:
            EmptyView()
        }
    }

    @ViewBuilder private var tabActions: some View {
        if !keyboardVisible, !usesTrailingTab || invitation != nil {
            HStack(spacing: 10) {
                if let invitation {
                    invitationBanner(invitation)
                        .background(Theme.card, in: Capsule())
                        .overlay { Capsule().strokeBorder(Theme.hairline).allowsHitTesting(false) }
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }
                Spacer(minLength: 0)
                if !usesTrailingTab { quickActionButton }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder private var quickActionButton: some View {
        let size: CGFloat = usesTrailingTab ? 62 : 58
        let button = Button {
            openQuickAction()
        } label: {
            ZStack {
                quickActionIcon(plus: !incomingPlus, entering: false)
                quickActionIcon(plus: incomingPlus, entering: true)
            }
            .onChange(of: showsQuickAdd, initial: true) { old, new in
                guard old != new else {
                    incomingPlus = new
                    iconProgress = 1
                    return
                }
                animateQuickAction(to: new)
            }
            .task(id: iconTransition) {
                guard iconProgress == 0 else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { iconProgress = 1 }
            }
            .accessibilityHidden(true)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.assistantButton, in: .circle)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.18))
                    .allowsHitTesting(false)
            }
            .contentShape(.circle)
        }
        .buttonStyle(PressScaleStyle())
        .highPriorityGesture(DragGesture(minimumDistance: 17, coordinateSpace: .global).onEnded { drag in
            guard abs(drag.translation.width) > 20, abs(drag.translation.width) > abs(drag.translation.height) else { return }
            iconDirection = drag.translation.width > 0 ? 1 : -1
            toggleQuickAction()
        })

        if usesTrailingTab {
            // Assistive technologies use the actual system tab in the same position.
            button.accessibilityRepresentation { EmptyView() }
        } else {
            button
                .accessibilityLabel(quickActionTitle)
                .accessibilityHint(canSwapQuickAction ? "Seitlich wischen, um die Aktion zu wechseln" : "")
                .accessibilityActions {
                    if canSwapQuickAction {
                        Button(quickActionSwitchTitle) { toggleQuickAction() }
                    }
                }
        }
    }

    private var quickActionTitle: String {
        if addsCookbook { return "Kochbuch hinzufügen" }
        return showsQuickAdd ? (quickAdd?.label ?? "Hinzufügen") : "KI"
    }

    private var quickActionAsset: String {
        showsQuickAdd ? "GnocchiActionPlus" : "GnocchiActionAssistant"
    }

    private var quickActionSwitchTitle: String {
        showsQuickAdd ? "Zu KI wechseln" : "Zu Plus wechseln"
    }

    private func quickActionIcon(plus: Bool, entering: Bool) -> some View {
        let progress = entering ? 1 - iconProgress : iconProgress
        return Image(plus ? "GnocchiActionPlus" : "GnocchiActionAssistant")
            .renderingMode(.template)
            .resizable().scaledToFit()
            .frame(width: 30, height: 30)
            .opacity(Double(1 - progress))
            .offset(x: reduceMotion ? 0 : (entering ? -1 : 1) * iconDirection * progress * 20)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double((entering ? -1 : 1) * iconDirection * progress * 32)))
            .scaleEffect(reduceMotion ? 1 : 1 - progress * 0.18)
    }

    private func animateQuickAction(to plus: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            incomingPlus = plus
            iconProgress = reduceMotion ? 1 : 0
        }
        iconTransition += 1
    }

    private func openQuickAction() {
        if selectedTab == .recipes, let add = navigationChrome.addCookbook { add() }
        else if showsQuickAdd { presentedQuickAdd = quickAdd }
        else { showingAssistant = true }
    }

    private func toggleQuickAction() {
        guard canSwapQuickAction else { return }
        prefersQuickAdd.toggle()
    }

    private func invitationBanner(_ invitation: GameSession) -> some View {
        let host = household.members.first { $0.id == invitation.created_by }?.name ?? "Familienmitglied"
        return GameInvitationBanner(host: host, session: invitation) {
            decide.openInvitation(invitation.id)
            selectedTab = .games
        } hide: {
            dismissedInvitation = invitation.id
        }
    }

    private var accountButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            AccountToolbarLink(email: email)
        }
    }
}

struct AccountToolbarLink: View {
    @Environment(NavigationChrome.self) private var chrome
    let email: String

    var body: some View {
        NavigationLink {
            AccountView(email: email)
        } label: {
            Label("Einstellungen", systemImage: "person.crop.circle")
        }
        .simultaneousGesture(TapGesture().onEnded { chrome.hideActions() })
    }
}

private struct GameInvitationBanner: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let host: String
    let session: GameSession
    let open: () -> Void
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: session.game.symbol).foregroundStyle(Color.accentColor)
                    if !textSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(host) lädt ein").font(.subheadline.weight(.semibold))
                            Text(session.game.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text("Mitspielen").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(host) lädt zu \(session.game.title) ein. Mitspielen.")
            Button(action: hide) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Einladung ausblenden")
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.trailing, 4)
    }
}
