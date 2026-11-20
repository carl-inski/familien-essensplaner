import Foundation

enum AppShareText {
    // Placeholder for the test app. Replace with the published listing before release.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id0000000000")!

    static func withFooter(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\nGeteilt mit Gnocchi\n" + appStoreURL.absoluteString
    }
}
