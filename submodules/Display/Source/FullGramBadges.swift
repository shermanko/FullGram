import Foundation
import UIKit

public struct FullGramBadgeRole: Codable, Equatable {
    public var label: String
    public var shortLabel: String?
    public var emoji: String
    public var customEmojiId: String?
    public var color: String

    public init(label: String, shortLabel: String? = nil, emoji: String, customEmojiId: String? = nil, color: String) {
        self.label = label
        self.shortLabel = shortLabel
        self.emoji = emoji
        self.customEmojiId = customEmojiId
        self.color = color
    }
}

public struct FullGramBadgesPayload: Codable {
    public var version: Int?
    public var roles: [String: FullGramBadgeRole]
    public var users: [String: String]
    public var usernames: [String: String]?

    public init(
        version: Int? = 1,
        roles: [String: FullGramBadgeRole],
        users: [String: String],
        usernames: [String: String]? = nil
    ) {
        self.version = version
        self.roles = roles
        self.users = users
        self.usernames = usernames
    }
}

public struct FullGramBadge: Equatable {
    public let roleId: String
    public let label: String
    public let shortLabel: String
    public let emoji: String
    public let customEmojiId: Int64?
    public let colorHex: String

    public var chipText: String {
        let short = self.shortLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if short.isEmpty {
            return self.emoji
        }
        if self.emoji.isEmpty {
            return short
        }
        return "\(self.emoji) \(short)"
    }

    public var uiColor: UIColor {
        return UIColor(hexString: self.colorHex) ?? UIColor(rgb: 0x007aff)
    }
}

public final class FullGramBadges {
    public static let shared = FullGramBadges()
    public static let didChangeNotification = Notification.Name("FullGram.BadgesDidChange")

    private let lock = NSRecursiveLock()
    private let defaults = UserDefaults.standard
    private let enabledKey = "fullgram.badges.enabled"
    private let urlKey = "fullgram.badges.url"
    private let lastSyncKey = "fullgram.badges.lastSync"

    private var roles: [String: FullGramBadgeRole] = [:]
    private var usersById: [Int64: String] = [:]
    private var usersByName: [String: String] = [:]
    private var cachedIsEnabled: Bool?
    private var cachedCustomPopupText: String?
    private var isRefreshing = false

    public static let builtInRoles: [String: FullGramBadgeRole] = [
        "creator": FullGramBadgeRole(label: "Создатель FullGram", shortLabel: "CREATOR", emoji: "👑", color: "#FF9500"),
        "official": FullGramBadgeRole(label: "Официальный ресурс FullGram", shortLabel: "FULLGRAM", emoji: "🛡", color: "#007AFF"),
        "premium": FullGramBadgeRole(label: "FullGram+", shortLabel: "FG+", emoji: "💎", color: "#AF52DE"),
        "dev": FullGramBadgeRole(label: "Разработчик", shortLabel: "DEV", emoji: "⚡", color: "#34C759")
    ]

    private static let builtInUsersById: [Int64: String] = [
        8899688273: "creator"
    ]

    private static let builtInUsernames: [String: String] = [
        "shermanko": "creator",
        "fullgram_mod": "official",
        "fullgramgroup": "official"
    ]

    private init() {
        self.roles = Self.builtInRoles
        self.usersById = Self.builtInUsersById
        self.usersByName = Self.builtInUsernames
        self.loadCache()
    }

