import Foundation
import UIKit
import ImageIO

// MARK: - Модели рамок аватара и анимаций открытия профиля (Discord Collectibles + Кастом)

public struct FullGramAvatarFramePreset: Equatable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let fileName: String
    public let accentHex: UInt32
    public let isBundled: Bool
    public let remoteURLs: [String]
    public let localCustomPath: String?

    public init(
        id: String,
        title: String,
        category: String,
        fileName: String,
        accentHex: UInt32,
        isBundled: Bool,
        remoteURLs: [String] = [],
        localCustomPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.fileName = fileName
        self.accentHex = accentHex
        self.isBundled = isBundled
        self.remoteURLs = remoteURLs
        self.localCustomPath = localCustomPath
    }
}

public struct FullGramProfileEffectPreset: Equatable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let layerURLs: [String]
    public let accentHex: UInt32

    public init(
        id: String,
        title: String,
        category: String,
        layerURLs: [String],
        accentHex: UInt32 = 0x7C4DFF
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.layerURLs = layerURLs
        self.accentHex = accentHex
    }
}

// MARK: - Каталог всей косметики Discord (663+ рамок, 329+ анимаций открытия профиля)

private struct FullGramDiscordCatalogPayload: Codable {
    struct FrameItem: Codable {
        let id: String
        let title: String
        let category: String
        let urls: [String]
    }
    struct EffectItem: Codable {
        let id: String
        let title: String
        let category: String
        let layers: [String]
    }
    let version: Int?
    let frames: [FrameItem]
    let profileEffects: [EffectItem]
}

public final class FullGramDiscordCosmeticsCatalog: @unchecked Sendable {
    public static let shared = FullGramDiscordCosmeticsCatalog()
    public static let didUpdateNotification = Notification.Name("FullGram.DiscordCosmeticsCatalogUpdated")

    private static let catalogURLs: [String] = [
        "https://fullgram.korsakovx.workers.dev/discord-cosmetics.json",
        "https://raw.githubusercontent.com/shermanko/FullGram/master/assets/discord_cosmetics.json",
        "https://cdn.jsdelivr.net/gh/shermanko/FullGram@master/assets/discord_cosmetics.json"
    ]
    private static let lastSyncKey = "fullgram.discordCatalog.lastSync"

