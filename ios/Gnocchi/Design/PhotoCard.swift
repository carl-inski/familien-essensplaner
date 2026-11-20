import SwiftUI
import UIKit

struct PhotoCard: View {
    var url: URL?
    var title: String
    var metadata: String? = nil
    var symbol: String = "fork.knife"
    var aspectRatio: CGFloat = 0.75
    var compact = false

    @Environment(\.dynamicTypeSize) private var textSize

    private var radius: CGFloat { compact ? Theme.radiusControl : Theme.radiusCard }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear.aspectRatio(aspectRatio, contentMode: .fit)
            VStack(spacing: compact ? 3 : 5) {
                if let metadata, !metadata.isEmpty {
                    Text(metadata)
                        .font(compact ? .caption2.weight(.medium) : .footnote.weight(.medium))
                        .foregroundStyle(Theme.recipeSecondary)
                        .lineLimit(compact && !textSize.isAccessibilitySize ? 1 : nil)
                }
                Text(title)
                    .font(compact ? .footnote.weight(.semibold) : .headline)
                    .lineLimit(textSize.isAccessibilitySize ? nil : 2)
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, compact ? 7 : 12)
            .padding(.top, compact ? 38 : 56)
            .padding(.bottom, compact ? 10 : 17)
            .frame(maxWidth: .infinity)
        }
        .background {
            artwork
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.25),
                        .init(color: .black.opacity(0.33), location: 0.53),
                        .init(color: .black.opacity(0.59), location: 0.76),
                        .init(color: .black.opacity(0.78), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .clipShape(.rect(cornerRadius: radius))
        .overlay {
            RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.recipeHighlight)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(compact ? 0.08 : 0.12), radius: compact ? 5 : 10, y: compact ? 3 : 5)
        .contentShape(.rect(cornerRadius: radius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(metadata ?? "")
    }

    private var artwork: some View {
        GeometryReader { geometry in
            CatalogImage(url: url) { image in
                let photo = image.resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                photo.overlay {
                    photo.blur(radius: compact ? 10 : 16, opaque: true)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0.28),
                                .init(color: .black.opacity(0.35), location: 0.52),
                                .init(color: .black.opacity(0.84), location: 0.69),
                                .init(color: .black, location: 0.81)
                            ], startPoint: .top, endPoint: .bottom)
                        }
                }
            } placeholder: {
                LinearGradient(colors: [Theme.photoPlaceholder, Theme.recipeBackdrop],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(alignment: .top) {
                        Image(systemName: symbol)
                            .font(.system(size: compact ? 23 : 32, weight: .light))
                            .foregroundStyle(Theme.recipeSecondary)
                            .padding(.top, geometry.size.height * 0.22)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

struct CatalogImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        if let url, url.isFileURL {
            if let image = UIImage(contentsOfFile: url.path) {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        } else {
            AsyncImage(url: url, content: content, placeholder: placeholder)
        }
    }
}
