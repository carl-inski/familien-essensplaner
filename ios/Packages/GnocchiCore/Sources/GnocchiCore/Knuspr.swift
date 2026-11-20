import Foundation

public enum Knuspr {
    public enum Assistant: String {
        case claude = "https://claude.ai/new"
        case chatGPT = "https://chatgpt.com/"
    }

    public static func prompt(lines: [String]) -> String {
        ([
            "Bitte lege über Knuspr diese Einkaufsliste in meinen Warenkorb.",
            "Wähle für jede Zeile ein passendes Produkt in ausreichender Menge (lieber die nächstgrößere Packung als zu wenig).",
            "Nicht bestellen und nichts aus dem Warenkorb entfernen. Sag mir am Ende kurz, was du nicht gefunden hast.",
            ""
        ] + lines.map { "- \($0)" }).joined(separator: "\n")
    }

    public static func link(for assistant: Assistant, prompt: String) -> URL? {
        // Match encodeURIComponent, including literals that form decoders treat as separators.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        guard let query = prompt.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: assistant.rawValue + "?q=" + query)
    }
}
