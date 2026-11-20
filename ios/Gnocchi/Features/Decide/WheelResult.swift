import SwiftUI

struct WheelResult: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let options: [String]
    let weights: [Int]
    let winner: String
    let title: (String) -> String
    var animateSpin = true
    var onReveal: (() -> Void)? = nil
    @State private var rotation = 0.0
    @State private var showingOptions = false

    private let colors: [Color] = [Theme.ink, Theme.inkSecondary, Theme.accent, Theme.ink.opacity(0.74)]

    var body: some View {
        let slices = sectors
        if !slices.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "arrowtriangle.down.fill").foregroundStyle(.primary)
                    .zIndex(1)
                    .accessibilityHidden(true)
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2
                    for slice in slices {
                        let start = Angle.degrees(slice.start - 90)
                        let end = Angle.degrees(slice.end - 90)
                        var segment = Path()
                        segment.move(to: center)
                        segment.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                        segment.closeSubpath()
                        context.fill(segment, with: .color(colors[slice.index % colors.count]))
                        let mid = (start.radians + end.radians) / 2
                        let point = CGPoint(x: center.x + cos(mid) * radius * 0.69, y: center.y + sin(mid) * radius * 0.69)
                        context.draw(Text(String(slice.index + 1)).font(.headline.monospacedDigit()).foregroundStyle(.white), at: point)
                    }
                }
                .frame(width: 166, height: 166)
                .rotationEffect(.degrees(rotation))
                .accessibilityHidden(true)

                DisclosureGroup("Gerichte auf dem Rad", isExpanded: $showingOptions) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slices, id: \.index) { slice in
                            HStack(spacing: 8) {
                                Text("\(slice.index + 1).").monospacedDigit()
                                Text(title(slice.id)).frame(maxWidth: .infinity, alignment: .leading)
                                if slice.id == winner {
                                    Image(systemName: "trophy.fill").foregroundStyle(Theme.accent)
                                        .accessibilityLabel("Gewonnen")
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            }
            .padding(.vertical, 8)
            .task {
                guard let selected = slices.first(where: { $0.id == winner }) else { return }
                let angle = 360 - (selected.start + selected.end) / 2
                if reduceMotion || !animateSpin { rotation = angle }
                else if rotation == 0 {
                    withAnimation(.easeOut(duration: 1.35)) { rotation = 720 + angle }
                    do { try await Task.sleep(for: .milliseconds(1_350)) }
                    catch { return }
                }
                onReveal?()
            }
        }
    }

    private var sectors: [Sector] {
        guard weights.count == options.count, !options.isEmpty else { return [] }
        let size = weights.map { Double(max(1, $0)) }
        let total = size.reduce(0, +)
        var angle = 0.0
        return options.indices.map { index in
            let next = angle + size[index] / total * 360
            defer { angle = next }
            return Sector(index: index, id: options[index], start: angle, end: next)
        }
    }

    private struct Sector {
        let index: Int
        let id: String
        let start: Double
        let end: Double
    }
}
