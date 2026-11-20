import SwiftUI

/// Jubel für besondere Momente (Einkauf erledigt, Woche voll geplant):
/// Ein Haken und Zutatenkonfetti bestätigen den Abschluss.
/// Verschwindet von allein und blockiert keine Eingaben.
struct Celebration: Equatable, Identifiable {
    let id = UUID()
    let title: String
    var detail: String?
}

private struct CelebrationOverlay: ViewModifier {
    @Binding var celebration: Celebration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppPreferences.self) private var preferences: AppPreferences?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let celebration {
                    ZStack {
                        if !reduceMotion { ConfettiRain().allowsHitTesting(false) }
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48, weight: .regular))
                                .foregroundStyle(Theme.success)
                                .accessibilityHidden(true)
                            Text(celebration.title)
                                .font(Theme.display(24, relativeTo: .title2))
                                .multilineTextAlignment(.center)
                            if let detail = celebration.detail {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 26)
                        .background(.regularMaterial, in: .rect(cornerRadius: 32, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Theme.hairline)
                        }
                        .shadow(color: .black.opacity(0.14), radius: 30, y: 12)
                        .padding(.horizontal, 36)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isStaticText)
                    }
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
                    .onTapGesture { dismiss() }
                    .task(id: celebration.id) {
                        // Bei Abbruch (Ansicht neu aufgebaut) stehen lassen, sonst wäre der Jubel sofort weg
                        do { try await Task.sleep(for: .seconds(3.2)) } catch { return }
                        dismiss()
                    }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.bounce, value: celebration)
            .sensoryFeedback(.success, trigger: celebration?.id) { _, new in
                new != nil && (preferences?.hapticsEnabled ?? true)
            }
    }

    private func dismiss() { celebration = nil }
}

extension View {
    /// Zeigt den Jubel, solange `celebration` gesetzt ist.
    func celebration(_ celebration: Binding<Celebration?>) -> some View {
        modifier(CelebrationOverlay(celebration: celebration))
    }
}

/// Fallende Zutaten. Reine Zeitfunktion, daher ohne Zustand und jederzeit abbrechbar.
private struct ConfettiRain: View {
    private struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let spin: Double
        let size: Double
        let kind: Int
        let sway: Double
    }

    private let pieces: [Piece] = (0..<34).map { index in
        // Feste, aber gestreute Werte: gleiches Bild bei jedem Start, kein Zufall im View-Aufbau nötig
        let f = Double(index)
        return Piece(
            x: (f * 0.6180339887).truncatingRemainder(dividingBy: 1),
            delay: (f * 0.137).truncatingRemainder(dividingBy: 0.9),
            speed: 0.55 + (f * 0.271).truncatingRemainder(dividingBy: 0.5),
            spin: 120 + (f * 53).truncatingRemainder(dividingBy: 260),
            size: 9 + (f * 3.7).truncatingRemainder(dividingBy: 9),
            kind: index % 3,
            sway: 10 + (f * 7.3).truncatingRemainder(dividingBy: 22)
        )
    }
    private let start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for piece in pieces {
                    let local = t - piece.delay
                    guard local > 0 else { continue }
                    let y = -20 + local * piece.speed * size.height * 0.62
                    guard y < size.height + 30 else { continue }
                    let x = piece.x * size.width + sin(local * 2.4 + piece.x * 9) * piece.sway
                    var layer = context
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .degrees(local * piece.spin))
                    layer.opacity = min(1, max(0, 2.6 - local))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 2, width: piece.size, height: piece.size)
                    switch piece.kind {
                    case 0: // Basilikumblatt
                        layer.fill(Path(ellipseIn: rect.insetBy(dx: piece.size * 0.18, dy: 0)), with: .color(Theme.success))
                    case 1: // Tomate
                        layer.fill(Path(ellipseIn: rect), with: .color(Theme.accent))
                    default: // Parmesanspan
                        layer.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: piece.size * 0.3), cornerRadius: 2),
                                   with: .color(Theme.inkSecondary))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Kurzmeldung

/// Kleine Pille am oberen Rand, die eine erledigte Aktion bestätigt.
struct ToastPill: View {
    let text: String
    var symbol = "checkmark.circle.fill"

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.onInk)
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Theme.ink, in: .capsule)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}
