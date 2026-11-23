import Foundation

public struct FullGramEconomyTransaction: Codable, Equatable, Sendable {
    public enum Currency: String, Codable, Sendable {
        case gram
        case stars
    }

    public let id: String
    public let timestamp: Int32
    public let currency: Currency
    public let amount: Double
    public let isIncoming: Bool
    public let title: String
    public let subtitle: String

    public init(
        id: String = UUID().uuidString,
        timestamp: Int32 = Int32(Date().timeIntervalSince1970),
        currency: Currency,
        amount: Double,
        isIncoming: Bool,
        title: String,
        subtitle: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.currency = currency
        self.amount = amount
        self.isIncoming = isIncoming
        self.title = title
        self.subtitle = subtitle
    }
}

public struct FullGramCatalogGift: Codable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let emoji: String
    public let starsPrice: Int64
    public let canUpgradeToNFT: Bool
    public let upgradeStars: Int64
    public let collectionName: String
    public let suggestedRealGiftIds: [Int64]

    public init(
        key: String,
        title: String,
        emoji: String,
        starsPrice: Int64,
        canUpgradeToNFT: Bool,
        upgradeStars: Int64 = 25,
        collectionName: String? = nil,
        suggestedRealGiftIds: [Int64] = []
    ) {
        self.key = key
        self.title = title
        self.emoji = emoji
        self.starsPrice = starsPrice
        self.canUpgradeToNFT = canUpgradeToNFT
        self.upgradeStars = upgradeStars
        self.collectionName = collectionName ?? title
        self.suggestedRealGiftIds = suggestedRealGiftIds
    }
}

public struct FullGramOwnedGift: Codable, Equatable, Sendable {
    public let id: String
    public let ownerPeerId: Int64
    public let senderName: String
    public let recipientName: String
    public let giftKey: String
    public let realGiftId: Int64?
    public let emoji: String
    public let title: String
    public let priceStars: Int64
    public let upgradeStars: Int64
    public let canUpgradeToNFT: Bool
    public let comment: String
    public let purchasedAt: Int32

    public var isUpgraded: Bool
    public var nftNumber: Int32?
    public var modelName: String?
    public var modelRarityPermille: Int?
    public var backdropName: String?
    public var backdropInnerHex: UInt32?
    public var backdropOuterHex: UInt32?
    public var backdropRarityPermille: Int?
    public var patternName: String?
    public var patternRarityPermille: Int?
    public var pinnedToProfile: Bool

    public var slug: String {
        let num = self.nftNumber ?? 1
        if let gid = self.realGiftId {
            return "FullGram-\(gid)-\(num)"
        }
        return "FullGramGift-\(self.giftKey)-\(num)"
    }
}

public struct FullGramCollectibleNumber: Codable, Equatable, Sendable {
    public let id: String
    public let number: String
    public let priceTon: Double
    public let priceUsd: Double
    public let purchasedAt: Int32
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        number: String,
        priceTon: Double,
        priceUsd: Double,
        purchasedAt: Int32 = Int32(Date().timeIntervalSince1970),
        isActive: Bool = true
    ) {
        self.id = id
        self.number = number
        self.priceTon = priceTon
        self.priceUsd = priceUsd
        self.purchasedAt = purchasedAt
        self.isActive = isActive
    }
}

public struct FullGramCollectibleUsername: Codable, Equatable, Sendable {
    public let id: String
    public let username: String
    public let priceTon: Double
    public let priceUsd: Double
    public let purchasedAt: Int32
    public var isActive: Bool
    public var isPrimary: Bool

    public init(
        id: String = UUID().uuidString,
        username: String,
        priceTon: Double,
        priceUsd: Double,
        purchasedAt: Int32 = Int32(Date().timeIntervalSince1970),
        isActive: Bool = true,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.username = username
        self.priceTon = priceTon
        self.priceUsd = priceUsd
        self.purchasedAt = purchasedAt
        self.isActive = isActive
        self.isPrimary = isPrimary
    }
}

