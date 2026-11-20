import AVFoundation
import SwiftUI
import UIKit

struct RecipeCamera: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: RecipeCamera
        init(parent: RecipeCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) else {
                parent.onCancel()
                return
            }
            parent.onPhoto(data)
        }
    }
}

struct RecipeImportPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let preview: UIImage

    init?(data: Data) {
        guard let jpeg = RecipePhoto.jpeg(from: data, maxPixelSize: 1_400), let preview = UIImage(data: jpeg) else { return nil }
        self.data = jpeg
        self.preview = preview
    }
}

enum RecipeVideoFrames {
    static func load(from url: URL) async -> [String] {
        let domains = ["cdninstagram.com", "fbcdn.net", "tiktokcdn.com", "tiktokcdn-us.com",
                       "tiktokcdn-eu.com", "tiktok.com"]
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host()?.lowercased(),
              domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return [] }

        return await withTaskGroup(of: [String].self) { group in
            group.addTask { await sample(url) }
            group.addTask {
                try? await Task.sleep(for: .seconds(18))
                return []
            }
            let frames = await group.next() ?? []
            group.cancelAll()
            return frames
        }
    }

    @MainActor private static func sample(_ url: URL) async -> [String] {
        let reader = FrameReader(url: url)
        return await withTaskCancellationHandler {
            guard let duration = try? await reader.asset.load(.duration) else { return [] }
            let length = duration.seconds
            guard length.isFinite, length > 0 && length <= 300 else { return [] }
            let fractions = [0.03, 0.12, 0.22, 0.33, 0.44, 0.55, 0.66, 0.77, 0.88, 0.96]
            var frames: [String] = []
            for fraction in fractions {
                if Task.isCancelled { break }
                let time = CMTime(seconds: length * fraction, preferredTimescale: 600)
                if let frame = await reader.image(at: time),
                   let photo = UIImage(cgImage: frame).jpegData(compressionQuality: 0.72) {
                    frames.append(photo.base64EncodedString())
                }
            }
            return frames
        } onCancel: {
            Task { @MainActor in reader.cancel() }
        }
    }

    @MainActor private final class FrameReader {
        let asset: AVURLAsset
        private let generator: AVAssetImageGenerator

        init(url: URL) {
            asset = AVURLAsset(url: url)
            generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
        }

        func image(at time: CMTime) async -> CGImage? {
            await withCheckedContinuation { continuation in
                generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, _ in
                    continuation.resume(returning: image)
                }
            }
        }

        func cancel() {
            asset.cancelLoading()
            generator.cancelAllCGImageGeneration()
        }
    }
}
