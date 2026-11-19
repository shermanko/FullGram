import Foundation
import UIKit
import ImageIO

public struct FullGramAvatarFramePreset: Equatable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let fileName: String
    public let accentHex: UInt32
    public let isBundled: Bool
}

public enum FullGramAvatarFrames {
    public static let didChangeNotification = Notification.Name("FullGram.AvatarFramesChanged")

    private static let showInChatsKey = "fullgram.frames.showInChats"

    private static let rawBaseURL = "https://raw.githubusercontent.com/shermanko/FullGram/master/assets/frames/"
    private static let cdnBaseURL = "https://cdn.jsdelivr.net/gh/shermanko/FullGram@master/assets/frames/"

    private static let stateLock = NSLock()
    private static var cachedShowInChats: Bool?

    public static var showInChatListAndMessages: Bool {
        get {
            self.stateLock.lock()
            if let v = self.cachedShowInChats {
                self.stateLock.unlock()
                return v
            }
            let resolved = (UserDefaults.standard.object(forKey: showInChatsKey) == nil)
                ? true
                : UserDefaults.standard.bool(forKey: showInChatsKey)
            self.cachedShowInChats = resolved
            self.stateLock.unlock()
            return resolved
        }
        set {
            self.stateLock.lock()
            self.cachedShowInChats = newValue
            self.stateLock.unlock()
            UserDefaults.standard.set(newValue, forKey: showInChatsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static func selectedFrameId(forPeerId peerId: Int64, selfPeerId: Int64? = nil) -> String? {
        return FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId ?? peerId)?.frameId
    }

    public static func setSelectedFrame(forPeerId peerId: Int64, frameId: String?) {
        FullGramCloudCosmetics.shared.setFrame(forPeerId: peerId, frameId: frameId)
    }

    public static func frame(forPeerId peerId: Int64?, selfPeerId: Int64?) -> FullGramAvatarFramePreset? {
        guard let cosmetics = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId),
              let id = cosmetics.frameId,
              !id.isEmpty else {
            return nil
        }
        return self.framesById[id]
    }

    /// 4 лёгкие рамки встроены офлайн в IPA, ещё 12 загружаются по требованию с GitHub/jsDelivr и кэшируются локально (экономия ~6 МБ IPA).
    public static let allFrames: [FullGramAvatarFramePreset] = [
        FullGramAvatarFramePreset(id: "futuristic_ui", title: "Futuristic UI", category: "Кибер", fileName: "frame_futuristic_ui", accentHex: 0x00E5FF, isBundled: true),
        FullGramAvatarFramePreset(id: "disxcore", title: "DISXCORE Headset", category: "Кибер", fileName: "frame_disxcore", accentHex: 0x7C4DFF, isBundled: true),
        FullGramAvatarFramePreset(id: "rainbow", title: "Hug the Rainbow", category: "Неон", fileName: "frame_rainbow", accentHex: 0xFF6B9D, isBundled: true),
        FullGramAvatarFramePreset(id: "smoke", title: "Dark Smoke", category: "Эффект", fileName: "frame_smoke", accentHex: 0x94A3B8, isBundled: true),
        FullGramAvatarFramePreset(id: "glitch", title: "Cyber Glitch", category: "Кибер", fileName: "frame_glitch", accentHex: 0xFF2A85, isBundled: false),
        FullGramAvatarFramePreset(id: "chromawave", title: "Chromawave", category: "Неон", fileName: "frame_chromawave", accentHex: 0x00FFA3, isBundled: false),
        FullGramAvatarFramePreset(id: "lightning", title: "Lightning Storm", category: "Стихия", fileName: "frame_lightning", accentHex: 0x38BDF8, isBundled: false),
        FullGramAvatarFramePreset(id: "blade_storm", title: "Blade Storm", category: "Стихия", fileName: "frame_blade_storm", accentHex: 0xF43F5E, isBundled: false),
        FullGramAvatarFramePreset(id: "radiating_energy", title: "Radiating Energy", category: "Аниме", fileName: "frame_radiating_energy", accentHex: 0xFBBF24, isBundled: false),
        FullGramAvatarFramePreset(id: "ki_energy", title: "Ki Aura", category: "Аниме", fileName: "frame_ki_energy", accentHex: 0x60A5FA, isBundled: false),
        FullGramAvatarFramePreset(id: "ufo", title: "UFO Abduction", category: "Космос", fileName: "frame_ufo", accentHex: 0x34D399, isBundled: false),
        FullGramAvatarFramePreset(id: "butterflies", title: "Butterflies", category: "Природа", fileName: "frame_butterflies", accentHex: 0xA78BFA, isBundled: false),
        FullGramAvatarFramePreset(id: "cat_ears", title: "Cat Ears", category: "Милые", fileName: "frame_cat_ears", accentHex: 0xF472B6, isBundled: false),
        FullGramAvatarFramePreset(id: "cozy_cat", title: "Cozy Cat", category: "Милые", fileName: "frame_cozy_cat", accentHex: 0xFB923C, isBundled: false),
        FullGramAvatarFramePreset(id: "in_love", title: "In Love", category: "Эмоции", fileName: "frame_in_love", accentHex: 0xFB7185, isBundled: false),
        FullGramAvatarFramePreset(id: "starry_eyed", title: "Starry Eyed", category: "Эмоции", fileName: "frame_starry_eyed", accentHex: 0xFACC15, isBundled: false)
    ]

    private static let framesById: [String: FullGramAvatarFramePreset] = Dictionary(
        uniqueKeysWithValues: allFrames.map { ($0.id, $0) }
    )

    public static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FullGramFrames", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func cachedDiskURL(for preset: FullGramAvatarFramePreset) -> URL {
        return self.cacheDirectory().appendingPathComponent("\(preset.fileName).png")
    }

