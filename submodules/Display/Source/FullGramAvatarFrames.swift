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
        "https://cdn.jsdelivr.net/gh/shermanko/FullGram@release/next/assets/discord_cosmetics.json",
        "https://raw.githubusercontent.com/shermanko/FullGram/release/next/assets/discord_cosmetics.json"
    ]
    private static let lastSyncKey = "fullgram.discordCatalog.lastSync"

    private let lock = NSRecursiveLock()
    private var discordFrames: [FullGramAvatarFramePreset] = []
    private var discordFramesById: [String: FullGramAvatarFramePreset] = [:]
    private var discordEffects: [FullGramProfileEffectPreset] = []
    private var discordEffectsById: [String: FullGramProfileEffectPreset] = [:]
    private var isFetching = false
    private var lastSyncTimestamp: TimeInterval = UserDefaults.standard.double(forKey: "fullgram.discordCatalog.lastSync")
    private var pendingCompletions: [(Bool) -> Void] = []

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
        case "FullGram": return 0x00F5D4
        case "Кибер": return 0x00E5FF
        case "Неон": return 0xFF2A85
        case "Аниме": return 0xFF6B9D
        case "Милые": return 0xF472B6
        case "Стихия": return 0xF43F5E
        case "Космос": return 0x818CF8
        case "Природа": return 0x34D399
        case "Игры": return 0xFBBF24
        case "Эмоции": return 0xFB7185
        case "Эффект": return 0x94A3B8
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
        self.lock.lock()
        let empty = self.discordFrames.isEmpty || self.discordEffects.isEmpty
        let last = self.lastSyncTimestamp
        let fetching = self.isFetching
        self.lock.unlock()
        if fetching || (!empty && Date().timeIntervalSince1970 - last < maxAge) {
            return
        }
        self.refreshNow(completion: nil)
    }

    public func refreshNow(completion: ((Bool) -> Void)? = nil) {
        self.lock.lock()
        if let completion {
            self.pendingCompletions.append(completion)
        }
        if self.isFetching {
            self.lock.unlock()
            return
        }
        self.isFetching = true
        self.lock.unlock()

        let urls = Self.catalogURLs.compactMap { URL(string: $0) }
        self.fetchMirror(urls: urls, index: 0)
    }

    private func fetchMirror(urls: [URL], index: Int) {
        guard index < urls.count else {
            self.lock.lock()
            self.isFetching = false
            let completions = self.pendingCompletions
            self.pendingCompletions.removeAll()
            self.lock.unlock()
            DispatchQueue.main.async {
                for cb in completions { cb(false) }
            }
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
                let now = Date().timeIntervalSince1970
                UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
                self.apply(payload)
                self.lock.lock()
                self.lastSyncTimestamp = now
                self.isFetching = false
                let completions = self.pendingCompletions
                self.pendingCompletions.removeAll()
                self.lock.unlock()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
                    NotificationCenter.default.post(name: FullGramAvatarFrames.didChangeNotification, object: nil)
                    NotificationCenter.default.post(name: FullGramProfileEffects.didChangeNotification, object: nil)
                    for cb in completions { cb(true) }
                }
                return
            }
            self.fetchMirror(urls: urls, index: index + 1)
        }.resume()
    }
}

// MARK: - Рамки аватара (встроенные + 663 Discord + кастомные из Фото/URL)

public enum FullGramAvatarFrames {
    public static let didChangeNotification = Notification.Name("FullGram.AvatarFramesChanged")

    private static let showInChatsKey = "fullgram.frames.showInChats"

    private static let workerFramesBaseURL = "https://fullgram.korsakovx.workers.dev/assets/frames/"
    private static let rawBaseURL = "https://raw.githubusercontent.com/shermanko/FullGram/release/next/assets/frames/"
    private static let cdnBaseURL = "https://cdn.jsdelivr.net/gh/shermanko/FullGram@release/next/assets/frames/"

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

    private static let favoritesKey = "fullgram.frames.favorites"

    public static var favoriteFrameIds: [String] {
        return UserDefaults.standard.stringArray(forKey: self.favoritesKey) ?? []
    }

    public static func isFavoriteFrame(_ id: String) -> Bool {
        return self.favoriteFrameIds.contains(id)
    }

    @discardableResult
    public static func toggleFavoriteFrame(_ id: String) -> Bool {
        var list = self.favoriteFrameIds
        let isFav: Bool
        if let idx = list.firstIndex(of: id) {
            list.remove(at: idx)
            isFav = false
        } else {
            list.insert(id, at: 0)
            isFav = true
        }
        UserDefaults.standard.set(list, forKey: self.favoritesKey)
        NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
        return isFav
    }

    public static func frame(forPeerId peerId: Int64?, selfPeerId: Int64?) -> FullGramAvatarFramePreset? {
        guard let peerId,
              let cosmetics = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId) else {
            return nil
        }
        if let customUrl = cosmetics.customFrameUrl, !customUrl.isEmpty, customUrl.lowercased().hasPrefix("https://") {
            var fnv: UInt64 = 14695981039346656037
            for byte in customUrl.utf8 {
                fnv ^= UInt64(byte)
                fnv = fnv &* 1099511628211
            }
            let safeHash = String(fnv, radix: 16)
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
        FullGramDiscordCosmeticsCatalog.shared.refreshIfNeeded(maxAge: 21600.0)
        return FullGramDiscordCosmeticsCatalog.shared.frame(id: id)
    }