    private let lock = NSRecursiveLock()
    private var discordFrames: [FullGramAvatarFramePreset] = []
    private var discordFramesById: [String: FullGramAvatarFramePreset] = [:]
    private var discordEffects: [FullGramProfileEffectPreset] = []
    private var discordEffectsById: [String: FullGramProfileEffectPreset] = [:]
    private var isFetching = false

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15.0
        cfg.timeoutIntervalForResource = 30.0
        return URLSession(configuration: cfg)
    }()

    private init() {
        self.loadDiskCache()
    }

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_discord_cosmetics.json")
    }

    private static func accentForCategory(_ category: String) -> UInt32 {
        switch category {
        case "Кибер": return 0x00E5FF
        case "Аниме": return 0xFF6B9D
        case "Милые": return 0xF472B6
        case "Стихия": return 0xF43F5E
        case "Космос": return 0x818CF8
        case "Природа": return 0x34D399
        case "Игры": return 0xFBBF24
        case "Флаги": return 0x38BDF8
        default: return 0x7C4DFF
        }
    }

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: self.cacheFileURL),
              let payload = try? JSONDecoder().decode(FullGramDiscordCatalogPayload.self, from: data) else {
            return
        }
        self.apply(payload)
    }

    private func apply(_ payload: FullGramDiscordCatalogPayload) {
        let mappedFrames: [FullGramAvatarFramePreset] = payload.frames.map { item in
            FullGramAvatarFramePreset(
                id: item.id,
                title: item.title,
                category: item.category,
                fileName: item.id,
                accentHex: Self.accentForCategory(item.category),
                isBundled: false,
                remoteURLs: item.urls
            )
        }
        let mappedEffects: [FullGramProfileEffectPreset] = payload.profileEffects.map { item in
            FullGramProfileEffectPreset(
                id: item.id,
                title: item.title,
                category: item.category,
                layerURLs: item.layers,
                accentHex: Self.accentForCategory(item.category)
            )
        }
        var fMap: [String: FullGramAvatarFramePreset] = [:]
        for f in mappedFrames { fMap[f.id] = f }
        var eMap: [String: FullGramProfileEffectPreset] = [:]
        for e in mappedEffects { eMap[e.id] = e }

        self.lock.lock()
        self.discordFrames = mappedFrames
        self.discordFramesById = fMap
        self.discordEffects = mappedEffects
        self.discordEffectsById = eMap
        self.lock.unlock()
    }

    public var frames: [FullGramAvatarFramePreset] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.discordFrames
    }

    public var profileEffects: [FullGramProfileEffectPreset] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.discordEffects
    }

    public func frame(id: String) -> FullGramAvatarFramePreset? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.discordFramesById[id]
    }

    public func profileEffect(id: String) -> FullGramProfileEffectPreset? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.discordEffectsById[id]
    }

    public func refreshIfNeeded(maxAge: TimeInterval = 3600.0) {
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        let empty = self.frames.isEmpty || self.profileEffects.isEmpty
        if !empty && Date().timeIntervalSince1970 - last < maxAge {
            return
        }
        self.refreshNow(completion: nil)
    }

    public func refreshNow(completion: ((Bool) -> Void)? = nil) {
        self.lock.lock()
        if self.isFetching {
            self.lock.unlock()
            return
        }
        self.isFetching = true
        self.lock.unlock()

        let urls = Self.catalogURLs.compactMap { URL(string: $0) }
        self.fetchMirror(urls: urls, index: 0, completion: completion)
    }

    private func fetchMirror(urls: [URL], index: Int, completion: ((Bool) -> Void)?) {
        guard index < urls.count else {
            self.lock.lock()
            self.isFetching = false
            self.lock.unlock()
            DispatchQueue.main.async { completion?(false) }
            return
        }
        var req = URLRequest(url: urls[index])
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Self.session.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            if let http = response as? HTTPURLResponse,
               (200 ..< 300).contains(http.statusCode),
               let data,
               data.count > 100,
               let payload = try? JSONDecoder().decode(FullGramDiscordCatalogPayload.self, from: data),
               !payload.frames.isEmpty {
                try? data.write(to: self.cacheFileURL, options: .atomic)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)
                self.apply(payload)
                self.lock.lock()
                self.isFetching = false
                self.lock.unlock()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                    NotificationCenter.default.post(name: FullGramAvatarFrames.didChangeNotification, object: nil)
                    NotificationCenter.default.post(name: FullGramProfileEffects.didChangeNotification, object: nil)
                    completion?(true)
                }
                return
            }
            self.fetchMirror(urls: urls, index: index + 1, completion: completion)
        }.resume()
    }
}

