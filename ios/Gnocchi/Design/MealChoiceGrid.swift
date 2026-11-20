import GnocchiCore
import SwiftUI

struct MealChoiceGrid: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var selection: Meal
    var detail: (Meal) -> String = { _ in "" }

    var body: some View {
        let count = textSize.isAccessibilitySize ? 1 : textSize > .large ? 2 : 4
        let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: count)
        LazyVGrid(columns: columns, spacing: 9) {
            ForEach(Meal.allCases, id: \.self) { meal in
                let selected = selection == meal
                Button {
                    selection = meal
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: meal.icon)
                            .font(.title2.weight(.medium))
                            .accessibilityHidden(true)
                        Text(meal.label)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(textSize.isAccessibilitySize ? nil : 1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 59)
                    .padding(5)
                    .background(selected ? Theme.accent.opacity(0.13) : Theme.card,
                                in: .rect(cornerRadius: Theme.radiusControl))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.radiusControl)
                            .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1)
                    }
                    .contentShape(.rect(cornerRadius: Theme.radiusControl))
                }
                .buttonStyle(.plain)
                .accessibilityValue(detail(meal))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