    public var isEnabled: Bool {
        get {
            self.lock.lock()
            if let v = self.cachedIsEnabled {
                self.lock.unlock()
                return v
            }
            let resolved: Bool = (self.defaults.object(forKey: self.enabledKey) == nil)
                ? true
                : self.defaults.bool(forKey: self.enabledKey)
            self.cachedIsEnabled = resolved
            self.lock.unlock()
            return resolved
        }
        set {
            self.lock.lock()
            self.cachedIsEnabled = newValue
            self.lock.unlock()
            self.defaults.set(newValue, forKey: self.enabledKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public static let defaultBadgesURL = "https://fullgram.korsakovx.workers.dev/badges.json"

    public var badgesURL: String {
        get {
            let stored = self.defaults.string(forKey: self.urlKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? Self.defaultBadgesURL : stored
        }
        set {
            self.defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: self.urlKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var totalCount: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.usersById.count + self.usersByName.count
    }

    public var roleSummaries: [(id: String, role: FullGramBadgeRole)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.roles
            .filter { !$0.key.hasPrefix("user_") && !$0.key.hasPrefix("name_") }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    public func rawAssignment(forPeerId peerId: Int64, username: String?) -> (roleId: String, role: FullGramBadgeRole)? {
        self.lock.lock()
        defer { self.lock.unlock() }

        let normId = FullGramCloudCosmetics.normalizedPeerId(peerId)
        var matchedRoleId = self.usersById[normId] ?? self.usersById[peerId]
        if matchedRoleId == nil, peerId < 0 {
            let raw = abs(peerId)
            matchedRoleId = self.usersById[raw]
        }
        if matchedRoleId == nil, let rawName = username, !rawName.isEmpty {
            let clean = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
            matchedRoleId = self.usersByName[clean]
        }
        guard let roleId = matchedRoleId, let role = self.roles[roleId] else {
            return nil
        }
        return (roleId, role)
    }

    public var customPopupText: String {
        get {
            self.lock.lock()
            if let v = self.cachedCustomPopupText {
                self.lock.unlock()
                return v
            }
            let resolved = UserDefaults.standard.string(forKey: "fullgram.badges.customPopupText") ?? ""
            self.cachedCustomPopupText = resolved
            self.lock.unlock()
            return resolved
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lock.lock()
            self.cachedCustomPopupText = trimmed
            self.lock.unlock()
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: "fullgram.badges.customPopupText")
            } else {
                UserDefaults.standard.set(trimmed, forKey: "fullgram.badges.customPopupText")
            }
            NotificationCenter.default.post(name: FullGramBadges.didChangeNotification, object: nil)
        }
    }

    public func resolvedPopupText(for badge: FullGramBadge) -> String {
        let custom = self.customPopupText
        if !custom.isEmpty {
            return custom
        }
        return badge.label
    }

    public func badge(forPeerId peerId: Int64, username: String?) -> FullGramBadge? {
        guard self.isEnabled else { return nil }
        guard let (roleId, role) = self.rawAssignment(forPeerId: peerId, username: username) else {
            return nil
        }
        return FullGramBadge(
            roleId: roleId,
            label: role.label,
            shortLabel: role.shortLabel ?? role.label,
            emoji: role.emoji,
            customEmojiId: role.customEmojiId.flatMap { Int64($0) },
            colorHex: role.color
        )
    }

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_badges.json")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: self.cacheFileURL),
              let payload = try? JSONDecoder().decode(FullGramBadgesPayload.self, from: data) else {
            return
        }
        self.applyPayload(payload)
    }

    private func applyPayload(_ payload: FullGramBadgesPayload) {
        self.lock.lock()
        var mergedRoles = Self.builtInRoles
        for (k, v) in payload.roles {
            mergedRoles[k] = v
        }

        var idMap = Self.builtInUsersById
        var nameMap = Self.builtInUsernames
        for (rawKey, roleId) in payload.users {
            let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if let num = Int64(trimmed) {
                idMap[num] = roleId
            } else {
                let clean = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
                if !clean.isEmpty {
                    nameMap[clean] = roleId
                }
            }
        }
        if let explicitNames = payload.usernames {
            for (rawName, roleId) in explicitNames {
                let clean = rawName.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
                if !clean.isEmpty { nameMap[clean] = roleId }
            }
        }

        self.roles = mergedRoles
        self.usersById = idMap
        self.usersByName = nameMap
        self.lock.unlock()
    }

    private static func mirrorURLs(from rawString: String) -> [URL] {
        let parts = rawString
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.compactMap { s -> URL? in
            guard let url = URL(string: s),
                  url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(),
                  !host.isEmpty,
                  host != "localhost",
                  !host.hasSuffix(".local") else {
                return nil
            }
            return url
        }
    }

    public func refreshIfNeeded() {
        guard !self.badgesURL.isEmpty else { return }
        let last = self.defaults.double(forKey: self.lastSyncKey)
        if Date().timeIntervalSince1970 - last < 1800.0 {
            return
        }
        self.refreshNow(completion: nil)
    }

    public func refreshNow(completion: ((Result<Int, Error>) -> Void)?) {
        let urls = Self.mirrorURLs(from: self.badgesURL)
        guard !urls.isEmpty else {
            DispatchQueue.main.async {
                completion?(.failure(NSError(domain: "FullGramBadges", code: 400, userInfo: [NSLocalizedDescriptionKey: "Укажите публичную https:// ссылку на badges.json (например Cloudflare Pages)."])))
            }
            return
        }

        self.lock.lock()
        if self.isRefreshing {
            self.lock.unlock()
            return
        }
        self.isRefreshing = true
        self.lock.unlock()

        self.fetchMirror(urls: urls, index: 0, lastError: nil, completion: completion)
    }

    private func fetchMirror(
        urls: [URL],
        index: Int,
        lastError: Error?,
        completion: ((Result<Int, Error>) -> Void)?
    ) {
        guard index < urls.count else {
            self.lock.lock()
            self.isRefreshing = false
            self.lock.unlock()
            let err = lastError ?? NSError(domain: "FullGramBadges", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить badges.json ни с одного зеркала."])
            DispatchQueue.main.async {
                completion?(.failure(err))
            }
            return
        }

        var req = URLRequest(url: urls[index])
        req.timeoutInterval = 10.0
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                self.fetchMirror(urls: urls, index: index + 1, lastError: error, completion: completion)
                return
            }
            guard (200 ..< 300).contains(status), let data, data.count <= 512_000 else {
                let httpErr = NSError(domain: "FullGramBadges", code: status, userInfo: [NSLocalizedDescriptionKey: "HTTP \(status) от \(urls[index].host ?? "")"])
                self.fetchMirror(urls: urls, index: index + 1, lastError: httpErr, completion: completion)
                return
            }
            do {
                let payload = try JSONDecoder().decode(FullGramBadgesPayload.self, from: data)
                try? data.write(to: self.cacheFileURL, options: .atomic)
                self.applyPayload(payload)
                self.defaults.set(Date().timeIntervalSince1970, forKey: self.lastSyncKey)

                self.lock.lock()
                self.isRefreshing = false
                let total = self.usersById.count + self.usersByName.count
                self.lock.unlock()

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                    completion?(.success(total))
                }
            } catch {
                self.fetchMirror(urls: urls, index: index + 1, lastError: error, completion: completion)
            }
        }.resume()
    }
}