// MARK: - Рамки аватара (встроенные + 663 Discord + кастомные из Фото/URL)

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

    public static func customFramesDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("FullGramCustomFrames", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func customLocalFrameURL(forPeerId peerId: Int64) -> URL {
        let norm = FullGramCloudCosmetics.normalizedPeerId(peerId)
        return self.customFramesDirectory().appendingPathComponent("custom_\(norm).png")
    }

    @discardableResult
    public static func saveCustomLocalFrame(data: Data, forPeerId peerId: Int64) -> Bool {
        let dst = self.customLocalFrameURL(forPeerId: peerId)
        do {
            try data.write(to: dst, options: .atomic)
            FullGramAnimatedImageDecoder.invalidate(cacheKey: "custom_local_\(FullGramCloudCosmetics.normalizedPeerId(peerId))")
            FullGramCloudCosmetics.shared.setFrame(forPeerId: peerId, frameId: "custom_local", customFrameUrl: nil)
            return true
        } catch {
            return false
        }
    }

    public static func setCustomURLFrame(urlString: String, forPeerId peerId: Int64) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased().hasPrefix("https://") else { return }
        FullGramCloudCosmetics.shared.setFrame(forPeerId: peerId, frameId: "custom_url", customFrameUrl: trimmed)
    }

    public static func selectedFrameId(forPeerId peerId: Int64, selfPeerId: Int64? = nil) -> String? {
        return FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId ?? peerId)?.frameId
    }

    public static func setSelectedFrame(forPeerId peerId: Int64, frameId: String?) {
        FullGramCloudCosmetics.shared.setFrame(forPeerId: peerId, frameId: frameId, customFrameUrl: nil)
    }

    public static func frame(forPeerId peerId: Int64?, selfPeerId: Int64?) -> FullGramAvatarFramePreset? {
        FullGramDiscordCosmeticsCatalog.shared.refreshIfNeeded()
        guard let peerId,
              let cosmetics = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId) else {
            return nil
        }
        if let customUrl = cosmetics.customFrameUrl, !customUrl.isEmpty, customUrl.lowercased().hasPrefix("https://") {
            let safeHash = String(abs(customUrl.hashValue))
            return FullGramAvatarFramePreset(
                id: "custom_url_\(safeHash)",
                title: "Своя рамка (URL)",
                category: "Кастом",
                fileName: "custom_url_\(safeHash)",
                accentHex: 0x00E5FF,
                isBundled: false,
                remoteURLs: [customUrl]
            )
        }
        guard let id = cosmetics.frameId, !id.isEmpty else {
            return nil
        }
        if id == "custom_local" {
            let localURL = self.customLocalFrameURL(forPeerId: peerId)
            if FileManager.default.fileExists(atPath: localURL.path) {
                let norm = FullGramCloudCosmetics.normalizedPeerId(peerId)
                return FullGramAvatarFramePreset(
                    id: "custom_local_\(norm)",
                    title: "Моя рамка",
                    category: "Кастом",
                    fileName: "custom_\(norm)",
                    accentHex: 0x00E5FF,
                    isBundled: false,
                    localCustomPath: localURL.path
                )
            }
            return nil
        }
        if let builtin = self.builtInFramesById[id] {
            return builtin
        }
        return FullGramDiscordCosmeticsCatalog.shared.frame(id: id)
    }

    public static let builtInFrames: [FullGramAvatarFramePreset] = [
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

    public static var allFrames: [FullGramAvatarFramePreset] {
        let discord = FullGramDiscordCosmeticsCatalog.shared.frames
        guard !discord.isEmpty else {
            return self.builtInFrames
        }
        return self.builtInFrames + discord
    }

    private static let builtInFramesById: [String: FullGramAvatarFramePreset] = Dictionary(
        uniqueKeysWithValues: builtInFrames.map { ($0.id, $0) }
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
        if !preset.remoteURLs.isEmpty {
            return preset.remoteURLs.compactMap { URL(string: $0) }
        }
        let file = "\(preset.fileName).png"
        return [
            URL(string: self.rawBaseURL + file),
            URL(string: self.cdnBaseURL + file)
        ].compactMap { $0 }
    }

    public static func frameURL(for preset: FullGramAvatarFramePreset) -> URL? {
        if let customPath = preset.localCustomPath, FileManager.default.fileExists(atPath: customPath) {
            return URL(fileURLWithPath: customPath)
        }
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

// MARK: - Анимации открытия профиля (Discord Profile Effects)

public enum FullGramProfileEffects {
    public static let didChangeNotification = Notification.Name("FullGram.ProfileEffectsChanged")

    public static var allEffects: [FullGramProfileEffectPreset] {
        return FullGramDiscordCosmeticsCatalog.shared.profileEffects
    }

    public static func selectedEffectId(forPeerId peerId: Int64, selfPeerId: Int64? = nil) -> String? {
        return FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId ?? peerId)?.profileEffectId
    }

    public static func setSelectedEffect(forPeerId peerId: Int64, effectId: String?) {
        FullGramCloudCosmetics.shared.setProfileEffect(forPeerId: peerId, effectId: effectId)
    }

    public static func effect(forPeerId peerId: Int64?, selfPeerId: Int64?) -> FullGramProfileEffectPreset? {
        FullGramDiscordCosmeticsCatalog.shared.refreshIfNeeded()
        guard let cosmetics = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId),
              let id = cosmetics.profileEffectId,
              !id.isEmpty else {
            return nil
        }
        return FullGramDiscordCosmeticsCatalog.shared.profileEffect(id: id)
    }

    public static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FullGramProfileEffects", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func cachedLayerURL(effectId: String, layerIndex: Int) -> URL {
        return self.cacheDirectory().appendingPathComponent("\(effectId)_layer\(layerIndex).png")
    }
}

