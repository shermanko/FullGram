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
            self.defaults.set(newValue, forKey: self.prefix + "whitelist")
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
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
        let full = self.prefix + key
        if self.defaults.object(forKey: full) == nil { return fallback }
        return self.defaults.bool(forKey: full)
    }

    private func setBool(_ key: String, _ value: Bool) {
        self.defaults.set(value, forKey: self.prefix + key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
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
        return self.whitelistDomains.contains { entry in
            lower == entry.lowercased() || lower.hasSuffix("." + entry.lowercased())
        }
    }

    public func inspectURL(_ rawUrl: String, forceCheck: Bool = false) -> FullGramAntiScamVerdict? {
        if !forceCheck {
            guard self.isEnabled && self.checkLinks else { return nil }
        }
        let trimmed = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) ?? URL(string: "https://" + trimmed),
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
        if !forceCheck && self.isWhitelisted(host: host) {
            return nil
        }

        var reasons: [String] = []
        var highRisk = false

        // 1. Userinfo (@) spoofing: https://t.me@evil.com
        if url.user != nil || (trimmed.contains("@") && (trimmed.components(separatedBy: "@").first?.contains("://") == true)) {
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
        let normalized = trimmed.lowercased().replacingOccurrences(of: "ё", with: "е")

        var score = 0
        var reasons: [String] = []

        for (phrase, reason, weight) in Self.highWeightPhrases {
            if normalized.contains(phrase) {
                score += weight
                reasons.append(reason)
            }
        }

        // Check embedded URLs inside message
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = trimmed as NSString
            let matches = detector.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                if let link = m.url?.absoluteString, let urlVerdict = self.inspectURL(link, forceCheck: true) {
                    score += (urlVerdict.severity == .high ? 3 : 2)
                    reasons.append(contentsOf: urlVerdict.reasons)
                } else if !matches.isEmpty && score >= 1 {
                    score += 1
                }
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

    // MARK: - Карточка 2: Анти-офер

    private static let offerKeywords: [String] = [
        "оффер", "офер", "offer", "предложение", "предлагаю", "сделка", "купить", "куплю",
        "продам", "продажа", "цена", "прайс", "обмен", "gift", "подарок", "fragment",
        "nft", "stars", "звезд", "ton", "usdt", "канал", "юзернейм", "username"
    ]

    public func inspectOffer(
        text: String,
        isForwarded: Bool,
        fromUnknownAuthor: Bool,
        viaBot: Bool,
        forceCheck: Bool = false
    ) -> FullGramAntiScamVerdict? {
        if !forceCheck {
            guard self.isEnabled && self.antiOfferEnabled else { return nil }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased().replacingOccurrences(of: "ё", with: "е")

        let looksLikeOffer = Self.offerKeywords.contains { normalized.contains($0) }
        var detectedLinks: [String] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = trimmed as NSString
            let matches = detector.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
            for m in matches {
                if let urlStr = m.url?.absoluteString {
                    detectedLinks.append(urlStr)
                }
            }
        }

        let hasDangerousUrl = detectedLinks.contains { self.inspectURL($0, forceCheck: true) != nil }
        guard looksLikeOffer || hasDangerousUrl else { return nil }

        var reasons: [String] = []
        if hasDangerousUrl || (!detectedLinks.isEmpty && looksLikeOffer) {
            let hasSuspiciousHost = detectedLinks.contains { link in
                guard let host = URL(string: link)?.host?.lowercased() else { return true }
                return !Self.officialTelegramDomains.contains(host) && !self.isWhitelisted(host: host)
            }
            if hasDangerousUrl || hasSuspiciousHost {
                reasons.append("подозрительная ссылка")
            }
        }
        if isForwarded {
            reasons.append(fromUnknownAuthor ? "пересланное сообщение от неизвестного" : "пересланное сообщение")
        }
        if viaBot {
            reasons.append("отправлено через бота")
        }

        guard !reasons.isEmpty else { return nil }
        return FullGramAntiScamVerdict(
            severity: (hasDangerousUrl || reasons.count >= 2) ? .high : .warning,
            host: nil,
            summary: "Возможен поддельный оффер",
            reasons: reasons
        )
    }

    // MARK: - Карточка 3: Анти-OTC

    public static let otcWarningText = "OTC — небезопасная сделка, гарант может оказаться скамом. Продолжай на свой страх и риск"

    private static let otcPatterns: [String] = [
        "\\botc\\b", "\\bотс\\b", "\\bescrow\\b", "гарант", "guarantor",
        "через гаранта", "гарант-бот", "гарант бот", "гарант-сервис",
        "безопасная сделка", "p2p сделк"
    ]

    public func inspectOTC(text: String, forceCheck: Bool = false) -> String? {
        if !forceCheck {
            guard self.isEnabled && self.antiOtcEnabled else { return nil }
        }
        let normalized = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        for pat in Self.otcPatterns {
            if normalized.range(of: pat, options: .regularExpression) != nil {
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