    public static func remoteURLs(for preset: FullGramAvatarFramePreset) -> [URL] {
        let file = "\(preset.fileName).png"
        return [
            URL(string: self.rawBaseURL + file),
            URL(string: self.cdnBaseURL + file)
        ].compactMap { $0 }
    }

    public static func frameURL(for preset: FullGramAvatarFramePreset) -> URL? {
        if let url = Bundle.main.url(forResource: preset.fileName, withExtension: "png", subdirectory: "FullGramFrames") {
            return url
        }
        if let url = Bundle.main.url(forResource: preset.fileName, withExtension: "png") {
            return url
        }
        let cached = self.cachedDiskURL(for: preset)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        return nil
    }
}

public final class FullGramAnimatedFrameSequence: @unchecked Sendable {
    public let frames: [CGImage]
    public let keyTimes: [NSNumber]
    public let totalDuration: CFTimeInterval

    init(frames: [CGImage], keyTimes: [NSNumber], totalDuration: CFTimeInterval) {
        self.frames = frames
        self.keyTimes = keyTimes
        self.totalDuration = totalDuration
    }
}

public final class FullGramAnimatedImageDecoder {
    private static let sequenceCache: NSCache<NSString, FullGramAnimatedFrameSequence> = {
        let c = NSCache<NSString, FullGramAnimatedFrameSequence>()
        c.countLimit = 8
        return c
    }()
    private static let decodeQueue = DispatchQueue(label: "FullGram.AvatarFrameDecode", qos: .userInitiated, attributes: .concurrent)
    private static let inflightLock = NSLock()
    private static var inflightCallbacks: [String: [@Sendable (FullGramAnimatedFrameSequence?) -> Void]] = [:]
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15.0
        cfg.timeoutIntervalForResource = 30.0
        return URLSession(configuration: cfg)
    }()

    public static func cachedSequence(for preset: FullGramAvatarFramePreset) -> FullGramAnimatedFrameSequence? {
        return self.sequenceCache.object(forKey: preset.id as NSString)
    }

    public static func sequenceAsync(
        for preset: FullGramAvatarFramePreset,
        maxPixelSize: Int = 220,
        completion: @escaping @Sendable (FullGramAnimatedFrameSequence?) -> Void
    ) {
        if let cached = self.cachedSequence(for: preset) {
            completion(cached)
            return
        }

        self.inflightLock.lock()
        if var callbacks = self.inflightCallbacks[preset.id] {
            callbacks.append(completion)
            self.inflightCallbacks[preset.id] = callbacks
            self.inflightLock.unlock()
            return
        }
        self.inflightCallbacks[preset.id] = [completion]
        self.inflightLock.unlock()

        func finish(_ seq: FullGramAnimatedFrameSequence?) {
            self.inflightLock.lock()
            let callbacks = self.inflightCallbacks.removeValue(forKey: preset.id) ?? []
            self.inflightLock.unlock()
            DispatchQueue.main.async {
                for cb in callbacks {
                    cb(seq)
                }
            }
        }

        self.decodeQueue.async {
            if let localSeq = self.sequence(for: preset, maxPixelSize: maxPixelSize) {
                finish(localSeq)
                return
            }
            guard !preset.isBundled else {
                finish(nil)
                return
            }
            self.downloadRemoteFrame(preset: preset, urls: FullGramAvatarFrames.remoteURLs(for: preset)) { ok in
                guard ok else {
                    finish(nil)
                    return
                }
                self.decodeQueue.async {
                    finish(self.sequence(for: preset, maxPixelSize: maxPixelSize))
                }
            }
        }
    }

    private static func downloadRemoteFrame(
        preset: FullGramAvatarFramePreset,
        urls: [URL],
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard let first = urls.first else {
            completion(false)
            return
        }
        let rest = Array(urls.dropFirst())
        self.session.dataTask(with: first) { data, response, _ in
            if let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               let data,
               data.count > 128,
               data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) {
                let dst = FullGramAvatarFrames.cachedDiskURL(for: preset)
                try? data.write(to: dst, options: .atomic)
                completion(true)
                return
            }
            if !rest.isEmpty {
                self.downloadRemoteFrame(preset: preset, urls: rest, completion: completion)
            } else {
                completion(false)
            }
        }.resume()
    }

    public static func sequence(for preset: FullGramAvatarFramePreset, maxPixelSize: Int = 220) -> FullGramAnimatedFrameSequence? {
        let cacheKey = preset.id as NSString
        if let cached = self.sequenceCache.object(forKey: cacheKey) {
            return cached
        }

        guard let url = FullGramAvatarFrames.frameURL(for: preset),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var images: [CGImage] = []
        var durations: [Double] = []
        images.reserveCapacity(count)
        durations.reserveCapacity(count)

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        var totalDuration: Double = 0.0
        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, i, thumbOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, i, nil) else {
                continue
            }
            let delay = self.frameDelay(source: source, index: i)
            images.append(cgImage)
            durations.append(delay)
            totalDuration += delay
        }

        guard !images.isEmpty else { return nil }
        if totalDuration <= 0.01 {
            totalDuration = Double(images.count) * 0.05
        }

        var keyTimes: [NSNumber] = []
        keyTimes.reserveCapacity(images.count + 1)
        var elapsed: Double = 0.0
        for d in durations {
            keyTimes.append(NSNumber(value: elapsed / totalDuration))
            elapsed += d
        }

        let seq = FullGramAnimatedFrameSequence(frames: images, keyTimes: keyTimes, totalDuration: totalDuration)
        self.sequenceCache.setObject(seq, forKey: cacheKey, cost: images.count * maxPixelSize)
        return seq
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.05
        }
        if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            if let unclamped = png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double, unclamped > 0.0 {
                return max(0.02, unclamped)
            }
            if let delay = png[kCGImagePropertyAPNGDelayTime] as? Double, delay > 0.0 {
                return max(0.02, delay)
            }
        }
        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0.0 {
                return max(0.02, unclamped)
            }
            if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0.0 {
                return max(0.02, delay)
            }
        }
        return 0.05
    }
}

