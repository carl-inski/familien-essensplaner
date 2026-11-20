import ImageIO
import SwiftUI

struct RecipeDetailPhoto {
    let url: URL?
    let image: CGImage
    let backdrop: Color

    static let neutralBackdrop = Color(white: 0.16)

    static func load(_ url: URL?) async -> Self? {
        guard let url else { return nil }
        do {
            let source: CGImageSource?
            if url.isFileURL {
                source = CGImageSourceCreateWithURL(url as CFURL, nil)
            } else {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
                source = CGImageSourceCreateWithData(data as CFData, nil)
            }
            guard !Task.isCancelled, let source else { return nil }
            return make(source: source, url: url)
        } catch {
            return nil
        }
    }

    static func load(coverData: Data) -> Self? {
        guard let source = CGImageSourceCreateWithData(coverData as CFData, nil) else { return nil }
        return make(source: source, url: nil)
    }

    private static func make(source: CGImageSource, url: URL?) -> Self? {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600
        ] as CFDictionary) else { return nil }
        return Self(url: url, image: image, backdrop: tint(from: image) ?? neutralBackdrop)
    }

    private static func tint(from image: CGImage) -> Color? {
        let side = 24
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                     bytesPerRow: side * 4, space: space,
                                     bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                                         | CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = bitmap.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        bitmap.interpolationQuality = .medium
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var weight = 0.0
        for index in stride(from: 0, to: side * side * 4, by: 4) {
            let alpha = Double(pixels[index + 3])
            guard alpha >= 200 else { continue }
            let r = Double(pixels[index]) / alpha
            let g = Double(pixels[index + 1]) / alpha
            let b = Double(pixels[index + 2]) / alpha
            let chroma = max(r, g, b) - min(r, g, b)
            let sampleWeight = 0.12 + chroma * chroma * 3
            red += r * sampleWeight
            green += g * sampleWeight
            blue += b * sampleWeight
            weight += sampleWeight
        }
        guard weight > 0 else { return nil }
        let peak = max(red, green, blue) / weight
        guard peak > 0.04 else { return nil }
        // Hellt dunkle Fotos an und hält selbst die hellste Farbe unter 0,33 sRGB.
        let scale = 0.26 / max(0.5, peak) / weight
        return Color(red: 0.07 + red * scale, green: 0.07 + green * scale, blue: 0.07 + blue * scale)
    }
}

struct RecipeDetailArtwork: View {
    var photo: RecipeDetailPhoto?
    var backdrop: Color
    var isCover = false

    var body: some View {
        GeometryReader { geometry in
            if let photo {
                let artwork = Image(decorative: photo.image, scale: 1).resizable()
                if isCover {
                    artwork
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.48, height: geometry.size.height * 0.68)
                        .clipShape(.rect(cornerRadius: Theme.radiusControl))
                        .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 62)
                } else {
                    artwork
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay {
                            LinearGradient(stops: [
                                .init(color: .black.opacity(0.46), location: 0),
                                .init(color: .clear, location: 0.23),
                                .init(color: .clear, location: 0.36),
                                .init(color: backdrop.opacity(0.28), location: 0.55),
                                .init(color: backdrop.opacity(0.94), location: 0.82),
                                .init(color: backdrop, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        }
                }
            } else {
                Image(systemName: isCover ? "book.closed" : "fork.knife")
                    .font(.largeTitle.weight(.light))
                    .foregroundStyle(Theme.recipeSecondary)
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.8)
            }
        }
        .accessibilityHidden(true)
    }
}
