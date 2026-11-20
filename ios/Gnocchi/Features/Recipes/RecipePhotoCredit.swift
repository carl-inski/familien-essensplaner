import Foundation

struct RecipePhotoCredit: Decodable, Sendable {
    let title: String
    let src: String?
    let author: String?
    let license: String?
    let licenseUrl: URL?
    let sourceUrl: URL?
    let hinweis: String?

    private static let catalog: [Self] = {
        guard let url = Bundle.main.url(forResource: "dish-photos", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Self].self, from: data)) ?? []
    }()

    static func credit(title: String, imagePath: String?) -> Self? {
        if let imagePath, !imagePath.isEmpty { return catalog.first { $0.src == imagePath } }
        let key = normalizedMediaTitle(title)
        return catalog.first { $0.src != nil && normalizedMediaTitle($0.title) == key }
    }
}

func normalizedMediaTitle(_ title: String) -> String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(with: Locale(identifier: "de"))
        .replacingOccurrences(of: #"\s+&\s+"#, with: " und ", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}
