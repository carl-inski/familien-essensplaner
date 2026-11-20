import SwiftUI
import UIKit

/// Farben, Maße und Bewegung für die iPhone-App.
enum Theme {
    // MARK: Farben

    static let paper = Color(light: 0xF6F6F8, dark: 0x121215)
    /// Karten und Listenzeilen.
    static let card = Color(light: 0xFFFFFF, dark: 0x1D1D22)
    /// Eingelassene Flächen in Karten (Chips, Felder).
    static let well = Color(light: 0xEDEDF1, dark: 0x2A2A31)
    /// Tinte: Text und die wichtigste Schaltfläche.
    static let ink = Color(light: 0x141417, dark: 0xF6F6F8)
    /// Schrift auf Tinte.
    static let onInk = Color(light: 0xFFFFFF, dark: 0x141417)
    static let inkSecondary = Color(light: 0x60616B, dark: 0xAAABB5)
    static let hairline = Color(light: 0x141417, dark: 0xFFFFFF).opacity(0.09)

    static let blush = Color(light: 0xFCEBF0, dark: 0xFCEBF0)
    static let accent = Color(light: 0x99445C, dark: 0xFFDCE7)
    static let success = Color(light: 0x23735D, dark: 0x76CFAD)

    // Neutraler Hintergrund für Fotos, die fehlen oder noch laden.
    static let recipeBackdrop = Color(light: 0x26262D, dark: 0x26262D)
    static let photoPlaceholder = Color(light: 0x525360, dark: 0x42434E)
    static let recipePanel = Color.black.opacity(0.17)
    static let recipeHighlight = Color.white.opacity(0.13)
    static let recipeSecondary = Color.white.opacity(0.76)
    static let recipeAction = Color.white
    static let recipeActionInk = Color.black
    static let assistantButton = Color(light: 0x141417, dark: 0x141417)

    static let importApricot = Color(light: 0xFFE0B7, dark: 0x51351D)
    static let importRose = Color(light: 0xFFDDD9, dark: 0x502E37)
    static let importMint = Color(light: 0xD6EEDF, dark: 0x254539)
    static let importPeriwinkle = Color(light: 0xE1E4FF, dark: 0x343954)
    static let importSand = Color(light: 0xF6ECD4, dark: 0x463C2A)

    // MARK: Maße

    static let radiusCard: CGFloat = 26
    static let radiusControl: CGFloat = 18
    static let gutter: CGFloat = 20

    // MARK: Bewegung

    /// Standard: kritisch gedämpft, kein Überschwingen.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 1)
    /// Nur nach einer Geste mit Schwung (Wurf, Loslassen) oder für Jubel.
    static let bounce = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let press = Animation.spring(response: 0.22, dampingFraction: 1)

    // MARK: Schrift

    /// Große, fette Überschrift. Skaliert mit der Textgröße des Systems.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size), weight: .bold)
    }
}

extension Color {
    /// Farbe mit eigenem Wert für helles und dunkles Erscheinungsbild.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

private extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

// MARK: - Hintergrund

/// Neutraler, deckender Bildschirmhintergrund.
struct PaperBackground: View {
    var body: some View {
        Theme.paper.ignoresSafeArea()
    }
}

extension View {
    /// Macht aus einer Liste, einem Formular oder einer Scrollansicht einen Gnocchi-Bildschirm.
    func gnScreen() -> some View {
        scrollContentBackground(.hidden)
            .background { PaperBackground() }
    }

    /// Weiße Karte mit großem Radius und feiner Kante.
    func gnCard(padding: CGFloat = 18, radius: CGFloat = Theme.radiusCard) -> some View {
        self.padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }
}

private struct RecipeSectionDragKey: EnvironmentKey {
    static let defaultValue: RecipeSectionDrag? = nil
}

extension EnvironmentValues {
    var recipeSectionDrag: RecipeSectionDrag? {
        get { self[RecipeSectionDragKey.self] }
        set { self[RecipeSectionDragKey.self] = newValue }
    }
}

struct RecipePanel<Content: View>: View {
    @Environment(\.recipeSectionDrag) private var drag
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let drag {
                        Spacer(minLength: 0)
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(Theme.recipeSecondary)
                            .contentShape(.rect)
                            .overlay { RecipeSectionHandle(title: title, drag: drag).accessibilityHidden(true) }
                            .accessibilityLabel("Rezeptbereich ziehen")
                            .accessibilityHint("Kurz halten und dann verschieben")
                    }
                }
                .padding(.vertical, drag == nil ? 0 : -8)
                Rectangle()
                    .fill(Theme.recipeHighlight)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.gutter)
        .background(Theme.recipePanel, in: .rect(cornerRadius: Theme.radiusCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .strokeBorder(Theme.recipeHighlight)
                .allowsHitTesting(false)
        }
    }
}