    public static let builtInFrames: [FullGramAvatarFramePreset] = [
        FullGramAvatarFramePreset(
            id: "dc_dark_roses_black",
            title: "Тёмные розы (Чёрный) · Dark Roses",
            category: "Стихия",
            fileName: "dc_dark_roses_black",
            accentHex: 0xA855F7,
            isBundled: false,
            remoteURLs: [
                "https://cdn.discordapp.com/avatar-decoration-presets/a_c7d0b92c2c06bbb3fed297b34a51d5e5.png?size=240&passthrough=true",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Avatar_Decorations/Dark%20Roses%20%28Black%29/Animated/Dark%20Roses%20%28Black%29_a_c7d0b92c2c06bbb3fed297b34a51d5e5.png"
            ]
        ),
        FullGramAvatarFramePreset(
            id: "dc_wraithling",
            title: "Нечисть · Wraithling",
            category: "Стихия",
            fileName: "dc_wraithling",
            accentHex: 0xCBD5E1,
            isBundled: false,
            remoteURLs: [
                "https://cdn.discordapp.com/avatar-decoration-presets/a_bec26d0726a0f2eb7491a7cd40ac9c73.png?size=240&passthrough=true",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Avatar_Decorations/Wraithling/Animated/Wraithling_a_bec26d0726a0f2eb7491a7cd40ac9c73.png"
            ]
        ),
        FullGramAvatarFramePreset(
            id: "dc_nightwraith",
            title: "Ночная нечисть · Nightwraith",
            category: "Стихия",
            fileName: "dc_nightwraith",
            accentHex: 0x94A3B8,
            isBundled: false,
            remoteURLs: [
                "https://cdn.discordapp.com/avatar-decoration-presets/a_9eaaf9cd10824e3856b65e85b490c056.png?size=240&passthrough=true",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Avatar_Decorations/Nightwraith/Animated/Nightwraith_a_9eaaf9cd10824e3856b65e85b490c056.png"
            ]
        ),
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

    public static let customFullGramFrames: [FullGramAvatarFramePreset] = [
        FullGramAvatarFramePreset(id: "fg_chrome_wings", title: "FG Chrome Wings", category: "FullGram", fileName: "fg_chrome_wings", accentHex: 0xE2E8F0, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_crimson_wings", title: "FG Crimson Wings", category: "FullGram", fileName: "fg_crimson_wings", accentHex: 0xFF2E4C, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_solar_flare", title: "FG Solar Orange", category: "FullGram", fileName: "fg_solar_flare", accentHex: 0xFF8C00, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_mascot_sparkle", title: "FG Mascot Sparkle", category: "FullGram", fileName: "fg_mascot_sparkle", accentHex: 0xF472B6, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_obsidian_blade", title: "FG Obsidian Edge", category: "FullGram", fileName: "fg_obsidian_blade", accentHex: 0x94A3B8, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_neon_core", title: "FG Neon Core", category: "FullGram", fileName: "fg_neon_core", accentHex: 0x00F5D4, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_stealth_hud", title: "FG Stealth HUD", category: "FullGram", fileName: "fg_stealth_hud", accentHex: 0x00E5FF, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_royal_crown", title: "FG Royal Gold", category: "FullGram", fileName: "fg_royal_crown", accentHex: 0xFFD700, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_void_prism", title: "FG Void Prism", category: "FullGram", fileName: "fg_void_prism", accentHex: 0xA855F7, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_arctic_chrome", title: "FG Arctic Chrome", category: "FullGram", fileName: "fg_arctic_chrome", accentHex: 0x67E8F9, isBundled: true),
        FullGramAvatarFramePreset(id: "fg_cyber_hex", title: "Cyber Hex Grid", category: "Кибер", fileName: "fg_cyber_hex", accentHex: 0x00E5FF, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_synthwave_ring", title: "Synthwave Sunset", category: "Неон", fileName: "fg_synthwave_ring", accentHex: 0xFF2A85, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_matrix_code", title: "Matrix Digital", category: "Кибер", fileName: "fg_matrix_code", accentHex: 0x00FF66, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_laser_scan", title: "Laser Scanner", category: "Кибер", fileName: "fg_laser_scan", accentHex: 0xFF0055, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_plasma_arc", title: "Plasma Arc", category: "Неон", fileName: "fg_plasma_arc", accentHex: 0xC084FC, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_holo_ring", title: "Hologram Prism", category: "Неон", fileName: "fg_holo_ring", accentHex: 0x38BDF8, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_glitch_pulse", title: "Glitch Pulse", category: "Кибер", fileName: "fg_glitch_pulse", accentHex: 0xFF2A85, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_turbo_rpm", title: "Turbo RPM", category: "Кибер", fileName: "fg_turbo_rpm", accentHex: 0xF97316, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_circuit_flow", title: "Circuit Flow", category: "Кибер", fileName: "fg_circuit_flow", accentHex: 0x10B981, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_vapor_wave", title: "Vaporwave 1984", category: "Неон", fileName: "fg_vapor_wave", accentHex: 0xF472B6, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_inferno_ring", title: "Inferno Flame", category: "Стихия", fileName: "fg_inferno_ring", accentHex: 0xFF4500, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_frost_crystal", title: "Frost Crystals", category: "Стихия", fileName: "fg_frost_crystal", accentHex: 0x60A5FA, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_thunder_bolt", title: "Thunder Storm", category: "Стихия", fileName: "fg_thunder_bolt", accentHex: 0xFACC15, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_toxic_venom", title: "Toxic Venom", category: "Стихия", fileName: "fg_toxic_venom", accentHex: 0x84CC16, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_blood_moon", title: "Blood Moon", category: "Стихия", fileName: "fg_blood_moon", accentHex: 0xDC2626, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_emerald_aura", title: "Emerald Aura", category: "Стихия", fileName: "fg_emerald_aura", accentHex: 0x34D399, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_ocean_tide", title: "Ocean Tide", category: "Стихия", fileName: "fg_ocean_tide", accentHex: 0x0EA5E9, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_magma_crack", title: "Magma Core", category: "Стихия", fileName: "fg_magma_crack", accentHex: 0xEA580C, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_wind_vortex", title: "Wind Vortex", category: "Стихия", fileName: "fg_wind_vortex", accentHex: 0xA5F3FC, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_arcane_runes", title: "Arcane Runes", category: "Стихия", fileName: "fg_arcane_runes", accentHex: 0x8B5CF6, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_nebula_swirl", title: "Nebula Swirl", category: "Космос", fileName: "fg_nebula_swirl", accentHex: 0x818CF8, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_supernova", title: "Supernova Burst", category: "Космос", fileName: "fg_supernova", accentHex: 0xFBBF24, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_saturn_orbit", title: "Orbital Moons", category: "Космос", fileName: "fg_saturn_orbit", accentHex: 0x38BDF8, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_starlight_halo", title: "Starlight Halo", category: "Космос", fileName: "fg_starlight_halo", accentHex: 0xE0E7FF, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_aurora_borealis", title: "Aurora Borealis", category: "Космос", fileName: "fg_aurora_borealis", accentHex: 0x2DD4BF, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_black_hole", title: "Event Horizon", category: "Космос", fileName: "fg_black_hole", accentHex: 0xF97316, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_comet_trail", title: "Comet Trail", category: "Космос", fileName: "fg_comet_trail", accentHex: 0x67E8F9, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_zodiac_gold", title: "Celestial Astrolabe", category: "Космос", fileName: "fg_zodiac_gold", accentHex: 0xF59E0B, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_sakura_petals", title: "Sakura Petals", category: "Аниме", fileName: "fg_sakura_petals", accentHex: 0xFF85B3, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_neko_neon", title: "Neko Neon Ears", category: "Милые", fileName: "fg_neko_neon", accentHex: 0xF472B6, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_pastel_hearts", title: "Pastel Hearts", category: "Милые", fileName: "fg_pastel_hearts", accentHex: 0xFB7185, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_angel_halo", title: "Angelic Halo", category: "Милые", fileName: "fg_angel_halo", accentHex: 0xFDE68A, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_devil_horns", title: "Crimson Horns", category: "Аниме", fileName: "fg_devil_horns", accentHex: 0xEF4444, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_butterfly_glow", title: "Neon Butterflies", category: "Природа", fileName: "fg_butterfly_glow", accentHex: 0xC084FC, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_lotus_bloom", title: "Lotus Bloom", category: "Природа", fileName: "fg_lotus_bloom", accentHex: 0xEC4899, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_rainbow_prism", title: "Rainbow Prism", category: "Неон", fileName: "fg_rainbow_prism", accentHex: 0xFF6B9D, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_candy_swirl", title: "Candy Swirl", category: "Милые", fileName: "fg_candy_swirl", accentHex: 0xF472B6, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_emerald_vine", title: "Emerald Vine", category: "Природа", fileName: "fg_emerald_vine", accentHex: 0x22C55E, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_fireflies", title: "Night Fireflies", category: "Природа", fileName: "fg_fireflies", accentHex: 0xFACC15, isBundled: false),
        FullGramAvatarFramePreset(id: "fg_diamond_lux", title: "Diamond Luxury", category: "FullGram", fileName: "fg_diamond_lux", accentHex: 0xE0F2FE, isBundled: true)
    ]

    public static func userUploadedPresets(forPeerId peerId: Int64) -> [FullGramAvatarFramePreset] {
        var list: [FullGramAvatarFramePreset] = []
        let norm = FullGramCloudCosmetics.normalizedPeerId(peerId)
        let localURL = self.customLocalFrameURL(forPeerId: peerId)
        if FileManager.default.fileExists(atPath: localURL.path) {
            list.append(FullGramAvatarFramePreset(
                id: "custom_local",
                title: "Моя рамка (Фото)",
                category: "Кастом",
                fileName: "custom_\(norm)",
                accentHex: 0x00E5FF,
                isBundled: false,
                localCustomPath: localURL.path
            ))
        }
        if let customUrl = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: peerId)?.customFrameUrl,
           !customUrl.isEmpty,
           customUrl.lowercased().hasPrefix("https://") {
            var fnv: UInt64 = 14695981039346656037
            for byte in customUrl.utf8 {
                fnv ^= UInt64(byte)
                fnv = fnv &* 1099511628211
            }
            let safeHash = String(fnv, radix: 16)
            list.append(FullGramAvatarFramePreset(
                id: "custom_url",
                title: "Своя рамка (URL)",
                category: "Кастом",
                fileName: "custom_url_\(safeHash)",
                accentHex: 0x00F5D4,
                isBundled: false,
                remoteURLs: [customUrl]
            ))
        }
        return list
    }

    public static var allFrames: [FullGramAvatarFramePreset] {
        let local = self.builtInFrames + self.customFullGramFrames
        let discord = FullGramDiscordCosmeticsCatalog.shared.frames
        guard !discord.isEmpty else {
            return local
        }
        let localIds = Set(local.map(\.id))
        return local + discord.filter { !localIds.contains($0.id) }
    }

    private static let builtInFramesById: [String: FullGramAvatarFramePreset] = Dictionary(
        uniqueKeysWithValues: (customFullGramFrames + builtInFrames).map { ($0.id, $0) }
    )

    public static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FullGramFramesV2", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func safeFileToken(_ raw: String) -> String {
        let cleaned = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? Character($0) : "_" }
        let str = String(cleaned)
        return str.isEmpty ? "item" : str
    }

    public static func cachedDiskURL(for preset: FullGramAvatarFramePreset) -> URL {
        return self.cacheDirectory().appendingPathComponent("\(Self.safeFileToken(preset.fileName)).png")
    }

    public static func cachedThumbnailDiskURL(for preset: FullGramAvatarFramePreset) -> URL {
        return self.cacheDirectory().appendingPathComponent("\(Self.safeFileToken(preset.fileName))_thumb.png")
    }

    public static func remoteURLs(for preset: FullGramAvatarFramePreset) -> [URL] {
        let strings = preset.remoteURLs
        if strings.isEmpty {
            let file = "\(preset.fileName).png"
            let baseList = [
                self.workerFramesBaseURL + file + "?v=2",
                self.rawBaseURL + file,
                self.cdnBaseURL + file
            ]
            return baseList.compactMap { URL(string: $0) }
        }
        var seen = Set<String>()
        var urls: [URL] = []
        let appendUnique: (String) -> Void = { s in
            guard !s.isEmpty, !seen.contains(s), let u = URL(string: s), u.scheme?.lowercased() == "https" else { return }
            seen.insert(s)
            urls.append(u)
        }
        for s in strings {
            appendUnique(s)
            if s.hasPrefix("https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/") {
                let tail = String(s.dropFirst("https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/".count))
                appendUnique("https://raw.githubusercontent.com/JulesZYTB/discord-collectibles-downloader/main/" + tail)
            }
        }
        return urls
    }

    public static func thumbnailRemoteURLs(for preset: FullGramAvatarFramePreset) -> [URL] {
        let baseURLs = self.remoteURLs(for: preset)
        return baseURLs.map { url in
            let str = url.absoluteString
            if str.contains("cdn.discordapp.com/avatar-decoration-presets/") {
                let fast = str
                    .replacingOccurrences(of: "size=240&passthrough=true", with: "size=128&passthrough=false")
                    .replacingOccurrences(of: "passthrough=true", with: "passthrough=false")
                return URL(string: fast) ?? url
            }
            return url
        }
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
    private static let favoritesKey = "fullgram.effects.favorites"

    public static var favoriteEffectIds: [String] {
        return UserDefaults.standard.stringArray(forKey: self.favoritesKey) ?? []
    }

    public static func isFavoriteEffect(_ id: String) -> Bool {
        return self.favoriteEffectIds.contains(id)
    }

    @discardableResult
    public static func toggleFavoriteEffect(_ id: String) -> Bool {
        var list = self.favoriteEffectIds
        let isFav: Bool
        if let idx = list.firstIndex(of: id) {
            list.remove(at: idx)
            isFav = false
        } else {
            list.insert(id, at: 0)
            isFav = true
        }
        UserDefaults.standard.set(list, forKey: self.favoritesKey)
        NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
        return isFav
    }

    public static let builtInEffects: [FullGramProfileEffectPreset] = [
        FullGramProfileEffectPreset(
            id: "pe_dark_roses_black",
            title: "Тёмные розы (Чёрный) · Dark Roses",
            category: "Стихия",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28Black%29/Animated/Dark%20Roses%20%28Black%29_layer_0_1462116613712253044_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28Black%29/Animated/Dark%20Roses%20%28Black%29_layer_1_1462116613712253044_1.png"
            ],
            accentHex: 0xA855F7
        ),
        FullGramProfileEffectPreset(
            id: "pe_dark_roses_nightshade",
            title: "Тёмные розы (Ночь) · Nightshade",
            category: "Стихия",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28Nightshade%29/Animated/Dark%20Roses%20%28Nightshade%29_layer_0_1462116613707796562_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28Nightshade%29/Animated/Dark%20Roses%20%28Nightshade%29_layer_1_1462116613707796562_1.png"
            ],
            accentHex: 0x7C3AED
        ),
        FullGramProfileEffectPreset(
            id: "pe_dark_roses_white",
            title: "Тёмные розы (Белый) · White Roses",
            category: "Стихия",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28White%29/Animated/Dark%20Roses%20%28White%29_layer_0_1462116613724569641_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28White%29/Animated/Dark%20Roses%20%28White%29_layer_1_1462116613724569641_1.png"
            ],
            accentHex: 0xE2E8F0
        ),
        FullGramProfileEffectPreset(
            id: "pe_dark_roses_blue",
            title: "Тёмные розы (Синий) · Blue Roses",
            category: "Стихия",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28Blue%29/Animated/Dark%20Roses%20%28Blue%29_layer_0_1462116613728895057_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dark%20Roses%20%28Blue%29/Animated/Dark%20Roses%20%28Blue%29_layer_1_1462116613728895057_1.png"
            ],
            accentHex: 0x38BDF8
        ),
        FullGramProfileEffectPreset(
            id: "pe_nightwraith",
            title: "Ночная нечисть · Nightwraith",
            category: "Стихия",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Nightwraith/Animated/Nightwraith_layer_0_1447609133111971963_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Nightwraith/Animated/Nightwraith_layer_1_1447609133111971963_1.png"
            ],
            accentHex: 0x94A3B8
        ),
        FullGramProfileEffectPreset(
            id: "pe_cyberspace",
            title: "Киберпространство · Cyberspace",
            category: "Кибер",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Cyberspace/Animated/Cyberspace_layer_0_1139323103193878569_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Cyberspace/Animated/Cyberspace_layer_1_1139323103193878569_1.png"
            ],
            accentHex: 0x00E5FF
        ),
        FullGramProfileEffectPreset(
            id: "pe_aurora_dreams",
            title: "Северное сияние · Aurora Dreams",
            category: "Космос",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Aurora%20Dreams/Animated/Aurora%20Dreams_layer_0_1314020996776329279_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Aurora%20Dreams/Animated/Aurora%20Dreams_layer_1_1314020996776329279_1.png"
            ],
            accentHex: 0x2DD4BF
        ),
        FullGramProfileEffectPreset(
            id: "pe_dragon_dance",
            title: "Танец дракона · Dragon Dance",
            category: "Аниме",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dragon%20Dance/Animated/Dragon%20Dance_layer_0_1202061726212947968_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dragon%20Dance/Animated/Dragon%20Dance_layer_1_1202061726212947968_1.png"
            ],
            accentHex: 0xF43F5E
        ),
        FullGramProfileEffectPreset(
            id: "pe_dragon_s_approach",
            title: "Приближение дракона · Dragon's Approach",
            category: "Аниме",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dragon%27s%20Approach/Animated/Dragon%27s%20Approach_layer_0_1379220459161128960_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Dragon%27s%20Approach/Animated/Dragon%27s%20Approach_layer_1_1379220459161128960_1.png"
            ],
            accentHex: 0xF97316
        ),
        FullGramProfileEffectPreset(
            id: "pe_liquid_moonlight",
            title: "Лунный свет · Liquid Moonlight",
            category: "Космос",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Liquid%20Moonlight/Animated/Liquid%20Moonlight_layer_0_1409898408021458976_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Liquid%20Moonlight/Animated/Liquid%20Moonlight_layer_1_1409898408021458976_1.png"
            ],
            accentHex: 0x818CF8
        ),
        FullGramProfileEffectPreset(
            id: "pe_moonlit_crystals",
            title: "Лунные кристаллы · Moonlit Crystals",
            category: "Космос",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Moonlit%20Crystals/Animated/Moonlit%20Crystals_layer_0_1409898408042303629_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Moonlit%20Crystals/Animated/Moonlit%20Crystals_layer_1_1409898408042303629_1.png"
            ],
            accentHex: 0x67E8F9
        ),
        FullGramProfileEffectPreset(
            id: "pe_butterfly_haven",
            title: "Бабочки · Butterfly Haven",
            category: "Природа",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Butterfly%20Haven/Animated/Butterfly%20Haven_layer_0_1404558257250373692_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Butterfly%20Haven/Animated/Butterfly%20Haven_layer_1_1404558257250373692_1.png"
            ],
            accentHex: 0xC084FC
        ),
        FullGramProfileEffectPreset(
            id: "pe_magic_hearts",
            title: "Магические сердца · Magic Hearts",
            category: "Милые",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Magic%20Hearts/Animated/Magic%20Hearts_layer_0_1139323100568244355_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Magic%20Hearts/Animated/Magic%20Hearts_layer_1_1139323100568244355_1.png"
            ],
            accentHex: 0xF472B6
        ),
        FullGramProfileEffectPreset(
            id: "pe_magic_hearts_gold",
            title: "Золотые сердца · Magic Hearts Gold",
            category: "Милые",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Magic%20Hearts%20%28Gold%29/Animated/Magic%20Hearts%20%28Gold%29_layer_0_1341895142495359141_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Magic%20Hearts%20%28Gold%29/Animated/Magic%20Hearts%20%28Gold%29_layer_1_1341895142495359141_1.png"
            ],
            accentHex: 0xFBBF24
        ),
        FullGramProfileEffectPreset(
            id: "pe_lofi_cat_zoomies",
            title: "Котик Lofi · Lofi Cat Zoomies",
            category: "Милые",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Lofi%20Cat%20Zoomies/Animated/Lofi%20Cat%20Zoomies_layer_0_1309668861901279422_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Lofi%20Cat%20Zoomies/Animated/Lofi%20Cat%20Zoomies_layer_1_1309668861901279422_1.png"
            ],
            accentHex: 0xFB923C
        ),
        FullGramProfileEffectPreset(
            id: "pe_mooncap_forest_pink",
            title: "Лунный лес · Mooncap Forest",
            category: "Космос",
            layerURLs: [
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Mooncap%20Forest%20%28Pink%29/Animated/Mooncap%20Forest%20%28Pink%29_layer_0_1324454241196310685_0.png",
                "https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/discord_collectibles/Profile_Effects/Mooncap%20Forest%20%28Pink%29/Animated/Mooncap%20Forest%20%28Pink%29_layer_1_1324454241196310685_1.png"
            ],
            accentHex: 0xEC4899
        )
    ]

    private static let builtInEffectsById: [String: FullGramProfileEffectPreset] = Dictionary(
        uniqueKeysWithValues: builtInEffects.map { ($0.id, $0) }
    )

    public static var allEffects: [FullGramProfileEffectPreset] {
        let discord = FullGramDiscordCosmeticsCatalog.shared.profileEffects
        guard !discord.isEmpty else {
            return self.builtInEffects
        }
        let builtInIds = Set(self.builtInEffects.map(\.id))
        return self.builtInEffects + discord.filter { !builtInIds.contains($0.id) }
    }

    public static func selectedEffectId(forPeerId peerId: Int64, selfPeerId: Int64? = nil) -> String? {
        return FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId ?? peerId)?.profileEffectId
    }

    public static func setSelectedEffect(forPeerId peerId: Int64, effectId: String?) {
        FullGramCloudCosmetics.shared.setProfileEffect(forPeerId: peerId, effectId: effectId)
    }

    public static func effect(forPeerId peerId: Int64?, selfPeerId: Int64?) -> FullGramProfileEffectPreset? {
        guard let cosmetics = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId),
              let id = cosmetics.profileEffectId,
              !id.isEmpty else {
            return nil
        }
        if let builtin = self.builtInEffectsById[id] {
            return builtin
        }
        FullGramDiscordCosmeticsCatalog.shared.refreshIfNeeded(maxAge: 21600.0)
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
        let safeId = String(effectId.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? Character($0) : "_" })
        let token = safeId.isEmpty ? "effect" : safeId
        return self.cacheDirectory().appendingPathComponent("\(token)_layer\(layerIndex).png")
    }

    public static func cachedThumbnailURL(effectId: String) -> URL {
        let safeId = String(effectId.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? Character($0) : "_" })
        let token = safeId.isEmpty ? "effect" : safeId
        return self.cacheDirectory().appendingPathComponent("\(token)_thumb.png")
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
        c.countLimit = 28
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()
    private static let thumbnailCache: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>()
        c.countLimit = 250
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()
    private static let decodeOpQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "FullGram.AvatarFrameDecode"
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 4
        return q
    }()
    private static let ioQueue = DispatchQueue(label: "FullGram.AvatarFrameIO", qos: .userInitiated, attributes: .concurrent)
    private static let inflightLock = NSLock()
    private static var inflightCallbacks: [String: [@Sendable (FullGramAnimatedFrameSequence?) -> Void]] = [:]
    private static var inflightDownloadCallbacks: [String: [@Sendable (Bool) -> Void]] = [:]
    private static var cancelledTokens: Set<UUID> = []
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15.0
        cfg.timeoutIntervalForResource = 45.0
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = URLCache(memoryCapacity: 12 * 1024 * 1024, diskCapacity: 48 * 1024 * 1024)
        return URLSession(configuration: cfg)
    }()

    private static let cachePruneOnce: Void = {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { _ in
            sequenceCache.removeAllObjects()
            thumbnailCache.removeAllObjects()
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 12.0) {
            pruneDirectoryIfNeeded(FullGramAvatarFrames.cacheDirectory(), maxBytes: 64 * 1024 * 1024)
            pruneDirectoryIfNeeded(FullGramProfileEffects.cacheDirectory(), maxBytes: 64 * 1024 * 1024)
        }
    }()

    private static func removeCorruptCachedFileIfNeeded(_ url: URL) {
        let framesPath = FullGramAvatarFrames.cacheDirectory().standardizedFileURL.path + "/"
        let effectsPath = FullGramProfileEffects.cacheDirectory().standardizedFileURL.path + "/"
        let targetPath = url.standardizedFileURL.path
        if targetPath.hasPrefix(framesPath) || targetPath.hasPrefix(effectsPath) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func pruneDirectoryIfNeeded(_ dir: URL, maxBytes: Int64) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return
        }
        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for u in urls {
            guard let vals = try? u.resourceValues(forKeys: keys) else { continue }
            let sz = Int64(vals.fileSize ?? 0)
            let dt = vals.contentAccessDate ?? vals.contentModificationDate ?? Date.distantPast
            entries.append((u, sz, dt))
            total += sz
        }
        guard total > maxBytes else { return }
        entries.sort { $0.date < $1.date }
        for item in entries {
            if total <= (maxBytes * 3) / 4 { break }
            try? fm.removeItem(at: item.url)
            total -= item.size
        }
    }

    private static func mirrorURLs(for urlStrings: [String]) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        let appendUnique: (String) -> Void = { str in
            guard !str.isEmpty, !seen.contains(str), let u = URL(string: str), u.scheme?.lowercased() == "https" else { return }
            seen.insert(str)
            urls.append(u)
        }
        for raw in urlStrings {
            appendUnique(raw)
            if raw.hasPrefix("https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/") {
                let tail = String(raw.dropFirst("https://cdn.jsdelivr.net/gh/JulesZYTB/discord-collectibles-downloader@main/".count))
                appendUnique("https://raw.githubusercontent.com/JulesZYTB/discord-collectibles-downloader/main/" + tail)
            } else if raw.hasPrefix("https://cdn.jsdelivr.net/gh/shermanko/FullGram@") {
                let tail = String(raw.dropFirst("https://cdn.jsdelivr.net/gh/shermanko/FullGram@".count))
                if let slashIdx = tail.firstIndex(of: "/") {
                    let branch = String(tail[..<slashIdx])
                    let rest = String(tail[tail.index(after: slashIdx)...])
                    appendUnique("https://raw.githubusercontent.com/shermanko/FullGram/\(branch)/\(rest)")
                }
            }
        }
        return urls
    }

    private static func isImageVisiblyOpaque(_ image: CGImage) -> Bool {
        let w = 16
        let h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &pixels,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: w * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return true
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var visibleCount = 0
        var i = 3
        while i < pixels.count {
            if pixels[i] >= 20 {
                visibleCount += 1
                if visibleCount >= 3 {
                    return true
                }
            }
            i += 4
        }
        return false
    }

    private static func writeThumbnailPNG(_ image: CGImage, to url: URL) {
        let tmpURL = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp.png")
        guard let dest = CGImageDestinationCreateWithURL(tmpURL as CFURL, "public.png" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) {
            let _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } else {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    public static func invalidate(cacheKey: String) {
        self.sequenceCache.removeObject(forKey: cacheKey as NSString)
        self.thumbnailCache.removeObject(forKey: ("thumb_" + cacheKey) as NSString)
    }

    public static func cachedSequence(for preset: FullGramAvatarFramePreset) -> FullGramAnimatedFrameSequence? {
        return self.sequenceCache.object(forKey: preset.id as NSString)
    }

    public static func cachedThumbnail(cacheKey: String) -> CGImage? {
        return self.thumbnailCache.object(forKey: ("thumb_" + cacheKey) as NSString)
    }

    public static func cancelThumbnail(token: UUID?) {
        guard let token else { return }
        self.inflightLock.lock()
        if self.cancelledTokens.count >= 512 {
            self.cancelledTokens.removeAll(keepingCapacity: true)
        }
        self.cancelledTokens.insert(token)
        self.inflightLock.unlock()
    }

    private static func isCancelled(_ token: UUID) -> Bool {
        self.inflightLock.lock()
        let flag = self.cancelledTokens.contains(token)
        self.inflightLock.unlock()
        return flag
    }

    public static func prefetchThumbnail(for preset: FullGramAvatarFramePreset, maxPixelSize: Int = 180) {
        let _ = Self.cachePruneOnce
        if self.cachedThumbnail(cacheKey: preset.id) != nil || self.cachedSequence(for: preset) != nil {
            return
        }
        self.ioQueue.async {
            if let localURL = FullGramAvatarFrames.frameURL(for: preset) {
                let thumbDst = (!preset.isBundled && preset.localCustomPath == nil) ? FullGramAvatarFrames.cachedThumbnailDiskURL(for: preset) : nil
                self.decodeOpQueue.addOperation {
                    _ = self.decodeStaticThumbnail(url: localURL, cacheKey: preset.id, maxPixelSize: maxPixelSize, diskCacheURL: thumbDst)
                }
                return
            }
            let thumbDst = FullGramAvatarFrames.cachedThumbnailDiskURL(for: preset)
            if FileManager.default.fileExists(atPath: thumbDst.path) {
                self.decodeOpQueue.addOperation {
                    _ = self.decodeStaticThumbnail(url: thumbDst, cacheKey: preset.id, maxPixelSize: maxPixelSize)
                }
                return
            }
            guard preset.localCustomPath == nil else { return }
            let thumbURLs = FullGramAvatarFrames.thumbnailRemoteURLs(for: preset)
            let fullURLs = FullGramAvatarFrames.remoteURLs(for: preset)
            let downloadDst = (thumbURLs == fullURLs) ? FullGramAvatarFrames.cachedDiskURL(for: preset) : thumbDst
            self.downloadRemoteImage(urls: thumbURLs, dst: downloadDst) { ok in
                guard ok else { return }
                self.decodeOpQueue.addOperation {
                    _ = self.decodeStaticThumbnail(url: downloadDst, cacheKey: preset.id, maxPixelSize: maxPixelSize, diskCacheURL: thumbDst)
                }
            }
        }
    }

    public static func prefetchProfileEffectThumbnail(effectId: String, layerURLs: [String], maxPixelSize: Int = 320) {
        let cacheKey = "pe_\(effectId)_thumb"
        if self.cachedThumbnail(cacheKey: cacheKey) != nil {
            return
        }
        let orderedIndices: [Int] = layerURLs.count > 1 ? [1, 0] : (layerURLs.isEmpty ? [] : [0])
        guard !orderedIndices.isEmpty else { return }
        let thumbDiskURL = FullGramProfileEffects.cachedThumbnailURL(effectId: effectId)
        self.ioQueue.async {
            if FileManager.default.fileExists(atPath: thumbDiskURL.path),
               let img = self.decodeStaticThumbnail(url: thumbDiskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize) {
                let _ = img
                return
            }
            for idx in orderedIndices {
                let layerURL = FullGramProfileEffects.cachedLayerURL(effectId: effectId, layerIndex: idx)
                if FileManager.default.fileExists(atPath: layerURL.path) {
                    if self.decodeStaticThumbnail(url: layerURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, diskCacheURL: thumbDiskURL) != nil {
                        return
                    }
                }
            }
            let primaryIdx = orderedIndices[0]
            let primaryDiskURL = FullGramProfileEffects.cachedLayerURL(effectId: effectId, layerIndex: primaryIdx)
            let urls = self.mirrorURLs(for: [layerURLs[primaryIdx]])
            self.downloadRemoteImage(urls: urls, dst: primaryDiskURL) { ok in
                guard ok else { return }
                self.decodeOpQueue.addOperation {
                    _ = self.decodeStaticThumbnail(url: primaryDiskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, diskCacheURL: thumbDiskURL)
                }
            }
        }
    }

    public static func prefetchProfileEffectThumbnail(effectId: String, urlString: String, maxPixelSize: Int = 320) {
        self.prefetchProfileEffectThumbnail(effectId: effectId, layerURLs: [urlString], maxPixelSize: maxPixelSize)
    }

    @discardableResult
    public static func thumbnailAsync(
        for preset: FullGramAvatarFramePreset,
        maxPixelSize: Int = 180,
        completion: @escaping @Sendable (CGImage?) -> Void
    ) -> UUID? {
        let _ = Self.cachePruneOnce
        if let cached = self.cachedThumbnail(cacheKey: preset.id) {
            completion(cached)
            return nil
        }
        if let seq = self.cachedSequence(for: preset), let visible = seq.frames.first(where: { self.isImageVisiblyOpaque($0) }) ?? seq.frames.first {
            self.thumbnailCache.setObject(visible, forKey: ("thumb_" + preset.id) as NSString, cost: max(1024, visible.bytesPerRow * visible.height))
            completion(visible)
            return nil
        }

        let token = UUID()
        self.ioQueue.async {
            guard !self.isCancelled(token) else { return }
            let thumbDst = (!preset.isBundled && preset.localCustomPath == nil) ? FullGramAvatarFrames.cachedThumbnailDiskURL(for: preset) : nil
            if let localURL = FullGramAvatarFrames.frameURL(for: preset) {
                self.decodeOpQueue.addOperation {
                    guard !self.isCancelled(token) else { return }
                    let img = self.decodeStaticThumbnail(url: localURL, cacheKey: preset.id, maxPixelSize: maxPixelSize, diskCacheURL: thumbDst)
                    guard !self.isCancelled(token) else { return }
                    DispatchQueue.main.async { completion(img) }
                }
                return
            }
            let diskThumb = FullGramAvatarFrames.cachedThumbnailDiskURL(for: preset)
            if FileManager.default.fileExists(atPath: diskThumb.path) {
                self.decodeOpQueue.addOperation {
                    guard !self.isCancelled(token) else { return }
                    let img = self.decodeStaticThumbnail(url: diskThumb, cacheKey: preset.id, maxPixelSize: maxPixelSize)
                    guard !self.isCancelled(token) else { return }
                    DispatchQueue.main.async { completion(img) }
                }
                return
            }
            guard preset.localCustomPath == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let thumbURLs = FullGramAvatarFrames.thumbnailRemoteURLs(for: preset)
            let fullURLs = FullGramAvatarFrames.remoteURLs(for: preset)
            let downloadDst = (thumbURLs == fullURLs) ? FullGramAvatarFrames.cachedDiskURL(for: preset) : diskThumb
            self.downloadRemoteImage(urls: thumbURLs, dst: downloadDst) { ok in
                guard !self.isCancelled(token) else { return }
                guard ok else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                self.decodeOpQueue.addOperation {
                    guard !self.isCancelled(token) else { return }
                    let img = self.decodeStaticThumbnail(url: downloadDst, cacheKey: preset.id, maxPixelSize: maxPixelSize, diskCacheURL: diskThumb)
                    guard !self.isCancelled(token) else { return }
                    DispatchQueue.main.async { completion(img) }
                }
            }
        }
        return token
    }

    @discardableResult
    public static func profileEffectThumbnailAsync(
        effectId: String,
        layerURLs: [String],
        maxPixelSize: Int = 320,
        completion: @escaping @Sendable (CGImage?) -> Void
    ) -> UUID? {
        let cacheKey = "pe_\(effectId)_thumb"
        if let cached = self.cachedThumbnail(cacheKey: cacheKey) {
            completion(cached)
            return nil
        }
        let orderedIndices: [Int] = layerURLs.count > 1 ? [1, 0] : (layerURLs.isEmpty ? [] : [0])
        for idx in orderedIndices {
            let layerKey = "pe_\(effectId)_\(idx)" as NSString
            if let seq = self.sequenceCache.object(forKey: layerKey),
               let visible = seq.frames.first(where: { self.isImageVisiblyOpaque($0) }) ?? seq.frames.first {
                self.thumbnailCache.setObject(visible, forKey: ("thumb_" + cacheKey) as NSString, cost: max(1024, visible.bytesPerRow * visible.height))
                completion(visible)
                return nil
            }
        }
        guard !orderedIndices.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }

        let token = UUID()
        let thumbDiskURL = FullGramProfileEffects.cachedThumbnailURL(effectId: effectId)
        self.ioQueue.async {
            guard !self.isCancelled(token) else { return }
            if FileManager.default.fileExists(atPath: thumbDiskURL.path) {
                self.decodeOpQueue.addOperation {
                    guard !self.isCancelled(token) else { return }
                    if let img = self.decodeStaticThumbnail(url: thumbDiskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize) {
                        DispatchQueue.main.async { completion(img) }
                    } else {
                        try? FileManager.default.removeItem(at: thumbDiskURL)
                        self.resolveProfileEffectThumbnailFromLayers(
                            effectId: effectId,
                            layerURLs: layerURLs,
                            orderedIndices: orderedIndices,
                            cacheKey: cacheKey,
                            maxPixelSize: maxPixelSize,
                            thumbDiskURL: thumbDiskURL,
                            token: token,
                            completion: completion
                        )
                    }
                }
                return
            }
            self.resolveProfileEffectThumbnailFromLayers(
                effectId: effectId,
                layerURLs: layerURLs,
                orderedIndices: orderedIndices,
                cacheKey: cacheKey,
                maxPixelSize: maxPixelSize,
                thumbDiskURL: thumbDiskURL,
                token: token,
                completion: completion
            )
        }
        return token
    }

    @discardableResult
    public static func profileEffectThumbnailAsync(
        effectId: String,
        urlString: String,
        maxPixelSize: Int = 320,
        completion: @escaping @Sendable (CGImage?) -> Void
    ) -> UUID? {
        return self.profileEffectThumbnailAsync(effectId: effectId, layerURLs: [urlString], maxPixelSize: maxPixelSize, completion: completion)
    }

    private static func resolveProfileEffectThumbnailFromLayers(
        effectId: String,
        layerURLs: [String],
        orderedIndices: [Int],
        cacheKey: String,
        maxPixelSize: Int,
        thumbDiskURL: URL,
        token: UUID,
        completion: @escaping @Sendable (CGImage?) -> Void
    ) {
        guard !self.isCancelled(token), let firstIdx = orderedIndices.first else {
            if !self.isCancelled(token) {
                DispatchQueue.main.async { completion(nil) }
            }
            return
        }
        let restIndices = Array(orderedIndices.dropFirst())
        let diskURL = FullGramProfileEffects.cachedLayerURL(effectId: effectId, layerIndex: firstIdx)
        if FileManager.default.fileExists(atPath: diskURL.path) {
            self.decodeOpQueue.addOperation {
                guard !self.isCancelled(token) else { return }
                if let img = self.decodeStaticThumbnail(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, diskCacheURL: thumbDiskURL),
                   self.isImageVisiblyOpaque(img) {
                    DispatchQueue.main.async { completion(img) }
                } else if !restIndices.isEmpty {
                    self.resolveProfileEffectThumbnailFromLayers(
                        effectId: effectId,
                        layerURLs: layerURLs,
                        orderedIndices: restIndices,
                        cacheKey: cacheKey,
                        maxPixelSize: maxPixelSize,
                        thumbDiskURL: thumbDiskURL,
                        token: token,
                        completion: completion
                    )
                } else {
                    let fallbackImg = self.decodeStaticThumbnail(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize)
                    DispatchQueue.main.async { completion(fallbackImg) }
                }
            }
            return
        }
        let urls = self.mirrorURLs(for: [layerURLs[firstIdx]])
        self.downloadRemoteImage(urls: urls, dst: diskURL) { ok in
            guard !self.isCancelled(token) else { return }
            guard ok else {
                if !restIndices.isEmpty {
                    self.resolveProfileEffectThumbnailFromLayers(
                        effectId: effectId,
                        layerURLs: layerURLs,
                        orderedIndices: restIndices,
                        cacheKey: cacheKey,
                        maxPixelSize: maxPixelSize,
                        thumbDiskURL: thumbDiskURL,
                        token: token,
                        completion: completion
                    )
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
                return
            }
            self.decodeOpQueue.addOperation {
                guard !self.isCancelled(token) else { return }
                if let img = self.decodeStaticThumbnail(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, diskCacheURL: thumbDiskURL),
                   self.isImageVisiblyOpaque(img) {
                    DispatchQueue.main.async { completion(img) }
                } else if !restIndices.isEmpty {
                    self.resolveProfileEffectThumbnailFromLayers(
                        effectId: effectId,
                        layerURLs: layerURLs,
                        orderedIndices: restIndices,
                        cacheKey: cacheKey,
                        maxPixelSize: maxPixelSize,
                        thumbDiskURL: thumbDiskURL,
                        token: token,
                        completion: completion
                    )
                } else {
                    let fallbackImg = self.decodeStaticThumbnail(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize)
                    DispatchQueue.main.async { completion(fallbackImg) }
                }
            }
        }
    }

    private static func downscaledCGImage(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let maxSide = max(image.width, image.height)
        guard maxPixelSize > 0, maxSide > maxPixelSize else {
            return image
        }
        let scale = CGFloat(maxPixelSize) / CGFloat(maxSide)
        let targetW = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let targetH = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: targetW,
                  height: targetH,
                  bitsPerComponent: 8,
                  bytesPerRow: targetW * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return ctx.makeImage() ?? image
    }

    private static func decodeSingleFrame(
        source: CGImageSource,
        index: Int,
        maxPixelSize: Int
    ) -> CGImage? {
        let safeMax = max(32, min(maxPixelSize, 1024))
        // Inspect header dimensions first to block PNG/GIF decompression bombs before decoding pixels.
        if let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] {
            let pw = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let ph = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
            if pw > 8192 || ph > 8192 || Int64(pw) * Int64(ph) > 25_000_000 {
                return nil
            }
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: safeMax,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let thumb = CGImageSourceCreateThumbnailAtIndex(source, index, thumbOptions as CFDictionary) {
            return thumb
        }
        return CGImageSourceCreateImageAtIndex(source, index, nil).map { self.downscaledCGImage($0, maxPixelSize: safeMax) }
    }

    private static func decodeStaticThumbnail(
        url: URL,
        cacheKey: String,
        maxPixelSize: Int,
        diskCacheURL: URL? = nil
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            self.removeCorruptCachedFileIfNeeded(url)
            return nil
        }
        let rawCount = CGImageSourceGetCount(source)
        guard rawCount > 0 else {
            self.removeCorruptCachedFileIfNeeded(url)
            return nil
        }

        var candidateIndices: [Int] = [0]
        if rawCount > 1 {
            let extra = [rawCount / 3, rawCount / 2, (rawCount * 2) / 3, max(0, rawCount - 1)]
            for idx in extra where idx >= 0 && idx < rawCount && !candidateIndices.contains(idx) {
                candidateIndices.append(idx)
            }
        }

        var firstDecoded: CGImage?
        var chosen: CGImage?
        for idx in candidateIndices {
            guard let img = self.decodeSingleFrame(source: source, index: idx, maxPixelSize: maxPixelSize) else {
                continue
            }
            if firstDecoded == nil {
                firstDecoded = img
            }
            if self.isImageVisiblyOpaque(img) {
                chosen = img
                break
            }
        }
        guard let finalImg = chosen ?? firstDecoded else {
            self.removeCorruptCachedFileIfNeeded(url)
            return nil
        }
        self.thumbnailCache.setObject(finalImg, forKey: ("thumb_" + cacheKey) as NSString, cost: max(1024, finalImg.bytesPerRow * finalImg.height))
        if rawCount > 1, let diskCacheURL, diskCacheURL != url || !FileManager.default.fileExists(atPath: diskCacheURL.path) {
            self.writeThumbnailPNG(finalImg, to: diskCacheURL)
        }
        return finalImg
    }

    public static func sequenceAsync(
        for preset: FullGramAvatarFramePreset,
        maxPixelSize: Int = 288,
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

        @Sendable func finish(_ seq: FullGramAnimatedFrameSequence?) {
            self.inflightLock.lock()
            let callbacks = self.inflightCallbacks.removeValue(forKey: preset.id) ?? []
            self.inflightLock.unlock()
            DispatchQueue.main.async {
                for cb in callbacks {
                    cb(seq)
                }
            }
        }

        self.ioQueue.async {
            if let localURL = FullGramAvatarFrames.frameURL(for: preset) {
                self.decodeOpQueue.addOperation {
                    finish(self.decodeFile(url: localURL, cacheKey: preset.id, maxPixelSize: maxPixelSize, maxFrames: 36))
                }
                return
            }
            guard preset.localCustomPath == nil else {
                finish(nil)
                return
            }
            let dst = FullGramAvatarFrames.cachedDiskURL(for: preset)
            self.downloadRemoteImage(urls: FullGramAvatarFrames.remoteURLs(for: preset), dst: dst) { ok in
                guard ok else {
                    finish(nil)
                    return
                }
                self.decodeOpQueue.addOperation {
                    finish(self.sequence(for: preset, maxPixelSize: maxPixelSize))
                }
            }
        }
    }

    public static func profileEffectLayerAsync(
        effectId: String,
        layerIndex: Int,
        urlString: String,
        maxPixelSize: Int = 960,
        completion: @escaping @Sendable (FullGramAnimatedFrameSequence?) -> Void
    ) {
        let cacheKey = "pe_\(effectId)_\(layerIndex)"
        if let cached = self.sequenceCache.object(forKey: cacheKey as NSString) {
            completion(cached)
            return
        }
        let urls = self.mirrorURLs(for: [urlString])
        guard !urls.isEmpty else {
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

        @Sendable func finish(_ seq: FullGramAnimatedFrameSequence?) {
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
        self.ioQueue.async {
            if FileManager.default.fileExists(atPath: diskURL.path) {
                self.decodeOpQueue.addOperation {
                    finish(self.decodeFile(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, maxFrames: 60))
                }
                return
            }
            self.downloadRemoteImage(urls: urls, dst: diskURL) { ok in
                guard ok else {
                    finish(nil)
                    return
                }
                self.decodeOpQueue.addOperation {
                    finish(self.decodeFile(url: diskURL, cacheKey: cacheKey, maxPixelSize: maxPixelSize, maxFrames: 60))
                }
            }
        }
    }

    private static func downloadRemoteImage(
        urls: [URL],
        dst: URL,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let key = dst.path
        self.inflightLock.lock()
        if var callbacks = self.inflightDownloadCallbacks[key] {
            callbacks.append(completion)
            self.inflightDownloadCallbacks[key] = callbacks
            self.inflightLock.unlock()
            return
        }
        self.inflightDownloadCallbacks[key] = [completion]
        self.inflightLock.unlock()

        @Sendable func finishDownload(_ ok: Bool) {
            self.inflightLock.lock()
            let callbacks = self.inflightDownloadCallbacks.removeValue(forKey: key) ?? []
            self.inflightLock.unlock()
            for cb in callbacks {
                cb(ok)
            }
        }

        self.performDownloadAttempt(urls: urls, dst: dst, completion: finishDownload)
    }

    private static func performDownloadAttempt(
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
               data.count > 128,
               data.count <= 8 * 1024 * 1024 {
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
                self.performDownloadAttempt(urls: rest, dst: dst, completion: completion)
            } else {
                completion(false)
            }
        }.resume()
    }

    public static func sequence(for preset: FullGramAvatarFramePreset, maxPixelSize: Int = 288) -> FullGramAnimatedFrameSequence? {
        if let cached = self.sequenceCache.object(forKey: preset.id as NSString) {
            return cached
        }
        guard let url = FullGramAvatarFrames.frameURL(for: preset) else {
            return nil
        }
        return self.decodeFile(url: url, cacheKey: preset.id, maxPixelSize: maxPixelSize, maxFrames: 36)
    }

    private static func decodeFile(
        url: URL,
        cacheKey: String,
        maxPixelSize: Int,
        maxFrames: Int
    ) -> FullGramAnimatedFrameSequence? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            self.removeCorruptCachedFileIfNeeded(url)
            return nil
        }
        let rawCount = CGImageSourceGetCount(source)
        guard rawCount > 0 else {
            self.removeCorruptCachedFileIfNeeded(url)
            return nil
        }

        let strideStep = max(1, (rawCount + maxFrames - 1) / maxFrames)
        var images: [CGImage] = []
        var durations: [Double] = []
        images.reserveCapacity(min(rawCount, maxFrames))
        durations.reserveCapacity(min(rawCount, maxFrames))

        var totalDuration: Double = 0.0
        var idx = 0
        while idx < rawCount {
            if let cgImage = self.decodeSingleFrame(source: source, index: idx, maxPixelSize: maxPixelSize) {
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
        keyTimes.append(NSNumber(value: 1.0))

        let seq = FullGramAnimatedFrameSequence(frames: images, keyTimes: keyTimes, totalDuration: totalDuration)
        let byteCost = images.reduce(0) { $0 + ($1.bytesPerRow * $1.height) }
        self.sequenceCache.setObject(seq, forKey: cacheKey as NSString, cost: max(1024, byteCost))
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
    private var activeThumbToken: UUID?
    public var onLoadingStateChanged: ((Bool) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.clipsToBounds = false
        self.layer.masksToBounds = false
        self.frameLayer.contentsGravity = .resizeAspect
        self.frameLayer.contentsScale = UIScreen.main.scale
        self.frameLayer.minificationFilter = .trilinear
        self.frameLayer.magnificationFilter = .trilinear
        self.layer.addSublayer(self.frameLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Slightly tighter scale for small chat-list avatars so frames never bleed into adjacent nicknames
        let scale: CGFloat = self.bounds.width < 52.0 ? 1.14 : 1.18
        let w = self.bounds.width * scale
        let h = self.bounds.height * scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frameLayer.frame = CGRect(
            x: (self.bounds.width - w) * 0.5,
            y: (self.bounds.height - h) * 0.5,
            width: w,
            height: h
        )
        CATransaction.commit()
    }

    public func cancelPendingLoad() {
        FullGramAnimatedImageDecoder.cancelThumbnail(token: self.activeThumbToken)
        self.activeThumbToken = nil
        self.pendingFrameId = nil
        self.currentFrameId = nil
        self.frameLayer.removeAllAnimations()
        self.frameLayer.contents = nil
        self.onLoadingStateChanged?(false)
    }

    public func stop() {
        self.cancelPendingLoad()
    }

    public func configureThumbnail(with preset: FullGramAvatarFramePreset?) {
        FullGramAnimatedImageDecoder.cancelThumbnail(token: self.activeThumbToken)
        self.activeThumbToken = nil
        guard let preset else {
            self.currentFrameId = nil
            self.pendingFrameId = nil
            self.frameLayer.removeAllAnimations()
            self.frameLayer.contents = nil
            self.isHidden = true
            self.onLoadingStateChanged?(false)
            return
        }
        self.isHidden = false
        if self.currentFrameId == preset.id && self.frameLayer.contents != nil {
            self.onLoadingStateChanged?(false)
            return
        }
        self.currentFrameId = nil
        self.pendingFrameId = preset.id
        self.frameLayer.removeAllAnimations()
        self.frameLayer.contents = nil

        if let cached = FullGramAnimatedImageDecoder.cachedThumbnail(cacheKey: preset.id) {
            self.currentFrameId = preset.id
            self.frameLayer.contents = cached
            self.onLoadingStateChanged?(false)
            return
        }
        self.onLoadingStateChanged?(true)
        let targetId = preset.id
        self.activeThumbToken = FullGramAnimatedImageDecoder.thumbnailAsync(for: preset, maxPixelSize: 180) { [weak self] img in
            Task { @MainActor in
                guard let self, self.pendingFrameId == targetId else { return }
                self.activeThumbToken = nil
                self.pendingFrameId = nil
                if let img {
                    self.currentFrameId = targetId
                    self.frameLayer.contents = img
                } else {
                    self.currentFrameId = nil
                    self.frameLayer.contents = nil
                }
                self.onLoadingStateChanged?(false)
            }
        }
    }

    public func configure(with preset: FullGramAvatarFramePreset?) {
        FullGramAnimatedImageDecoder.cancelThumbnail(token: self.activeThumbToken)
        self.activeThumbToken = nil
        guard let preset else {
            self.currentFrameId = nil
            self.pendingFrameId = nil
            self.frameLayer.removeAllAnimations()
            self.frameLayer.contents = nil
            self.isHidden = true
            return
        }
        self.isHidden = false
        if self.currentFrameId == preset.id && self.frameLayer.contents != nil && self.frameLayer.animation(forKey: "fg.apng") != nil {
            return
        }
        self.currentFrameId = nil
        self.pendingFrameId = preset.id

        if let cached = FullGramAnimatedImageDecoder.cachedSequence(for: preset) {
            self.apply(sequence: cached, frameId: preset.id)
            return
        }

        self.frameLayer.removeAllAnimations()
        self.frameLayer.contents = FullGramAnimatedImageDecoder.cachedThumbnail(cacheKey: preset.id)
        let targetId = preset.id
        FullGramAnimatedImageDecoder.sequenceAsync(for: preset) { [weak self] seq in
            Task { @MainActor in
                guard let self, self.pendingFrameId == targetId else { return }
                self.apply(sequence: seq, frameId: targetId)
            }
        }
    }

    private func apply(sequence seq: FullGramAnimatedFrameSequence?, frameId: String) {
        self.pendingFrameId = nil
        self.frameLayer.removeAllAnimations()

        guard let seq, !seq.frames.isEmpty else {
            self.currentFrameId = nil
            self.frameLayer.contents = nil
            return
        }
        self.currentFrameId = frameId

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
    private var activeThumbToken: UUID?
    public var onLoadingStateChanged: ((Bool) -> Void)?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.clipsToBounds = true
        self.introLayer.contentsGravity = .resizeAspectFill
        self.introLayer.contentsScale = UIScreen.main.scale
        self.introLayer.minificationFilter = .trilinear
        self.introLayer.magnificationFilter = .trilinear
        self.ambientLayer.contentsGravity = .resizeAspectFill
        self.ambientLayer.contentsScale = UIScreen.main.scale
        self.ambientLayer.minificationFilter = .trilinear
        self.ambientLayer.magnificationFilter = .trilinear
        self.layer.addSublayer(self.ambientLayer)
        self.layer.addSublayer(self.introLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.ambientLayer.frame = self.bounds
        self.introLayer.frame = self.bounds
        CATransaction.commit()
    }

    public func cancelPendingLoad() {
        FullGramAnimatedImageDecoder.cancelThumbnail(token: self.activeThumbToken)
        self.activeThumbToken = nil
        self.pendingEffectId = nil
        self.currentEffectId = nil
        self.introLayer.removeAllAnimations()
        self.introLayer.contents = nil
        self.ambientLayer.removeAllAnimations()
        self.ambientLayer.contents = nil
        self.onLoadingStateChanged?(false)
    }

    public func stop() {
        self.cancelPendingLoad()
    }

    public func configureThumbnail(with preset: FullGramProfileEffectPreset?) {
        FullGramAnimatedImageDecoder.cancelThumbnail(token: self.activeThumbToken)
        self.activeThumbToken = nil
        guard let preset, !preset.layerURLs.isEmpty else {
            self.currentEffectId = nil
            self.pendingEffectId = nil
            self.introLayer.removeAllAnimations()
            self.introLayer.contents = nil
            self.ambientLayer.removeAllAnimations()
            self.ambientLayer.contents = nil
            self.isHidden = true
            self.onLoadingStateChanged?(false)
            return
        }
        self.isHidden = false
        if self.currentEffectId == preset.id && self.introLayer.contents != nil {
            self.onLoadingStateChanged?(false)
            return
        }
        self.currentEffectId = nil
        self.pendingEffectId = preset.id
        self.introLayer.removeAllAnimations()
        self.introLayer.contents = nil
        self.ambientLayer.removeAllAnimations()
        self.ambientLayer.contents = nil

        let cacheKey = "pe_\(preset.id)_thumb"
        if let cached = FullGramAnimatedImageDecoder.cachedThumbnail(cacheKey: cacheKey) {
            self.currentEffectId = preset.id
            self.introLayer.contents = cached
            self.onLoadingStateChanged?(false)
            return
        }
        self.onLoadingStateChanged?(true)
        let targetId = preset.id
        self.activeThumbToken = FullGramAnimatedImageDecoder.profileEffectThumbnailAsync(
            effectId: targetId,
            layerURLs: preset.layerURLs,
            maxPixelSize: 320
        ) { [weak self] img in
            Task { @MainActor in
                guard let self, self.pendingEffectId == targetId else { return }
                self.pendingEffectId = nil
                self.activeThumbToken = nil
                if let img {
                    self.currentEffectId = targetId
                    self.introLayer.contents = img
                }
                self.onLoadingStateChanged?(false)
            }
        }
    }

    public func configure(with preset: FullGramProfileEffectPreset?, forceReplay: Bool = false) {
        FullGramAnimatedImageDecoder.cancelThumbnail(token: self.activeThumbToken)
        self.activeThumbToken = nil
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
