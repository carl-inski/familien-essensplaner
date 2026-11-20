import SwiftUI

// MARK: - Schaltflächen

/// Die wichtigste Aktion eines Bildschirms: Tinte, volle Breite, Pillenform.
struct InkButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink
    var foreground: Color = Theme.onInk
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(enabled ? foreground : Theme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .background(enabled ? tint : Theme.well, in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

/// Zweite Aktion: ruhige Fläche, gleiche Form.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .background(Theme.card, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1) }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle() }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
}

// MARK: - Fortschrittsring

/// Ring wie auf einem Tellerrand: zeigt einen Anteil, in der Mitte steht frei wählbarer Inhalt.
struct ProgressRing<Center: View>: View {
    let value: Double
    var lineWidth: CGFloat = 7
    var tint: Color = Theme.accent
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.well, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Theme.spring, value: value)
            center
        }
    }
}

// MARK: - Auswahlkarte

/// Antwortkarte im Onboarding: Symbol, Titel, Unterzeile, Auswahlpunkt.
struct OptionCard: View {
    let symbol: String
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? Theme.onInk : Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(selected ? Theme.onInk.opacity(0.16) : Theme.well, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail).font(.subheadline)
                            .foregroundStyle(selected ? Theme.onInk.opacity(0.75) : Theme.inkSecondary)
                    }
                }
                .foregroundStyle(selected ? Theme.onInk : Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.onInk : Theme.inkSecondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(selected ? Theme.ink : Theme.card, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: selected ? 0 : 1)
            }
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(Theme.spring, value: selected)
    }
}

/// Reagiert schon beim Antippen, nicht erst beim Loslassen.
struct PressScaleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(reduceMotion && configuration.isPressed ? 0.82 : 1)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : Theme.press, value: configuration.isPressed)
    }
}

// MARK: - Laden

struct AppLoadingView: View {
    let label: String

    var body: some View {
        ProgressView(label)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { PaperBackground() }
    }
}
