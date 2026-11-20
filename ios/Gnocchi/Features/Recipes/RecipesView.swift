import CoreTransferable
import GnocchiCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecipesView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(NavigationChrome.self) private var navigationChrome
    let accountEmail: String
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var searchVisible = false
    @State private var filters = RecipeFilters()
    @State private var order = RecipeOrder.alphabetical
    @State private var filtering = false
    @State private var folderEditor: FolderRoute?
    @State private var searchResult: SearchResult?
    @State private var creating = false
    @State private var stackSource: Recipe?
    @State private var recipeAction: RecipeActionRequest?
    @State private var openedStackRecipe: Recipe?
    @State private var gridID = UUID()
    @AppStorage("gnocchi.recipeStacks") private var storedStacks = Data()
    @AppStorage("gnocchi.recipeFavorites") private var storedFavorites = Data()
    @Namespace private var zoom
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .footnote) private var filterRowHeight: CGFloat = 44

    /// Zwei Kacheln nebeneinander, bei sehr großer Schrift eine.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: textSize.isAccessibilitySize ? 1 : 2)
    }

    private struct FolderRoute: Identifiable {
        let id = UUID()
        let folder: RecipeFolder?
    }

    private struct SearchResult {
        let term: String
        let ids: Set<String>
    }

    private enum SearchScrollZone: Equatable, Sendable {
        case pulledDown, resting, pushedUp
    }

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var title: String {
        if filters.folder == RecipeFilters.unfiled { return "Ohne Ordner" }
        if filters.folder == RecipeFilters.favorites { return "Favoriten" }
        return store.folders.first { $0.id == filters.folder }?.name ?? "Rezepte"
    }

    private var familyStacks: [String: RecipeStacks] {
        (try? JSONDecoder().decode([String: RecipeStacks].self, from: storedStacks)) ?? [:]
    }

    private var familyFavorites: [String: Set<String>] {
        (try? JSONDecoder().decode([String: Set<String>].self, from: storedFavorites)) ?? [:]
    }

    private var favorites: Set<String> {
        store.household.flatMap { familyFavorites[$0.id] } ?? []
    }

    private var selectedFolderID: String? {
        store.folders.first { $0.id == filters.folder }?.id
    }

    private func toggleFavorite(_ recipe: Recipe) {
        guard let familyID = store.household?.id, store.recipes.contains(where: { $0.id == recipe.id }) else { return }
        var families = familyFavorites
        var favorites = families[familyID] ?? []
        if !favorites.insert(recipe.id).inserted { favorites.remove(recipe.id) }
        families[familyID] = favorites.isEmpty ? nil : favorites
        if let data = try? JSONEncoder().encode(families) { storedFavorites = data }
    }

    private func updateStacks(_ update: (inout RecipeStacks) -> Void) {
        guard let familyID = store.household?.id else { return }
        var households = familyStacks
        var stacks = households[familyID] ?? RecipeStacks()
        update(&stacks)
        stacks.retainRecipes(in: Set(store.recipes.map(\.id)))
        guard stacks != (households[familyID] ?? RecipeStacks()) else { return }
        households[familyID] = stacks.stacks.isEmpty ? nil : stacks
        if let data = try? JSONEncoder().encode(households) { storedStacks = data }
    }

    private var results: [Recipe] {
        let history = CookingSummary.from(store.cookingHistory)
        let today = BerlinDay.today()
        let local = Set(store.recipes.matching(term).map(\.id))
        let remote = searchResult?.term == term ? searchResult?.ids ?? [] : []
        let favoriteIDs = favorites
        let filtered = store.recipes.filter {
            (local.contains($0.id) || remote.contains($0.id))
                && filters.includes($0, cooked: history[$0.id], today: today)
                && (filters.folder != RecipeFilters.favorites || favoriteIDs.contains($0.id))
        }
        return order.sorted(filtered, history: history)
    }

    var body: some View {
        let results = self.results
        let stacks = store.household.flatMap { familyStacks[$0.id] } ?? RecipeStacks()
        let items = RecipeGridItem.grouped(results, by: stacks)
        recipeGrid(items, stacks: stacks)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .gnScreen()
            .navigationDestination(isPresented: Binding(
                get: { openedStackRecipe != nil },
                set: { if !$0 { openedStackRecipe = nil } }
            )) {
                if let recipe = openedStackRecipe {
                    RecipeDetailView(recipe: recipe).zoomDestination(id: recipe.id, in: zoom)
                }
            }
            .toolbar { recipeToolbar }
            .sheet(isPresented: $creating) {
                NavigationStack { RecipeAddSheet(folderID: selectedFolderID) }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $filtering) {
                NavigationStack { RecipeFilterView(filters: $filters, order: $order) }
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $folderEditor) { route in
                NavigationStack { FolderEditor(folder: route.folder) { filters.folder = $0 } }
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $stackSource) { source in
                NavigationStack {
                    RecipeStackPicker(source: source, stacks: stacks) { target in
                        guard store.recipes.contains(where: { $0.id == source.id }),
                              store.recipes.contains(where: { $0.id == target.id }) else { return }
                        updateStacks { $0.combine(source.id, with: target.id) }
                    }
                }
                .presentationDragIndicator(.visible)
            }
            .recipeActions($recipeAction)
            .onChange(of: store.recipes.map(\.id), initial: true) {
                if store.loaded { updateStacks { _ in } }
            }
            .onChange(of: store.household?.id) {
                gridID = UUID()
                query = ""
                filters = RecipeFilters()
                setSearchVisible(false)
            }
            .task(id: term) { await searchRemotely(for: term) }
            .refreshable {
                await store.load()
                await store.refreshCookingHistory()
            }
    }

    @ViewBuilder private var emptyResults: some View {
        if !term.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if filters.folder == RecipeFilters.favorites && favorites.isEmpty {
            ContentUnavailableView("Noch keine Favoriten", systemImage: "star",
                                   description: Text("Markiere ein Rezept mit dem Stern."))
        } else if filters != RecipeFilters() {
            ContentUnavailableView {
                Label("Keine passenden Rezepte", systemImage: "line.3.horizontal.decrease")
            } actions: {
                Button("Filter zurücksetzen") { filters = RecipeFilters() }
            }
        }
    }

    @ToolbarContentBuilder private var recipeToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
        }
        ToolbarItemGroup(placement: .topBarLeading) {
            NavigationLink {
                CookbookShelf()
            } label: {
                Label("Kochbuchregal", systemImage: "books.vertical")
            }
            NavigationLink {
                LongNotCookedView()
            } label: {
                Label("Lange nicht gegessen", systemImage: "clock.arrow.circlepath")
            }
            Menu {
                Picker("Ordner", selection: $filters.folder) {
                    Text("Alle Rezepte").tag(nil as String?)
                    Text("Favoriten").tag(Optional(RecipeFilters.favorites))
                    Text("Ohne Ordner").tag(Optional(RecipeFilters.unfiled))
                    ForEach(store.folders) { Text($0.label).tag(Optional($0.id)) }
                }
                Button("Neuer Ordner", systemImage: "folder.badge.plus") { folderEditor = FolderRoute(folder: nil) }
                if let folder = store.folders.first(where: { $0.id == filters.folder }) {
                    Button("Ordner bearbeiten", systemImage: "pencil") { folderEditor = FolderRoute(folder: folder) }
                }
            } label: {
                Label("Ordner", systemImage: filters.folder == nil ? "folder" : "folder.fill")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { filtering = true } label: {
                Label("Filter und Sortierung", systemImage: filters == RecipeFilters() ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            AccountToolbarLink(email: accountEmail)
        }
    }

    private func recipeGrid(_ items: [RecipeGridItem], stacks: RecipeStacks) -> some View {
        VStack(spacing: 0) {
            if searchVisible {
                VStack(alignment: .leading, spacing: 8) {
                    searchBar(close: closeSearch)
                    quickFilters
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ScrollView {
                recipeGridContent(items, stacks: stacks)
                    .onGeometryChange(for: SearchScrollZone.self) { geometry in
                        let offset = geometry.frame(in: .named("recipe-grid-scroll")).minY
                        if offset > 20 { return .pulledDown }
                        if offset < -38 { return .pushedUp }
                        return .resting
                    } action: { zone in
                        switch zone {
                        case .pulledDown: openSearch(focus: false)
                        case .pushedUp where !searchFocused: setSearchVisible(false)
                        case .pushedUp, .resting: break
                        }
                    }
            }
            .coordinateSpace(name: "recipe-grid-scroll")
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
        }
        .accessibilityAction(named: Text("Rezepte suchen")) {
            openSearch(focus: true)
        }
    }

    private func recipeGridContent(_ items: [RecipeGridItem], stacks: RecipeStacks) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.display(34))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 10)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                addRecipeTile
                ForEach(items) { item in
                    RecipeGridTile(
                        item: item, zoom: zoom, gridID: gridID,
                        favorites: favorites, toggleFavorite: toggleFavorite,
                        openStackRecipe: {
                            navigationChrome.hideActions()
                            openedStackRecipe = $0
                        },
                        dropRecipe: { dropRecipe($0, onto: item.id) }
                    ) { recipe in
                        RecipeActionMenu(url: recipe.sharingURL(), perform: {
                            recipeAction = RecipeActionRequest(recipe: recipe, action: $0)
                        }) {
                            stackOptions(for: recipe, stacks: stacks)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
            if items.isEmpty { emptyResults }
        }
    }

    private func searchBar(close: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityHidden(true)
            TextField("Rezepte suchen", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            Button("Suche schließen", systemImage: "xmark.circle.fill", action: close)
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.inkSecondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 13)
        .background(Theme.well, in: .capsule)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 5)
    }

    private var quickFilters: some View {
        let tags = Set(store.recipes.flatMap { $0.tags ?? [] }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return VStack(alignment: .leading, spacing: 6) {
            filterRow("Ordner") {
                HStack(spacing: 6) {
                    filterChip("Alle Ordner", icon: "folder", selected: filters.folder == nil) { filters.folder = nil }
                    filterChip("Favoriten", icon: "star", selected: filters.folder == RecipeFilters.favorites) {
                        filters.folder = RecipeFilters.favorites
                    }
                    ForEach(store.folders) { folder in
                        filterChip(folder.name, selected: filters.folder == folder.id) { filters.folder = folder.id }
                    }
                    filterChip("Ohne Ordner", selected: filters.folder == RecipeFilters.unfiled) {
                        filters.folder = RecipeFilters.unfiled
                    }
                }
            }
            filterRow("Tags") {
                HStack(spacing: 6) {
                    filterChip("Alle Tags", icon: "tag", selected: filters.tag == nil) { filters.tag = nil }
                    ForEach(tags, id: \.self) { tag in
                        filterChip(tag, selected: filters.tag == tag) {
                            filters.tag = filters.tag == tag ? nil : tag
                        }
                    }
                }
            }
        }
    }

    private func filterRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HorizontalRecipeFilters(content: content())
        .frame(height: max(44, filterRowHeight))
        .accessibilityLabel(label)
    }

    private func filterChip(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).accessibilityHidden(true) }
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 31)
            .foregroundStyle(selected ? Theme.onInk : Theme.ink)
            .background(selected ? Theme.ink : Theme.well, in: .capsule)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setSearchVisible(_ visible: Bool) {
        guard visible != searchVisible else { return }
        withAnimation(reduceMotion ? nil : Theme.press) { searchVisible = visible }
    }

    private func openSearch(focus: Bool) {
        setSearchVisible(true)
        if focus { searchFocused = true }
    }

    private func closeSearch() {
        searchFocused = false
        query = ""
        setSearchVisible(false)
    }

    private var addRecipeTile: some View {
        Button {
            creating = true
        } label: {
            ZStack {
                Color.clear.aspectRatio(0.75, contentMode: .fit)
                VStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(Theme.card, in: .circle)
                    Text("Rezept hinzufügen")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .background(Theme.well, in: .rect(cornerRadius: Theme.radiusCard))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.hairline)
            }
            .contentShape(.rect(cornerRadius: Theme.radiusCard))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Rezept hinzufügen")
    }

    private func dropRecipe(_ payload: RecipeTileDrag, onto targetID: RecipeGridItem.ID) -> Bool {
        guard payload.gridID == gridID, let familyID = store.household?.id else { return false }
        let stacks = familyStacks[familyID] ?? RecipeStacks()
        let visible = RecipeGridItem.grouped(results, by: stacks)
        guard let source = visible.first(where: { $0.recipes.contains { $0.id == payload.recipeID } }),
              let target = visible.first(where: { $0.id == targetID }),
              source.id != target.id else { return false }
        withAnimation(reduceMotion ? nil : Theme.spring) {
            updateStacks { $0.combine(payload.recipeID, with: target.recipe.id) }
        }
        return true
    }

    private func searchRemotely(for requested: String) async {
        searchResult = nil
        guard requested.count >= 2, !store.isDemo else { return }
        do {
            try await Task.sleep(for: .milliseconds(180))
            let ids = try await store.searchRecipeIDs(requested)
            if !Task.isCancelled { searchResult = SearchResult(term: requested, ids: ids) }
        } catch {
            // Die lokale Suche funktioniert auch ohne Verbindung.
        }
    }

    private func stackOptions(for recipe: Recipe, stacks: RecipeStacks) -> some View {
        let stack = stacks.containing(recipe.id)
        let canStack = store.recipes.count > (stack?.recipeIDs.count ?? 1)
        return Menu("Stapel", systemImage: "rectangle.stack") {
            Button(stack == nil ? "Rezept stapeln" : "Stapel erweitern", systemImage: "rectangle.stack.badge.plus") {
                stackSource = recipe
            }
            .disabled(!canStack)
            if let stack {
                Button("Rezept aus Stapel nehmen", systemImage: "rectangle.stack.badge.minus") {
                    updateStacks { $0.remove(recipe.id) }
                }
                if stack.recipeIDs.count > 2 {
                    Button("Stapel auflösen", systemImage: "square.on.square") {
                        updateStacks { $0.dissolve(containing: recipe.id) }
                    }
                }
            }
        }
        .disabled(!canStack && stack == nil)
    }
}

