import SwiftUI

struct CollapsingActionScrollView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var expanded: Bool
    @ViewBuilder var content: Content
    @State private var activity = 0
    @State private var scrolling = false
    @State private var observedOffset: Int?

    var body: some View {
        scroll
            .task(id: activity) {
                guard activity > 0, !scrolling else { return }
                do { try await Task.sleep(for: .milliseconds(650)) }
                catch { return }
                if !scrolling { setExpanded(false) }
            }
    }

    @ViewBuilder private var scroll: some View {
        if #available(iOS 18, *) {
            ScrollView { content }
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .interacting, .decelerating, .animating:
                        guard !scrolling else { return }
                        scrolling = true
                        activity += 1
                        setExpanded(true)
                    case .idle:
                        guard scrolling else { return }
                        scrolling = false
                        activity += 1
                    case .tracking:
                        break
                    @unknown default:
                        break
                    }
                }
        } else {
            ScrollView {
                content.onGeometryChange(for: Int.self) {
                    Int($0.frame(in: .named("collapsing-action")).minY.rounded())
                } action: { offset in
                    defer { observedOffset = offset }
                    guard let previous = observedOffset, offset != previous else { return }
                    activity += 1
                    setExpanded(true)
                }
            }
            .coordinateSpace(name: "collapsing-action")
        }
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        withAnimation(reduceMotion ? nil : Theme.press) { expanded = value }
    }
}