public struct FullGramChatGiftPayload: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case gift
        case nft
        case upgrade
        case stars
    }

    public let kind: Kind
    public let giftRecordId: String
    public let title: String
    public let emoji: String
    public let number: Int32?
    public let starsPrice: Int64
    public let modelName: String?
    public let backdropName: String?
    public let backdropInnerHex: UInt32?
    public let backdropOuterHex: UInt32?
    public let patternName: String?
    public let rarityText: String?
    public let comment: String
    public let canUpgrade: Bool
    public let senderName: String
    public let slug: String?

    public init(
        kind: Kind,
        giftRecordId: String,
        title: String,
        emoji: String,
        number: Int32? = nil,
        starsPrice: Int64 = 0,
        modelName: String? = nil,
        backdropName: String? = nil,
        backdropInnerHex: UInt32? = nil,
        backdropOuterHex: UInt32? = nil,
        patternName: String? = nil,
        rarityText: String? = nil,
        comment: String = "",
        canUpgrade: Bool = false,
        senderName: String = "",
        slug: String? = nil
    ) {
        self.kind = kind
        self.giftRecordId = giftRecordId
        self.title = title
        self.emoji = emoji
        self.number = number
        self.starsPrice = starsPrice
        self.modelName = modelName
        self.backdropName = backdropName
        self.backdropInnerHex = backdropInnerHex
        self.backdropOuterHex = backdropOuterHex
        self.patternName = patternName
        self.rarityText = rarityText
        self.comment = comment
        self.canUpgrade = canUpgrade
        self.senderName = senderName
        self.slug = slug
    }

    private static let markerPrefix = "\u{2063}FG_GIFT:"
    private static let markerSuffix = "\u{2063}"

    public func encodeMessageText() -> String {
        let header: String
        let displayTitle = FullGramGrantedNFT.decoratedTitle(self.title)
        switch self.kind {
        case .nft, .upgrade:
            let numStr = self.number.map { " #\($0)" } ?? ""
            header = "\(self.emoji) Подарок NFT: \(displayTitle)\(numStr)"
        case .gift:
            header = "\(self.emoji) Подарок: \(displayTitle) (\(self.starsPrice) ★)"
        case .stars:
            header = "⭐️ Подарок: \(self.starsPrice) Звёзд Telegram"
        }
        var lines: [String] = [header]
        if let model = self.modelName, !model.isEmpty {
            let bg = self.backdropName.map { " · Фон: \($0)" } ?? ""
            lines.append("Модель: \(model)\(bg)")
        }
        if !self.comment.isEmpty {
            lines.append("«\(self.comment)»")
        }
        if let data = try? JSONEncoder().encode(self) {
            let b64 = data.base64EncodedString()
            lines.append("\(Self.markerPrefix)\(b64)\(Self.markerSuffix)")
        }
        return lines.joined(separator: "\n")
    }

    public static func parse(from text: String) -> FullGramChatGiftPayload? {
        guard let startRange = text.range(of: Self.markerPrefix) else {
            return nil
        }
        let afterStart = text[startRange.upperBound...]
        let b64: String
        if let endRange = afterStart.range(of: Self.markerSuffix) {
            b64 = String(afterStart[..<endRange.lowerBound])
        } else {
            b64 = String(afterStart).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = Data(base64Encoded: b64) else {
            return nil
        }
        return try? JSONDecoder().decode(FullGramChatGiftPayload.self, from: data)
    }

    public static let openCardNotification = Notification.Name("FullGram.OpenChatGiftCard")
}

public final class FullGramEconomy: @unchecked Sendable {
    public static let shared = FullGramEconomy()
    public static let didChangeNotification = Notification.Name("FullGram.EconomyDidChange")
    public static let openGiftMarketNotification = Notification.Name("FullGram.OpenGiftMarketRequested")
    public static let approxTonUsdRate: Double = 5.40

    public struct BackdropPreset: Sendable {
        public let name: String
        public let innerHex: UInt32
        public let outerHex: UInt32
        public let rarityPermille: Int
    }