private struct HorizontalRecipeFilters<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> FilterController<Content> {
        FilterController(content: content)
    }

    func updateUIViewController(_ controller: FilterController<Content>, context: Context) {
        controller.host.rootView = content
    }

    final class FilterController<Row: View>: UIViewController {
        let host: UIHostingController<Row>

        init(content: Row) {
            host = UIHostingController(rootView: content)
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            let scroll = UIScrollView()
            scroll.backgroundColor = .clear
            scroll.bounces = false
            scroll.alwaysBounceVertical = false
            scroll.alwaysBounceHorizontal = false
            scroll.isDirectionalLockEnabled = true
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.contentInsetAdjustmentBehavior = .never
            view = scroll

            addChild(host)
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.sizingOptions = .intrinsicContentSize
            scroll.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: Theme.gutter),
                host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -Theme.gutter),
                host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                host.view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
            ])
            host.didMove(toParent: self)
        }
    }
}

private struct RecipeTileDrag: Codable, Transferable {
    let gridID: UUID
    let recipeID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json).visibility(.ownProcess)
    }
}

private struct RecipeStack: Codable, Equatable, Identifiable {
    let id: UUID
    var recipeIDs: [String]
}

private struct RecipeStacks: Codable, Equatable {
    private(set) var stacks: [RecipeStack] = []

