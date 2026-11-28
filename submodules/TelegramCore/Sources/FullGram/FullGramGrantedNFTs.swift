import Foundation
import Postbox
import SwiftSignalKit

public struct FullGramGrantedNFT: Codable, Equatable, Sendable {
    public var id: String
    public var giftId: String
    public var title: String
    public var modelName: String
    public var backdropName: String
    public var backdropId: Int32?
    public var patternName: String
    public var number: Int32
    public var note: String
    public var pinned: Bool
    public var hidden: Bool
    public var grantedAt: Int32

    public static func decoratedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "NFT" : trimmed
        if base.lowercased().hasSuffix("(fullgram)") {
            return base
        }
        return "\(base) (FullGram)"
    }

    public var numericGiftId: Int64? {
        return Int64(self.giftId)
    }

    public init(
        id: String,
        giftId: String,
        title: String,
        modelName: String,
        backdropName: String,
        backdropId: Int32? = nil,
        patternName: String,
        number: Int32,
        note: String = "",
        pinned: Bool = true,
        hidden: Bool = false,
        grantedAt: Int32 = Int32(Date().timeIntervalSince1970)
    ) {
        self.id = id
        self.giftId = giftId
        self.title = title
        self.modelName = modelName
        self.backdropName = backdropName
        self.backdropId = backdropId
        self.patternName = patternName
        self.number = number
        self.note = note
        self.pinned = pinned
        self.hidden = hidden
        self.grantedAt = grantedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case giftId
        case title
        case modelName
        case backdropName
        case backdropId
        case patternName
        case number
        case note
        case pinned
        case hidden
        case grantedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        if let str = try? c.decode(String.self, forKey: .giftId) {
            self.giftId = str
        } else if let num = try? c.decode(Int64.self, forKey: .giftId) {
            self.giftId = String(num)
        } else {
            self.giftId = ""
        }
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? "NFT"
        self.modelName = try c.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        self.backdropName = try c.decodeIfPresent(String.self, forKey: .backdropName) ?? ""
        self.backdropId = try c.decodeIfPresent(Int32.self, forKey: .backdropId)
        self.patternName = try c.decodeIfPresent(String.self, forKey: .patternName) ?? ""
        self.number = try c.decodeIfPresent(Int32.self, forKey: .number) ?? 1
        self.note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? true
        self.hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        self.grantedAt = try c.decodeIfPresent(Int32.self, forKey: .grantedAt) ?? Int32(Date().timeIntervalSince1970)
    }
}

private struct FullGramGrantedNFTsPayload: Codable {
    var version: Int?
    var users: [String: [FullGramGrantedNFT]]
}

public final class FullGramGrantedNFTStore: @unchecked Sendable {
    public static let shared = FullGramGrantedNFTStore()
    public static let didChangeNotification = Notification.Name("FullGram.GrantedNFTsDidChange")

    private static let nftsURL = "https://fullgram.korsakovx.workers.dev/nfts.json"
    private static let lastSyncKey = "fullgram.nfts.lastSync"

    private let lock = NSRecursiveLock()
    private var serverUsersById: [Int64: [FullGramGrantedNFT]] = [:]
    private var localUsersById: [Int64: [FullGramGrantedNFT]] = [:]
    private var usersById: [Int64: [FullGramGrantedNFT]] = [:]
    private var isRefreshing = false
    private var needsFollowUpRefresh = false
    private var pendingCompletions: [@Sendable (Bool) -> Void] = []
    private var _onServerNFTAction: (@Sendable (
        _ actorPeerId: Int64,
        _ targetPeerId: Int64,
        _ toPeerId: Int64?,
        _ entryId: String,
        _ slug: String,
        _ action: String,
        _ modelName: String?,
        _ backdropName: String?,
        _ backdropId: Int32?,
        _ patternName: String?,
        _ number: Int32?
    ) -> Void)?

