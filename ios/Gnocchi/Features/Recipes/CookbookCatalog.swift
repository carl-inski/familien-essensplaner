import Foundation

private struct CookbookCatalogEntry: Decodable, Sendable {
    let title: String
    let isbn: String?
    let authors: [String]
    let publisher: String?
    let year: Int?
    let coverUrl: String?
    let quelle: String?
    let hinweis: String?
    let coverQuelle: String?

    static let entries: [String: Self] = {
        guard let url = Bundle.main.url(forResource: "cookbook-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let books = try? JSONDecoder().decode([Self].self, from: data) else { return [:] }
        return Dictionary(books.map { (normalizedMediaTitle($0.title), $0) }, uniquingKeysWith: { _, last in last })
    }()
}

extension Cookbook {
    private var catalogEntry: CookbookCatalogEntry? { CookbookCatalogEntry.entries[normalizedMediaTitle(title)] }

    var presented: Cookbook {
        guard let entry = catalogEntry else { return self }
        let authorsArePlaceholder = authors.isEmpty || (entry.title == "Leon Fast Food Vegetarisch" && authors == ["Leon"])
        let storedPublisher = cookbookField(publisher ?? "")
        let notesArePlaceholder = notes == nil || notes == "" || notes == "Autor/Verlag per ISBN ergänzen"
        return Cookbook(id: id, title: title, authors: authorsArePlaceholder ? entry.authors : authors,
                        publisher: storedPublisher == "GU" ? entry.publisher ?? publisher : storedPublisher ?? entry.publisher,
                        year: year ?? entry.year, isbn: cookbookField(isbn ?? "") ?? entry.isbn,
                        coverPath: cookbookField(coverPath ?? "") ?? entry.coverUrl,
                        notes: notesArePlaceholder ? entry.hinweis : notes)
    }

    var isbnSource: String? {
        guard let entry = catalogEntry, let known = entry.isbn, let isbn,
              isbn.uppercased().filter({ "0123456789X".contains($0) }) == known.uppercased().filter({ "0123456789X".contains($0) }) else { return nil }
        return entry.quelle
    }

    var coverSource: String? {
        guard let entry = catalogEntry, let coverPath, coverPath == entry.coverUrl else { return nil }
        return entry.coverQuelle
    }
}