// MARK: - APNG / GIF декодер (общий для рамок и анимаций профиля)

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
        c.countLimit = 12
        return c
    }()
    private static let decodeQueue = DispatchQueue(label: "FullGram.AvatarFrameDecode", qos: .userInitiated, attributes: .concurrent)
    private static let inflightLock = NSLock()
    private static var inflightCallbacks: [String: [@Sendable (FullGramAnimatedFrameSequence?) -> Void]] = [:]
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 18.0
        cfg.timeoutIntervalForResource = 35.0
        return URLSession(configuration: cfg)
    }()

    public static func invalidate(cacheKey: String) {
        self.sequenceCache.removeObject(forKey: cacheKey as NSString)
    }

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
            guard !preset.isBundled && preset.localCustomPath == nil else {
                finish(nil)
                return
            }
            let dst = FullGramAvatarFrames.cachedDiskURL(for: preset)
            self.downloadRemoteImage(urls: FullGramAvatarFrames.remoteURLs(for: preset), dst: dst) { ok in
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

    public static func profileEffectLayerAsync(
        effectId: String,
        layerIndex: Int,
        urlString: String,
        maxPixelSize: Int = 380,
        completion: @escaping @Sendable (FullGramAnimatedFrameSequence?) -> Void
    ) {
        let cacheKey = "pe_\(effectId)_\(layerIndex)"
        if let cached = self.sequenceCache.object(forKey: cacheKey as NSString) {
            completion(cached)
            return
        }
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        self.inflightLock.lock()
        if var callbacks = self.inflightCallbacks[cacheKey] {
            callbacks.append(completion)
            self.inflightCallbacks[cacheKey] = callbacks
            self.inflightLock.unlock()
            return
        }
        self.inflightCallbacks[cacheKey] = [completion]
        self.inflightLock.unlock()

        func finish(_ seq: FullGramAnimatedFrameSequence?) {
            self.inflightLock.lock()
            let callbacks = self.inflightCallbacks.removeValue(forKey: cacheKey) ?? []
            self.inflightLock.unlock()
            DispatchQueue.main.async {
                for cb in callbacks {
                    cb(seq)
                }
            }
        }

        let diskURL = FullGramProfileEffects.cachedLayerURL(effectId: effectId, layerIndex: layerIndex)
        self.decodeQueue.async {
            if FileManager.default.fileExists(atPath: diskURL.path),
               let seq = self.decodeFile(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, maxFrames: 45) {
                finish(seq)
                return
            }
            self.downloadRemoteImage(urls: [url], dst: diskURL) { ok in
                guard ok else {
                    finish(nil)
                    return
                }
                self.decodeQueue.async {
                    finish(self.decodeFile(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, maxFrames: 45))
                }
            }
        }
    }

    private static func downloadRemoteImage(
        urls: [URL],
        dst: URL,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard let first = urls.first else {
            completion(false)
            return
        }
        let rest = Array(urls.dropFirst())
        var req = URLRequest(url: first)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        self.session.dataTask(with: req) { data, response, _ in
            if let http = response as? HTTPURLResponse,
               http.statusCode == 200,
               let data,
               data.count > 128 {
                let isPNG = data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])
                let isGIF = data.prefix(3) == Data([0x47, 0x49, 0x46])
                let isWEBP = data.count > 12 && data.prefix(4) == Data([0x52, 0x49, 0x46, 0x46])
                let isJPG = data.prefix(2) == Data([0xFF, 0xD8])
                if isPNG || isGIF || isWEBP || isJPG {
                    try? data.write(to: dst, options: .atomic)
                    completion(true)
                    return
                }
            }
            if !rest.isEmpty {
                self.downloadRemoteImage(urls: rest, dst: dst, completion: completion)
            } else {
                completion(false)
            }
        }.resume()
    }

    public static func sequence(for preset: FullGramAvatarFramePreset, maxPixelSize: Int = 220) -> FullGramAnimatedFrameSequence? {
        if let cached = self.sequenceCache.object(forKey: preset.id as NSString) {
            return cached
        }
        guard let url = FullGramAvatarFrames.frameURL(for: preset) else {
            return nil
        }
        return self.decodeFile(url: url, cacheKey: preset.id, maxPixelSize: maxPixelSize, maxFrames: 60)
    }

    private static func decodeFile(
        url: URL,
        cacheKey: String,
        maxPixelSize: Int,
        maxFrames: Int
    ) -> FullGramAnimatedFrameSequence? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let rawCount = CGImageSourceGetCount(source)
        guard rawCount > 0 else { return nil }

        let strideStep = max(1, (rawCount + maxFrames - 1) / maxFrames)
        var images: [CGImage] = []
        var durations: [Double] = []
        images.reserveCapacity(min(rawCount, maxFrames))
        durations.reserveCapacity(min(rawCount, maxFrames))

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        var totalDuration: Double = 0.0
        var idx = 0
        while idx < rawCount {
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, idx, thumbOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, idx, nil) {
                var delay = 0.0
                let endIdx = min(rawCount, idx + strideStep)
                for j in idx ..< endIdx {
                    delay += self.frameDelay(source: source, index: j)
                }
                images.append(cgImage)
                durations.append(delay)
                totalDuration += delay
            }
            idx += strideStep
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
        self.sequenceCache.setObject(seq, forKey: cacheKey as NSString, cost: images.count * maxPixelSize)
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

