import SwiftUI

struct IngredientEmojiCatalogView: View {
    private enum Layout: String, Hashable {
        case names = "Begriffe A–Z"
        case motifs = "Nach Motiv"
    }

    private enum Artwork: Hashable {
        case generated(String)
        case illustration(String)
        case emoji(String)
    }

    private struct MotifGroup: Identifiable, Hashable {
        let artwork: Artwork
        let terms: [IngredientEmojiCatalog.Term]

        var id: Artwork { artwork }
        var name: String {
            if terms.count > 1, case let .emoji(value) = artwork { return value }
            return terms[0].name
        }
    }

    @State private var layout: Layout = .names
    @State private var query = ""
    @State private var selectedMotif: MotifGroup?

    private static let alphabeticalTerms = IngredientEmojiCatalog.terms.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }

    private var matchingTerms: [IngredientEmojiCatalog.Term] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.alphabeticalTerms }
        let key = IngredientEmojiCatalog.key(query)
        return Self.alphabeticalTerms.filter { term in
            term.emoji == query || (!key.isEmpty && term.searchKey.contains(key))
        }
    }

    var body: some View {
        let terms = matchingTerms
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $layout) {
                Text(Layout.names.rawValue).tag(Layout.names)
                Text(Layout.motifs.rawValue).tag(Layout.motifs)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)

            if terms.isEmpty {
                ContentUnavailableView("Keine Begriffe gefunden", systemImage: "magnifyingglass")
            } else if layout == .names {
                List {
                    Section {
                        ForEach(terms) { IngredientEmojiCatalogRow(term: $0) }
                    } header: {
                        Text(terms.count == 1 ? "1 Begriff" : "\(terms.count.formatted()) Begriffe")
                    }
                }
                .scrollContentBackground(.hidden)
            } else {
                motifs(terms)
            }
        }
        .gnScreen()
        .navigationTitle("Zutaten-Emojis")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Zutat oder Emoji suchen")
        .navigationDestination(item: $selectedMotif) { group in
            List(group.terms) { IngredientEmojiCatalogRow(term: $0) }
                .gnScreen()
                .navigationTitle(group.name)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func motifs(_ terms: [IngredientEmojiCatalog.Term]) -> some View {
        let generated = terms.filter(\.hasGeneratedImage).map {
            MotifGroup(artwork: .generated($0.searchKey), terms: [$0])
        }
        let shared = Dictionary(grouping: terms.filter { !$0.hasGeneratedImage }) { term in
            term.illustration.map(Artwork.illustration) ?? .emoji(term.emoji)
        }.map { MotifGroup(artwork: $0.key, terms: $0.value) }.sorted {
            if $0.terms.count != $1.terms.count { return $0.terms.count > $1.terms.count }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !generated.isEmpty {
                    Text("Eigene Emojis · \(generated.count.formatted())")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    motifGrid(generated)
                }
                if !shared.isEmpty {
                    Text("Gemeinsam genutzte Motive")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    motifGrid(shared)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 10)
        }
    }

    private func motifGrid(_ groups: [MotifGroup]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
            ForEach(groups) { group in
                Button {
                    selectedMotif = group
                } label: {
                    VStack(spacing: 4) {
                        switch group.artwork {
                        case let .generated(key):
                            if let image = IngredientEmojiImages.image(for: key) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 33, height: 33)
                            }
                        case let .illustration(asset):
                            Image(asset).resizable().scaledToFit().frame(width: 30, height: 30)
                        case let .emoji(value):
                            Text(value).font(.title2)
                        }
                        Text(group.terms.count == 1 ? group.name : group.terms.count.formatted())
                            .font(.caption2)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(Theme.card, in: .rect(cornerRadius: Theme.radiusControl))
                    .contentShape(.rect)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(group.terms.count == 1
                                        ? group.name : "\(group.name), \(group.terms.count) Begriffe")
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }
}

private struct IngredientEmojiCatalogRow: View {
    let term: IngredientEmojiCatalog.Term

    var body: some View {
        HStack(spacing: 12) {
            IngredientIcon(name: term.name, aisle: nil)
                .frame(minWidth: 32)
                .accessibilityHidden(true)
            Text(term.name).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}
