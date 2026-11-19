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
    public var grantedAt: Int32

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
    private var usersById: [Int64: [FullGramGrantedNFT]] = [:]
    private var isRefreshing = false

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10.0
        cfg.timeoutIntervalForResource = 15.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private init() {
        self.loadDiskCache()
    }

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_nfts.json")
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
                    mapped[id] = valid
                }
            }
        }
        self.lock.lock()
        self.usersById = mapped
        self.lock.unlock()
    }

    public func gifts(forPeerId peerId: Int64) -> [FullGramGrantedNFT] {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let direct = self.usersById[peerId] {
            return direct
        }
        if peerId < 0, let positive = self.usersById[abs(peerId)] {
            return positive
        }
        return []
    }

    public func hasGifts(forPeerId peerId: Int64) -> Bool {
        return !self.gifts(forPeerId: peerId).isEmpty
    }

    public func refreshIfNeeded(maxAge: TimeInterval = 45.0) {
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if Date().timeIntervalSince1970 - last < maxAge {
            return
        }
        self.refreshNow(completion: nil)
    }

    public func refreshNow(completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: Self.nftsURL) else {
            DispatchQueue.main.async { completion?(false) }
            return
        }
        self.lock.lock()
        if self.isRefreshing {
            self.lock.unlock()
            return
        }
        self.isRefreshing = true
        self.lock.unlock()

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Self.session.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.isRefreshing = false
                self.lock.unlock()
            }
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let data,
                  data.count <= 2_000_000,
                  let payload = try? JSONDecoder().decode(FullGramGrantedNFTsPayload.self, from: data) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            try? data.write(to: self.cacheFileURL, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)
            self.applyPayload(payload)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                completion?(true)
            }
        }.resume()
    }
}

private func fullGramBuildUniqueGift(
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
        title: item.title.isEmpty ? "NFT" : item.title,
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
        let items = FullGramGrantedNFTStore.shared.gifts(forPeerId: rawId)
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
                    savedToProfile: true,
                    pinnedToTop: item.pinned,
                    convertStars: nil,
                    canUpgrade: false,
                    canExportDate: nil,
                    upgradeStars: nil,
                    transferStars: nil,
                    canTransferDate: nil,
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
