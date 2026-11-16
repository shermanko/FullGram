import Foundation
import UIKit
import CoreImage
import CoreVideo
import Vision
import Display

/// Real-time face masks for round video messages (`Меняет лицо в кружке`):
/// pixelate, blur, emoji, or the FullGram mascot icon (`FullGramIcon_FullGramMascot.png`).
final class FullGramRoundVideoMask {
    private let mask: FullGramRoundMask
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var faces: [CGRect] = []
    private var frameIndex = 0
    private var cachedEmojiImage: CIImage?
    private var cachedMascotImage: CIImage?

    static func makeIfEnabled() -> FullGramRoundVideoMask? {
        let mask = FullGramRoundMask.current
        guard mask != .off else { return nil }
        return FullGramRoundVideoMask(mask: mask)
    }

    private init(mask: FullGramRoundMask) {
        self.mask = mask
    }

    private func updateFaces(_ buffer: CVPixelBuffer) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        try? handler.perform([request])
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        let found = (request.results ?? []).map { observation -> CGRect in
            let box = observation.boundingBox
            return CGRect(
                x: box.minX * width,
                y: box.minY * height,
                width: box.width * width,
                height: box.height * height
            ).insetBy(dx: -box.width * width * 0.18, dy: -box.height * height * 0.25)
        }
        if !found.isEmpty || self.frameIndex % 30 == 0 {
            self.faces = found
        }
    }

    private func emojiOverlay(size: CGFloat) -> CIImage? {
        if let cached = self.cachedEmojiImage, abs(cached.extent.width - size) < 1.0 {
            return cached
        }
        let side = max(24.0, size)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            ("😎" as NSString).draw(
                in: CGRect(x: 0.0, y: 0.0, width: side, height: side),
                withAttributes: [.font: UIFont.systemFont(ofSize: side * 0.85)]
            )
        }
        self.cachedEmojiImage = image.cgImage.map { CIImage(cgImage: $0) }
        return self.cachedEmojiImage
    }

    private func mascotOverlay(size: CGFloat) -> CIImage? {
        let base: CIImage?
        if let cached = self.cachedMascotImage {
            base = cached
        } else if let path = Bundle.main.path(forResource: "FullGramIcon_FullGramMascot", ofType: "png"),
                  let uiImage = UIImage(contentsOfFile: path),
                  let cgImage = uiImage.cgImage {
            let ci = CIImage(cgImage: cgImage)
            self.cachedMascotImage = ci
            base = ci
        } else {
            return self.emojiOverlay(size: size)
        }
        guard let mascot = base, mascot.extent.width > 0.0, mascot.extent.height > 0.0 else {
            return nil
        }
        let scale = max(24.0, size) / max(mascot.extent.width, mascot.extent.height)
        return mascot.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    func renderInPlace(_ buffer: CVPixelBuffer) {
        self.frameIndex += 1
        if self.frameIndex % 4 == 1 {
            self.updateFaces(buffer)
        }
        guard !self.faces.isEmpty else { return }

        let source = CIImage(cvPixelBuffer: buffer)
        var image = source

        for face in self.faces {
            let region = face.intersection(source.extent)
            guard !region.isEmpty else { continue }
            let covered: CIImage
            switch self.mask {
            case .off:
                continue
            case .pixelate:
                covered = source
                    .applyingFilter("CIPixellate", parameters: [
                        kCIInputScaleKey: max(8.0, region.width / 12.0),
                        kCIInputCenterKey: CIVector(x: region.midX, y: region.midY)
                    ])
                    .cropped(to: region)
            case .blur:
                covered = source
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [
                        kCIInputRadiusKey: max(10.0, region.width / 10.0)
                    ])
                    .cropped(to: region)
            case .emoji:
                guard let overlay = self.emojiOverlay(size: max(region.width, region.height).rounded()) else { continue }
                covered = overlay.transformed(by: CGAffineTransform(
                    translationX: region.midX - overlay.extent.width / 2.0,
                    y: region.midY - overlay.extent.height / 2.0
                ))
            case .mascot:
                guard let overlay = self.mascotOverlay(size: max(region.width, region.height).rounded()) else { continue }
                covered = overlay.transformed(by: CGAffineTransform(
                    translationX: region.midX - overlay.extent.width / 2.0 - overlay.extent.minX,
                    y: region.midY - overlay.extent.height / 2.0 - overlay.extent.minY
                ))
            }
            image = covered.composited(over: image)
        }

        if image !== source {
            self.context.render(image.cropped(to: source.extent), to: buffer)
        }
    }
}
