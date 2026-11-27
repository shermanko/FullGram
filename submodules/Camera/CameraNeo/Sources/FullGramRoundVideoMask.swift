import Foundation
import UIKit
import CoreImage
import CoreText
import CoreVideo
import Vision
import Display

/// Real-time face masks for round video messages (`Меняет лицо в кружке`):
/// pixelate, blur, emoji, or the FullGram mascot icon (`FullGramIcon_FullGramMascot.png`).
final class FullGramRoundVideoMask {
    private let mask: FullGramRoundMask
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private var faces: [CGRect] = []
    private var frameIndex = 0
    private var emptyDetectionCount = 0
    private var cachedEmojiImage: CIImage?
    private var cachedMascotImage: CIImage?
    private var cachedScaledMascot: (size: CGFloat, image: CIImage)?

    static func makeIfEnabled() -> FullGramRoundVideoMask? {
        let mask = FullGramRoundMask.current
        guard mask != .off else { return nil }
        return FullGramRoundVideoMask(mask: mask)
    }

    private init(mask: FullGramRoundMask) {
        self.mask = mask
    }

    private func updateFaces(_ buffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        try? handler.perform([self.faceRequest])
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        let found = (self.faceRequest.results ?? []).map { observation -> CGRect in
            let box = observation.boundingBox
            return CGRect(
                x: box.minX * width,
                y: box.minY * height,
                width: box.width * width,
                height: box.height * height
            ).insetBy(dx: -box.width * width * 0.18, dy: -box.height * height * 0.25)
        }
        if !found.isEmpty {
            self.emptyDetectionCount = 0
            self.faces = found
        } else {
            self.emptyDetectionCount += 1
            if self.emptyDetectionCount >= 8 {
                self.faces = []
            }
        }
    }

    private func emojiOverlay(size: CGFloat) -> CIImage? {
        guard size.isFinite, size > 0.0 else { return nil }
        let side = min(512.0, max(24.0, (size / 4.0).rounded() * 4.0))
        if let cached = self.cachedEmojiImage, abs(cached.extent.width - side) < 2.0 {
            return cached
        }
        let dim = Int(side)
        guard dim > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgContext = CGContext(
                  data: nil,
                  width: dim,
                  height: dim,
                  bitsPerComponent: 8,
                  bytesPerRow: dim * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        let ctFont = CTFontCreateWithName("AppleColorEmoji" as CFString, side * 0.78, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont
        ]
        let attrStr = NSAttributedString(string: "😎", attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetImageBounds(line, cgContext)
        cgContext.textPosition = CGPoint(
            x: (side - bounds.width) * 0.5 - bounds.minX,
            y: (side - bounds.height) * 0.5 - bounds.minY
        )
        CTLineDraw(line, cgContext)
        self.cachedEmojiImage = cgContext.makeImage().map { CIImage(cgImage: $0) }
        return self.cachedEmojiImage
    }

    private func mascotOverlay(size: CGFloat) -> CIImage? {
        guard size.isFinite, size > 0.0 else { return nil }
        let targetSide = min(512.0, max(24.0, (size / 4.0).rounded() * 4.0))
        if let scaled = self.cachedScaledMascot, abs(scaled.size - targetSide) < 2.0 {
            return scaled.image
        }
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
        let scale = targetSide / max(mascot.extent.width, mascot.extent.height)
        let scaledImg = mascot.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        self.cachedScaledMascot = (targetSide, scaledImg)
        return scaledImg
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
