import SwiftUI

struct CookbookShelf: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var adding = false
    @Namespace private var zoom

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: textSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(store.cookbooks) { stored in
                    let book = stored.presented
                    let id = "book-\(book.id)"
                    NavigationLink {
                        CookbookDetail(book: book).zoomDestination(id: id, in: zoom)
                    } label: {
                        PhotoCard(url: book.coverURL, title: book.title,
                                  metadata: book.authors.formatted(.list(type: .and)), symbol: "book.closed")
                            .zoomSource(id: id, in: zoom)
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .overlay {
            if store.cookbooks.isEmpty {
                ContentUnavailableView {
                    Label("Das Regal ist leer", systemImage: "books.vertical")
                } actions: {
                    Button("Buch hinzufügen") { adding = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            if !usesSystemQuickAction {
                Button("Kochbuch hinzufügen", systemImage: "plus") { adding = true }
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.semibold))
                    .frame(width: 54, height: 54)
                    .foregroundStyle(.black)
                    .background(.white, in: .circle)
                    .overlay { Circle().strokeBorder(.black.opacity(0.12)).allowsHitTesting(false) }
                    .buttonStyle(PressScaleStyle())
                    .padding(.trailing, Theme.gutter)
            }
        }
        .navigationActionSurface(addCookbook: { adding = true })
        .navigationTitle("Kochbuchregal")
        .gnScreen()
        .refreshable { await store.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Buch hinzufügen", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { CookbookEditor() }
                .presentationDragIndicator(.visible)
        }
    }
    private var usesSystemQuickAction: Bool {
        if #available(iOS 26, *) { return horizontalSizeClass == .compact }
        return false
    }

}

struct CookbookCover: View {
    let book: Cookbook

    var body: some View {
        CatalogImage(url: book.presented.coverURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Color.accentColor.opacity(0.14).overlay {
                Image(systemName: "book.closed").font(.title).foregroundStyle(Color.accentColor)
            }
        }
        .aspectRatio(0.75, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}

struct CookbookDetail: View {
    @Environment(NavigationChrome.self) private var chrome
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast
    private let initialBook: Cookbook
    @State private var photo: RecipeDetailPhoto?
    @State private var sheet: Sheet?
    @State private var showsLinkLabel = false
    @State private var showRemoval = false
    @State private var unlinking: Recipe?
    @State private var busy = false
    @State private var error: String?

    private enum Sheet: Identifiable {
        case edit, link, reference, page(Recipe)

        var id: String {
            switch self {
            case .edit: "edit"
            case .link: "link"
            case .reference: "reference"
            case .page(let recipe): "page/\(recipe.id)"
            }
        }
    }

    init(book: Cookbook) { initialBook = book }

    private var book: Cookbook {
        store.cookbooks.first { $0.id == initialBook.id } ?? initialBook
    }

    private var currentPhoto: RecipeDetailPhoto? { photo?.url == book.presented.coverURL ? photo : nil }
    private var backdrop: Color {
        if contrast == .increased { return RecipeDetailPhoto.neutralBackdrop }
        return currentPhoto?.backdrop ?? RecipeDetailPhoto.neutralBackdrop
    }

    private var recipes: [Recipe] {
        store.recipes.filter { $0.cookbookID == book.id }.sorted { left, right in
            let leftPage = left.cookbookPage ?? Int.max
            let rightPage = right.cookbookPage ?? Int.max
            if leftPage != rightPage { return leftPage < rightPage }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    var body: some View {
        let details = book.presented
        cookbookList(details)
        .task(id: details.coverURL) {
            let loaded = await RecipeDetailPhoto.load(details.coverURL)
            guard !Task.isCancelled else { return }
            photo = loaded
        }
        .environment(\.recipeSectionDrag, nil)
        .environment(\.colorScheme, .dark)
        .tint(.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { chrome.hideActions() }
        .disabled(busy)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rezept verknüpfen", systemImage: "link") { sheet = .link }
                    Button("Verweis anlegen", systemImage: "bookmark") { sheet = .reference }
                    Divider()
                    Button("Buch bearbeiten", systemImage: "pencil") { sheet = .edit }
                    Button("Aus dem Regal entfernen", systemImage: "trash", role: .destructive) { showRemoval = true }
                } label: {
                    Label("Weitere Buchaktionen", systemImage: "ellipsis")
                }
                .menuOrder(.fixed)
            }
        }
        .sheet(item: $sheet) { route in
            NavigationStack {
                switch route {
                case .edit: CookbookEditor(book: book)
                case .link: CookbookRecipeLink(book: book)
                case .reference: CookbookReference(book: book)
                case .page(let recipe): CookbookLinkPage(recipe: recipe, book: book, editingPage: true) { sheet = nil }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("„\(book.title)“ aus dem Regal entfernen?", isPresented: $showRemoval, titleVisibility: .visible) {
            Button("Buch entfernen", role: .destructive) {
                Task {
                    await update {
                        try await store.removeCookbook(book)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Verknüpfte Rezepte bleiben in deiner Sammlung.")
        }
        .confirmationDialog("Kochbuch-Verknüpfung lösen?", isPresented: Binding(
            get: { unlinking != nil }, set: { if !$0 { unlinking = nil } }
        ), titleVisibility: .visible, presenting: unlinking) { recipe in
            Button("Verknüpfung lösen", role: .destructive) {
                Task { await update { try await store.linkRecipe(recipe, to: nil, page: nil) } }
            }
        } message: { recipe in
            Text(recipe.title)
        }
        .alert("Kochbuch", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func cookbookList(_ details: Cookbook) -> some View {
        CollapsingActionScrollView(expanded: $showsLinkLabel) {
            VStack(spacing: 0) {
                hero(details)
                VStack(spacing: 15) {
                    facts(details)
                    linkedRecipes
                    bookMetadata(details)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 18)
            }
            .foregroundStyle(.white)
        }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 62)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea(edges: .top)
        .background(backdrop.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { linkButton }
    }

    private func facts(_ details: Cookbook) -> some View {
        HStack(spacing: 11) {
            Label(recipes.count == 1 ? "1 Rezept" : "\(recipes.count) Rezepte", systemImage: "fork.knife")
            if let year = details.year {
                Circle().fill(Theme.recipeSecondary).frame(width: 3, height: 3).accessibilityHidden(true)
                Label(String(year), systemImage: "calendar")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(Theme.recipePanel, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.recipeHighlight).allowsHitTesting(false) }
        .accessibilityElement(children: .combine)
    }

    private func bookMetadata(_ details: Cookbook) -> some View {
        RecipePanel("Zum Buch") {
            if let publisher = details.publisher { LabeledContent("Verlag", value: publisher) }
            if let isbn = details.isbn {
                LabeledContent("ISBN", value: isbn)
                if let source = details.isbnSource {
                    Text(source).font(.subheadline).foregroundStyle(Theme.recipeSecondary)
                }
            } else {
                Button("ISBN ergänzen", systemImage: "barcode") { sheet = .edit }
            }
            if let notes = details.notes, !notes.isEmpty {
                Text(notes).foregroundStyle(Theme.recipeSecondary)
            }
            if let source = details.coverSource {
                Text(source).font(.footnote).foregroundStyle(Theme.recipeSecondary)
            }
        }
    }

    private var linkedRecipes: some View {
        RecipePanel("Rezepte") {
            if recipes.isEmpty {
                Text("Noch keine verknüpften Rezepte").foregroundStyle(Theme.recipeSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recipes) { recipe in
                        linkedRecipeRow(recipe)
                        if recipe.bookConfirmed == false {
                            Button("Verknüpfung bestätigen", systemImage: "checkmark.circle") {
                                Task { await update { try await store.linkRecipe(recipe, to: book, page: recipe.cookbookPage) } }
                            }
                            .font(.footnote.weight(.medium))
                            .accessibilityLabel("Verknüpfung von \(recipe.title) bestätigen")
                        }
                    }
                }
            }
        }
    }

    private func linkedRecipeRow(_ recipe: Recipe) -> some View {
        let pageAction = recipe.cookbookPage == nil ? "Seitenzahl ergänzen" : "Seitenzahl ändern"
        return NavigationLink {
            RecipeDetailView(recipe: recipe)
        } label: {
            HStack(spacing: 11) {
                CatalogImage(url: recipe.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Theme.recipeHighlight.overlay {
                        Image(systemName: "fork.knife").foregroundStyle(Theme.recipeSecondary)
                    }
                }
                .frame(width: 47, height: 47)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if let page = recipe.cookbookPage {
                        Text("Seite \(page)").font(.caption).foregroundStyle(Theme.recipeSecondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.recipeSecondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.recipeHighlight, in: .rect(cornerRadius: Theme.radiusControl))
            .contentShape(.rect(cornerRadius: Theme.radiusControl))
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button(pageAction, systemImage: "pencil") { sheet = .page(recipe) }
            Button("Verknüpfung lösen", systemImage: "minus.circle", role: .destructive) { unlinking = recipe }
        }
    }

    private func hero(_ details: Cookbook) -> some View {
        let hasCover = details.coverURL != nil
        return VStack(spacing: 10) {
            Text(details.title)
                .font(Theme.display(36))
                .tracking(-0.9)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !details.authors.isEmpty {
                Text(details.authors.formatted(.list(type: .and)))
                    .foregroundStyle(Theme.recipeSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .frame(maxWidth: 620)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, hasCover ? 329 : 149)
        .padding(.bottom, 17)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack {
                if currentPhoto != nil {
                    RecipeDetailArtwork(photo: currentPhoto, backdrop: backdrop)
                        .blur(radius: 22)
                        .opacity(0.56)
                        .clipped()
                        .mask(alignment: .top) {
                            LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                        }
                }
                RecipeDetailArtwork(photo: currentPhoto, backdrop: backdrop, isCover: true)
                    .padding(.top, hasCover ? 0 : 60)
            }
            .frame(height: hasCover ? 367 : 149)
        }
    }

    private var linkButton: some View {
        Button {
            sheet = .link
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link").accessibilityHidden(true)
                if showsLinkLabel {
                    Text("Rezept verknüpfen")
                        .transition(.opacity.combined(with: .scale(scale: 0.93, anchor: .trailing)))
                }
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, showsLinkLabel ? 17 : 0)
            .frame(minWidth: 50, minHeight: 50)
            .foregroundStyle(Theme.recipeActionInk)
            .background(Theme.recipeAction, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Rezept verknüpfen")
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

    private func update(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await operation() }
        catch let failure as CookbookError { error = failure.localizedDescription }
        catch { self.error = "Die Änderung konnte nicht gespeichert werden." }
    }
}
