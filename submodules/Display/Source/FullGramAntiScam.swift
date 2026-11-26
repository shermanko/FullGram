import Foundation

public enum FullGramAntiScamSeverity {
    case warning
    case high
}

public struct FullGramAntiScamVerdict {
    public let severity: FullGramAntiScamSeverity
    public let host: String?
    public let summary: String
    public let reasons: [String]
}

public final class FullGramAntiScam {
    public static let shared = FullGramAntiScam()
    public static let didChangeNotification = Notification.Name("FullGram.AntiScamChanged")

    private let defaults = UserDefaults.standard
    private let prefix = "fullgram.antiscam."
    private let whitelistLock = NSLock()
    private var cachedLowerWhitelist: [String]?
    private var boolCache: [String: Bool] = [:]

    private static let detectorLock = NSLock()
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let otcRegexes: [NSRegularExpression] = [
        "\\botc\\b", "\\bотс\\b", "\\bescrow\\b", "\\bguarantor\\b",
        "через\\s+гарант", "гарант[\\-\\s]бот", "гарант[\\-\\s]сервис",
        "гарант\\s+@", "сделка\\s+с\\s+гарант", "нужен\\s+гарант", "ищу\\s+гарант",
        "безопасная\\s+сделка", "p2p\\s+сделк"
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private init() {}

    public var isEnabled: Bool {
        get { self.bool("enabled", default: true) }
        set { self.setBool("enabled", newValue) }
    }

    public var checkLinks: Bool {
        get { self.bool("checkLinks", default: true) }
        set { self.setBool("checkLinks", newValue) }
    }

    public var warnShorteners: Bool {
        get { self.bool("warnShorteners", default: true) }
        set { self.setBool("warnShorteners", newValue) }
    }

    public var protectDangerFiles: Bool {
        get { self.bool("protectDangerFiles", default: true) }
        set { self.setBool("protectDangerFiles", newValue) }
    }

    public var markScamMessages: Bool {
        get { self.bool("markScamMessages", default: true) }
        set { self.setBool("markScamMessages", newValue) }
    }

    public var antiOfferEnabled: Bool {
        get { self.bool("antiOffer", default: true) }
        set { self.setBool("antiOffer", newValue) }
    }

    public var antiOtcEnabled: Bool {
        get { self.bool("antiOtc", default: true) }
        set { self.setBool("antiOtc", newValue) }
    }

    // MARK: - Moderation Rules (Templates, Links, New Accounts, Mass Joins)

    public struct RuleEvent: Codable, Equatable, Sendable {
        public let timestamp: Int32
        public let chatPeerId: Int64
        public let authorId: Int64
        public let ruleName: String
        public let detail: String
    }

    public var ruleBanByTemplates: Bool {
        get { self.bool("ruleBanByTemplates", default: false) }
        set { self.setBool("ruleBanByTemplates", newValue) }
    }

    public var ruleBanByLinks: Bool {
        get { self.bool("ruleBanByLinks", default: false) }
        set { self.setBool("ruleBanByLinks", newValue) }
    }

    public var ruleBanNewAccounts: Bool {
        get { self.bool("ruleBanNewAccounts", default: false) }
        set { self.setBool("ruleBanNewAccounts", newValue) }
    }

    public var ruleNewAccountRequireNoAvatar: Bool {
        get { self.bool("ruleNewAccountNoAvatar", default: false) }
        set { self.setBool("ruleNewAccountNoAvatar", newValue) }
    }

    public var ruleBanMassJoins: Bool {
        get { self.bool("ruleBanMassJoins", default: false) }
        set { self.setBool("ruleBanMassJoins", newValue) }
    }

    public var ruleAutoBanInAdminGroups: Bool {
        get { self.bool("ruleAutoBanInAdminGroups", default: false) }
        set { self.setBool("ruleAutoBanInAdminGroups", newValue) }
    }

    public var ruleNewAccountMinId: Int64 {
        get {
            let v = Int64(self.defaults.integer(forKey: self.prefix + "ruleNewAccountMinId"))
            return v > 0 ? v : 7_000_000_000
        }
        set {
            self.defaults.set(Int(max(100_000, newValue)), forKey: self.prefix + "ruleNewAccountMinId")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var ruleMassJoinLimit: Int {
        get {
            let v = self.defaults.integer(forKey: self.prefix + "ruleMassJoinLimit")
            return v >= 2 ? v : 5
        }
        set {
            self.defaults.set(max(2, newValue), forKey: self.prefix + "ruleMassJoinLimit")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var ruleMassJoinWindowSeconds: Int {
        get {
            let v = self.defaults.integer(forKey: self.prefix + "ruleMassJoinWindow")
            return v >= 5 ? v : 30
        }
        set {
            self.defaults.set(max(5, newValue), forKey: self.prefix + "ruleMassJoinWindow")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var ruleCustomTemplates: [String] {
        get {
            if let saved = self.defaults.stringArray(forKey: self.prefix + "ruleTemplates") {
                return saved
            }
            return ["крипто сигнал", "заработок в день", "бесплатные звёзды", "инвестиции без риска", "переходи в био"]
        }
        set {
            self.defaults.set(newValue, forKey: self.prefix + "ruleTemplates")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public func addCustomTemplate(_ template: String) {
        let clean = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var current = self.ruleCustomTemplates
        if !current.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            current.append(clean)
            self.ruleCustomTemplates = current
        }
    }

    public func removeCustomTemplate(_ template: String) {
        self.ruleCustomTemplates = self.ruleCustomTemplates.filter { $0 != template }
    }

    public var ruleEvents: [RuleEvent] {
        get {
            guard let data = self.defaults.data(forKey: self.prefix + "ruleEvents"),
                  let list = try? JSONDecoder().decode([RuleEvent].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue.prefix(60))) {
                self.defaults.set(data, forKey: self.prefix + "ruleEvents")
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }

    public func clearRuleEvents() {
        self.ruleEvents = []
    }

    private let raidLock = NSLock()
    private var joinTimestampsByChat: [Int64: [Int32]] = [:]
    private var recentRuleEventKeys: [String: TimeInterval] = [:]

    private func recordRuleEvent(chatPeerId: Int64, authorId: Int64, ruleName: String, detail: String) {
        let dedupKey = "\(chatPeerId):\(authorId):\(ruleName)"
        let now = Date().timeIntervalSince1970
        self.raidLock.lock()
        if let prev = self.recentRuleEventKeys[dedupKey], now - prev < 60.0 {
            self.raidLock.unlock()
            return
        }
        self.recentRuleEventKeys[dedupKey] = now
        self.raidLock.unlock()

        var list = self.ruleEvents
        list.insert(RuleEvent(timestamp: Int32(now), chatPeerId: chatPeerId, authorId: authorId, ruleName: ruleName, detail: detail), at: 0)
        self.ruleEvents = list
        self.recordDetection()
    }

    public func recordMemberJoin(chatPeerId: Int64, userId: Int64, timestamp: Int32) -> String? {
        guard self.isEnabled && self.ruleBanMassJoins else { return nil }
        let window = Int32(self.ruleMassJoinWindowSeconds)
        let limit = self.ruleMassJoinLimit
        let cutoff = timestamp - window

        self.raidLock.lock()
        var arr = self.joinTimestampsByChat[chatPeerId] ?? []
        arr.append(timestamp)
        arr = arr.filter { $0 >= cutoff }
        self.joinTimestampsByChat[chatPeerId] = arr
        let count = arr.count
        self.raidLock.unlock()

        if count >= limit {
            let reason = "Массовое вступление: \(count) входов за \(window) сек."
            self.recordRuleEvent(chatPeerId: chatPeerId, authorId: userId, ruleName: "Анти-рейд", detail: reason)
            return reason
        }
        return nil
    }

    public func inspectModerationRules(
        text: String,
        authorRawId: Int64,
        hasUsername: Bool,
        hasAvatar: Bool,
        chatPeerId: Int64,
        forceCheck: Bool = false
    ) -> (rule: String, reason: String)? {
        if !forceCheck {
            guard self.isEnabled else { return nil }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if self.ruleBanByTemplates, !trimmed.isEmpty {
            let normalized = Self.normalize(trimmed)
            for tpl in self.ruleCustomTemplates where !tpl.isEmpty {
                if tpl.hasPrefix("/"), tpl.hasSuffix("/"), tpl.count > 2 {
                    let pattern = String(tpl.dropFirst().dropLast())
                    if let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                       rx.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
                        let reason = "Совпадение с шаблоном \(tpl)"
                        self.recordRuleEvent(chatPeerId: chatPeerId, authorId: authorRawId, ruleName: "Шаблон", detail: reason)
                        return ("Бан по шаблону", reason)
                    }
                } else if normalized.contains(Self.normalize(tpl)) {
                    let reason = "Стоп-фраза: «\(tpl)»"
                    self.recordRuleEvent(chatPeerId: chatPeerId, authorId: authorRawId, ruleName: "Шаблон", detail: reason)
                    return ("Бан по шаблону", reason)
                }
            }
        }

        if self.ruleBanByLinks, !trimmed.isEmpty {
            let links = self.extractLinks(in: trimmed)
            let suspiciousLinks = links.filter { link in
                guard let url = URL(string: link), let host = url.host?.lowercased() else { return true }
                if self.isWhitelisted(host: host) { return false }
                if (host == "t.me" || host == "telegram.me") && link.contains("+") {
                    return true
                }
                return !Self.officialTelegramDomains.contains(host) || link.contains("joinchat")
            }
            if let first = suspiciousLinks.first {
                let reason = "Запрещённая ссылка: \(first)"
                self.recordRuleEvent(chatPeerId: chatPeerId, authorId: authorRawId, ruleName: "Ссылка", detail: reason)
                return ("Бан по ссылкам", reason)
            }
        }

        if self.ruleBanNewAccounts, authorRawId >= self.ruleNewAccountMinId {
            let suspiciousProfile = !self.ruleNewAccountRequireNoAvatar || !hasAvatar || !hasUsername
            if suspiciousProfile {
                let reason = "Новый аккаунт (ID \(authorRawId)\(hasAvatar ? "" : ", без фото"))"
                self.recordRuleEvent(chatPeerId: chatPeerId, authorId: authorRawId, ruleName: "Новый аккаунт", detail: reason)
                return ("Новый аккаунт", reason)
            }
        }

        return nil
    }

    public var blockedCount: Int {
        get { self.defaults.integer(forKey: self.prefix + "blockedCount") }
        set {
            self.defaults.set(newValue, forKey: self.prefix + "blockedCount")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var whitelistDomains: [String] {
        get {
            return self.defaults.stringArray(forKey: self.prefix + "whitelist") ?? []
        }
        set {
            self.whitelistLock.lock()
            self.cachedLowerWhitelist = newValue.map { $0.lowercased() }
            self.whitelistLock.unlock()
            self.defaults.set(newValue, forKey: self.prefix + "whitelist")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private func lowercasedWhitelist() -> [String] {
        self.whitelistLock.lock()
        defer { self.whitelistLock.unlock() }
        if let cached = self.cachedLowerWhitelist {
            return cached
        }
        let loaded = (self.defaults.stringArray(forKey: self.prefix + "whitelist") ?? []).map { $0.lowercased() }
        self.cachedLowerWhitelist = loaded
        return loaded
    }

    public func addWhitelistedDomain(_ host: String) {
        let normalized = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var current = self.whitelistDomains
        if !current.contains(normalized) {
            current.append(normalized)
            self.whitelistDomains = current
        }
    }

    public func removeWhitelistedDomain(_ host: String) {
        let normalized = host.lowercased()
        self.whitelistDomains = self.whitelistDomains.filter { $0.lowercased() != normalized }
    }

    public func clearWhitelist() {
        self.whitelistDomains = []
    }

    public func recordDetection() {
        self.blockedCount += 1
    }

    private func bool(_ key: String, default fallback: Bool) -> Bool {
        self.whitelistLock.lock()
        if let cached = self.boolCache[key] {
            self.whitelistLock.unlock()
            return cached
        }
        let full = self.prefix + key
        let resolved = (self.defaults.object(forKey: full) == nil) ? fallback : self.defaults.bool(forKey: full)
        self.boolCache[key] = resolved
        self.whitelistLock.unlock()
        return resolved
    }

    private func setBool(_ key: String, _ value: Bool) {
        self.whitelistLock.lock()
        self.boolCache[key] = value
        self.whitelistLock.unlock()
        self.defaults.set(value, forKey: self.prefix + key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    @inline(__always)
    private static func normalize(_ text: String) -> String {
        let lower = text.lowercased()
        return lower.contains("ё") ? lower.replacingOccurrences(of: "ё", with: "е") : lower
    }

    // MARK: - Domain & URL Inspection

    private static let officialTelegramDomains: Set<String> = [
        "t.me", "telegram.me", "telegram.org", "telegram.dog", "telegra.ph",
        "telesco.pe", "fragment.com", "ton.org", "contest.com", "translations.telegram.org",
        "bugs.telegram.org", "core.telegram.org", "desktop.telegram.org", "web.telegram.org"
    ]

    private static let shortenerDomains: Set<String> = [
        "bit.ly", "clck.ru", "tinyurl.com", "cutt.ly", "t.co", "goo.su",
        "is.gd", "v.gd", "rb.gy", "shorturl.at", "vk.cc", "cli.co", "qps.ru"
    ]

    private static let typosquatFragments: [String] = [
        "telegarm", "teiegram", "telegran", "telegam", "telegrm", "tellegram",
        "telergam", "tg-verify", "tg-support", "telegram-gift", "telegram-premium",
        "telegram-support", "telegram-verify", "fragment-gift", "fragment-claim",
        "ton-airdrop", "ton-claim", "tonkeeper-claim", "notcoin-claim", "wallet-verify"
    ]

    private static let phishingPathKeywords: [String] = [
        "verify", "login", "signin", "auth", "claim", "airdrop", "seed", "mnemonic",
        "wallet", "connect", "bonus", "gift", "premium", "support", "security", "restore", "unlock"
    ]

    private static let highRiskTlds: Set<String> = [
        "zip", "mov", "tk", "ml", "ga", "cf", "gq", "top", "click", "xyz", "rest", "cfd", "sbs", "icu", "buzz"
    ]

    public func isWhitelisted(host: String) -> Bool {
        let lower = host.lowercased()
        return self.lowercasedWhitelist().contains { entry in
            lower == entry || lower.hasSuffix("." + entry)
        }
    }

    public func inspectURL(_ rawUrl: String, forceCheck: Bool = false) -> FullGramAntiScamVerdict? {
        if !forceCheck {
            guard self.isEnabled && self.checkLinks else { return nil }
        }
        let trimmed = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let lowerFull = trimmed.lowercased()
        if (host == "t.me" || host == "telegram.me"),
           (lowerFull.contains("startapp=") || lowerFull.contains("start=")),
           let query = url.query?.lowercased(),
           (query.contains("drain") || query.contains("seed") || query.contains("mnemonic") || query.contains("airdrop") || query.contains("claim") || query.contains("verify")) {
            return FullGramAntiScamVerdict(
                severity: .warning,
                host: host,
                summary: "Подозрительный параметр запуска Mini App / бота в t.me",
                reasons: ["Ссылка t.me содержит параметры раздачи/верификации (\(query)); не вводите сид-фразы и коды входа"]
            )
        }
        if Self.officialTelegramDomains.contains(host) || Self.officialTelegramDomains.contains(where: { host.hasSuffix("." + $0) }) {
            return nil
        }
        if self.isWhitelisted(host: host) {
            return nil
        }

        var reasons: [String] = []
        var highRisk = false

        // 1. Userinfo (@) spoofing: https://t.me@evil.com (only in authority, not path/query like youtube.com/@channel)
        let authorityHasAt: Bool = {
            guard let schemeRange = trimmed.range(of: "://") else { return false }
            let afterScheme = trimmed[schemeRange.upperBound...]
            let authorityEnd = afterScheme.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? afterScheme.endIndex
            return afterScheme[..<authorityEnd].contains("@")
        }()
        if url.user != nil || authorityHasAt {
            reasons.append("Маскировка реального домена через символ «@»")
            highRisk = true
        }

        // 2. Punycode / IDN homograph domain (xn--)
        if host.contains("xn--") {
            reasons.append("Punycode-домен (xn--): возможна подмена похожих букв")
            highRisk = true
        }

        // 3. Raw IPv4 host
        if Self.isIPv4Host(host) {
            reasons.append("Ссылка ведёт напрямую на IP-адрес (\(host)) вместо домена")
            highRisk = true
        }

        // 4. Telegram / crypto typosquatting & brand impersonation
        for frag in Self.typosquatFragments where host.contains(frag) {
            reasons.append("Домен имитирует Telegram / криптосервис («\(frag)»)")
            highRisk = true
            break
        }
        if !highRisk && (host.contains("telegram") || host.contains("fragment") || host.hasPrefix("t-me")) {
            reasons.append("Сторонний домен использует название Telegram/Fragment")
            highRisk = true
        }

        // 5. High-risk TLD combined with phishing path keywords
        let tld = host.split(separator: ".").last.map(String.init) ?? ""
        let hasPhishingWord = Self.phishingPathKeywords.contains { lowerFull.contains($0) }
        if Self.highRiskTlds.contains(tld) && hasPhishingWord {
            reasons.append("Подозрительная доменная зона .\(tld) в связке с авторизацией/раздачей")
            highRisk = true
        }

        // 6. Unencrypted HTTP on login/wallet pages
        if scheme == "http" && hasPhishingWord {
            reasons.append("Незащищённое HTTP-соединение на странице входа или кошелька")
        }

        // 7. URL shorteners
        if (forceCheck || self.warnShorteners) && (Self.shortenerDomains.contains(host) || Self.shortenerDomains.contains(where: { host.hasSuffix("." + $0) })) {
            reasons.append("Сокращённая ссылка (\(host)) скрывает конечный адрес перехода")
        }

        guard !reasons.isEmpty else { return nil }
        return FullGramAntiScamVerdict(
            severity: highRisk ? .high : .warning,
            host: host,
            summary: highRisk ? "Обнаружены признаки фишинга или подмены домена" : "Потенциально небезопасная ссылка",
            reasons: reasons
        )
    }

    // MARK: - Dangerous File Inspection

    private static let dangerousExtensions: Set<String> = [
        "apk", "exe", "scr", "bat", "cmd", "vbs", "vbe", "js", "jse",
        "msi", "msp", "hta", "ps1", "lnk", "pif", "com", "reg", "jar"
    ]

    public func inspectFileName(_ fileName: String?, forceCheck: Bool = false) -> String? {
        if !forceCheck {
            guard self.isEnabled && self.protectDangerFiles else { return nil }
        }
        guard let rawName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else {
            return nil
        }
        let lower = rawName.lowercased()
        let parts = lower.split(separator: ".").map(String.init)
        guard parts.count >= 2, let ext = parts.last else { return nil }

        if Self.dangerousExtensions.contains(ext) {
            if parts.count >= 3 {
                return "Файл «\(rawName)» имеет двойное расширение с исполняемым типом .\(ext) — это частый приём маскировки вредоносных файлов."
            }
            return "Файл «\(rawName)» имеет исполняемое/скриптовое расширение .\(ext). Убедитесь, что доверяете отправителю."
        }
        return nil
    }

    // MARK: - Incoming Message Heuristic

    private static let highWeightPhrases: [(String, String, Int)] = [
        ("подтвердите аккаунт", "Запрос подтверждения аккаунта", 2),
        ("аккаунт будет заблокирован", "Запугивание блокировкой аккаунта", 3),
        ("ваш аккаунт заблокирован", "Ложное уведомление о блокировке", 3),
        ("telegram security", "Упоминание поддельной службы безопасности", 2),
        ("support telegram", "Упоминание фейковой поддержки", 2),
        ("код подтверждения", "Упоминание кода входа Telegram", 2),
        ("введите код", "Просьба ввести код", 2),
        ("seed phrase", "Запрос seed-фразы кошелька", 3),
        ("сид-фраз", "Запрос сид-фразы кошелька", 3),
        ("connect wallet", "Призыв подключить кошелёк", 2),
        ("подключите кошелек", "Призыв подключить кошелёк", 2),
        ("airdrop", "Упоминание крипто-airdrop", 1),
        ("раздача ton", "Обещание раздачи TON", 2),
        ("бесплатный telegram premium", "Обещание бесплатного Premium", 2),
        ("вы выиграли", "Уведомление о фейковом выигрыше", 2),
        ("заберите подарок", "Призыв забрать подарок по ссылке", 1),
        ("срочно перейдите", "Давление срочно перейти по ссылке", 2)
    ]

    public func inspectIncomingMessage(_ text: String, forceCheck: Bool = false) -> FullGramAntiScamVerdict? {
        if !forceCheck {
            guard self.isEnabled && self.markScamMessages else { return nil }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return nil }
        let normalized = Self.normalize(trimmed)

        var score = 0
        var reasons: [String] = []

        for (phrase, reason, weight) in Self.highWeightPhrases {
            if normalized.contains(phrase) {
                score += weight
                reasons.append(reason)
            }
        }

        let links = self.extractLinks(in: trimmed)
        for link in links {
            if let urlVerdict = self.inspectURL(link, forceCheck: true) {
                score += (urlVerdict.severity == .high ? 3 : 2)
                reasons.append(contentsOf: urlVerdict.reasons)
            } else if score >= 1 {
                score += 1
            }
        }

        guard score >= 3 else { return nil }
        return FullGramAntiScamVerdict(
            severity: score >= 4 ? .high : .warning,
            host: nil,
            summary: "В тексте обнаружены признаки скама или фишинга",
            reasons: Array(Set(reasons)).sorted()
        )
    }

    private func extractLinks(in text: String) -> [String] {
        guard (text.contains(".") || text.contains("://")),
              let detector = Self.linkDetector else {
            return []
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        Self.detectorLock.lock()
        let matches = detector.matches(in: text, range: range)
        Self.detectorLock.unlock()
        return matches.compactMap { $0.url?.absoluteString }
    }

    // MARK: - Карточка 2: Анти-офер (контекстно-смысловой анализатор)

    private static let offerAssetKeywords: [String] = [
        "nft", "нфт", "gift", "подарок", "подарк", "fragment", "фрагмент",
        "stars", "звезд", "ton", "тон", "usdt", "канал", "юзернейм", "username",
        "аккаунт", "акк", "скин", "токен", "крипт", "ваучер", "чек"
    ]

    private static let offerSentenceRegexes: [NSRegularExpression] = [
        "(?:предлагаю|сделаю|есть|готов\\s+(?:дать|сделать|купить|продать|обменять))\\s+(?:тебе\\s+|вам\\s+)?(?:выгодн\\w+\\s+)?(?:оф+ер|сделк|цену|обмен|выкуп)",
        "(?:куплю|продам|скупаю|выкуплю|обменяю|отдам)\\s+(?:срочно\\s+)?(?:твой|ваш|любой|редк\\w+|нфт|nft|подар|канал|акк|звезд|ton|usdt)",
        "(?:успей|торопись|только\\s+сегодня|ограниченн\\w+\\s+предложени|забери\\s+(?:свой\\s+)?(?:подарок|приз|бонус|выигрыш))",
        "(?:без\\s+предоплат|по\\s+предоплат|скинь\\s+первым|кидай\\s+первым|оплата\\s+(?:на\\s+карту|после|впер[е]?д)|чек\\s+(?:скину|в\\s+лс))",
        "(?:переходи\\s+(?:в\\s+)?бот|подтверди\\s+(?:сделку|в\\s+боте|кошелек)|подключи\\s+кошелек|авторизуй)",
        "(?:доход|заработок|профит)\\s+(?:от\\s+)?\\d+",
        "(?:пиши|обращайся|ответь)\\s+в\\s+(?:лс|личк|директ)",
        "(?:good\\s+offer|special\\s+offer|limited\\s+offer|want\\s+to\\s+(?:buy|sell|trade)|claim\\s+your\\s+(?:gift|reward|bonus)|send\\s+first)"
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let offerPriceRegex = try? NSRegularExpression(
        pattern: #"(?:\b\d[\d\s.,]{0,12}\s*(?:ton|usdt|stars?|зв[е]?зд\w*|руб\w*|₽|\$|€|rub|btc|eth|trx|sol)\b|(?:цена|прайс|бюджет|отдам\s+за|куплю\s+за|продам\s+за)\s*[:\-]?\s*\d)"#
    )

    private static let offerUrgencyOrPressureKeywords: [String] = [
        "предоплат", "гарант", "escrow", "срочно", "только сейчас", "только сегодня",
        "скинь первым", "кидай первым", "договор", "оформлю", "бронирую",
        "выкуп", "выгодн", "гарантир", "удво", "airdrop", "аирдроп", "claim"
    ]

    private static let offerContactDiversionRegex = try? NSRegularExpression(
        pattern: #"(?:@[a-z0-9_]{4,}|в\s+лс\b|в\s+личк|\bdm\s+me\b)"#
    )

    public func inspectOffer(
        text: String,
        isForwarded: Bool,
        fromUnknownAuthor: Bool,
        viaBot: Bool,
        isChannelPost: Bool = false,
        forceCheck: Bool = false
    ) -> FullGramAntiScamVerdict? {
        if !forceCheck {
            guard self.isEnabled && self.antiOfferEnabled && !isChannelPost else { return nil }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return nil }
        let normalized = Self.normalize(trimmed)
        let fullRange = NSRange(location: 0, length: (normalized as NSString).length)

        let detectedLinks = self.extractLinks(in: trimmed)
        let hasDangerousUrl = detectedLinks.contains { self.inspectURL($0, forceCheck: true) != nil }
        let hasExternalLink = detectedLinks.contains { link in
            guard let host = URL(string: link)?.host?.lowercased() else { return true }
            return !Self.officialTelegramDomains.contains(host) && !self.isWhitelisted(host: host)
        }

        let hasOfferSentence = Self.offerSentenceRegexes.contains { $0.firstMatch(in: normalized, range: fullRange) != nil }
        let matchedAssets = Self.offerAssetKeywords.filter { normalized.contains($0) }.count
        let hasAsset = matchedAssets > 0
        let hasPrice = Self.offerPriceRegex?.firstMatch(in: normalized, range: fullRange) != nil
        let hasPressure = Self.offerUrgencyOrPressureKeywords.contains { normalized.contains($0) }
        let hasDiversion = Self.offerContactDiversionRegex?.firstMatch(in: normalized, range: fullRange) != nil
        let mentionsOfferWord = normalized.contains("офер") || normalized.contains("оффер") || normalized.contains("offer") || normalized.contains("сделк")

        var score = 0
        var reasons: [String] = []

        if hasDangerousUrl {
            score += 4
            reasons.append("опасная/подозрительная ссылка")
        } else if hasExternalLink && (hasOfferSentence || hasAsset || hasPrice || mentionsOfferWord) {
            score += 2
            reasons.append("внешняя ссылка в коммерческом контексте")
        }

        if hasOfferSentence {
            score += 3
            reasons.append("формулировка коммерческого оффера")
        } else if mentionsOfferWord && (hasAsset || hasPrice || hasPressure || hasDiversion || isForwarded) {
            score += 2
            reasons.append("упоминание оффера/сделки")
        }

        if hasPrice {
            score += 1
            reasons.append("указана цена или сумма")
        }
        if hasAsset && (hasPrice || hasOfferSentence || hasPressure || hasDiversion || matchedAssets >= 2) {
            score += 1
            reasons.append("упоминание подарка/NFT/крипты/актива")
        }
        if hasPressure {
            score += 2
            reasons.append("признаки срочности или предоплаты")
        }
        if hasDiversion && (hasOfferSentence || hasAsset || hasPrice || hasPressure) {
            score += 1
            reasons.append("увод диалога в ЛС или к стороннему контакту")
        }
        if isForwarded && (score >= 2 || hasAsset || hasPrice) {
            score += 1
            reasons.append(fromUnknownAuthor ? "переслано от неизвестного источника" : "пересланное предложение")
        }
        // Не срабатываем просто из-за того, что сообщение от бота — бот лишь повышает риск при наличии реальных признаков сделки.
        if viaBot && score >= 3 {
            reasons.append("отправлено через бота")
        }

        let strongSignals = (hasDangerousUrl ? 1 : 0)
            + (hasOfferSentence ? 1 : 0)
            + (hasPrice ? 1 : 0)
            + (hasPressure ? 1 : 0)
            + (hasAsset ? 1 : 0)

        guard hasDangerousUrl || (score >= 3 && strongSignals >= 2) else {
            return nil
        }

        let summary = hasOfferSentence
            ? "Обнаружено предложение сделки / оффер в тексте"
            : "Возможен подозрительный оффер"
        return FullGramAntiScamVerdict(
            severity: (hasDangerousUrl || score >= 4) ? .high : .warning,
            host: nil,
            summary: summary,
            reasons: reasons
        )
    }

    // MARK: - Карточка 3: Анти-OTC

    public static let otcWarningText = "OTC — небезопасная сделка, гарант может оказаться скамом. Продолжай на свой страх и риск"

    public func inspectOTC(text: String, forceCheck: Bool = false) -> String? {
        if !forceCheck {
            guard self.isEnabled && self.antiOtcEnabled else { return nil }
        }
        let normalized = Self.normalize(text)
        let range = NSRange(location: 0, length: (normalized as NSString).length)
        for regex in Self.otcRegexes {
            if regex.firstMatch(in: normalized, range: range) != nil {
                return Self.otcWarningText
            }
        }
        return nil
    }

    public func inspectOTCUrl(_ rawUrl: String, forceCheck: Bool = false) -> String? {
        if !forceCheck {
            guard self.isEnabled && self.antiOtcEnabled else { return nil }
        }
        let lower = rawUrl.lowercased()
        let urlMarkers = ["otc", "garant", "guarantor", "escrow"]
        if urlMarkers.contains(where: { lower.contains($0) }) {
            return Self.otcWarningText
        }
        return nil
    }

    private static func isIPv4Host(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            if let num = Int(p), num >= 0, num <= 255 { return true }
            return false
        }
    }
}