    func containing(_ recipeID: String) -> RecipeStack? {
        stacks.first { $0.recipeIDs.contains(recipeID) }
    }

    mutating func combine(_ source: String, with target: String) {
        guard source != target else { return }
        let sourceIndex = stacks.firstIndex { $0.recipeIDs.contains(source) }
        let targetIndex = stacks.firstIndex { $0.recipeIDs.contains(target) }
        if let targetIndex {
            guard sourceIndex != targetIndex else { return }
            let added = sourceIndex.map { stacks[$0].recipeIDs } ?? [source]
            stacks[targetIndex].recipeIDs.append(contentsOf: added)
            if let sourceIndex { stacks.remove(at: sourceIndex) }
        } else if let sourceIndex {
            stacks[sourceIndex].recipeIDs.append(target)
        } else {
            stacks.append(RecipeStack(id: UUID(), recipeIDs: [source, target]))
        }
    }

    mutating func remove(_ recipeID: String) {
        guard let index = stacks.firstIndex(where: { $0.recipeIDs.contains(recipeID) }) else { return }
        stacks[index].recipeIDs.removeAll { $0 == recipeID }
        if stacks[index].recipeIDs.count < 2 { stacks.remove(at: index) }
    }

    mutating func dissolve(containing recipeID: String) {
        stacks.removeAll { $0.recipeIDs.contains(recipeID) }
    }

    mutating func retainRecipes(in recipeIDs: Set<String>) {
        for index in stacks.indices {
            stacks[index].recipeIDs.removeAll { !recipeIDs.contains($0) }
        }
        stacks.removeAll { $0.recipeIDs.count < 2 }
    }
}

private struct RecipeGridItem: Identifiable {
    enum ID: Hashable {
        case single(String)
        case stack(UUID)
    }

    let id: ID
    let recipe: Recipe
    var otherRecipes: [Recipe] = []
    var recipes: [Recipe] { [recipe] + otherRecipes }

    static func grouped(_ recipes: [Recipe], by stacks: RecipeStacks) -> [Self] {
        let recipesByID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var stacksByRecipe: [String: RecipeStack] = [:]
        for stack in stacks.stacks {
            for id in stack.recipeIDs { stacksByRecipe[id] = stack }
        }
        var placed = Set<UUID>()
        return recipes.compactMap { recipe in
            guard let stack = stacksByRecipe[recipe.id] else {
                return Self(id: .single(recipe.id), recipe: recipe)
            }
            guard placed.insert(stack.id).inserted else { return nil }
            let visible = stack.recipeIDs.compactMap { recipesByID[$0] }
            guard let first = visible.first else { return nil }
            return Self(id: .stack(stack.id), recipe: first, otherRecipes: Array(visible.dropFirst()))
        }
    }
}

private struct RecipeStackPicker: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let source: Recipe
    let stacks: RecipeStacks
    let onChoose: (Recipe) -> Void

    var body: some View {
        let sourceStack = stacks.containing(source.id)
        let excluded = Set(sourceStack?.recipeIDs ?? [source.id])
        let available = store.recipes.filter { !excluded.contains($0.id) }
        let matched = Set(available.matching(query).map(\.id))
        let choices = RecipeGridItem.grouped(available, by: stacks)
            .filter { $0.recipes.contains { matched.contains($0.id) } }
        List {
            Section {
                ForEach(choices) { choice in
                    let recipe = choice.recipes.first { matched.contains($0.id) } ?? choice.recipe
                    Button {
                        onChoose(recipe)
                        dismiss()
                    } label: {
                        RecipeRow(recipe: recipe, detail: choice.otherRecipes.isEmpty ? nil : "Stapel · \(choice.recipes.count) Rezepte")
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Mit „\(source.title)“ stapeln")
                    .textCase(nil)
            }
        }
        .overlay {
            if choices.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Keine weiteren Rezepte", systemImage: "rectangle.stack")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, prompt: "Rezept oder Stapel suchen")
        .navigationTitle(sourceStack == nil ? "Rezepte stapeln" : "Stapel erweitern")
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
        }
    }
}

@available(iOS 18, *)
private struct RecipeStackPan: UIGestureRecognizerRepresentable {
    let onPan: (UIPanGestureRecognizer) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> DirectionDelegate { DirectionDelegate() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        onPan(recognizer)
    }

    final class DirectionDelegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: nil)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}