// MARK: - View для рамки аватара

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
        if self.currentFrameId == preset.id && self.frameLayer.contents != nil {
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

// MARK: - View для анимации открытия профиля (Discord Profile Effects)

public final class FullGramProfileEffectOverlayView: UIView {
    private let introLayer = CALayer()
    private let ambientLayer = CALayer()
    private var currentEffectId: String?
    private var pendingEffectId: String?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.clipsToBounds = true
        self.introLayer.contentsGravity = .resizeAspectFill
        self.ambientLayer.contentsGravity = .resizeAspectFill
        self.layer.addSublayer(self.ambientLayer)
        self.layer.addSublayer(self.introLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.ambientLayer.frame = self.bounds
        self.introLayer.frame = self.bounds
    }

    public func configure(with preset: FullGramProfileEffectPreset?, forceReplay: Bool = false) {
        guard let preset, !preset.layerURLs.isEmpty else {
            self.currentEffectId = nil
            self.pendingEffectId = nil
            self.introLayer.removeAllAnimations()
            self.introLayer.contents = nil
            self.ambientLayer.removeAllAnimations()
            self.ambientLayer.contents = nil
            self.isHidden = true
            return
        }
        self.isHidden = false
        if !forceReplay && self.currentEffectId == preset.id {
            return
        }
        self.pendingEffectId = preset.id
        self.currentEffectId = preset.id
        self.introLayer.removeAllAnimations()
        self.introLayer.contents = nil
        self.ambientLayer.removeAllAnimations()
        self.ambientLayer.contents = nil

        let targetId = preset.id
        let introURL = preset.layerURLs[0]
        let ambientURL = preset.layerURLs.count > 1 ? preset.layerURLs[1] : nil

        FullGramAnimatedImageDecoder.profileEffectLayerAsync(effectId: targetId, layerIndex: 0, urlString: introURL) { [weak self] seq in
            Task { @MainActor in
                guard let self, self.pendingEffectId == targetId else { return }
                self.play(sequence: seq, on: self.introLayer, loop: ambientURL == nil)
            }
        }

        if let ambientURL {
            FullGramAnimatedImageDecoder.profileEffectLayerAsync(effectId: targetId, layerIndex: 1, urlString: ambientURL) { [weak self] seq in
                Task { @MainActor in
                    guard let self, self.pendingEffectId == targetId else { return }
                    self.play(sequence: seq, on: self.ambientLayer, loop: true)
                }
            }
        }
    }

    private func play(sequence seq: FullGramAnimatedFrameSequence?, on layer: CALayer, loop: Bool) {
        layer.removeAllAnimations()
        guard let seq, !seq.frames.isEmpty else {
            layer.contents = nil
            return
        }
        if seq.frames.count == 1 {
            layer.contents = seq.frames[0]
            return
        }
        layer.contents = seq.frames[0]
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = seq.frames
        anim.keyTimes = seq.keyTimes
        anim.duration = seq.totalDuration
        anim.calculationMode = .discrete
        anim.repeatCount = loop ? .infinity : 1
        anim.isRemovedOnCompletion = !loop
        if !loop {
            layer.contents = nil
        }
        layer.add(anim, forKey: "fg.pe")
    }
}