    public var onServerNFTAction: (@Sendable (
        _ actorPeerId: Int64,
        _ targetPeerId: Int64,
        _ toPeerId: Int64?,
        _ entryId: String,
        _ slug: String,
        _ action: String,
        _ modelName: String?,
        _ backdropName: String?,
        _ backdropId: Int32?,
        _ patternName: String?,
        _ number: Int32?
    ) -> Void)? {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self._onServerNFTAction
        }
        set {
            self.lock.lock()
            self._onServerNFTAction = newValue
            self.lock.unlock()
        }
    }

    public static func candidatePeerIds(for raw: Int64) -> [Int64] {
        var ids: [Int64] = [raw]
        let u = UInt64(bitPattern: raw)
        if raw < 0, raw != Int64.min {
            let pos = abs(raw)
            if !ids.contains(pos) { ids.append(pos) }
        }
        // If `raw` is a Postbox PeerId.toInt64() encoded value (high bits shifted left by 35), decode the real Telegram ID.
        if raw > 0 && u >= (1 << 35) {
            let low = u & 0xffffffff
            let high = u >> 35
            let decoded = Int64(bitPattern: (high << 32) | low)
            if decoded > 0 && !ids.contains(decoded) {
                ids.append(decoded)
            }
        } else if raw > 0 {
            // Also compute the Postbox CloudUser PeerId.toInt64() form so legacy server keys match.
            let low = u & 0xffffffff
            let high = (u >> 32) & 0xffffffff
            if high > 0 {
                let encoded = Int64(bitPattern: (high << 35) | low)
                if !ids.contains(encoded) {
                    ids.append(encoded)
                }
            }
        }
        return ids
    }

    public static func normalizedTelegramId(for raw: Int64) -> Int64 {
        let u = UInt64(bitPattern: raw)
        if raw > 0 && u >= (1 << 35) {
            let low = u & 0xffffffff
            let high = u >> 35
            return Int64(bitPattern: (high << 32) | low)
        }
        if raw == Int64.min {
            return Int64.max
        }
        return raw < 0 ? abs(raw) : raw
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10.0
        cfg.timeoutIntervalForResource = 15.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private init() {
        self.loadLocalItemsCache()
        self.loadDiskCache()
        self.rebuildCombinedLocked()
    }

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_nfts.json")
    }

    private var localItemsFileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_local_nfts_v1.json")
    }

    private func loadLocalItemsCache() {
        guard let data = try? Data(contentsOf: self.localItemsFileURL),
              let payload = try? JSONDecoder().decode(FullGramGrantedNFTsPayload.self, from: data) else {
            return
        }
        var mapped: [Int64: [FullGramGrantedNFT]] = [:]
        for (k, list) in payload.users {
            if let id = Int64(k) {
                let norm = Self.normalizedTelegramId(for: id)
                if var existing = mapped[norm] {
                    let seenIds = Set(existing.map { $0.id })
                    for item in list where !seenIds.contains(item.id) {
                        existing.append(item)
                    }
                    mapped[norm] = existing
                } else {
                    mapped[norm] = list
                }
            }
        }
        self.localUsersById = mapped
    }

    private func saveLocalItemsLocked() {
        var strUsers: [String: [FullGramGrantedNFT]] = [:]
        for (k, list) in self.localUsersById where !list.isEmpty {
            strUsers[String(k)] = list
        }
        let payload = FullGramGrantedNFTsPayload(version: 1, users: strUsers)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: self.localItemsFileURL, options: .atomic)
        }
    }

    private func rebuildCombinedLocked() {
        var combined: [Int64: [FullGramGrantedNFT]] = [:]
        let allPeers = Set(self.serverUsersById.keys).union(self.localUsersById.keys)
        for peer in allPeers {
            var merged: [FullGramGrantedNFT] = []
            var seenIds = Set<String>()
            if let locals = self.localUsersById[peer] {
                for item in locals where seenIds.insert(item.id).inserted {
                    merged.append(item)
                }
            }
            if let servers = self.serverUsersById[peer] {
                for item in servers where seenIds.insert(item.id).inserted {
                    merged.append(item)
                }
            }
            if !merged.isEmpty {
                combined[peer] = merged
            }
        }
        self.usersById = combined
    }

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: self.cacheFileURL),
              let payload = try? JSONDecoder().decode(FullGramGrantedNFTsPayload.self, from: data) else {
            return
        }
        self.applyPayload(payload)
    }

    private func applyPayload(_ payload: FullGramGrantedNFTsPayload) {
        var mapped: [Int64: [FullGramGrantedNFT]] = [:]
        for (k, list) in payload.users {
            if let id = Int64(k) {
                let valid = list.filter { $0.numericGiftId != nil }
                if !valid.isEmpty {
                    let norm = Self.normalizedTelegramId(for: id)
                    var existing = mapped[norm] ?? []
                    let existingIds = Set(existing.map { $0.id })
                    for item in valid where !existingIds.contains(item.id) {
                        existing.append(item)
                    }
                    mapped[norm] = existing
                }
            }
        }
        self.lock.lock()
        self.serverUsersById = mapped
        // Clean up optimistic non-eco local entries that are now confirmed in serverUsersById
        for (peer, serverItems) in mapped {
            if var locals = self.localUsersById[peer] {
                let serverIds = Set(serverItems.map(\.id))
                locals.removeAll { !$0.id.hasPrefix("eco_") && serverIds.contains($0.id) }
                if locals.isEmpty {
                    self.localUsersById.removeValue(forKey: peer)
                } else {
                    self.localUsersById[peer] = locals
                }
            }
        }
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
    }

    public func gifts(forPeerId peerId: Int64) -> [FullGramGrantedNFT] {
        self.lock.lock()
        defer { self.lock.unlock() }
        var seen = Set<String>()
        var combined: [FullGramGrantedNFT] = []
        for key in Self.candidatePeerIds(for: peerId) {
            if let list = self.usersById[key] {
                for item in list where seen.insert(item.id).inserted {
                    combined.append(item)
                }
            }
        }
        return combined
    }

    public func appendLocal(peerId: Int64, nft: FullGramGrantedNFT) {
        let norm = Self.normalizedTelegramId(for: peerId)
        self.lock.lock()
        var list = self.localUsersById[norm] ?? []
        list.removeAll { $0.id == nft.id }
        list.insert(nft, at: 0)
        self.localUsersById[norm] = list
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public func removeLocal(peerId: Int64, entryId: String) {
        self.lock.lock()
        for key in Self.candidatePeerIds(for: peerId) {
            if var list = self.localUsersById[key] {
                list.removeAll { $0.id == entryId }
                if list.isEmpty {
                    self.localUsersById.removeValue(forKey: key)
                } else {
                    self.localUsersById[key] = list
                }
            }
            if var sList = self.serverUsersById[key] {
                sList.removeAll { $0.id == entryId }
                if sList.isEmpty {
                    self.serverUsersById.removeValue(forKey: key)
                } else {
                    self.serverUsersById[key] = sList
                }
            }
        }
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private static func matchesSlug(_ item: FullGramGrantedNFT, slug: String) -> Bool {
        if let gid = item.numericGiftId {
            if "FullGram-\(gid)-\(item.number)".caseInsensitiveCompare(slug) == .orderedSame {
                return true
            }
        }
        if item.id.hasPrefix("eco_") {
            let ecoId = String(item.id.dropFirst(4))
            if !ecoId.isEmpty && (slug.caseInsensitiveCompare(ecoId) == .orderedSame || slug.caseInsensitiveCompare("eco_\(ecoId)") == .orderedSame) {
                return true
            }
        }
        if "FullGram-\(item.giftId)-\(item.number)".caseInsensitiveCompare(slug) == .orderedSame {
            return true
        }
        return false
    }

    public func setHiddenLocal(peerId: Int64, slug: String, hidden: Bool) -> FullGramGrantedNFT? {
        var matched: FullGramGrantedNFT?
        self.lock.lock()
        for key in Self.candidatePeerIds(for: peerId) {
            if var list = self.localUsersById[key] {
                for idx in list.indices where Self.matchesSlug(list[idx], slug: slug) {
                    list[idx].hidden = hidden
                    if hidden { list[idx].pinned = false }
                    matched = list[idx]
                }
                self.localUsersById[key] = list
            }
            if var sList = self.serverUsersById[key] {
                for idx in sList.indices where Self.matchesSlug(sList[idx], slug: slug) {
                    sList[idx].hidden = hidden
                    if hidden { sList[idx].pinned = false }
                    matched = sList[idx]
                }
                self.serverUsersById[key] = sList
            }
        }
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        if let m = matched {
            if m.id.hasPrefix("eco_") {
                FullGramEconomy.shared.syncOwnedGiftStateFromProfile(ecoEntryId: String(m.id.dropFirst(4)), pinned: m.pinned, hidden: m.hidden)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
        return matched
    }

    public func setPinnedLocal(peerId: Int64, slug: String, pinned: Bool) -> FullGramGrantedNFT? {
        var matched: FullGramGrantedNFT?
        self.lock.lock()
        for key in Self.candidatePeerIds(for: peerId) {
            if var list = self.localUsersById[key] {
                for idx in list.indices where Self.matchesSlug(list[idx], slug: slug) {
                    list[idx].pinned = pinned
                    if pinned { list[idx].hidden = false }
                    matched = list[idx]
                }
                self.localUsersById[key] = list
            }
            if var sList = self.serverUsersById[key] {
                for idx in sList.indices where Self.matchesSlug(sList[idx], slug: slug) {
                    sList[idx].pinned = pinned
                    if pinned { sList[idx].hidden = false }
                    matched = sList[idx]
                }
                self.serverUsersById[key] = sList
            }
        }
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        if let m = matched {
            if m.id.hasPrefix("eco_") {
                FullGramEconomy.shared.syncOwnedGiftStateFromProfile(ecoEntryId: String(m.id.dropFirst(4)), pinned: m.pinned, hidden: m.hidden)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
        return matched
    }

    public func setPinnedSlugsLocal(peerId: Int64, pinnedSlugs: Set<String>) {
        let lowerPinned = Set(pinnedSlugs.map { $0.lowercased() })
        var changedIds: [(String, Bool, Bool)] = []
        self.lock.lock()
        for key in Self.candidatePeerIds(for: peerId) {
            if var list = self.localUsersById[key] {
                for idx in list.indices {
                    let gidStr = list[idx].numericGiftId.map(String.init) ?? list[idx].giftId
                    let s = "fullgram-\(gidStr)-\(list[idx].number)".lowercased()
                    let shouldPin = lowerPinned.contains(s)
                    if list[idx].pinned != shouldPin {
                        list[idx].pinned = shouldPin
                        if shouldPin { list[idx].hidden = false }
                        changedIds.append((list[idx].id, list[idx].pinned, list[idx].hidden))
                    }
                }
                self.localUsersById[key] = list
            }
            if var sList = self.serverUsersById[key] {
                for idx in sList.indices {
                    let gidStr = sList[idx].numericGiftId.map(String.init) ?? sList[idx].giftId
                    let s = "fullgram-\(gidStr)-\(sList[idx].number)".lowercased()
                    let shouldPin = lowerPinned.contains(s)
                    if sList[idx].pinned != shouldPin {
                        sList[idx].pinned = shouldPin
                        if shouldPin { sList[idx].hidden = false }
                        changedIds.append((sList[idx].id, sList[idx].pinned, sList[idx].hidden))
                    }
                }
                self.serverUsersById[key] = sList
            }
        }
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        for (entryId, p, h) in changedIds where entryId.hasPrefix("eco_") {
            FullGramEconomy.shared.syncOwnedGiftStateFromProfile(ecoEntryId: String(entryId.dropFirst(4)), pinned: p, hidden: h)
        }
        if !changedIds.isEmpty {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }

    public func removeBySlugLocal(peerId: Int64, slug: String) -> FullGramGrantedNFT? {
        var removed: FullGramGrantedNFT?
        self.lock.lock()
        for key in Self.candidatePeerIds(for: peerId) {
            if var list = self.localUsersById[key] {
                for item in list where Self.matchesSlug(item, slug: slug) {
                    removed = item
                    break
                }
                list.removeAll { Self.matchesSlug($0, slug: slug) }
                if list.isEmpty {
                    self.localUsersById.removeValue(forKey: key)
                } else {
                    self.localUsersById[key] = list
                }
            }
            if var sList = self.serverUsersById[key] {
                for item in sList where Self.matchesSlug(item, slug: slug) {
                    if removed == nil { removed = item }
                    break
                }
                sList.removeAll { Self.matchesSlug($0, slug: slug) }
                if sList.isEmpty {
                    self.serverUsersById.removeValue(forKey: key)
                } else {
                    self.serverUsersById[key] = sList
                }
            }
        }
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        if let rem = removed {
            if rem.id.hasPrefix("eco_") {
                FullGramEconomy.shared.removeOwnedGift(id: String(rem.id.dropFirst(4)), removeFromGrantedStore: false)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
        return removed
    }

    public func transferBySlugLocal(fromPeerId: Int64, toPeerId: Int64, slug: String) -> FullGramGrantedNFT? {
        let normTo = Self.normalizedTelegramId(for: toPeerId)
        self.lock.lock()
        var found: FullGramGrantedNFT?
        for key in Self.candidatePeerIds(for: fromPeerId) {
            if var list = self.localUsersById[key] {
                for item in list where Self.matchesSlug(item, slug: slug) {
                    if found == nil { found = item }
                    break
                }
                list.removeAll { Self.matchesSlug($0, slug: slug) }
                if list.isEmpty {
                    self.localUsersById.removeValue(forKey: key)
                } else {
                    self.localUsersById[key] = list
                }
            }
            if var sList = self.serverUsersById[key] {
                for item in sList where Self.matchesSlug(item, slug: slug) {
                    if found == nil { found = item }
                    break
                }
                sList.removeAll { Self.matchesSlug($0, slug: slug) }
                if sList.isEmpty {
                    self.serverUsersById.removeValue(forKey: key)
                } else {
                    self.serverUsersById[key] = sList
                }
            }
        }
        guard var transferred = found else {
            self.lock.unlock()
            return nil
        }
        transferred.pinned = true
        transferred.hidden = false
        var dstList = self.localUsersById[normTo] ?? []
        dstList.removeAll { $0.id == transferred.id }
        dstList.insert(transferred, at: 0)
        self.localUsersById[normTo] = dstList
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        if transferred.id.hasPrefix("eco_") {
            FullGramEconomy.shared.syncOwnedGiftOwnerFromProfile(
                ecoEntryId: String(transferred.id.dropFirst(4)),
                toPeerId: toPeerId
            )
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
        return transferred
    }

    public func updateBySlugLocal(
        peerId: Int64,
        slug: String,
        modelName: String,
        backdropName: String,
        backdropId: Int32?,
        patternName: String,
        number: Int32? = nil
    ) -> FullGramGrantedNFT? {
        var updated: FullGramGrantedNFT?
        self.lock.lock()
        for key in Self.candidatePeerIds(for: peerId) {
            if var list = self.localUsersById[key] {
                for idx in list.indices where Self.matchesSlug(list[idx], slug: slug) {
                    list[idx].modelName = modelName
                    list[idx].backdropName = backdropName
                    list[idx].backdropId = backdropId
                    list[idx].patternName = patternName
                    if let number, number >= 1 {
                        list[idx].number = number
                    }
                    updated = list[idx]
                }
                self.localUsersById[key] = list
            }
            if var sList = self.serverUsersById[key] {
                for idx in sList.indices where Self.matchesSlug(sList[idx], slug: slug) {
                    sList[idx].modelName = modelName
                    sList[idx].backdropName = backdropName
                    sList[idx].backdropId = backdropId
                    sList[idx].patternName = patternName
                    if let number, number >= 1 {
                        sList[idx].number = number
                    }
                    updated = sList[idx]
                }
                self.serverUsersById[key] = sList
            }
        }
        self.saveLocalItemsLocked()
        self.rebuildCombinedLocked()
        self.lock.unlock()
        if let u = updated {
            if u.id.hasPrefix("eco_") {
                FullGramEconomy.shared.syncOwnedGiftTraitsFromProfile(
                    ecoEntryId: String(u.id.dropFirst(4)),
                    modelName: modelName,
                    backdropName: backdropName,
                    patternName: patternName,
                    number: u.number
                )
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
        return updated
    }

    public func hasGifts(forPeerId peerId: Int64) -> Bool {
        return !self.gifts(forPeerId: peerId).isEmpty
    }

    public func findBySlug(_ slug: String) -> (peerId: Int64, nft: FullGramGrantedNFT)? {
        self.lock.lock()
        defer { self.lock.unlock() }
        for (peerId, list) in self.usersById {
            for item in list {
                guard let gid = item.numericGiftId else { continue }
                let expectedSlug = "FullGram-\(gid)-\(item.number)"
                if expectedSlug.caseInsensitiveCompare(slug) == .orderedSame {
                    return (peerId, item)
                }
            }
        }
        return nil
    }

    public func refreshIfNeeded(maxAge: TimeInterval = 45.0) {
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if Date().timeIntervalSince1970 - last < maxAge {
            return
        }
        self.refreshNow(completion: nil)
    }

    public func refreshNow(completion: (@Sendable (Bool) -> Void)? = nil) {
        guard let url = URL(string: Self.nftsURL) else {
            DispatchQueue.main.async { completion?(false) }
            return
        }
        self.lock.lock()
        if let completion {
            self.pendingCompletions.append(completion)
        }
        if self.isRefreshing {
            self.needsFollowUpRefresh = true
            self.lock.unlock()
            return
        }
        self.isRefreshing = true
        self.needsFollowUpRefresh = false
        self.lock.unlock()

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Self.session.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let finish: (Bool) -> Void = { ok in
                self.lock.lock()
                self.isRefreshing = false
                let shouldRetry = self.needsFollowUpRefresh
                self.needsFollowUpRefresh = false
                let completions = self.pendingCompletions
                self.pendingCompletions.removeAll()
                self.lock.unlock()
                DispatchQueue.main.async {
                    if ok {
                        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                    }
                    for cb in completions { cb(ok) }
                }
                if shouldRetry {
                    self.refreshNow(completion: nil)
                }
            }
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let data,
                  data.count <= 2_000_000,
                  let payload = try? JSONDecoder().decode(FullGramGrantedNFTsPayload.self, from: data) else {
                finish(false)
                return
            }

            try? data.write(to: self.cacheFileURL, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)
            self.applyPayload(payload)

            finish(true)
        }.resume()
    }
}

func fullGramBuildUniqueGift(
    item: FullGramGrantedNFT,
    ownerPeerId: EnginePeer.Id,
    attributes: [StarGift.UniqueGift.Attribute]
) -> StarGift.UniqueGift? {
    guard let giftId = item.numericGiftId else { return nil }

    let models = attributes.filter { if case .model = $0 { return true } else { return false } }
    let patterns = attributes.filter { if case .pattern = $0 { return true } else { return false } }
    let backdrops = attributes.filter { if case .backdrop = $0 { return true } else { return false } }

    let chosenModel: StarGift.UniqueGift.Attribute? = models.first(where: {
        if case let .model(name, _, _, _) = $0 {
            return !item.modelName.isEmpty && name.caseInsensitiveCompare(item.modelName) == .orderedSame
        }
        return false
    }) ?? models.first

    let chosenPattern: StarGift.UniqueGift.Attribute? = patterns.first(where: {
        if case let .pattern(name, _, _) = $0 {
            return !item.patternName.isEmpty && name.caseInsensitiveCompare(item.patternName) == .orderedSame
        }
        return false
    }) ?? patterns.first

    let chosenBackdrop: StarGift.UniqueGift.Attribute? = backdrops.first(where: {
        if case let .backdrop(name, id, _, _, _, _, _) = $0 {
            if let targetId = item.backdropId, id == targetId {
                return true
            }
            return !item.backdropName.isEmpty && name.caseInsensitiveCompare(item.backdropName) == .orderedSame
        }
        return false
    }) ?? backdrops.first

    guard let model = chosenModel, let pattern = chosenPattern, let backdrop = chosenBackdrop else {
        return nil
    }

    let slug = "FullGram-\(giftId)-\(item.number)"
    let uniqueId = giftId &+ Int64(item.number) &+ Int64(item.id.hashValue & 0xFFFF)
    return StarGift.UniqueGift(
        id: uniqueId,
        giftId: giftId,
        title: FullGramGrantedNFT.decoratedTitle(item.title),
        number: max(1, item.number),
        slug: slug,
        owner: .peerId(ownerPeerId),
        attributes: [model, pattern, backdrop],
        availability: StarGift.UniqueGift.Availability(issued: max(1, item.number), total: max(item.number, 10000)),
        giftAddress: nil,
        resellAmounts: nil,
        resellForTonOnly: false,
        releasedBy: nil,
        valueAmount: nil,
        valueCurrency: nil,
        valueUsdAmount: nil,
        flags: [],
        themePeerId: nil,
        peerColor: nil,
        hostPeerId: nil,
        minOfferStars: nil,
        craftChancePermille: nil
    )
}

func fullGramGrantedGiftsSignal(
    account: Account,
    peerId: EnginePeer.Id
) -> Signal<[ProfileGiftsContext.State.StarGift], NoError> {
    guard peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudChannel else {
        return .single([])
    }
    let rawId = peerId.id._internalGetInt64Value()
    FullGramGrantedNFTStore.shared.refreshIfNeeded()

    let changeTrigger = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let counter = Atomic<Int>(value: 0)
        let observer = NotificationCenter.default.addObserver(
            forName: FullGramGrantedNFTStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            subscriber.putNext(counter.modify { $0 + 1 })
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    return changeTrigger
    |> mapToSignal { _ -> Signal<[ProfileGiftsContext.State.StarGift], NoError> in
        let isOwnProfile = (peerId == account.peerId)
        let items = FullGramGrantedNFTStore.shared.gifts(forPeerId: rawId).filter { isOwnProfile || !$0.hidden }
        guard !items.isEmpty else {
            return .single([])
        }
        let giftIds = Array(Set(items.compactMap { $0.numericGiftId }))
        guard !giftIds.isEmpty else {
            return .single([])
        }
        let attrSignals: [Signal<(Int64, [StarGift.UniqueGift.Attribute]), NoError>] = giftIds.map { gid in
            return _internal_getStarGiftUpgradeAttributes(account: account, giftId: gid)
            |> take(1)
            |> map { attrs in
                return (gid, attrs ?? [])
            }
        }
        return combineLatest(attrSignals)
        |> map { pairs -> [ProfileGiftsContext.State.StarGift] in
            var byGiftId: [Int64: [StarGift.UniqueGift.Attribute]] = [:]
            for (gid, attrs) in pairs {
                byGiftId[gid] = attrs
            }
            var result: [ProfileGiftsContext.State.StarGift] = []
            for item in items {
                guard let gid = item.numericGiftId,
                      let attrs = byGiftId[gid],
                      !attrs.isEmpty,
                      let unique = fullGramBuildUniqueGift(item: item, ownerPeerId: peerId, attributes: attrs) else {
                    continue
                }
                let row = ProfileGiftsContext.State.StarGift(
                    gift: .unique(unique),
                    reference: .slug(slug: unique.slug),
                    fromPeer: nil,
                    date: item.grantedAt,
                    text: item.note.isEmpty ? nil : item.note,
                    entities: nil,
                    nameHidden: false,
                    savedToProfile: !item.hidden,
                    pinnedToTop: item.pinned,
                    convertStars: nil,
                    canUpgrade: isOwnProfile,
                    canExportDate: nil,
                    upgradeStars: isOwnProfile ? 0 : nil,
                    transferStars: isOwnProfile ? 0 : nil,
                    canTransferDate: isOwnProfile ? 0 : nil,
                    canResaleDate: nil,
                    collectionIds: nil,
                    prepaidUpgradeHash: nil,
                    upgradeSeparate: false,
                    dropOriginalDetailsStars: nil,
                    number: item.number,
                    isRefunded: false,
                    canCraftAt: nil
                )
                result.append(row)
            }
            return result
        }
    }
}

func fullGramResolveUniqueGift(
    account: Account,
    slug: String
) -> Signal<StarGift.UniqueGift, GetUniqueStarGiftError> {
    let matched = FullGramGrantedNFTStore.shared.findBySlug(slug)
    let resolvedItem: FullGramGrantedNFT
    let ownerPeerId: EnginePeer.Id
    if let matched {
        resolvedItem = matched.nft
        ownerPeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(matched.peerId))
    } else {
        // Fallback: parse "FullGram-<giftId>-<number>" directly
        let parts = slug.split(separator: "-")
        guard parts.count == 3,
              parts[0].caseInsensitiveCompare("FullGram") == .orderedSame,
              let gid = Int64(parts[1]), gid > 0,
              let num = Int32(parts[2]), num >= 1 else {
            return .fail(.invalidSlug)
        }
        resolvedItem = FullGramGrantedNFT(
            id: slug,
            giftId: String(gid),
            title: "NFT",
            modelName: "",
            backdropName: "",
            backdropId: nil,
            patternName: "",
            number: num
        )
        ownerPeerId = account.peerId
    }
    guard let gid = resolvedItem.numericGiftId else {
        return .fail(.invalidSlug)
    }
    return _internal_getStarGiftUpgradeAttributes(account: account, giftId: gid)
    |> take(1)
    |> castError(GetUniqueStarGiftError.self)
    |> mapToSignal { attrs -> Signal<StarGift.UniqueGift, GetUniqueStarGiftError> in
        guard let attrs, !attrs.isEmpty,
              let unique = fullGramBuildUniqueGift(item: resolvedItem, ownerPeerId: ownerPeerId, attributes: attrs) else {
            return .fail(.invalidSlug)
        }
        return .single(unique)
    }
}