private struct RecipeGridTile<Options: View>: View {
    @Environment(NavigationChrome.self) private var navigationChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var activeID: String?
    @State private var isDropTarget = false
    @State private var panOffset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0
    let item: RecipeGridItem
    let zoom: Namespace.ID
    let gridID: UUID
    let favorites: Set<String>
    let toggleFavorite: (Recipe) -> Void
    let openStackRecipe: (Recipe) -> Void
    let dropRecipe: (RecipeTileDrag) -> Bool
    @ViewBuilder let options: (Recipe) -> Options

    private var index: Int { item.recipes.firstIndex { $0.id == activeID } ?? 0 }
    private var isStack: Bool { !item.otherRecipes.isEmpty }

    var body: some View {
        let recipe = item.recipes[index]
        Group {
            if isStack {
                swipeableTile(for: recipe)
                    .offset(x: reduceMotion ? 0 : panOffset + dragOffset)
                    .background {
                        stackBacks
                    }
                    .overlay(alignment: .topTrailing) {
                        Button { cycle(by: 1) } label: {
                            Label("\(index + 1)/\(item.recipes.count)", systemImage: "rectangle.stack")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background {
                                    Capsule().fill(.black.opacity(reduceTransparency ? 1 : 0.7))
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Nächstes Rezept im Stapel")
                        .accessibilityValue("Rezept \(index + 1) von \(item.recipes.count)")
                        .padding(.trailing, 5)
                    }
                    .padding(.bottom, 8)
            } else {
                link(to: recipe)
            }
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .strokeBorder(.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .dropDestination(for: RecipeTileDrag.self) { items, _ in
            guard items.count == 1, let payload = items.first else { return false }
            return dropRecipe(payload)
        } isTargeted: {
            isDropTarget = $0
        }
        .overlay(alignment: .topLeading) { favoriteButton(recipe) }
        .sensoryFeedback(.selection, trigger: activeID)
    }

    private func favoriteButton(_ recipe: Recipe) -> some View {
        let selected = favorites.contains(recipe.id)
        return Button {
            toggleFavorite(recipe)
        } label: {
            Image(systemName: selected ? "star.fill" : "star")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(reduceTransparency ? 1 : 0.68), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel(selected ? "\(recipe.title) aus Favoriten entfernen" : "\(recipe.title) als Favorit markieren")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func link(to recipe: Recipe) -> some View {
        NavigationLink {
            RecipeDetailView(recipe: recipe)
                .zoomDestination(id: recipe.id, in: zoom)
        } label: {
            RecipeTile(recipe: recipe)
                .zoomSource(id: recipe.id, in: zoom)
                .id(recipe.id)
                .transition(.opacity)
                .draggable(RecipeTileDrag(gridID: gridID, recipeID: recipe.id))
        }
        .buttonStyle(PressScaleStyle())
        .simultaneousGesture(TapGesture().onEnded { navigationChrome.hideActions() })
        .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.radiusCard))
        .contextMenu { options(recipe) }
        .menuOrder(.fixed)
    }

    private func swipeableTile(for recipe: Recipe) -> some View {
        stackSwipe(on: RecipeTile(recipe: recipe)
            .zoomSource(id: recipe.id, in: zoom)
            .id(recipe.id)
            .transition(.opacity)
            .contentShape(.interaction, .rect(cornerRadius: Theme.radiusCard))
            .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.radiusCard))
            .draggable(RecipeTileDrag(gridID: gridID, recipeID: recipe.id)))
            .onTapGesture { openStackRecipe(recipe) }
            .contextMenu { options(recipe) }
            .menuOrder(.fixed)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openStackRecipe(recipe) }
            .accessibilityAction(named: Text("Nächstes Rezept im Stapel")) { cycle(by: 1) }
            .accessibilityAction(named: Text("Vorheriges Rezept im Stapel")) { cycle(by: -1) }
    }

    @ViewBuilder private func stackSwipe(on tile: some View) -> some View {
        if #available(iOS 18, *) {
            tile.gesture(RecipeStackPan { recognizer in
                let distance = recognizer.translation(in: nil).x
                switch recognizer.state {
                case .began, .changed:
                    panOffset = min(16, max(-16, distance / 3))
                case .ended:
                    panOffset = 0
                    let projected = distance + recognizer.velocity(in: nil).x * 0.15
                    finishSwipe(distance: distance, projected: projected)
                case .failed, .cancelled:
                    panOffset = 0
                default:
                    break
                }
            })
        } else {
            tile.simultaneousGesture(legacyStackDrag)
        }
    }