    public static let defaultBackdrops: [BackdropPreset] = [
        BackdropPreset(name: "Sapphire", innerHex: 0x3E7BF2, outerHex: 0x1A397A, rarityPermille: 15),
        BackdropPreset(name: "Cyber Violet", innerHex: 0x9C5BFF, outerHex: 0x3D1E73, rarityPermille: 12),
        BackdropPreset(name: "Emerald", innerHex: 0x38C97E, outerHex: 0x125433, rarityPermille: 20),
        BackdropPreset(name: "Crimson", innerHex: 0xE84B5A, outerHex: 0x6E1721, rarityPermille: 10),
        BackdropPreset(name: "Midnight Gold", innerHex: 0xF5B73B, outerHex: 0x6E4909, rarityPermille: 8),
        BackdropPreset(name: "Onyx", innerHex: 0x4B515B, outerHex: 0x1A1D22, rarityPermille: 5),
        BackdropPreset(name: "Aquamarine", innerHex: 0x3ED1C8, outerHex: 0x12575B, rarityPermille: 25),
        BackdropPreset(name: "Rose Quartz", innerHex: 0xF475B5, outerHex: 0x6B204A, rarityPermille: 18)
    ]

    public static let defaultModels: [(name: String, rarityPermille: Int)] = [
        ("Onyx", 5), ("24K Gold", 8), ("Cyberpunk", 10), ("Crystal", 12),
        ("Velvet", 15), ("Hologram", 10), ("Emerald Mint", 20), ("Classic", 35)
    ]

    public static let defaultPatterns: [(name: String, rarityPermille: Int)] = [
        ("Crown", 5), ("Diamond", 8), ("Lightning", 12), ("Starlight", 15),
        ("TON Gem", 10), ("Clover", 20), ("Moon", 25), ("Sparkle", 30)
    ]

    /// Real Telegram Stars gift catalog with authentic launch prices.
    public static let defaultCatalog: [FullGramCatalogGift] = [
        FullGramCatalogGift(key: "heart", title: "Сердце", emoji: "💝", starsPrice: 15, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "teddy_bear", title: "Плюшевый мишка", emoji: "🧸", starsPrice: 15, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "gift_box", title: "Подарочная коробка", emoji: "🎁", starsPrice: 25, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "rose", title: "Роза", emoji: "🌹", starsPrice: 25, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "lol_pop", title: "Lol Pop", emoji: "🍭", starsPrice: 25, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "delicious_cake", title: "Delicious Cake", emoji: "🎂", starsPrice: 50, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "bouquet", title: "Букет цветов", emoji: "💐", starsPrice: 50, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "rocket", title: "Ракета", emoji: "🚀", starsPrice: 50, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "champagne", title: "Шампанское", emoji: "🍾", starsPrice: 50, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "evil_eye", title: "Evil Eye", emoji: "🧿", starsPrice: 100, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "trophy", title: "Кубок", emoji: "🏆", starsPrice: 100, canUpgradeToNFT: false),
        FullGramCatalogGift(key: "diamond_ring", title: "Diamond Ring", emoji: "💎", starsPrice: 100, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "top_hat", title: "Top Hat", emoji: "🎩", starsPrice: 250, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "crystal_ball", title: "Crystal Ball", emoji: "🔮", starsPrice: 250, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "signet_ring", title: "Signet Ring", emoji: "💍", starsPrice: 500, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "swiss_watch", title: "Swiss Watch", emoji: "⌚️", starsPrice: 500, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "durovs_cap", title: "Durov's Cap", emoji: "🧢", starsPrice: 1000, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "plush_pepe", title: "Plush Pepe", emoji: "🐸", starsPrice: 2000, canUpgradeToNFT: true, upgradeStars: 25),
        FullGramCatalogGift(key: "astral_shard", title: "Astral Shard", emoji: "💠", starsPrice: 2500, canUpgradeToNFT: true, upgradeStars: 25)
    ]

    private struct State: Codable {
        var gramBalance: Double = 0.0
        var starsBalance: Int64 = 0
        var lastSyncedCloudGram: Double? = nil
        var lastSyncedCloudStars: Int64? = nil
        var transactions: [FullGramEconomyTransaction] = []
        var ownedGifts: [FullGramOwnedGift] = []
        var customNumbers: [FullGramCollectibleNumber] = []
        var customUsernames: [FullGramCollectibleUsername] = []
    }

    private let lock = NSLock()
    private let defaults = UserDefaults.standard
    private let stateKey = "fullgram.economy.state.v1"
    private var state: State