public final class FullGramAvatarFrameView: UIView {
    private let frameLayer = CALayer()
    private var currentFrameId: String?
    private var pendingFrameId: String?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.clipsToBounds = false
        self.frameLayer.contentsGravity = .resizeAspect
        self.layer.addSublayer(self.frameLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale: CGFloat = 1.24
        let w = self.bounds.width * scale
        let h = self.bounds.height * scale
        self.frameLayer.frame = CGRect(
            x: (self.bounds.width - w) * 0.5,
            y: (self.bounds.height - h) * 0.5,
            width: w,
            height: h
        )
    }

    public func configure(with preset: FullGramAvatarFramePreset?) {
        guard let preset else {
            self.currentFrameId = nil
            self.pendingFrameId = nil
            self.frameLayer.removeAllAnimations()
            self.frameLayer.contents = nil
            self.isHidden = true
            return
        }
        self.isHidden = false
        if self.currentFrameId == preset.id && self.frameLayer.animation(forKey: "fg.apng") != nil {
            return
        }
        self.pendingFrameId = preset.id

        if let cached = FullGramAnimatedImageDecoder.cachedSequence(for: preset) {
            self.apply(sequence: cached, frameId: preset.id)
            return
        }

        self.frameLayer.removeAllAnimations()
        let targetId = preset.id
        FullGramAnimatedImageDecoder.sequenceAsync(for: preset) { [weak self] seq in
            Task { @MainActor in
                guard let self, self.pendingFrameId == targetId else { return }
                self.apply(sequence: seq, frameId: targetId)
            }
        }
    }

    private func apply(sequence seq: FullGramAnimatedFrameSequence?, frameId: String) {
        self.currentFrameId = frameId
        self.frameLayer.removeAllAnimations()

        guard let seq, !seq.frames.isEmpty else {
            self.frameLayer.contents = nil
            return
        }

        if seq.frames.count == 1 {
            self.frameLayer.contents = seq.frames[0]
            return
        }

        self.frameLayer.contents = seq.frames[0]
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = seq.frames
        anim.keyTimes = seq.keyTimes
        anim.duration = seq.totalDuration
        anim.calculationMode = .discrete
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        self.frameLayer.add(anim, forKey: "fg.apng")
    }
}