    private var legacyStackDrag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .updating($dragOffset) { value, offset, _ in
                let delta = value.translation
                if abs(delta.width) > abs(delta.height) * 1.4 {
                    offset = min(16, max(-16, delta.width / 3))
                }
            }
            .onEnded { value in
                let delta = value.translation
                guard abs(delta.width) > abs(delta.height) * 1.4 else { return }
                finishSwipe(distance: delta.width, projected: value.predictedEndTranslation.width)
            }
    }

    private func finishSwipe(distance: CGFloat, projected: CGFloat) {
        let isFlick = abs(distance) >= 12 && abs(projected) >= 44 && distance * projected > 0
        if abs(distance) >= 32 || isFlick {
            cycle(by: distance < 0 ? 1 : -1)
        }
    }

    private func cycle(by step: Int) {
        let recipes = item.recipes
        let target = (index + step + recipes.count) % recipes.count
        withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : Theme.spring) {
            activeID = recipes[target].id
        }
    }

    private var stackBacks: some View {
        let recipes = item.recipes
        let rear = (1..<min(3, recipes.count)).map { recipes[(index + $0) % recipes.count] }
        return GeometryReader { proxy in
            ZStack {
                ForEach(Array(rear.enumerated().reversed()), id: \.element.id) { offset, recipe in
                    let side: Double = offset == 0 ? 1 : -1
                    PhotoCard(url: recipe.imageURL, title: recipe.title, compact: true)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.radiusCard)
                                .fill(.black.opacity(0.16))
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(0.98)
                        .rotationEffect(.degrees(side * 5))
                        .offset(x: side * 3, y: 3 + CGFloat(offset) * 4)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum RecipePickerScope: String, CaseIterable, Identifiable {
    case all, oldest

    var id: Self { self }

    var label: String {
        switch self {
        case .all: "Alle"
        case .oldest: "Lange nicht"
        }
    }

    func results(_ recipes: [Recipe], history: [String: CookingSummary], query: String) -> [Recipe] {
        let matches = recipes.matching(query)
        switch self {
        case .all: return matches
        case .oldest: return RecipeOrder.oldest.sorted(matches, history: history)
        }
    }
}

struct RecipePicker: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var selection: String?
    var context: String?
    var leftoverTarget: MealSlot?
    var onLeftover: ((MealPlanEntry) -> Void)?
    var onChoose: ((Recipe) -> Void)?
    @State private var query = ""
    @State private var scope: RecipePickerScope = .all

    private var scopePicker: some View {
        Picker("Rezeptwahl", selection: $scope) {
            ForEach(RecipePickerScope.allCases) { option in Text(option.label).tag(option) }
        }
    }

    var body: some View {
        let history = CookingSummary.from(store.cookingHistory)
        let matches = scope.results(store.recipes, history: history, query: query)
        let books = Dictionary(uniqueKeysWithValues: store.cookbooks.map { ($0.id, $0.title) })
        List {
            Section {
                if textSize.isAccessibilitySize { scopePicker.pickerStyle(.menu) }
                else { scopePicker.pickerStyle(.segmented) }
                if let leftoverTarget, let onLeftover {
                    NavigationLink {
                        LeftoverSourcePicker(target: leftoverTarget, onChoose: onLeftover)
                    } label: {
                        Label("Reste / Meal Prep", systemImage: "takeoutbag.and.cup.and.straw")
                    }
                }
            } header: {
                if let context {
                    Text(context)
                        .font(.subheadline)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Section {
                if selection != nil && query.isEmpty {
                    Button("Rezept entfernen", role: .destructive) {
                        selection = nil
                        dismiss()
                    }
                }
                if matches.isEmpty {
                    if store.recipes.isEmpty {
                        ContentUnavailableView {
                            Label("Noch keine Rezepte", systemImage: "book")
                        } actions: {
                            NavigationLink("Rezept anlegen") { RecipeEditor() }
                        }
                    } else if !query.isEmpty { ContentUnavailableView.search(text: query) }
                    else {
                        ContentUnavailableView("Keine Rezepte", systemImage: "book")
                    }
                }
                ForEach(matches) { recipe in
                    let book = recipe.cookbookID.flatMap { books[$0] }
                    let lastCooked = history[recipe.id].map { "Gekocht am \(cookingDateLabel($0.latest))" } ?? "Noch nie gekocht"
                    Button {
                        if let onChoose { onChoose(recipe) }
                        else {
                            selection = recipe.id
                            dismiss()
                        }
                    } label: {
                        HStack {
                            RecipeRow(recipe: recipe, detail: [book, lastCooked].compactMap { $0 }.joined(separator: " · "))
                            Spacer()
                            if selection == recipe.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Ausgewählt")
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Rezept auswählen")
        .gnScreen()
        .searchable(text: $query, prompt: "Rezept oder Zutat suchen")
    }
}

struct LeftoverSourcePicker: View {
    @Environment(HouseholdStore.self) private var store
    let target: MealSlot
    let onChoose: (MealPlanEntry) -> Void
    @State private var entries: [MealPlanEntry]?
    @State private var loadFailed = false

    var body: some View {
        List {
            if let entries {
                if entries.isEmpty {
                    ContentUnavailableView("Keine Ursprungsgerichte", systemImage: "fork.knife",
                                           description: Text("Wähle einen Termin mit einem Kochtag in den zehn Tagen davor."))
                }
                ForEach(entries) { entry in
                    if let recipe = store.recipeForMeal(recipeID: entry.recipeID, leftoverOf: nil) {
                        Button { onChoose(entry) } label: {
                            RecipeRow(recipe: recipe, detail: "\(cookingDateLabel(entry.date)) · \(entry.meal.label)")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } else if loadFailed {
                Button("Erneut laden", systemImage: "arrow.clockwise") { Task { await load() } }
            } else {
                ProgressView("Gerichte werden geladen")
            }
        }
        .navigationTitle("Reste / Meal Prep")
        .navigationBarTitleDisplayMode(.inline)
        .gnScreen()
        .task(id: target) { await load() }
    }

    private func load() async {
        do {
            entries = try await store.recentLeftoverSources(before: target)
            loadFailed = false
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            RecipeThumbnail(recipe: recipe)
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.body.weight(.semibold))
                if let subtitle = detail ?? recipe.subtitle ?? recipe.timeText {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private extension Recipe {
    var dietLabel: String? {
        switch diet?.lowercased() {
        case "vegan": "Vegan"
        case "vegetarisch": "Vegetarisch"
        case "fisch": "Fisch"
        case "fleisch": "Fleisch"
        default: nil
        }
    }

    var dietSymbol: String {
        switch diet?.lowercased() {
        case "fisch": "fish.fill"
        default: "leaf"
        }
    }

    var durationLabel: String? {
        timeMin.map { "\($0) Min." } ?? timeText
    }
}

/// Hochformat mit Titel und Metadaten auf dem Foto.
struct RecipeTile: View {
    let recipe: Recipe

    private var metadata: String? {
        let details = [recipe.dietLabel, recipe.durationLabel].compactMap { $0 }
        return details.isEmpty ? recipe.subtitle : details.joined(separator: " · ")
    }

    var body: some View {
        PhotoCard(url: recipe.imageURL, title: recipe.title, metadata: metadata)
    }
}

extension View {
    /// Kachel, aus der das Rezept beim Öffnen herauswächst (ab iOS 18).
    @ViewBuilder func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) { matchedTransitionSource(id: id, in: namespace) } else { self }
    }

    /// Ziel der Vergrößerung; mit Wischen nach unten geht es zurück in die Kachel.
    @ViewBuilder func zoomDestination(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) { navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
    }
}

struct RecipeThumbnail: View {
    let recipe: Recipe

    var body: some View {
        CatalogImage(url: recipe.imageURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.accentColor.opacity(0.12).overlay {
                Image(systemName: "fork.knife").foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct RecipeDetailView: View {
    @Environment(NavigationChrome.self) private var chrome
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let initialRecipe: Recipe
    private let coverData: Data?
    private let review: DraftReview?
    @State private var photo: RecipeDetailPhoto?
    @State private var localPhoto: RecipeDetailPhoto?
    @State private var targetServings: Int?
    @State private var recipeAction: RecipeActionRequest?
    @State private var showingAttribution = false
    @State private var showsScheduleLabel = false
    @State private var detailVisibilityID = UUID()
    @AppStorage("gnocchi.recipeSectionOrder") private var sectionOrder = ""
    @State private var sectionFrames: [RecipeSection: CGRect] = [:]
    @State private var sectionMove: SectionMove?

    private struct SectionMove {
        let section: RecipeSection
        let title: String
        let scroll: UIScrollView
        var location: CGPoint
    }

    private struct SectionFrames: PreferenceKey {
        static let defaultValue: [RecipeSection: CGRect] = [:]

        static func reduce(value: inout [RecipeSection: CGRect], nextValue: () -> [RecipeSection: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
        }
    }

    struct DraftReview {
        let warnings: [String]
        let saving: Bool
        let canSave: Bool
        let edit: () -> Void
        let save: () -> Void
    }

    init(recipe: Recipe, coverData: Data? = nil, review: DraftReview? = nil) {
        initialRecipe = recipe
        self.coverData = coverData
        self.review = review
    }

    private var recipe: Recipe {
        if review != nil { return initialRecipe }
        return store.recipes.first { $0.id == initialRecipe.id } ?? initialRecipe
    }

    private var book: Cookbook? {
        store.cookbooks.first { $0.id == recipe.cookbookID }
    }

    private var currentPhoto: RecipeDetailPhoto? {
        if let localPhoto { return localPhoto }
        return photo?.url == recipe.imageURL ? photo : nil
    }
    private var backdrop: Color {
        if contrast == .increased { return RecipeDetailPhoto.neutralBackdrop }
        return currentPhoto?.backdrop ?? RecipeDetailPhoto.neutralBackdrop
    }

    private var displayedServings: Int? {
        guard (recipe.servings ?? 0) > 0 else { return nil }
        return targetServings ?? (review != nil || store.members.isEmpty ? recipe.servings : store.members.count)
    }

    private var portionsLabel: String? {
        if let text = recipe.servingsText, !text.isEmpty, Int(text) == nil { return text }
        guard let servings = recipe.servings, servings > 0 else { return nil }
        return servings == 1 ? "1 Portion" : "\(servings) Portionen"
    }

    private var facts: [(symbol: String, value: String)] {
        var result: [(String, String)] = []
        if let time = recipe.durationLabel { result.append(("clock", time)) }
        if let portionsLabel, recipe.ingredients.isEmpty || (recipe.servings ?? 0) <= 0 {
            result.append(("person.2", portionsLabel))
        }
        if let energy = recipe.nutrition?["kcal"], !energy.isEmpty {
            let value = "\(energy) kcal"
            result.append(("flame", recipe.nutritionEstimated == true ? "ca. \(value)" : value))
        }
        return result
    }

    private var factStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                ForEach(facts, id: \.symbol) { fact in
                    if fact.symbol != facts.first?.symbol {
                        Rectangle().fill(Theme.recipeHighlight).frame(width: 1, height: 18)
                            .accessibilityHidden(true)
                    }
                    factLabel(fact)
                }
            }
            VStack(spacing: 10) {
                ForEach(facts, id: \.symbol) { factLabel($0) }
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 15)
        .background(Theme.recipePanel, in: .capsule)
        .overlay { Capsule().strokeBorder(Theme.recipeHighlight).allowsHitTesting(false) }
    }

    private func factLabel(_ fact: (symbol: String, value: String)) -> some View {
        Label(fact.value, systemImage: fact.symbol)
            .multilineTextAlignment(.center)
    }

    private var hero: some View {
        let hasPhoto = coverData != nil || recipe.imageURL != nil
        return VStack(spacing: 10) {
            if review != nil {
                Label("Entwurf", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.recipeHighlight, in: .capsule)
            }
            if let diet = recipe.dietLabel {
                Label {
                    Text(diet)
                } icon: {
                    if diet == "Fleisch" {
                        MeatSymbol()
                            .fill(.white)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: recipe.dietSymbol)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            Text(recipe.title)
                .font(Theme.display(36))
                .tracking(-0.9)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = recipe.subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(Theme.recipeSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, hasPhoto ? 314 : 118)
        .padding(.bottom, 14)
        .frame(minHeight: hasPhoto ? 395 : nil, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            if hasPhoto {
                RecipeDetailArtwork(photo: currentPhoto, backdrop: backdrop)
                    .frame(height: 395)
            }
        }
    }

    private var organizationSummary: String {
        let folder = store.folders.first { $0.id == recipe.folderID }?.label
        let tags = (recipe.tags ?? []).map { "#\($0)" }.joined(separator: " ")
        return [folder, tags.isEmpty ? nil : tags].compactMap { $0 }.joined(separator: " · ")
    }

    private var ingredientGroups: [[Recipe.Ingredient]] {
        recipe.ingredients.sorted { $0.position < $1.position }.reduce(into: []) { groups, ingredient in
            if let last = groups.last, last.first?.group == ingredient.group {
                groups[groups.count - 1].append(ingredient)
            } else {
                groups.append([ingredient])
            }
        }
    }

    private var ingredientPanel: some View {
        let base = recipe.servings ?? 0
        let servings = displayedServings ?? base
        let factor = base > 0 ? Double(servings) / Double(base) : nil
        return RecipePanel("Zutaten") {
            if review != nil, let portionsLabel {
                Text(portionsLabel).font(.body.weight(.semibold))
            } else if base > 0, !recipe.ingredients.isEmpty {
                Stepper(value: Binding(get: { displayedServings ?? base }, set: { targetServings = $0 }),
                        in: 1...max(40, base, store.members.count)) {
                    Text(servings == 1 ? "1 Portion" : "\(servings) Portionen")
                        .font(.body.weight(.semibold))
                }
                .tint(.white)
            }
            if recipe.ingredients.isEmpty {
                Text("Die Zutaten stehen im Kochbuch.").foregroundStyle(Theme.recipeSecondary)
            }
            ForEach(Array(ingredientGroups.enumerated()), id: \.offset) { _, ingredients in
                VStack(alignment: .leading, spacing: 0) {
                    if let group = ingredients.first?.group, !group.isEmpty {
                        Text(group)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.recipeSecondary)
                            .padding(.bottom, 6)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(ingredients) { ingredient in
                        RecipeIngredientRow(ingredient: ingredient, amount: ingredient.amountLabel(factor: factor))
                    }
                }
            }
            if review == nil, !recipe.ingredients.isEmpty, !store.isDemo, let url = Backend.bringURL(for: recipe.sharingURL(servings: displayedServings)) {
                Link(destination: url) {
                    Label("Zutaten in Bring! übernehmen", systemImage: "cart")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(Theme.recipeHighlight, in: .capsule)
                }
                if base <= 0 {
                    Text("Ohne Portionsangabe lassen sich die Mengen nicht umrechnen.")
                        .font(.footnote)
                        .foregroundStyle(Theme.recipeSecondary)
                }
            }
        }
    }

    private var preparation: some View {
        let mentions = IngredientMentions(ingredients: recipe.ingredients, reviewedAliases: recipe.ingredientEmojiAliases)
        return RecipePanel("Zubereitung") {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1).")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.recipeSecondary)
                    PreparationStep(step: step, mentions: mentions)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var recipeDetails: some View {
        RecipePanel("Zum Rezept") {
            if let book {
                NavigationLink {
                    CookbookDetail(book: book)
                } label: {
                    HStack(spacing: 12) {
                        CookbookCover(book: book).frame(width: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.body.weight(.medium))
                            if let page = recipe.cookbookPage {
                                Text("Seite \(page)").font(.subheadline).foregroundStyle(Theme.recipeSecondary)
                            }
                            if recipe.bookConfirmed == false {
                                Text("Verknüpfung zu bestätigen").font(.caption).foregroundStyle(Theme.recipeSecondary)
                            }
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.recipeSecondary)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Kochbuch öffnen")
                }
            }
            if !organizationSummary.isEmpty {
                LabeledContent("Ordner und Tags", value: organizationSummary)
            }
            if let source = recipe.source, !source.isEmpty {
                LabeledContent("Rezeptquelle", value: source)
            }
        }
    }

    private var visibleSections: [RecipeSection] {
        RecipeSection.ordered(sectionOrder).filter { section in
            switch section {
            case .rating, .price, .notes, .history: review == nil
            case .nutrition: review == nil || recipe.nutrition != nil
            case .ingredients: !recipe.ingredients.isEmpty || book != nil
            case .preparation: !recipe.steps.isEmpty
            case .tips: recipe.tip?.isEmpty == false
            case .about: book != nil || !organizationSummary.isEmpty || recipe.source?.isEmpty == false
            }
        }
    }

    private var content: some View {
        let sections = visibleSections
        let target = sectionMove.flatMap { dropTarget(for: $0) }
        return VStack(spacing: 15) {
            if let review, !review.warnings.isEmpty {
                RecipePanel("Import prüfen") {
                    ForEach(Array(Set(review.warnings)).sorted(), id: \.self) { warning in
                        Label(warning, systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.recipeSecondary)
                    }
                }
            }
            if !facts.isEmpty { factStrip }
            ForEach(sections) { section in
                sectionView(section)
                    .environment(\.recipeSectionDrag, review == nil
                                 ? RecipeSectionDrag(section: section, handle: trackSectionMove) : nil)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: SectionFrames.self, value: [section: geometry.frame(in: .global)])
                        }
                    }
                    .opacity(sectionMove?.section == section ? 0.48 : 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusCard)
                            .strokeBorder(target == section ? .white.opacity(0.85) : .clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                    .accessibilityActions {
                        if review == nil, let index = sections.firstIndex(of: section) {
                            if index > 0 {
                                Button("Abschnitt nach oben verschieben") { _ = moveSection(section, onto: sections[index - 1]) }
                            }
                            if index + 1 < sections.count {
                                Button("Abschnitt nach unten verschieben") { _ = moveSection(section, onto: sections[index + 1]) }
                            }
                        }
                    }
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 620)
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
    }

    private func trackSectionMove(
        _ section: RecipeSection, title: String, gesture: UILongPressGestureRecognizer, scroll: UIScrollView
    ) {
        let location = gesture.location(in: scroll.window)
        switch gesture.state {
        case .began:
            sectionMove = SectionMove(section: section, title: title, scroll: scroll, location: location)
        case .changed:
            guard sectionMove?.section == section else { return }
            sectionMove?.location = location
        case .ended:
            guard var move = sectionMove, move.section == section else { return }
            move.location = location
            let target = dropTarget(for: move)
            sectionMove = nil
            if let target {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    _ = moveSection(section, onto: target)
                }
            }
        case .cancelled, .failed:
            if sectionMove?.section == section { sectionMove = nil }
        default:
            break
        }
    }

    private func dragViewport(for scroll: UIScrollView) -> CGRect {
        guard let window = scroll.window else { return .null }
        let frame = scroll.convert(scroll.bounds, to: window)
        let safeArea = window.bounds.inset(by: window.safeAreaInsets)
        return frame.intersection(safeArea.inset(by: UIEdgeInsets(top: 44, left: 0, bottom: 55, right: 0)))
    }

    private func dropTarget(for move: SectionMove) -> RecipeSection? {
        let viewport = dragViewport(for: move.scroll)
        guard !viewport.isEmpty, viewport.minX <= move.location.x, move.location.x <= viewport.maxX else { return nil }
        let y = min(max(move.location.y, viewport.minY + 10), viewport.maxY - 10)
        return visibleSections.first { section in
            guard let frame = sectionFrames[section] else { return false }
            return frame.minY - 8 <= y && y <= frame.maxY + 8
        }
    }

    private func scrollWhileMovingSection() async {
        while let move = sectionMove, !Task.isCancelled {
            let scroll = move.scroll
            let viewport = dragViewport(for: scroll)
            if !viewport.isEmpty {
                let edge: CGFloat = 62
                let up = max(0, viewport.minY + edge - move.location.y)
                let down = max(0, move.location.y - viewport.maxY + edge)
                let velocity = max(-1, min(1, (down - up) / edge)) * 5
                if abs(velocity) > 0.1 {
                    let minY = -scroll.adjustedContentInset.top
                    let maxY = max(minY, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    let offset = min(max(scroll.contentOffset.y + velocity, minY), maxY)
                    if offset != scroll.contentOffset.y {
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                    }
                }
            }
            do { try await Task.sleep(for: .milliseconds(16)) }
            catch { return }
        }
    }

    private var sectionDragPreview: some View {
        GeometryReader { geometry in
            if let move = sectionMove {
                let origin = geometry.frame(in: .global).origin
                Label(move.title, systemImage: "line.3.horizontal")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundStyle(.black)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.20), radius: 9, y: 4)
                    .position(x: geometry.size.width / 2, y: move.location.y - origin.y - 28)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func moveSection(_ source: RecipeSection, onto target: RecipeSection) -> Bool {
        guard source != target else { return false }
        var sections = RecipeSection.ordered(sectionOrder)
        guard let from = sections.firstIndex(of: source), let to = sections.firstIndex(of: target) else { return false }
        sections.remove(at: from)
        sections.insert(source, at: to)
        sectionOrder = sections.map(\.rawValue).joined(separator: ",")
        return true
    }

    @ViewBuilder private func sectionView(_ section: RecipeSection) -> some View {
        switch section {
        case .ingredients:
            if !recipe.ingredients.isEmpty || book != nil { ingredientPanel }
        case .preparation:
            if !recipe.steps.isEmpty { preparation }
        case .tips:
            if let tip = recipe.tip, !tip.isEmpty { RecipePanel("Tipps") { Text(tip) } }
        case .rating:
            RecipeRatingTile(recipeID: recipe.id).id(recipe.id)
        case .nutrition:
            RecipeNutritionTile(recipe: recipe)
        case .price:
            RecipePortionPriceTile(recipe: recipe, portions: displayedServings).id(recipe.id)
        case .notes:
            RecipeNotes(recipeID: recipe.id)
        case .history:
            RecipeCookingHistory(recipe: recipe, servings: displayedServings ?? recipe.servings, sheetColorScheme: colorScheme)
        case .about:
            if book != nil || !organizationSummary.isEmpty || recipe.source?.isEmpty == false { recipeDetails }
        }
    }

    private var scheduleButton: some View {
        Button {
            perform(.schedule)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus").accessibilityHidden(true)
                if showsScheduleLabel {
                    Text("Zur Woche")
                        .transition(.opacity.combined(with: .scale(scale: 0.93, anchor: .trailing)))
                }
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, showsScheduleLabel ? 17 : 0)
            .frame(minWidth: 50, minHeight: 50)
            .foregroundStyle(Theme.recipeActionInk)
            .background(Theme.recipeAction, in: .capsule)
            .overlay { Capsule().strokeBorder(.white.opacity(0.35)).allowsHitTesting(false) }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Zur Woche")
        .frame(maxWidth: 620, alignment: .trailing)
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [backdrop.opacity(0), backdrop], startPoint: .top, endPoint: .center)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            hero.foregroundStyle(.white)
            content
        }
    }

    var body: some View {
        CollapsingActionScrollView(expanded: $showsScheduleLabel) { detailContent }
        .onPreferenceChange(SectionFrames.self) { sectionFrames = $0 }
        .task(id: sectionMove?.section) {
            if sectionMove != nil { await scrollWhileMovingSection() }
        }
        .onDisappear {
            sectionMove = nil
            chrome.setRecipeDetailVisible(false, id: detailVisibilityID)
        }
        .overlay { sectionDragPreview }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 62)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea(edges: .top)
        .background(backdrop.ignoresSafeArea())
        .task(id: recipe.imageURL) {
            let loaded = await RecipeDetailPhoto.load(recipe.imageURL)
            guard !Task.isCancelled else { return }
            photo = loaded
        }
        .task(id: coverData) { localPhoto = coverData.flatMap(RecipeDetailPhoto.load(coverData:)) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let review {
                Button(action: review.save) {
                    if review.saving { ProgressView().tint(.black).accessibilityLabel("Speichert …") }
                    else { Label("Rezept sichern", systemImage: "checkmark") }
                }
                .buttonStyle(InkButtonStyle(tint: .white, foreground: .black))
                .disabled(!review.canSave)
                .allowsHitTesting(!review.saving)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(colors: [.clear, backdrop], startPoint: .top, endPoint: .center)
                        .ignoresSafeArea(edges: .bottom)
                }
            } else {
                scheduleButton
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { chrome.setRecipeDetailVisible(true, id: detailVisibilityID) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let review {
                    Button("Bearbeiten", systemImage: "pencil", action: review.edit).disabled(review.saving)
                } else {
                    if recipe.photoCredit?.licenseUrl != nil {
                        Button("Bildnachweis", systemImage: "info.circle") { showingAttribution = true }
                    }
                    Menu {
                        RecipeActionMenu(url: recipe.sharingURL(servings: displayedServings), perform: perform) {
                            EmptyView()
                        }
                    } label: {
                        Label("Weitere Rezeptaktionen", systemImage: "ellipsis")
                    }
                    .menuOrder(.fixed)
                }
            }
        }
        .recipeActions($recipeAction) { dismiss() }
        .sheet(isPresented: $showingAttribution) {
            NavigationStack {
                if let credit = recipe.photoCredit {
                    List {
                        if let author = credit.author, let url = credit.sourceUrl {
                            Link(author, destination: url)
                        } else if let author = credit.author {
                            Text(author)
                        }
                        if let license = credit.license, let url = credit.licenseUrl {
                            Link(license, destination: url)
                        }
                        Text("Das Foto wird in der App zugeschnitten.")
                            .foregroundStyle(.secondary)
                    }
                    .navigationTitle("Bildnachweis")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Fertig") { showingAttribution = false }
                        }
                    }
                }
            }
            .compactRecipeSheet()
        }
    }

    private func perform(_ action: RecipeAction) {
        recipeAction = RecipeActionRequest(recipe: recipe, action: action)
    }


}

private struct RecipeIngredientRow: View {
    let ingredient: Recipe.Ingredient
    let amount: String

    var body: some View {
        HStack(spacing: 13) {
            IngredientIcon(name: ingredient.name, aisle: ingredient.aisle)
                .frame(minWidth: 32)
                .accessibilityHidden(true)
            if amount.isEmpty {
                Text(ingredient.name)
            } else {
                Text("\(Text(amount).fontWeight(.semibold)) \(ingredient.name)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

}

extension [Recipe] {
    func matching(_ query: String) -> [Recipe] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return self }
        return filter { recipe in
            recipe.title.localizedStandardContains(search)
                || recipe.subtitle?.localizedStandardContains(search) == true
                || recipe.tags?.contains { $0.localizedStandardContains(search) } == true
                || recipe.ingredients.contains { $0.name.localizedStandardContains(search) }
        }
    }
}