    private init() {
        if let data = defaults.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            self.state = decoded
        } else {
            self.state = State()
        }
    }

    private func saveLocked() {
        if let encoded = try? JSONEncoder().encode(self.state) {
            self.defaults.set(encoded, forKey: self.stateKey)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private func appendTxLocked(currency: FullGramEconomyTransaction.Currency, amount: Double, isIncoming: Bool, title: String, subtitle: String) {
        let tx = FullGramEconomyTransaction(
            currency: currency,
            amount: amount,
            isIncoming: isIncoming,
            title: title,
            subtitle: subtitle
        )
        self.state.transactions.insert(tx, at: 0)
        if self.state.transactions.count > 200 {
            self.state.transactions = Array(self.state.transactions.prefix(200))
        }
    }

    // MARK: - Wallet & Stars

    public var gramBalance: Double {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.gramBalance
    }

    public var starsBalance: Int64 {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.starsBalance
    }

    public var transactions: [FullGramEconomyTransaction] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.transactions
    }

    public func setGramBalance(_ rawAmount: Double, note: String = "Выдача баланса FullGram") {
        let clean = rawAmount.isFinite ? max(0.0, rawAmount) : 0.0
        self.lock.lock()
        let delta = clean - self.state.gramBalance
        self.state.gramBalance = clean
        if abs(delta) > 0.0001 {
            self.appendTxLocked(
                currency: .gram,
                amount: abs(delta),
                isIncoming: delta >= 0,
                title: note,
                subtitle: delta >= 0 ? "Зачисление на баланс" : "Корректировка баланса"
            )
        }
        self.saveLocked()
        self.lock.unlock()
    }

    public func setStarsBalance(_ rawAmount: Int64, note: String = "Выдача звёзд FullGram") {
        let clean = max(0, rawAmount)
        self.lock.lock()
        let delta = clean - self.state.starsBalance
        self.state.starsBalance = clean
        if delta != 0 {
            self.appendTxLocked(
                currency: .stars,
                amount: Double(abs(delta)),
                isIncoming: delta >= 0,
                title: note,
                subtitle: delta >= 0 ? "Пополнение баланса" : "Корректировка баланса"
            )
        }
        self.saveLocked()
        self.lock.unlock()
    }

    @discardableResult
    public func spendGram(_ amount: Double, title: String, subtitle: String) -> Bool {
        guard amount >= 0.0 else { return false }
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.state.gramBalance + 0.000001 >= amount else { return false }
        self.state.gramBalance = max(0.0, self.state.gramBalance - amount)
        self.appendTxLocked(currency: .gram, amount: amount, isIncoming: false, title: title, subtitle: subtitle)
        self.saveLocked()
        return true
    }

    @discardableResult
    public func spendStars(_ amount: Int64, title: String, subtitle: String) -> Bool {
        guard amount >= 0 else { return false }
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.state.starsBalance >= amount else { return false }
        self.state.starsBalance -= amount
        self.appendTxLocked(currency: .stars, amount: Double(amount), isIncoming: false, title: title, subtitle: subtitle)
        self.saveLocked()
        return true
    }

    @discardableResult
    public func giftStars(peerName: String, amount: Int64) -> Bool {
        guard amount > 0 else { return false }
        return self.spendStars(amount, title: "Подарок ★ \(peerName)", subtitle: "Отправлено \(amount) Звёзд Telegram")
    }

    // MARK: - Gifts & NFT Upgrades

    public var ownedGifts: [FullGramOwnedGift] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.ownedGifts
    }

    public func ownedGifts(forPeerId peerId: Int64) -> [FullGramOwnedGift] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.ownedGifts.filter { $0.ownerPeerId == peerId }
    }

    public func findOwnedGift(id: String) -> FullGramOwnedGift? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.ownedGifts.first { $0.id == id }
    }

    public func purchaseGift(
        catalogGift: FullGramCatalogGift,
        realGiftId: Int64?,
        forPeerId ownerPeerId: Int64,
        recipientName: String,
        senderName: String,
        comment: String,
        preUpgrade: Bool
    ) -> FullGramOwnedGift? {
        let totalCost = catalogGift.starsPrice + (preUpgrade && catalogGift.canUpgradeToNFT ? catalogGift.upgradeStars : 0)
        self.lock.lock()
        guard self.state.starsBalance >= totalCost else {
            self.lock.unlock()
            return nil
        }
        self.state.starsBalance -= totalCost
        self.appendTxLocked(
            currency: .stars,
            amount: Double(totalCost),
            isIncoming: false,
            title: "Подарок \(catalogGift.emoji) \(catalogGift.title)",
            subtitle: preUpgrade ? "Покупка + апгрейд до NFT для \(recipientName)" : "Покупка для \(recipientName)"
        )

        var gift = FullGramOwnedGift(
            id: UUID().uuidString,
            ownerPeerId: ownerPeerId,
            senderName: senderName,
            recipientName: recipientName,
            giftKey: catalogGift.key,
            realGiftId: realGiftId ?? catalogGift.suggestedRealGiftIds.first,
            emoji: catalogGift.emoji,
            title: catalogGift.title,
            priceStars: catalogGift.starsPrice,
            upgradeStars: catalogGift.upgradeStars,
            canUpgradeToNFT: catalogGift.canUpgradeToNFT,
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            purchasedAt: Int32(Date().timeIntervalSince1970),
            isUpgraded: false,
            nftNumber: nil,
            modelName: nil,
            modelRarityPermille: nil,
            backdropName: nil,
            backdropInnerHex: nil,
            backdropOuterHex: nil,
            backdropRarityPermille: nil,
            patternName: nil,
            patternRarityPermille: nil,
            pinnedToProfile: true
        )

        if preUpgrade && catalogGift.canUpgradeToNFT {
            Self.applyUpgradeTraits(to: &gift, model: nil, backdrop: nil, pattern: nil, number: nil)
        }
        self.state.ownedGifts.insert(gift, at: 0)
        self.saveLocked()
        self.lock.unlock()

        if gift.isUpgraded {
            Self.syncToGrantedNFTStore(gift)
        }
        return gift
    }

    public func upgradeGift(
        id: String,
        customModel: (String, Int)? = nil,
        customBackdrop: BackdropPreset? = nil,
        customPattern: (String, Int)? = nil,
        customNumber: Int32? = nil,
        chargeStars: Bool = true
    ) -> FullGramOwnedGift? {
        self.lock.lock()
        guard let idx = self.state.ownedGifts.firstIndex(where: { $0.id == id }) else {
            self.lock.unlock()
            return nil
        }
        var gift = self.state.ownedGifts[idx]
        if chargeStars && !gift.isUpgraded && gift.upgradeStars > 0 {
            guard self.state.starsBalance >= gift.upgradeStars else {
                self.lock.unlock()
                return nil
            }
            self.state.starsBalance -= gift.upgradeStars
            self.appendTxLocked(
                currency: .stars,
                amount: Double(gift.upgradeStars),
                isIncoming: false,
                title: "Апгрейд NFT: \(gift.emoji) \(gift.title)",
                subtitle: "Улучшение подарка в коллекционный NFT"
            )
        }
        Self.applyUpgradeTraits(to: &gift, model: customModel, backdrop: customBackdrop, pattern: customPattern, number: customNumber)
        self.state.ownedGifts[idx] = gift
        self.saveLocked()
        self.lock.unlock()

        Self.syncToGrantedNFTStore(gift)
        return gift
    }

    public func togglePinGift(id: String) {
        self.lock.lock()
        guard let idx = self.state.ownedGifts.firstIndex(where: { $0.id == id }) else {
            self.lock.unlock()
            return
        }
        self.state.ownedGifts[idx].pinnedToProfile.toggle()
        let updated = self.state.ownedGifts[idx]
        self.saveLocked()
        self.lock.unlock()

        if updated.isUpgraded {
            Self.syncToGrantedNFTStore(updated)
        }
    }

    private static func applyUpgradeTraits(
        to gift: inout FullGramOwnedGift,
        model: (String, Int)?,
        backdrop: BackdropPreset?,
        pattern: (String, Int)?,
        number: Int32?
    ) {
        let pickedModel = model ?? Self.defaultModels.randomElement() ?? ("Classic", 35)
        let pickedBackdrop = backdrop ?? Self.defaultBackdrops.randomElement() ?? BackdropPreset(name: "Sapphire", innerHex: 0x3E7BF2, outerHex: 0x1A397A, rarityPermille: 15)
        let pickedPattern = pattern ?? Self.defaultPatterns.randomElement() ?? ("Sparkle", 30)
        let pickedNumber = max(1, number ?? gift.nftNumber ?? Int32.random(in: 1 ... 9999))

        gift.isUpgraded = true
        gift.nftNumber = pickedNumber
        gift.modelName = pickedModel.0
        gift.modelRarityPermille = pickedModel.1
        gift.backdropName = pickedBackdrop.name
        gift.backdropInnerHex = pickedBackdrop.innerHex
        gift.backdropOuterHex = pickedBackdrop.outerHex
        gift.backdropRarityPermille = pickedBackdrop.rarityPermille
        gift.patternName = pickedPattern.0
        gift.patternRarityPermille = pickedPattern.1
    }

    public static func syncToGrantedNFTStore(_ gift: FullGramOwnedGift) {
        guard gift.isUpgraded, let gid = gift.realGiftId else { return }
        let nft = FullGramGrantedNFT(
            id: "eco_\(gift.id)",
            giftId: String(gid),
            title: FullGramGrantedNFT.decoratedTitle(gift.title),
            modelName: gift.modelName ?? "",
            backdropName: gift.backdropName ?? "",
            backdropId: nil,
            patternName: gift.patternName ?? "",
            number: gift.nftNumber ?? 1,
            note: gift.comment,
            pinned: gift.pinnedToProfile,
            grantedAt: gift.purchasedAt
        )
        FullGramGrantedNFTStore.shared.appendLocal(peerId: gift.ownerPeerId, nft: nft)
    }

    // MARK: - Collectible Anonymous Numbers (+888) & Usernames (Fragment)

    public var customNumbers: [FullGramCollectibleNumber] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.customNumbers
    }

    public var activeCustomNumber: FullGramCollectibleNumber? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.customNumbers.first { $0.isActive }
    }

    public var customUsernames: [FullGramCollectibleUsername] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.customUsernames
    }

    public var activeCustomUsernames: [FullGramCollectibleUsername] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.customUsernames.filter { $0.isActive }
    }

    public static func normalizeAnonymousNumber(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        var core = digits
        if core.hasPrefix("888") {
            core = String(core.dropFirst(3))
        }
        while core.count < 8 {
            core.append(contentsOf: String(Int.random(in: 0...9)))
        }
        if core.count > 8 {
            core = String(core.prefix(8))
        }
        let part1 = core.prefix(4)
        let part2 = core.dropFirst(4)
        return "+888 \(part1) \(part2)"
    }

    @discardableResult
    public func buyAnonymousNumber(rawNumber: String, priceTon: Double, deductFromBalance: Bool) -> FullGramCollectibleNumber? {
        let normalized = Self.normalizeAnonymousNumber(rawNumber)
        let cleanTon = max(0.0, priceTon)
        self.lock.lock()
        if deductFromBalance {
            guard self.state.gramBalance + 0.000001 >= cleanTon else {
                self.lock.unlock()
                return nil
            }
            self.state.gramBalance = max(0.0, self.state.gramBalance - cleanTon)
            self.appendTxLocked(
                currency: .gram,
                amount: cleanTon,
                isIncoming: false,
                title: "Покупка номера \(normalized)",
                subtitle: "Fragment Collectible Number"
            )
        }
        for i in self.state.customNumbers.indices {
            self.state.customNumbers[i].isActive = false
        }
        let item = FullGramCollectibleNumber(
            number: normalized,
            priceTon: cleanTon,
            priceUsd: (cleanTon * Self.approxTonUsdRate * 100.0).rounded() / 100.0,
            isActive: true
        )
        self.state.customNumbers.insert(item, at: 0)
        self.saveLocked()
        self.lock.unlock()
        return item
    }

    public func setActiveCustomNumber(id: String?) {
        self.lock.lock()
        for i in self.state.customNumbers.indices {
            self.state.customNumbers[i].isActive = (self.state.customNumbers[i].id == id)
        }
        self.saveLocked()
        self.lock.unlock()
    }

    public func removeCustomNumber(id: String) {
        self.lock.lock()
        self.state.customNumbers.removeAll { $0.id == id }
        self.saveLocked()
        self.lock.unlock()
    }

    public func findCollectibleNumber(_ raw: String) -> FullGramCollectibleNumber? {
        let targetDigits = raw.filter(\.isNumber)
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.state.customNumbers.first { $0.number.filter(\.isNumber) == targetDigits }
    }

    @discardableResult
    public func buyCollectibleUsername(rawUsername: String, priceTon: Double, isPrimary: Bool, deductFromBalance: Bool) -> FullGramCollectibleUsername? {
        let clean = rawUsername.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "@"))).lowercased()
        guard clean.count >= 4 else { return nil }
        let cleanTon = max(0.0, priceTon)
        self.lock.lock()
        if deductFromBalance {
            guard self.state.gramBalance + 0.000001 >= cleanTon else {
                self.lock.unlock()
                return nil
            }
            self.state.gramBalance = max(0.0, self.state.gramBalance - cleanTon)
            self.appendTxLocked(
                currency: .gram,
                amount: cleanTon,
                isIncoming: false,
                title: "Покупка @\(clean)",
                subtitle: "Fragment Collectible Username"
            )
        }
        if isPrimary {
            for i in self.state.customUsernames.indices {
                self.state.customUsernames[i].isPrimary = false
            }
        }
        self.state.customUsernames.removeAll { $0.username == clean }
        let item = FullGramCollectibleUsername(
            username: clean,
            priceTon: cleanTon,
            priceUsd: (cleanTon * Self.approxTonUsdRate * 100.0).rounded() / 100.0,
            isActive: true,
            isPrimary: isPrimary
        )
        self.state.customUsernames.insert(item, at: 0)
        self.saveLocked()
        self.lock.unlock()
        return item
    }

    public func setPrimaryCollectibleUsername(id: String) {
        self.lock.lock()
        for i in self.state.customUsernames.indices {
            let match = (self.state.customUsernames[i].id == id)
            self.state.customUsernames[i].isPrimary = match
            if match {
                self.state.customUsernames[i].isActive = true
            }
        }
        self.saveLocked()
        self.lock.unlock()
    }

    public func toggleCollectibleUsernameActive(id: String) {
        self.lock.lock()
        if let idx = self.state.customUsernames.firstIndex(where: { $0.id == id }) {
            self.state.customUsernames[idx].isActive.toggle()
            if !self.state.customUsernames[idx].isActive {
                self.state.customUsernames[idx].isPrimary = false
            }
        }
        self.saveLocked()
        self.lock.unlock()
    }

    public func removeCollectibleUsername(id: String) {
        self.lock.lock()
        self.state.customUsernames.removeAll { $0.id == id }
        self.saveLocked()
        self.lock.unlock()
    }

    public func findCollectibleUsername(_ raw: String) -> FullGramCollectibleUsername? {
        let clean = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "@"))).lowercased()
        self.lock.lock()
        defer { self.lock.unlock() }
        if let local = self.state.customUsernames.first(where: { $0.username == clean && $0.isActive }) {
            return local
        }
        for (_, user) in self.cloudUsers {
            if let match = user.usernames.first(where: { $0.username.lowercased() == clean && $0.isActive }) {
                return match
            }
        }
        return nil
    }

    public struct CloudEconomyUser: Codable, Equatable, Sendable {
        public var gramBalance: Double
        public var starsBalance: Int64
        public var usernames: [FullGramCollectibleUsername]
        public var numbers: [FullGramCollectibleNumber]

        public init(
            gramBalance: Double = 0,
            starsBalance: Int64 = 0,
            usernames: [FullGramCollectibleUsername] = [],
            numbers: [FullGramCollectibleNumber] = []
        ) {
            self.gramBalance = gramBalance
            self.starsBalance = starsBalance
            self.usernames = usernames
            self.numbers = numbers
        }
    }

    private struct CloudEconomyPayload: Codable {
        var version: Int?
        var users: [String: CloudEconomyUser]
    }

    private static let economyURL = "https://fullgram.korsakovx.workers.dev/economy.json"
    private static let lastEconomySyncKey = "fullgram.economy.lastSync"
    private var cloudUsers: [Int64: CloudEconomyUser] = [:]
    private var isRefreshingCloud = false

    public func activeCustomNumber(forPeerId peerId: Int64, isSelf: Bool) -> FullGramCollectibleNumber? {
        if isSelf, let local = self.activeCustomNumber {
            return local
        }
        let norm = FullGramGrantedNFTStore.normalizedTelegramId(for: peerId)
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.cloudUsers[norm]?.numbers.first(where: { $0.isActive })
    }

    public func activeCustomUsernames(forPeerId peerId: Int64, isSelf: Bool) -> [FullGramCollectibleUsername] {
        let norm = FullGramGrantedNFTStore.normalizedTelegramId(for: peerId)
        self.lock.lock()
        let cloud = self.cloudUsers[norm]?.usernames.filter { $0.isActive } ?? []
        let local = isSelf ? self.state.customUsernames.filter { $0.isActive } : []
        self.lock.unlock()
        var merged = local
        let existing = Set(local.map { $0.username.lowercased() })
        for item in cloud where !existing.contains(item.username.lowercased()) {
            merged.append(item)
        }
        return merged
    }

    public func refreshCloudIfNeeded(selfPeerId: Int64? = nil, maxAge: TimeInterval = 45.0) {
        let last = UserDefaults.standard.double(forKey: Self.lastEconomySyncKey)
        if Date().timeIntervalSince1970 - last < maxAge { return }
        self.refreshCloudNow(selfPeerId: selfPeerId)
    }

    public func refreshCloudNow(selfPeerId: Int64? = nil, completion: (@Sendable (Bool) -> Void)? = nil) {
        guard let url = URL(string: Self.economyURL) else {
            completion?(false)
            return
        }
        self.lock.lock()
        if self.isRefreshingCloud {
            self.lock.unlock()
            completion?(false)
            return
        }
        self.isRefreshingCloud = true
        self.lock.unlock()

        var req = URLRequest(url: url)
        req.timeoutInterval = 10.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.isRefreshingCloud = false
                self.lock.unlock()
            }
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  let data,
                  let payload = try? JSONDecoder().decode(CloudEconomyPayload.self, from: data) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            var mapped: [Int64: CloudEconomyUser] = [:]
            for (k, v) in payload.users {
                if let rawId = Int64(k) {
                    mapped[FullGramGrantedNFTStore.normalizedTelegramId(for: rawId)] = v
                }
            }
            self.lock.lock()
            self.cloudUsers = mapped
            if let selfPeerId {
                let norm = FullGramGrantedNFTStore.normalizedTelegramId(for: selfPeerId)
                if let me = mapped[norm] {
                    if me.gramBalance >= 0,
                       self.state.lastSyncedCloudGram == nil || abs((self.state.lastSyncedCloudGram ?? 0) - me.gramBalance) > 0.001 {
                        if me.gramBalance > 0 || self.state.lastSyncedCloudGram != nil {
                            self.state.gramBalance = me.gramBalance
                        }
                        self.state.lastSyncedCloudGram = me.gramBalance
                    }
                    if me.starsBalance >= 0,
                       self.state.lastSyncedCloudStars == nil || self.state.lastSyncedCloudStars != me.starsBalance {
                        if me.starsBalance > 0 || self.state.lastSyncedCloudStars != nil {
                            self.state.starsBalance = me.starsBalance
                        }
                        self.state.lastSyncedCloudStars = me.starsBalance
                    }
                    let existingNames = Set(self.state.customUsernames.map { $0.username.lowercased() })
                    for u in me.usernames where !existingNames.contains(u.username.lowercased()) {
                        self.state.customUsernames.append(u)
                    }
                    let existingNums = Set(self.state.customNumbers.map { $0.number })
                    for n in me.numbers where !existingNums.contains(n.number) {
                        self.state.customNumbers.append(n)
                    }
                    if let encoded = try? JSONEncoder().encode(self.state) {
                        self.defaults.set(encoded, forKey: self.stateKey)
                    }
                }
            }
            self.lock.unlock()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastEconomySyncKey)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                completion?(true)
            }
        }.resume()
    }
}
