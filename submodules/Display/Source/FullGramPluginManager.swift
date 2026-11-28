import Foundation
import UIKit
import CryptoKit
import Darwin

public enum FullGramPluginNotifications {
    public static let pluginsDidChange = Notification.Name("FullGram.PluginsDidChange")
    public static let toastRequested = Notification.Name("FullGram.PluginToastRequested")
    public static let alertRequested = Notification.Name("FullGram.PluginAlertRequested")
    public static let runCommandInChatRequested = Notification.Name("FullGram.PluginRunCommandInChatRequested")
    public static let openUIRequested = Notification.Name("FullGram.PluginOpenUIRequested")
    public static let profileUpdateRequested = Notification.Name("FullGram.PluginProfileUpdateRequested")
    public static let sendMessageRequested = Notification.Name("FullGram.PluginSendMessageRequested")
    public static let setDraftRequested = Notification.Name("FullGram.PluginSetDraftRequested")
    public static let backgroundStateDidChange = Notification.Name("FullGram.PluginBackgroundStateDidChange")
}

public struct FullGramPluginAccountProfile: Codable, Equatable {
    public var peerId: Int64
    public var firstName: String
    public var lastName: String
    public var username: String
    public var bio: String
    public var phone: String
    public var originalFirstName: String
    public var originalLastName: String
    public var updatedAt: TimeInterval

    public var fullName: String {
        let f = self.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = self.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        if f.isEmpty { return l }
        if l.isEmpty { return f }
        return "\(f) \(l)"
    }

    public init(
        peerId: Int64 = 0,
        firstName: String = "",
        lastName: String = "",
        username: String = "",
        bio: String = "",
        phone: String = "",
        originalFirstName: String = "",
        originalLastName: String = "",
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.peerId = peerId
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.bio = bio
        self.phone = phone
        self.originalFirstName = originalFirstName
        self.originalLastName = originalLastName
        self.updatedAt = updatedAt
    }

    public func toPluginValue(includePhone: Bool = false) -> FullGramPluginValue {
        var dict: [String: FullGramPluginValue] = [
            "id": .int(self.peerId),
            "peer_id": .int(self.peerId),
            "first_name": .string(self.firstName),
            "last_name": .string(self.lastName),
            "full_name": .string(self.fullName),
            "name": .string(self.fullName),
            "username": .string(self.username),
            "bio": .string(self.bio),
            "original_first_name": .string(self.originalFirstName),
            "original_last_name": .string(self.originalLastName),
            "updated_at": .double(self.updatedAt)
        ]
        if includePhone {
            dict["phone"] = .string(self.phone)
        }
        return .table(FullGramPluginTableBox(dict: dict))
    }
}

public enum FullGramPluginTimeHelper {
    private static let boldDigits: [Character] = Array("𝟎𝟏𝟐𝟑𝟒𝟓𝟔𝟕𝟖𝟗")
    private static let monoDigits: [Character] = Array("𝟶𝟷𝟸𝟹𝟺𝟻𝟼𝟽𝟾𝟿")
    private static let doubleDigits: [Character] = Array("𝟘𝟙𝟚𝟛𝟜𝟝𝟞𝟟𝟠𝟡")
    private static let sansDigits: [Character] = Array("𝟢𝟣𝟤𝟥𝟦𝟧𝟨𝟩𝟪𝟫")
    private static let circledDigits: [Character] = Array("⓪①②③④⑤⑥⑦⑧⑨")
    private static let clockEmojis: [String] = [
        "🕛", "🕧", "🕐", "🕜", "🕑", "🕝", "🕒", "🕞",
        "🕓", "🕟", "🕔", "🕠", "🕕", "🕡", "🕖", "🕢",
        "🕗", "🕣", "🕘", "🕤", "🕙", "🕥", "🕚", "🕦"
    ]

    public static func stylizeDigits(_ text: String, style: String) -> String {
        let target: [Character]?
        switch style.lowercased() {
        case "bold", "serif_bold": target = Self.boldDigits
        case "mono", "monospace": target = Self.monoDigits
        case "double", "blackboard": target = Self.doubleDigits
        case "sans": target = Self.sansDigits
        case "circled", "fancy", "bubble": target = Self.circledDigits
        default: target = nil
        }
        guard let target else { return text }
        var out = ""
        out.reserveCapacity(text.count * 2)
        for ch in text {
            if let ascii = ch.asciiValue, ascii >= 48, ascii <= 57 {
                out.append(target[Int(ascii - 48)])
            } else {
                out.append(ch)
            }
        }
        return out
    }

    public static func clockEmoji(hour: Int, minute: Int) -> String {
        let h12 = hour % 12
        let half = minute >= 30 ? 1 : 0
        let idx = (h12 * 2 + half) % Self.clockEmojis.count
        return Self.clockEmojis[idx]
    }

    public static func buildPhoneTimeDict(date: Date = Date()) -> [String: FullGramPluginValue] {
        let cal = Calendar.current
        let tz = TimeZone.current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        let rawWday = comps.weekday ?? 1 // 1 = Sunday
        let isoWday = rawWday == 1 ? 7 : (rawWday - 1) // 1 = Mon .. 7 = Sun

        let hm = String(format: "%02d:%02d", hour, minute)
        let hms = String(format: "%02d:%02d:%02d", hour, minute, second)
        let dateStr = String(format: "%02d.%02d.%04d", day, month, year)
        let formatted = "\(dateStr) \(hms)"

        let (weekdayName, weekdayShort, monthName, iso) = Self.formatCalendarLabels(date: date, tz: tz)

        let offsetSec = tz.secondsFromGMT(for: date)
        let sign = offsetSec >= 0 ? "+" : "-"
        let absOff = abs(offsetSec)
        let offsetStr = String(format: "%@%02d:%02d", sign, absOff / 3600, (absOff % 3600) / 60)

        let jFmt = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? "HH"
        let is24h = !jFmt.contains("a")

        let ts = date.timeIntervalSince1970
        let safeTs = ts.isFinite ? max(-62_135_596_800.0, min(253_402_300_799.0, ts)) : 0.0
        return [
            "timestamp": .double(safeTs),
            "unix": .int(Int64(safeTs)),
            "unix_ms": .int(Int64((safeTs * 1000.0).rounded())),
            "hm": .string(hm),
            "hms": .string(hms),
            "formatted": .string(formatted),
            "date": .string(dateStr),
            "iso": .string(iso),
            "year": .int(Int64(year)),
            "month": .int(Int64(month)),
            "day": .int(Int64(day)),
            "hour": .int(Int64(hour)),
            "minute": .int(Int64(minute)),
            "second": .int(Int64(second)),
            "weekday": .int(Int64(isoWday)),
            "weekday_name": .string(weekdayName),
            "weekday_short": .string(weekdayShort),
            "month_name": .string(monthName),
            "timezone": .string(tz.identifier),
            "timezone_abbr": .string(tz.abbreviation(for: date) ?? ""),
            "utc_offset": .int(Int64(offsetSec)),
            "utc_offset_str": .string(offsetStr),
            "is_24h": .bool(is24h),
            "bold_hm": .string(Self.stylizeDigits(hm, style: "bold")),
            "mono_hm": .string(Self.stylizeDigits(hm, style: "mono")),
            "double_hm": .string(Self.stylizeDigits(hm, style: "double")),
            "fancy_hm": .string(Self.stylizeDigits(hm, style: "circled")),
            "clock_emoji": .string(Self.clockEmoji(hour: hour, minute: minute))
        ]
    }

    private static let formatterLock = NSLock()
    private static let ruLocale = Locale(identifier: "ru_RU")
    private static let weekdayNameFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = ruLocale
        df.dateFormat = "EEEE"
        return df
    }()
    private static let weekdayShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = ruLocale
        df.dateFormat = "EEE"
        return df
    }()
    private static let monthNameFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = ruLocale
        df.dateFormat = "MMMM"
        return df
    }()
    private static let isoFormatter = ISO8601DateFormatter()
    private static let customTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.timeZone = TimeZone.current
        return df
    }()

    private static func formatCalendarLabels(date: Date, tz: TimeZone) -> (String, String, String, String) {
        self.formatterLock.lock()
        defer { self.formatterLock.unlock() }
        self.weekdayNameFormatter.timeZone = tz
        self.weekdayShortFormatter.timeZone = tz
        self.monthNameFormatter.timeZone = tz
        return (
            self.weekdayNameFormatter.string(from: date).capitalized,
            self.weekdayShortFormatter.string(from: date).capitalized,
            self.monthNameFormatter.string(from: date).capitalized,
            self.isoFormatter.string(from: date)
        )
    }

    public static func formatTime(format: String?, timestamp: Double?, style: String?) -> String {
        let date = timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date()
        self.formatterLock.lock()
        self.customTimeFormatter.locale = Locale.current
        self.customTimeFormatter.timeZone = TimeZone.current
        self.customTimeFormatter.dateFormat = (format?.isEmpty == false) ? format! : "dd.MM.yyyy HH:mm:ss"
        let rendered = self.customTimeFormatter.string(from: date)
        self.formatterLock.unlock()
        if let style, !style.isEmpty {
            return Self.stylizeDigits(rendered, style: style)
        }
        return rendered
    }
}

public struct FullGramRemotePluginItem: Codable, Equatable {
    public let id: String
    public let name: String
    public let language: FullGramPluginLanguage
    public let version: String
    public let author: String
    public let description: String
    public let url: String?
    public let code: String?
}

public struct FullGramRemoteCatalog: Codable {
    public let version: Int?
    public let plugins: [FullGramRemotePluginItem]
}

private final class FullGramLoadedPlugin: @unchecked Sendable {
    let descriptor: FullGramPluginDescriptor
    var luaVM: FullGramLuaVM?
    var pythonVM: FullGramPythonVM?
    var rustVM: FullGramRustVM?
    var registeredCommands: [String: ([FullGramPluginValue]) throws -> FullGramPluginValue] = [:]
    var eventListeners: [String: [([FullGramPluginValue]) throws -> FullGramPluginValue]] = [:]
    var lastError: String?

    var hasOutgoingHook: Bool = false
    var hasRenderHook: Bool = false
    var hasCommandHook: Bool = false
    var hasMessageActionHook: Bool = false
    var hasBackgroundHook: Bool = false
    var backgroundHookName: String?
    var hasAppStateHook: Bool = false
    var hasIncomingHook: Bool = false
    var hasLoadHook: Bool = false
    var hasUnloadHook: Bool = false

    init(descriptor: FullGramPluginDescriptor) {
        self.descriptor = descriptor
    }
}

public final class FullGramPluginManager: @unchecked Sendable {
    public static let shared = FullGramPluginManager()
    public static let officialCatalogURL = "https://fullgram.korsakovx.workers.dev/plugins.json"

    private struct DeviceSnapshot {
        var model: String = "iPhone"
        var systemName: String = "iOS"
        var systemVersion: String = ""
        var batteryLevel: Int = -1
        var batteryState: String = "unknown"
        var isCharging: Bool = false
        var appState: String = "foreground"
        var isBackground: Bool = false
    }

    private let lock = NSRecursiveLock()
    private let systemEnabledKey = "fullgram.plugins.systemEnabled"
    private let backgroundEnabledKey = "fullgram.plugins.backgroundEnabled"
    private let catalogURLKey = "fullgram.plugins.catalogURL"
    private let cachedProfileKey = "fullgram.plugins.cachedProfile"
    private let originalNickKey = "fullgram.plugins.originalNickname"
    private static let layoutFixerModeKey = "fullgram.plugin.store.fg_layout_fixer.mode"

    // Nick Clock keys shared with fg_nick_clock plugin storage
    private static let nickClockPrefix = "fullgram.plugin.store.fg_nick_clock."

    public var layoutFixerMode: String {
        get {
            let val = UserDefaults.standard.string(forKey: Self.layoutFixerModeKey) ?? "ru2en"
            return (val == "en2ru" || val == "auto") ? val : "ru2en"
        }
        set {
            let normalized = (newValue == "en2ru" || newValue == "auto") ? newValue : "ru2en"
            UserDefaults.standard.set(normalized, forKey: Self.layoutFixerModeKey)
            self.postPluginsDidChange()
        }
    }

    public var layoutFixerModeTitle: String {
        switch self.layoutFixerMode {
        case "en2ru":
            return "Англ → Рус"
        case "auto":
            return "Авто (Рус ↔ Англ)"
        default:
            return "Рус → Англ"
        }
    }

    private final class FullGramNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private struct ReloadPlan {
        let generation: UInt64
        let systemEnabled: Bool
        let toCompile: [FullGramPluginDescriptor]
        let oldUnloadPlugins: [FullGramLoadedPlugin]
    }

    private static let noRedirectDelegate = FullGramNoRedirectDelegate()
    private static let pluginHTTPSession: URLSession = {
        return URLSession(configuration: .ephemeral, delegate: noRedirectDelegate, delegateQueue: nil)
    }()

    private var descriptors: [FullGramPluginDescriptor] = []
    private var loaded: [String: FullGramLoadedPlugin] = [:]
    private var cachedOrderedPlugins: [FullGramLoadedPlugin] = []
    private var cachedRenderPlugins: [FullGramLoadedPlugin] = []
    private var logsByPlugin: [String: [String]] = [:]
    private var cachedSystemEnabled: Bool?
    private var cachedBackgroundEnabled: Bool?
    private var hasRenderHooks: Bool = false
    private var didInitialize = false
    private var renderHookDepth = 0
    private var reloadGeneration: UInt64 = 0

    // Background execution engine
    private let backgroundQueue = DispatchQueue(label: "com.fullgram.plugins.background", qos: .utility)
    private var backgroundTimer: DispatchSourceTimer?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var didRegisterLifecycleObservers = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var backgroundTickCount: Int64 = 0
    private var lastTickByPlugin: [String: TimeInterval] = [:]
    private var tickCountByPlugin: [String: Int64] = [:]
    private var runtimeIntervalsByPlugin: [String: Int] = [:]
    private var deviceSnapshot = DeviceSnapshot()

    // Account profile cache & Telegram bridge
    private var cachedProfile = FullGramPluginAccountProfile()
    private var lastAppliedFirstName: String?
    private var lastAppliedLastName: String?
    private var lastAppliedBio: String?
    private var lastNicknameRequestTime: TimeInterval = 0
    private var pendingNicknameUpdate: (firstName: String, lastName: String)?
    private var pendingNicknameWorkItem: DispatchWorkItem?
    private let minNicknameUpdateInterval: TimeInterval = 15.0

    private var bridgeUpdateName: ((String, String, ((Bool) -> Void)?) -> Void)?
    private var bridgeUpdateUsername: ((String, ((Bool) -> Void)?) -> Void)?
    private var bridgeUpdateBio: ((String, ((Bool) -> Void)?) -> Void)?
    private var bridgeSendMessage: ((Int64?, String) -> Bool)?
    private var bridgeSetDraft: ((Int64?, String) -> Bool)?
    private var bridgeActiveChatInfo: (() -> [String: FullGramPluginValue]?)?

    private static let logDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
    private static let commandHintRegex = try? NSRegularExpression(pattern: #"(?:command|cmd)\s*==\s*["']([a-zA-Z0-9_-]+)["']"#)
    private static let plugSubcommandRegex = try? NSRegularExpression(pattern: #"subcommand\s*==\s*["']([a-zA-Z0-9_-]+)["']"#)
    private let vmLock = NSRecursiveLock()

    public var catalogURL: String {
        get {
            let stored = UserDefaults.standard.string(forKey: self.catalogURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? Self.officialCatalogURL : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: self.catalogURLKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: self.catalogURLKey)
            }
        }
    }

    private init() {
        self.loadCachedProfileFromDisk()
    }

    public var isSystemEnabled: Bool {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            if let cached = self.cachedSystemEnabled {
                return cached
            }
            let resolved: Bool
            if UserDefaults.standard.object(forKey: self.systemEnabledKey) == nil {
                resolved = true
            } else {
                resolved = UserDefaults.standard.bool(forKey: self.systemEnabledKey)
            }
            self.cachedSystemEnabled = resolved
            return resolved
        }
        set {
            self.lock.lock()
            self.cachedSystemEnabled = newValue
            self.lock.unlock()
            UserDefaults.standard.set(newValue, forKey: self.systemEnabledKey)
            self.reloadRuntime()
            self.postPluginsDidChange()
        }
    }

    public var isBackgroundExecutionEnabled: Bool {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            if let cached = self.cachedBackgroundEnabled {
                return cached
            }
            let resolved: Bool
            if UserDefaults.standard.object(forKey: self.backgroundEnabledKey) == nil {
                resolved = true
            } else {
                resolved = UserDefaults.standard.bool(forKey: self.backgroundEnabledKey)
            }
            self.cachedBackgroundEnabled = resolved
            return resolved
        }
        set {
            self.lock.lock()
            self.cachedBackgroundEnabled = newValue
            self.lock.unlock()
            UserDefaults.standard.set(newValue, forKey: self.backgroundEnabledKey)
            self.lock.lock()
            self.syncBackgroundSchedulerLocked()
            self.lock.unlock()
            self.postPluginsDidChange()
            self.postBackgroundStateChanged()
        }
    }

    // MARK: - Nick & Clock Shared Settings

    public var nickClockEnabled: Bool {
        get { return Self.readPluginStoreBool(prefix: Self.nickClockPrefix, key: "clock_enabled", default: false) }
        set {
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "clock_enabled", value: newValue)
            if newValue {
                if self.plugin(id: "fg_nick_clock")?.isEnabled == false {
                    self.setPluginEnabled(id: "fg_nick_clock", enabled: true)
                }
                self.captureOriginalNicknameIfNeeded()
                _ = self.applyLiveNicknameClockNow()
            } else {
                _ = self.restoreOriginalNickname(pluginId: "fg_nick_clock")
            }
            self.lock.lock()
            self.syncBackgroundSchedulerLocked()
            self.lock.unlock()
            self.postPluginsDidChange()
        }
    }

    public var nickClockTemplate: String {
        get {
            let val = Self.readPluginStoreString(prefix: Self.nickClockPrefix, key: "clock_template") ?? ""
            return val.isEmpty ? "{name} | ⌚ {time}" : val
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "clock_template", value: clean.isEmpty ? "{name} | ⌚ {time}" : clean)
            if self.nickClockEnabled {
                _ = self.applyLiveNicknameClockNow(force: true)
            }
            self.postPluginsDidChange()
        }
    }

    public var nickClockStyle: String {
        get {
            let val = Self.readPluginStoreString(prefix: Self.nickClockPrefix, key: "clock_style") ?? "bold"
            return val.isEmpty ? "bold" : val
        }
        set {
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "clock_style", value: newValue)
            if self.nickClockEnabled {
                _ = self.applyLiveNicknameClockNow(force: true)
            }
            self.postPluginsDidChange()
        }
    }

    public var nickClockBaseFirstName: String {
        get {
            let stored = Self.readPluginStoreString(prefix: Self.nickClockPrefix, key: "base_first_name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stored.isEmpty { return stored }
            let prof = self.currentProfile()
            return prof.originalFirstName.isEmpty ? prof.firstName : prof.originalFirstName
        }
        set {
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "base_first_name", value: newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            if self.nickClockEnabled {
                _ = self.applyLiveNicknameClockNow(force: true)
            }
        }
    }

    public var nickClockBaseLastName: String {
        get {
            if let stored = Self.readPluginStoreString(prefix: Self.nickClockPrefix, key: "base_last_name") {
                return stored
            }
            let prof = self.currentProfile()
            return prof.originalLastName.isEmpty ? prof.lastName : prof.originalLastName
        }
        set {
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "base_last_name", value: newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            if self.nickClockEnabled {
                _ = self.applyLiveNicknameClockNow(force: true)
            }
        }
    }

    public var nickClockInterval: Int {
        get {
            let raw = Self.readPluginStoreInt(prefix: Self.nickClockPrefix, key: "clock_interval", default: 30)
            return min(3600, max(10, raw))
        }
        set {
            let clamped = min(3600, max(10, newValue))
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "clock_interval", value: clamped)
            self.setPluginBackground(id: "fg_nick_clock", enabled: true, interval: clamped)
        }
    }

    public var nickClockUpdateBio: Bool {
        get { return Self.readPluginStoreBool(prefix: Self.nickClockPrefix, key: "bio_enabled", default: false) }
        set {
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "bio_enabled", value: newValue)
            if newValue {
                _ = self.applyLiveBioClockNow()
            }
            self.postPluginsDidChange()
        }
    }

    public var nickClockBioTemplate: String {
        get {
            let val = Self.readPluginStoreString(prefix: Self.nickClockPrefix, key: "bio_template") ?? ""
            return val.isEmpty ? "⌚ {time} • 📅 {date} • 🔋 {battery}%" : val
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.writePluginStoreValue(prefix: Self.nickClockPrefix, key: "bio_template", value: clean.isEmpty ? "⌚ {time} • 📅 {date}" : clean)
            if self.nickClockUpdateBio {
                _ = self.applyLiveBioClockNow()
            }
        }
    }

    private static func readPluginStoreRaw(prefix: String, key: String) -> Any? {
        guard let stored = UserDefaults.standard.object(forKey: prefix + key) else { return nil }
        if let data = stored as? Data,
           let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return obj
        }
        return stored
    }

    private static func readPluginStoreBool(prefix: String, key: String, default fallback: Bool) -> Bool {
        guard let raw = Self.readPluginStoreRaw(prefix: prefix, key: key) else { return fallback }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String { return ["true", "1", "yes", "on"].contains(s.lowercased()) }
        return fallback
    }

    private static func readPluginStoreInt(prefix: String, key: String, default fallback: Int) -> Int {
        guard let raw = Self.readPluginStoreRaw(prefix: prefix, key: key) else { return fallback }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String, let v = Int(s) { return v }
        return fallback
    }

    private static func readPluginStoreString(prefix: String, key: String) -> String? {
        guard let raw = Self.readPluginStoreRaw(prefix: prefix, key: key) else { return nil }
        if let s = raw as? String { return s }
        return String(describing: raw)
    }

    private static func writePluginStoreValue(prefix: String, key: String, value: Any) {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []) {
            UserDefaults.standard.set(data, forKey: prefix + key)
        } else {
            UserDefaults.standard.set(value, forKey: prefix + key)
        }
    }

    private var pluginsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = docs.appendingPathComponent("FullGramPlugins", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var manifestURL: URL {
        return self.pluginsDirectoryURL.appendingPathComponent("manifest.json")
    }

    private static let legacyBuiltInPluginIds: Set<String> = [
        "fg_quick_commands",
        "fg_inline_calc",
        "fg_python_formatter",
        "fg_message_counter",
        "fg_chat_info",
        "fg_snippets",
        "fg_notes",
        "fg_layout_fixer",
        "fg_casino",
        "fg_anti_typos",
        "fg_deadlines",
        "fg_nick_clock"
    ]

    private func ensureLoaded() {
        self.lock.lock()
        guard !self.didInitialize else {
            self.lock.unlock()
            return
        }
        self.didInitialize = true

        self.registerLifecycleObserversIfNeeded()

        var purgedBuiltIns = false
        if let data = try? Data(contentsOf: self.manifestURL),
           let decoded = try? JSONDecoder().decode([FullGramPluginDescriptor].self, from: data) {
            var restored: [FullGramPluginDescriptor] = []
            for var item in decoded {
                if item.isBuiltIn || Self.legacyBuiltInPluginIds.contains(item.id) {
                    let scriptURL = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
                    try? FileManager.default.removeItem(at: scriptURL)
                    purgedBuiltIns = true
                    continue
                }
                let scriptURL = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
                if let diskCode = try? String(contentsOf: scriptURL, encoding: .utf8), !diskCode.isEmpty {
                    item.code = diskCode
                }
                restored.append(item)
            }
            self.descriptors = restored
        }

        if purgedBuiltIns {
            self.persistLocked()
        }
        let plan = self.prepareReloadLocked()
        self.lock.unlock()
        self.finishReloadOutsideLock(plan)
    }

    private func persistLocked() {
        let dir = self.pluginsDirectoryURL
        for item in self.descriptors {
            let scriptURL = dir.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
            try? item.code.write(to: scriptURL, atomically: true, encoding: .utf8)
        }
        if let data = try? JSONEncoder().encode(self.descriptors) {
            try? data.write(to: self.manifestURL, options: .atomic)
        }
    }

    public func allPlugins() -> [FullGramPluginDescriptor] {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.descriptors
    }

    public func plugin(id: String) -> FullGramPluginDescriptor? {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.descriptors.first(where: { $0.id == id })
    }

    public func error(forPluginId id: String) -> String? {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loaded[id]?.lastError
    }

    public func logs(forPluginId id: String) -> [String] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.logsByPlugin[id] ?? []
    }

    public func clearLogs(forPluginId id: String) {
        self.lock.lock()
        self.logsByPlugin[id] = []
        self.lock.unlock()
    }

    private func appendLog(pluginId: String, message: String) {
        self.lock.lock()
        let line = "[\(Self.logDateFormatter.string(from: Date()))] \(message)"
        var arr = self.logsByPlugin[pluginId] ?? []
        arr.append(line)
        if arr.count > 200 {
            arr.removeFirst(arr.count - 200)
        }
        self.logsByPlugin[pluginId] = arr
        self.lock.unlock()
    }

    @discardableResult
    public func savePlugin(
        id: String? = nil,
        name: String,
        language: FullGramPluginLanguage,
        code: String,
        enabled: Bool? = nil,
        backgroundEnabled: Bool? = nil,
        backgroundInterval: Int? = nil
    ) -> FullGramPluginDescriptor {
        self.ensureLoaded()
        let meta = FullGramPluginMetadata.parse(from: code, fallbackName: name, language: language)
        let rawId = (id?.isEmpty == false ? id! : meta.id)
        let sanitizedId = rawId.lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let resolvedId = sanitizedId.isEmpty ? meta.id : sanitizedId

        self.lock.lock()
        let existingIndex = self.descriptors.firstIndex(where: { $0.id == resolvedId })
        let wasEnabled = existingIndex.map { self.descriptors[$0].isEnabled } ?? true
        let wasBuiltIn = existingIndex.map { self.descriptors[$0].isBuiltIn } ?? false
        let prevBgEnabled = existingIndex.map { self.descriptors[$0].backgroundEnabled } ?? false
        let prevBgInterval = existingIndex.map { self.descriptors[$0].backgroundInterval } ?? 30
        let resolvedBgEnabled = backgroundEnabled ?? (meta.backgroundEnabled ? true : prevBgEnabled)
        let resolvedBgInterval = min(3600, max(5, backgroundInterval ?? (meta.backgroundEnabled ? meta.backgroundInterval : prevBgInterval)))

        let descriptor = FullGramPluginDescriptor(
            id: resolvedId,
            name: meta.name.isEmpty ? name : meta.name,
            language: language,
            version: meta.version,
            author: meta.author,
            description: meta.description,
            code: code,
            isEnabled: enabled ?? wasEnabled,
            isBuiltIn: wasBuiltIn,
            updatedAt: Date().timeIntervalSince1970,
            permissions: meta.permissions,
            backgroundEnabled: resolvedBgEnabled,
            backgroundInterval: resolvedBgInterval
        )
        if let idx = existingIndex {
            self.descriptors[idx] = descriptor
        } else {
            self.descriptors.append(descriptor)
        }
        self.persistLocked()
        let plan = self.prepareReloadLocked()
        self.lock.unlock()
        self.finishReloadOutsideLock(plan)

        self.postPluginsDidChange()
        return descriptor
    }

    private func postPluginsDidChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: FullGramPluginNotifications.pluginsDidChange, object: nil)
            }
        }
    }

    private func postBackgroundStateChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: FullGramPluginNotifications.backgroundStateDidChange, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: FullGramPluginNotifications.backgroundStateDidChange, object: nil)
            }
        }
    }

    public func setPluginEnabled(id: String, enabled: Bool) {
        self.ensureLoaded()
        self.lock.lock()
        var plan: ReloadPlan?
        if let idx = self.descriptors.firstIndex(where: { $0.id == id }) {
            self.descriptors[idx].isEnabled = enabled
            self.persistLocked()
            plan = self.prepareReloadLocked()
        }
        self.lock.unlock()
        if let plan {
            self.finishReloadOutsideLock(plan)
        }
        self.postPluginsDidChange()
    }

    public func setPluginBackground(id: String, enabled: Bool, interval: Int? = nil) {
        self.ensureLoaded()
        self.lock.lock()
        if let idx = self.descriptors.firstIndex(where: { $0.id == id }) {
            self.descriptors[idx].backgroundEnabled = enabled
            if let interval {
                let clamped = min(3600, max(5, interval))
                self.descriptors[idx].backgroundInterval = clamped
                self.runtimeIntervalsByPlugin[id] = clamped
            }
            if !enabled {
                self.runtimeIntervalsByPlugin.removeValue(forKey: id)
            }
            self.persistLocked()
            self.syncBackgroundSchedulerLocked()
        }
        self.lock.unlock()
        self.postPluginsDidChange()
        self.postBackgroundStateChanged()
    }

    public func deletePlugin(id: String) {
        self.ensureLoaded()
        var unloadedPlugin: FullGramLoadedPlugin?
        self.lock.lock()
        if let idx = self.descriptors.firstIndex(where: { $0.id == id }) {
            if let old = self.loaded[id], old.hasUnloadHook {
                unloadedPlugin = old
            }
            let item = self.descriptors.remove(at: idx)
            let scriptURL = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
            try? FileManager.default.removeItem(at: scriptURL)
            self.loaded.removeValue(forKey: id)
            self.cachedOrderedPlugins.removeAll { $0.descriptor.id == id }
            self.cachedRenderPlugins.removeAll { $0.descriptor.id == id }
            self.lastTickByPlugin.removeValue(forKey: id)
            self.tickCountByPlugin.removeValue(forKey: id)
            self.runtimeIntervalsByPlugin.removeValue(forKey: id)
            self.hasRenderHooks = !self.cachedRenderPlugins.isEmpty
            self.persistLocked()
            self.syncBackgroundSchedulerLocked()
        }
        self.lock.unlock()
        // Invoke on_unload outside self.lock to prevent AB-BA deadlock with self.vmLock.
        if let old = unloadedPlugin {
            self.invokeLifecycleHook(plugin: old, name: "on_unload", args: [])
        }
        self.postPluginsDidChange()
    }

    public func importPlugin(from url: URL, preferredFileName: String? = nil) throws -> FullGramPluginDescriptor {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let maxPluginBytes = 256 * 1024
        if let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize), fileSize > maxPluginBytes {
            throw FullGramPluginError("Файл плагина превышает 256 КБ")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let rawData = try handle.read(upToCount: maxPluginBytes + 1) ?? Data()
        guard rawData.count <= maxPluginBytes else {
            throw FullGramPluginError("Файл плагина превышает 256 КБ")
        }
        guard let code = String(data: rawData, encoding: .utf8) else {
            throw FullGramPluginError("Файл плагина должен быть в кодировке UTF-8")
        }
        let sourceName = preferredFileName?.isEmpty == false ? preferredFileName! : url.lastPathComponent
        let ext = (sourceName as NSString).pathExtension.lowercased()
        let baseName = (sourceName as NSString).deletingPathExtension
        let language: FullGramPluginLanguage
        if ext == "py" {
            language = .python
        } else if ext == "rs" {
            language = .rust
        } else if ext == "lua" {
            language = .lua
        } else if code.contains("def on_") || code.contains("import fullgram") || code.contains("# @name") {
            language = .python
        } else if code.contains("fn on_") || code.contains("fullgram::") || code.contains("// @name") {
            language = .rust
        } else {
            language = .lua
        }
        let fallbackName = baseName.isEmpty ? "Импортированный плагин" : baseName
        return self.savePlugin(id: nil, name: fallbackName, language: language, code: code, enabled: true)
    }

    public func exportFileURL(forPluginId id: String) -> URL? {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let item = self.descriptors.first(where: { $0.id == id }) else { return nil }
        let url = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
        try? item.code.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func reloadRuntime() {
        self.lock.lock()
        let plan = self.prepareReloadLocked()
        self.lock.unlock()
        self.finishReloadOutsideLock(plan)
    }

    private func prepareReloadLocked() -> ReloadPlan {
        self.reloadGeneration &+= 1
        let gen = self.reloadGeneration
        let oldUnloadPlugins = self.cachedOrderedPlugins.filter { $0.hasUnloadHook }
        self.loaded.removeAll()
        self.cachedOrderedPlugins.removeAll()
        self.cachedRenderPlugins.removeAll()
        self.hasRenderHooks = false
        guard self.isSystemEnabled else {
            self.syncBackgroundSchedulerLocked()
            return ReloadPlan(generation: gen, systemEnabled: false, toCompile: [], oldUnloadPlugins: oldUnloadPlugins)
        }
        let toCompile = self.descriptors.filter { $0.isEnabled }
        return ReloadPlan(generation: gen, systemEnabled: true, toCompile: toCompile, oldUnloadPlugins: oldUnloadPlugins)
    }

    private func finishReloadOutsideLock(_ plan: ReloadPlan) {
        let compiled: [FullGramLoadedPlugin] = plan.systemEnabled ? plan.toCompile.map { self.compile(descriptor: $0) } : []

        var newLoadPlugins: [FullGramLoadedPlugin] = []
        self.lock.lock()
        if self.reloadGeneration == plan.generation && plan.systemEnabled && self.isSystemEnabled {
            var anyRender = false
            for runtime in compiled {
                if runtime.hasRenderHook {
                    anyRender = true
                    self.cachedRenderPlugins.append(runtime)
                }
                self.loaded[runtime.descriptor.id] = runtime
                self.cachedOrderedPlugins.append(runtime)
            }
            self.hasRenderHooks = anyRender
            newLoadPlugins = self.cachedOrderedPlugins.filter { $0.hasLoadHook }
            self.syncBackgroundSchedulerLocked()
        }
        self.lock.unlock()

        let oldUnloadPlugins = plan.oldUnloadPlugins
        if !oldUnloadPlugins.isEmpty || !newLoadPlugins.isEmpty {
            // Invoke lifecycle hooks outside self.lock to prevent AB-BA deadlock with self.vmLock.
            self.backgroundQueue.async { [weak self] in
                guard let self else { return }
                for old in oldUnloadPlugins {
                    self.invokeLifecycleHook(plugin: old, name: "on_unload", args: [])
                }
                for plugin in newLoadPlugins {
                    self.invokeLifecycleHook(plugin: plugin, name: "on_load", args: [])
                }
            }
        }
    }

    // MARK: - Profile Cache, Nickname Management & Telegram Bridge

    private func loadCachedProfileFromDisk() {
        if let data = UserDefaults.standard.data(forKey: self.cachedProfileKey),
           let decoded = try? JSONDecoder().decode(FullGramPluginAccountProfile.self, from: data) {
            self.cachedProfile = decoded
        }
        if let origData = UserDefaults.standard.data(forKey: self.originalNickKey),
           let orig = try? JSONDecoder().decode([String: String].self, from: origData) {
            if let f = orig["first"], !f.isEmpty {
                self.cachedProfile.originalFirstName = f
                self.cachedProfile.originalLastName = orig["last"] ?? ""
            }
        }
    }

    private func saveCachedProfileLocked() {
        if let data = try? JSONEncoder().encode(self.cachedProfile) {
            UserDefaults.standard.set(data, forKey: self.cachedProfileKey)
        }
    }

    public func currentProfile() -> FullGramPluginAccountProfile {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.cachedProfile
    }

    public func captureOriginalNicknameIfNeeded() {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.cachedProfile.originalFirstName.isEmpty && !self.cachedProfile.firstName.isEmpty {
            self.cachedProfile.originalFirstName = self.cachedProfile.firstName
            self.cachedProfile.originalLastName = self.cachedProfile.lastName
            if let data = try? JSONEncoder().encode(["first": self.cachedProfile.originalFirstName, "last": self.cachedProfile.originalLastName]) {
                UserDefaults.standard.set(data, forKey: self.originalNickKey)
            }
            self.saveCachedProfileLocked()
        }
    }

    public func updateCachedAccountProfile(
        peerId: Int64,
        firstName: String,
        lastName: String,
        username: String,
        phone: String,
        bio: String? = nil
    ) {
        self.lock.lock()
        self.cachedProfile.peerId = peerId
        self.cachedProfile.firstName = firstName
        self.cachedProfile.lastName = lastName
        self.cachedProfile.username = username
        self.cachedProfile.phone = phone
        if let bio {
            self.cachedProfile.bio = bio
        }
        if self.cachedProfile.originalFirstName.isEmpty && !firstName.isEmpty {
            self.cachedProfile.originalFirstName = firstName
            self.cachedProfile.originalLastName = lastName
            if let data = try? JSONEncoder().encode(["first": firstName, "last": lastName]) {
                UserDefaults.standard.set(data, forKey: self.originalNickKey)
            }
        }
        self.cachedProfile.updatedAt = Date().timeIntervalSince1970
        self.saveCachedProfileLocked()
        self.lock.unlock()
    }

    public func registerTelegramBridge(
        updateName: @escaping (String, String, ((Bool) -> Void)?) -> Void,
        updateUsername: @escaping (String, ((Bool) -> Void)?) -> Void,
        updateBio: @escaping (String, ((Bool) -> Void)?) -> Void,
        sendMessage: @escaping (Int64?, String) -> Bool,
        setDraft: @escaping (Int64?, String) -> Bool,
        activeChatInfo: @escaping () -> [String: FullGramPluginValue]?
    ) {
        self.lock.lock()
        self.bridgeUpdateName = updateName
        self.bridgeUpdateUsername = updateUsername
        self.bridgeUpdateBio = updateBio
        self.bridgeSendMessage = sendMessage
        self.bridgeSetDraft = setDraft
        self.bridgeActiveChatInfo = activeChatInfo
        self.lock.unlock()
    }

    public func formatNicknameTemplate(
        _ template: String,
        baseFirstName: String? = nil,
        baseLastName: String? = nil,
        style: String = "normal"
    ) -> (firstName: String, lastName: String) {
        let profile = self.currentProfile()
        let resolvedFirst = (baseFirstName?.isEmpty == false) ? baseFirstName! : (profile.originalFirstName.isEmpty ? profile.firstName : profile.originalFirstName)
        let resolvedLast = baseLastName ?? (profile.originalLastName.isEmpty ? profile.lastName : profile.originalLastName)
        let resolvedFull = resolvedLast.isEmpty ? resolvedFirst : "\(resolvedFirst) \(resolvedLast)"

        let timeDict = FullGramPluginTimeHelper.buildPhoneTimeDict()
        let hmRaw = timeDict["hm"]?.asString ?? "00:00"
        let hmsRaw = timeDict["hms"]?.asString ?? "00:00:00"
        let styledHm = FullGramPluginTimeHelper.stylizeDigits(hmRaw, style: style)
        let styledHms = FullGramPluginTimeHelper.stylizeDigits(hmsRaw, style: style)
        let dateStr = timeDict["date"]?.asString ?? ""
        let weekday = timeDict["weekday_name"]?.asString ?? ""
        let weekdayShort = timeDict["weekday_short"]?.asString ?? ""
        let clockEmoji = timeDict["clock_emoji"]?.asString ?? "⌚"
        let boldHm = timeDict["bold_hm"]?.asString ?? hmRaw
        let monoHm = timeDict["mono_hm"]?.asString ?? hmRaw
        let fancyHm = timeDict["fancy_hm"]?.asString ?? hmRaw
        let devInfo = self.currentDeviceSnapshot()
        let batteryStr = devInfo.batteryLevel >= 0 ? "\(devInfo.batteryLevel)" : "100"

        var rendered = template
        let replacements: [(String, String)] = [
            ("{time}", styledHm),
            ("{time_sec}", styledHms),
            ("{time_raw}", hmRaw),
            ("{time_bold}", boldHm),
            ("{time_mono}", monoHm),
            ("{time_fancy}", fancyHm),
            ("{clock}", clockEmoji),
            ("{date}", dateStr),
            ("{weekday}", weekday),
            ("{weekday_short}", weekdayShort),
            ("{battery}", batteryStr),
            ("{first_name}", resolvedFirst),
            ("{last_name}", resolvedLast),
            ("{name}", resolvedFull.isEmpty ? "FullGram" : resolvedFull)
        ]
        for (token, val) in replacements {
            rendered = rendered.replacingOccurrences(of: token, with: val)
        }

        // Telegram firstName limit is 64 chars, lastName limit is 64 chars
        if let pipeRange = rendered.range(of: "||") {
            let fn = String(rendered[..<pipeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = String(rendered[pipeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let clampedFn = fn.isEmpty ? (resolvedFirst.isEmpty ? styledHm : resolvedFirst) : String(fn.prefix(64))
            return (clampedFn, String(ln.prefix(64)))
        }
        let clean = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean.isEmpty ? styledHm : String(clean.prefix(64)), resolvedLast)
    }

    @discardableResult
    public func requestSetNickname(
        firstName: String,
        lastName: String = "",
        pluginId: String = "system",
        force: Bool = false
    ) -> Bool {
        let cleanFirst = String(firstName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        let cleanLast = String(lastName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !cleanFirst.isEmpty else { return false }

        self.captureOriginalNicknameIfNeeded()

        self.lock.lock()
        if !force && self.lastAppliedFirstName == cleanFirst && self.lastAppliedLastName == cleanLast {
            self.lock.unlock()
            return true
        }
        let now = Date().timeIntervalSince1970
        let elapsed = now - self.lastNicknameRequestTime
        if !force && elapsed < self.minNicknameUpdateInterval {
            self.pendingNicknameUpdate = (cleanFirst, cleanLast)
            if self.pendingNicknameWorkItem == nil {
                let delay = max(1.0, self.minNicknameUpdateInterval - elapsed + 0.2)
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    let pending = self.pendingNicknameUpdate
                    self.pendingNicknameUpdate = nil
                    self.pendingNicknameWorkItem = nil
                    self.lock.unlock()
                    if let pending {
                        _ = self.requestSetNickname(firstName: pending.firstName, lastName: pending.lastName, pluginId: pluginId, force: true)
                    }
                }
                self.pendingNicknameWorkItem = work
                self.backgroundQueue.asyncAfter(deadline: .now() + delay, execute: work)
            }
            self.lock.unlock()
            return true
        }

        self.lastNicknameRequestTime = now
        self.lastAppliedFirstName = cleanFirst
        self.lastAppliedLastName = cleanLast
        self.cachedProfile.firstName = cleanFirst
        self.cachedProfile.lastName = cleanLast
        self.cachedProfile.updatedAt = now
        self.saveCachedProfileLocked()
        let bridge = self.bridgeUpdateName
        self.lock.unlock()

        self.appendLog(pluginId: pluginId, message: "Nickname -> \(cleanFirst)\(cleanLast.isEmpty ? "" : " \(cleanLast)")")

        DispatchQueue.main.async {
            if let bridge {
                bridge(cleanFirst, cleanLast, nil)
            } else {
                NotificationCenter.default.post(
                    name: FullGramPluginNotifications.profileUpdateRequested,
                    object: nil,
                    userInfo: ["kind": "name", "firstName": cleanFirst, "lastName": cleanLast, "pluginId": pluginId]
                )
            }
        }
        return true
    }

    @discardableResult
    public func restoreOriginalNickname(pluginId: String = "system") -> Bool {
        self.lock.lock()
        let origFirst = self.cachedProfile.originalFirstName
        let origLast = self.cachedProfile.originalLastName
        self.pendingNicknameWorkItem?.cancel()
        self.pendingNicknameWorkItem = nil
        self.pendingNicknameUpdate = nil
        self.lock.unlock()

        guard !origFirst.isEmpty else { return false }
        return self.requestSetNickname(firstName: origFirst, lastName: origLast, pluginId: pluginId, force: true)
    }

    @discardableResult
    public func requestSetUsername(_ username: String, pluginId: String = "system") -> Bool {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        self.lock.lock()
        self.cachedProfile.username = clean
        self.cachedProfile.updatedAt = Date().timeIntervalSince1970
        self.saveCachedProfileLocked()
        let bridge = self.bridgeUpdateUsername
        self.lock.unlock()

        DispatchQueue.main.async {
            if let bridge {
                bridge(clean, nil)
            } else {
                NotificationCenter.default.post(
                    name: FullGramPluginNotifications.profileUpdateRequested,
                    object: nil,
                    userInfo: ["kind": "username", "username": clean, "pluginId": pluginId]
                )
            }
        }
        return true
    }

    @discardableResult
    public func requestSetBio(_ bio: String, pluginId: String = "system") -> Bool {
        let clean = String(bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140))
        self.lock.lock()
        if self.lastAppliedBio == clean {
            self.lock.unlock()
            return true
        }
        self.lastAppliedBio = clean
        self.cachedProfile.bio = clean
        self.cachedProfile.updatedAt = Date().timeIntervalSince1970
        self.saveCachedProfileLocked()
        let bridge = self.bridgeUpdateBio
        self.lock.unlock()

        DispatchQueue.main.async {
            if let bridge {
                bridge(clean, nil)
            } else {
                NotificationCenter.default.post(
                    name: FullGramPluginNotifications.profileUpdateRequested,
                    object: nil,
                    userInfo: ["kind": "bio", "bio": clean, "pluginId": pluginId]
                )
            }
        }
        return true
    }

    @discardableResult
    public func applyLiveNicknameClockNow(force: Bool = false) -> String {
        let pair = self.formatNicknameTemplate(
            self.nickClockTemplate,
            baseFirstName: self.nickClockBaseFirstName,
            baseLastName: self.nickClockBaseLastName,
            style: self.nickClockStyle
        )
        _ = self.requestSetNickname(firstName: pair.firstName, lastName: pair.lastName, pluginId: "fg_nick_clock", force: force)
        return pair.lastName.isEmpty ? pair.firstName : "\(pair.firstName) \(pair.lastName)"
    }

    @discardableResult
    public func applyLiveBioClockNow() -> String {
        let pair = self.formatNicknameTemplate(
            self.nickClockBioTemplate,
            baseFirstName: self.nickClockBaseFirstName,
            baseLastName: self.nickClockBaseLastName,
            style: self.nickClockStyle
        )
        _ = self.requestSetBio(pair.firstName, pluginId: "fg_nick_clock")
        return pair.firstName
    }

    // MARK: - Background Execution & Device Lifecycle

    private func registerLifecycleObserversIfNeeded() {
        guard !self.didRegisterLifecycleObservers else { return }
        self.didRegisterLifecycleObservers = true

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                UIDevice.current.isBatteryMonitoringEnabled = true
                self?.refreshDeviceSnapshotOnMain()
            }
        }

        let nc = NotificationCenter.default
        self.lifecycleObservers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.refreshDeviceSnapshotOnMain(appState: "background", isBackground: true)
                self.beginBackgroundKeepAliveIfNeededOnMain()
            }
            self.backgroundQueue.async {
                self.dispatchAppStateHooks(state: "background")
                _ = self.triggerBackgroundTick(force: true)
            }
        })
        self.lifecycleObservers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.endBackgroundTaskOnMain()
                self.refreshDeviceSnapshotOnMain(appState: "foreground", isBackground: false)
            }
            self.backgroundQueue.async {
                self.dispatchAppStateHooks(state: "foreground")
                _ = self.triggerBackgroundTick(force: true)
            }
        })
        self.lifecycleObservers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.endBackgroundTaskOnMain()
                self.refreshDeviceSnapshotOnMain(appState: "foreground", isBackground: false)
            }
        })
        self.lifecycleObservers.append(nc.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.refreshDeviceSnapshotOnMain()
            }
        })
        self.lifecycleObservers.append(nc.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.refreshDeviceSnapshotOnMain()
            }
        })
    }

    @MainActor
    private func refreshDeviceSnapshotOnMain(appState: String? = nil, isBackground: Bool? = nil) {
        let dev = UIDevice.current
        if !dev.isBatteryMonitoringEnabled {
            dev.isBatteryMonitoringEnabled = true
        }
        let levelRaw = dev.batteryLevel
        let batteryPct = levelRaw >= 0 ? Int((levelRaw * 100.0).rounded()) : -1
        let stateStr: String
        let charging: Bool
        switch dev.batteryState {
        case .charging:
            stateStr = "charging"
            charging = true
        case .full:
            stateStr = "full"
            charging = true
        case .unplugged:
            stateStr = "unplugged"
            charging = false
        default:
            stateStr = "unknown"
            charging = false
        }
        let resolvedAppState: String
        let resolvedBg: Bool
        if let appState, let isBackground {
            resolvedAppState = appState
            resolvedBg = isBackground
        } else {
            switch UIApplication.shared.applicationState {
            case .background:
                resolvedAppState = "background"
                resolvedBg = true
            case .inactive:
                resolvedAppState = "inactive"
                resolvedBg = false
            default:
                resolvedAppState = "foreground"
                resolvedBg = false
            }
        }
        self.lock.lock()
        self.deviceSnapshot = DeviceSnapshot(
            model: dev.model,
            systemName: dev.systemName,
            systemVersion: dev.systemVersion,
            batteryLevel: batteryPct,
            batteryState: stateStr,
            isCharging: charging,
            appState: resolvedAppState,
            isBackground: resolvedBg
        )
        self.lock.unlock()
    }

    @MainActor
    private func beginBackgroundKeepAliveIfNeededOnMain() {
        self.lock.lock()
        let hasActiveBg = self.isSystemEnabled && self.isBackgroundExecutionEnabled && self.cachedOrderedPlugins.contains { plugin in
            let id = plugin.descriptor.id
            let wantsBg = plugin.descriptor.backgroundEnabled || self.runtimeIntervalsByPlugin[id] != nil || (id == "fg_nick_clock" && self.nickClockEnabled)
            return plugin.hasBackgroundHook && wantsBg
        }
        let alreadyActive = self.backgroundTaskId != .invalid
        self.lock.unlock()

        guard hasActiveBg, !alreadyActive else { return }
        let taskId = UIApplication.shared.beginBackgroundTask(withName: "FullGramPluginBackground") { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.endBackgroundTaskOnMain()
                }
            }
        }
        self.lock.lock()
        self.backgroundTaskId = taskId
        self.lock.unlock()
    }

    @MainActor
    private func endBackgroundTaskOnMain() {
        self.lock.lock()
        let taskId = self.backgroundTaskId
        self.backgroundTaskId = .invalid
        self.lock.unlock()
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
        }
    }

    private func currentDeviceSnapshot() -> DeviceSnapshot {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.deviceSnapshot
    }

    private func buildDeviceInfoDict() -> [String: FullGramPluginValue] {
        let snap = self.currentDeviceSnapshot()
        return [
            "model": .string(snap.model),
            "system_name": .string(snap.systemName),
            "system_version": .string(snap.systemVersion),
            "battery_level": .int(Int64(snap.batteryLevel)),
            "battery_percent": .int(Int64(snap.batteryLevel)),
            "battery_state": .string(snap.batteryState),
            "is_charging": .bool(snap.isCharging),
            "is_low_power": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled),
            "locale": .string(Locale.current.identifier),
            "timezone": .string(TimeZone.current.identifier),
            "app_state": .string(snap.appState),
            "is_background": .bool(snap.isBackground),
            "uptime": .double(ProcessInfo.processInfo.systemUptime)
        ]
    }

    private func syncBackgroundSchedulerLocked() {
        let shouldRun = self.isSystemEnabled && self.isBackgroundExecutionEnabled && self.cachedOrderedPlugins.contains { plugin in
            let id = plugin.descriptor.id
            let wantsBg = plugin.descriptor.backgroundEnabled || self.runtimeIntervalsByPlugin[id] != nil || (id == "fg_nick_clock" && self.nickClockEnabled)
            return plugin.hasBackgroundHook && wantsBg
        }
        if !shouldRun {
            self.backgroundTimer?.cancel()
            self.backgroundTimer = nil
            return
        }
        if self.backgroundTimer != nil { return }
        let timer = DispatchSource.makeTimerSource(queue: self.backgroundQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: .seconds(5), leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            _ = self?.triggerBackgroundTick(force: false)
        }
        self.backgroundTimer = timer
        timer.resume()
    }

    public func backgroundStatusSummary() -> (running: Bool, activeCount: Int, totalTicks: Int64) {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        let count = self.cachedOrderedPlugins.filter { plugin in
            let id = plugin.descriptor.id
            let wantsBg = plugin.descriptor.backgroundEnabled || self.runtimeIntervalsByPlugin[id] != nil || (id == "fg_nick_clock" && self.nickClockEnabled)
            return plugin.hasBackgroundHook && wantsBg
        }.count
        return (self.backgroundTimer != nil, count, self.backgroundTickCount)
    }

    private func invokeCallable(
        _ fn: ([FullGramPluginValue]) throws -> FullGramPluginValue,
        on plugin: FullGramLoadedPlugin,
        args: [FullGramPluginValue]
    ) throws -> FullGramPluginValue {
        if let lua = plugin.luaVM {
            return try lua.invoke(fn, args: args)
        } else if let py = plugin.pythonVM {
            return try py.invoke(fn, args: args)
        } else if let rs = plugin.rustVM {
            return try rs.invoke(fn, args: args)
        }
        return try fn(args)
    }

    private func invokeLifecycleHook(plugin: FullGramLoadedPlugin, name: String, args: [FullGramPluginValue]) {
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        do {
            if let lua = plugin.luaVM, lua.hasFunction(name) {
                _ = try lua.callFunction(name, args: args)
            } else if let py = plugin.pythonVM, py.hasFunction(name) {
                _ = try py.callFunction(name, args: args)
            } else if let rs = plugin.rustVM, rs.hasFunction(name) {
                _ = try rs.callFunction(name, args: args)
            }
        } catch {
            self.appendLog(pluginId: plugin.descriptor.id, message: "\(name) error: \(error.localizedDescription)")
        }
    }

    private func dispatchAppStateHooks(state: String) {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled else {
            self.lock.unlock()
            return
        }
        let targets = self.cachedOrderedPlugins.filter { $0.hasAppStateHook }
        self.lock.unlock()
        guard !targets.isEmpty else { return }

        let timeDict = FullGramPluginTimeHelper.buildPhoneTimeDict()
        for plugin in targets {
            let ctx = FullGramPluginTableBox(dict: [
                "state": .string(state),
                "in_background": .bool(state == "background"),
                "time": .table(FullGramPluginTableBox(dict: timeDict))
            ])
            self.invokeLifecycleHook(plugin: plugin, name: "on_app_state", args: [.table(ctx)])
        }
    }

    @discardableResult
    public func triggerBackgroundTick(pluginId: String? = nil, force: Bool = false) -> Int {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled && (self.isBackgroundExecutionEnabled || force) else {
            self.lock.unlock()
            return 0
        }
        let ordered = self.cachedOrderedPlugins
        let snap = self.deviceSnapshot
        self.lock.unlock()

        let now = Date().timeIntervalSince1970
        var executed = 0

        for plugin in ordered {
            let id = plugin.descriptor.id
            if let pluginId, id != pluginId { continue }
            guard plugin.hasBackgroundHook, let hookName = plugin.backgroundHookName else { continue }

            self.lock.lock()
            let wantsBg = force || plugin.descriptor.backgroundEnabled || self.runtimeIntervalsByPlugin[id] != nil || (id == "fg_nick_clock" && self.nickClockEnabled)
            let interval = TimeInterval(self.runtimeIntervalsByPlugin[id] ?? plugin.descriptor.backgroundInterval)
            let lastTs = self.lastTickByPlugin[id] ?? 0
            if !wantsBg || (!force && (now - lastTs) < max(5.0, interval)) {
                self.lock.unlock()
                continue
            }
            self.lastTickByPlugin[id] = now
            self.backgroundTickCount += 1
            let pluginTick = (self.tickCountByPlugin[id] ?? 0) + 1
            self.tickCountByPlugin[id] = pluginTick
            self.lock.unlock()

            let timeBox = FullGramPluginTableBox(dict: FullGramPluginTimeHelper.buildPhoneTimeDict())
            let hasProfilePerm = plugin.descriptor.permissions.contains {
                let p = $0.lowercased()
                return p == "profile" || p == "all" || p == "*"
            }
            let profileVal = self.currentProfile().toPluginValue(includePhone: hasProfilePerm)
            let deviceBox = FullGramPluginTableBox(dict: self.buildDeviceInfoDict())
            let ctx = FullGramPluginTableBox(dict: [
                "tick": .int(pluginTick),
                "interval": .int(Int64(interval)),
                "in_background": .bool(snap.isBackground),
                "app_state": .string(snap.appState),
                "time": .table(timeBox),
                "profile": profileVal,
                "device": .table(deviceBox)
            ])

            self.invokeLifecycleHook(plugin: plugin, name: hookName, args: [.table(ctx)])
            executed += 1
        }
        return executed
    }

    public func processIncomingMessage(
        text: String,
        peerId: Int64,
        senderName: String,
        timestamp: Int32,
        isGroup: Bool,
        isChannel: Bool
    ) {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled else {
            self.lock.unlock()
            return
        }
        let targets = self.cachedOrderedPlugins.filter { $0.hasIncomingHook }
        self.lock.unlock()
        guard !targets.isEmpty else { return }

        self.backgroundQueue.async { [weak self] in
            guard let self else { return }
            let timeDict = FullGramPluginTimeHelper.buildPhoneTimeDict()
            for plugin in targets {
                let ctx = FullGramPluginTableBox(dict: [
                    "text": .string(text),
                    "peer_id": .int(peerId),
                    "sender_name": .string(senderName),
                    "timestamp": .int(Int64(timestamp)),
                    "is_group": .bool(isGroup),
                    "is_channel": .bool(isChannel),
                    "time": .table(FullGramPluginTableBox(dict: timeDict))
                ])
                self.invokeLifecycleHook(plugin: plugin, name: "on_incoming_message", args: [.table(ctx)])
            }
        }
    }

    private static let chatStatsThreadKey = "FullGram.Plugin.ChatStats"

    private static func isBlockedIPv4(_ ipv4HostOrder: UInt32) -> Bool {
        let b0 = (ipv4HostOrder >> 24) & 0xFF
        let b1 = (ipv4HostOrder >> 16) & 0xFF
        if b0 == 0 { return true }
        if b0 == 10 { return true }
        if b0 == 100 && (b1 >= 64 && b1 <= 127) { return true }
        if b0 == 127 { return true }
        if b0 == 169 && b1 == 254 { return true }
        if b0 == 172 && (b1 >= 16 && b1 <= 31) { return true }
        if b0 == 192 && b1 == 168 { return true }
        if b0 == 198 && (b1 == 18 || b1 == 19) { return true }
        if b0 >= 224 { return true }
        return false
    }

    private static func isBlockedIPv6(_ addr: in6_addr) -> Bool {
        var addrCopy = addr
        let bytes = withUnsafeBytes(of: &addrCopy) { Array($0) }
        guard bytes.count == 16 else { return true }
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && (bytes[15] == 0 || bytes[15] == 1) { return true }
        let isV4Mapped = bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xFF && bytes[11] == 0xFF
        if isV4Mapped {
            let v4 = (UInt32(bytes[12]) << 24) | (UInt32(bytes[13]) << 16) | (UInt32(bytes[14]) << 8) | UInt32(bytes[15])
            return Self.isBlockedIPv4(v4)
        }
        if (bytes[0] & 0xFE) == 0xFC { return true }
        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }
        if bytes[0] == 0xFF { return true }
        return false
    }

    private static func isBlockedHost(_ host: String) -> Bool {
        var clean = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("[") && clean.hasSuffix("]") {
            clean = String(clean.dropFirst().dropLast())
        }
        if clean.isEmpty || clean == "localhost" || clean.hasSuffix(".local") || clean.hasSuffix(".internal") || clean.hasSuffix(".arpa") {
            return true
        }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let status = clean.withCString { cHost in
            getaddrinfo(cHost, nil, &hints, &res)
        }
        defer {
            if let res {
                freeaddrinfo(res)
            }
        }
        guard status == 0, let first = res else {
            return true
        }
        var resolvedAny = false
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            if let sa = info.pointee.ai_addr {
                let family = Int32(sa.pointee.sa_family)
                if family == AF_INET {
                    let sin = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    let v4 = UInt32(bigEndian: sin.sin_addr.s_addr)
                    resolvedAny = true
                    if Self.isBlockedIPv4(v4) { return true }
                } else if family == AF_INET6 {
                    let sin6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                    resolvedAny = true
                    if Self.isBlockedIPv6(sin6.sin6_addr) { return true }
                }
            }
            cursor = info.pointee.ai_next
        }
        return !resolvedAny
    }

    private func performSyncHTTPRequest(
        urlString: String,
        method: String = "GET",
        body: String? = nil,
        headers: [String: String] = [:],
        timeout: Double = 8.0,
        pluginId: String
    ) -> (status: Int, body: String?, error: String?) {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty else {
            return (0, nil, "Invalid URL")
        }
        if Self.isBlockedHost(host) {
            self.appendLog(pluginId: pluginId, message: "BLOCKED: SSRF to private host \(host)")
            return (0, nil, "Private/local network hosts are blocked")
        }
        if Thread.isMainThread {
            self.appendLog(pluginId: pluginId, message: "WARN: \(method) \(urlString) blocked on main thread")
            return (0, nil, "Network calls are blocked on main thread")
        }
        self.vmLock.lock()
        let insideRender = self.renderHookDepth > 0
        self.vmLock.unlock()
        if insideRender {
            self.appendLog(pluginId: pluginId, message: "BLOCKED: network call forbidden inside on_render_message")
            return (0, nil, "Network calls forbidden in on_render_message")
        }

        final class HTTPResponseBox: @unchecked Sendable {
            private let lock = NSLock()
            private var status: Int = 0
            private var body: String?
            private var error: String?

            func set(status: Int, body: String?, error: String?) {
                self.lock.lock()
                defer { self.lock.unlock() }
                self.status = status
                self.body = body
                self.error = error
            }

            func read() -> (Int, String?, String?) {
                self.lock.lock()
                defer { self.lock.unlock() }
                return (self.status, self.body, self.error)
            }
        }

        let sem = DispatchSemaphore(value: 0)
        let box = HTTPResponseBox()

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = min(20.0, max(1.0, timeout))
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        if let body, !body.isEmpty {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        let task = Self.pluginHTTPSession.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var respError: String?
            var respBody: String?
            if let error {
                respError = error.localizedDescription
            } else if let data, data.count <= 1_048_576 {
                respBody = String(data: data, encoding: .utf8)
            }
            box.set(status: status, body: respBody, error: respError)
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + min(21.0, max(1.5, timeout + 0.5))) == .timedOut {
            task.cancel()
            return (0, nil, "Request timed out")
        }
        return box.read()
    }

    private func makeHostAPI(
        pluginId: String,
        commandsBox: FullGramLoadedPlugin?,
        isSandboxTest: Bool = false,
        logCapture: ((String) -> Void)? = nil
    ) -> [String: FullGramPluginValue] {
        let storagePrefix = "fullgram.plugin.store.\(pluginId)."
        let sharedPrefix = "fullgram.plugin.shared."
        let grantedPermissions = Set((commandsBox?.descriptor.permissions ?? []).map { $0.lowercased() })
        let hasPermission: (String) -> Bool = { perm in
            return grantedPermissions.contains(perm) || grantedPermissions.contains("all") || grantedPermissions.contains("*")
        }
        let allowProfile = hasPermission("profile")
        let allowChat = hasPermission("chat")
        let allowClipboard = hasPermission("clipboard")
        let allowNetwork = !isSandboxTest && hasPermission("net")

        let logFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            let text = args.map { $0.asString }.joined(separator: " ")
            logCapture?(text)
            self?.appendLog(pluginId: pluginId, message: text)
            return .nil
        }

        let toastFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let text = args.first?.asString ?? ""
            guard !text.isEmpty else { return .nil }
            logCapture?("[toast] \(text)")
            if !isSandboxTest {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: FullGramPluginNotifications.toastRequested,
                        object: nil,
                        userInfo: ["text": text, "pluginId": pluginId]
                    )
                }
            }
            return .nil
        }

        let alertFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let title = args.first?.asString ?? "Плагин"
            let message = args.count > 1 ? args[1].asString : ""
            logCapture?("[alert] \(title): \(message)")
            if !isSandboxTest {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: FullGramPluginNotifications.alertRequested,
                        object: nil,
                        userInfo: ["title": title, "message": message, "pluginId": pluginId]
                    )
                }
            }
            return .bool(true)
        }

        let openUIFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let first = args.first ?? .nil
            var specDict: [String: Any] = ["pluginId": pluginId]
            switch first {
            case let .string(kind):
                specDict["kind"] = kind
            case let .table(box):
                if let dict = box.toJSONObject() as? [String: Any] {
                    for (k, v) in dict {
                        specDict[k] = v
                    }
                }
            default:
                break
            }
            logCapture?("[open_ui] \(specDict["kind"] ?? pluginId)")
            if !isSandboxTest {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: FullGramPluginNotifications.openUIRequested,
                        object: nil,
                        userInfo: specDict
                    )
                }
            }
            return .bool(true)
        }

        let clipboardSetFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard allowClipboard else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: clipboard_set requires @permission clipboard")
                return .bool(false)
            }
            let text = args.first?.asString ?? ""
            if !isSandboxTest {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        UIPasteboard.general.string = text
                    }
                }
            }
            return .bool(true)
        }

        let clipboardGetFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard allowClipboard else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: clipboard_get requires @permission clipboard")
                return .string("")
            }
            // Avoid DispatchQueue.main.sync while vmLock is held (deadlocks with main-thread hooks).
            guard Thread.isMainThread else {
                return .string("")
            }
            return MainActor.assumeIsolated {
                .string(UIPasteboard.general.string ?? "")
            }
        }

        let hapticFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let style = (args.first?.asString ?? "light").lowercased()
            if !isSandboxTest {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        switch style {
                        case "success":
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        case "warning":
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        case "error":
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        case "selection":
                            UISelectionFeedbackGenerator().selectionChanged()
                        case "medium":
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        case "heavy":
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        default:
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
            }
            return .bool(true)
        }

        let makeStorageGet: (String) -> ([FullGramPluginValue]) -> FullGramPluginValue = { prefix in
            return { args in
                let key = args.first?.asString ?? ""
                let fallback = args.count > 1 ? args[1] : .nil
                guard !key.isEmpty, let stored = UserDefaults.standard.object(forKey: prefix + key) else {
                    return fallback
                }
                if let data = stored as? Data,
                   let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    return FullGramPluginValue.fromJSONObject(obj, forPython: true)
                }
                return FullGramPluginValue.fromJSONObject(stored, forPython: true)
            }
        }

        let makeStorageSet: (String) -> ([FullGramPluginValue]) -> FullGramPluginValue = { prefix in
            return { args in
                guard !isSandboxTest else { return .bool(false) }
                let key = args.first?.asString ?? ""
                guard !key.isEmpty else { return .bool(false) }
                let val = args.count > 1 ? args[1] : .nil
                if case .nil = val {
                    UserDefaults.standard.removeObject(forKey: prefix + key)
                } else {
                    let obj = val.toJSONObject()
                    if JSONSerialization.isValidJSONObject(obj),
                       let data = try? JSONSerialization.data(withJSONObject: obj, options: []) {
                        UserDefaults.standard.set(data, forKey: prefix + key)
                    } else if obj is NSNull {
                        UserDefaults.standard.removeObject(forKey: prefix + key)
                    } else {
                        UserDefaults.standard.set(obj, forKey: prefix + key)
                    }
                }
                return .bool(true)
            }
        }

        let storageGetFn = makeStorageGet(storagePrefix)
        let storageSetFn = makeStorageSet(storagePrefix)
        let storageDeleteFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            guard !isSandboxTest else { return .bool(false) }
            let key = args.first?.asString ?? ""
            guard !key.isEmpty else { return .bool(false) }
            UserDefaults.standard.removeObject(forKey: storagePrefix + key)
            return .bool(true)
        }
        let storageKeysFn: ([FullGramPluginValue]) -> FullGramPluginValue = { _ in
            let keys = UserDefaults.standard.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(storagePrefix) }
                .map { String($0.dropFirst(storagePrefix.count)) }
                .sorted()
            return .table(FullGramPluginTableBox(array: keys.map { .string($0) }))
        }
        let storageClearFn: ([FullGramPluginValue]) -> FullGramPluginValue = { _ in
            guard !isSandboxTest else { return .bool(false) }
            let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(storagePrefix) }
            for k in keys { UserDefaults.standard.removeObject(forKey: k) }
            return .bool(true)
        }

        let sharedGetFn = makeStorageGet(sharedPrefix)
        let sharedSetFn = makeStorageSet(sharedPrefix)

        // Phone Time API
        let getTimeFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let ts = args.first?.asDouble
            let date = ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
            return .table(FullGramPluginTableBox(dict: FullGramPluginTimeHelper.buildPhoneTimeDict(date: date)))
        }
        let formatTimeFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let fmt = args.first.flatMap { val -> String? in
                if case .nil = val { return nil }
                return val.asString
            }
            let ts = args.count > 1 ? args[1].asDouble : nil
            let style = args.count > 2 ? args[2].asString : nil
            return .string(FullGramPluginTimeHelper.formatTime(format: fmt, timestamp: ts, style: style))
        }
        let stylizeTimeFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let text = args.first?.asString ?? ""
            let style = args.count > 1 ? args[1].asString : "bold"
            return .string(FullGramPluginTimeHelper.stylizeDigits(text, style: style))
        }

        // Device Info API
        let getDeviceInfoFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard let self else { return .table(FullGramPluginTableBox()) }
            return .table(FullGramPluginTableBox(dict: self.buildDeviceInfoDict()))
        }
        let getBatteryFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard let self else { return .table(FullGramPluginTableBox()) }
            let snap = self.currentDeviceSnapshot()
            return .table(FullGramPluginTableBox(dict: [
                "level": .int(Int64(snap.batteryLevel)),
                "percent": .int(Int64(snap.batteryLevel)),
                "state": .string(snap.batteryState),
                "is_charging": .bool(snap.isCharging),
                "is_low_power": .bool(ProcessInfo.processInfo.isLowPowerModeEnabled)
            ]))
        }

        // Profile & Nickname API
        let getProfileFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            return self?.currentProfile().toPluginValue(includePhone: allowProfile) ?? .table(FullGramPluginTableBox())
        }
        let setNicknameFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard allowProfile else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: set_nickname requires @permission profile")
                return .bool(false)
            }
            guard let self, let first = args.first?.asString else { return .bool(false) }
            let last = args.count > 1 ? (args[1].asString == "nil" ? "" : args[1].asString) : ""
            logCapture?("[set_nickname] \(first) \(last)")
            if isSandboxTest { return .bool(true) }
            return .bool(self.requestSetNickname(firstName: first, lastName: last, pluginId: pluginId))
        }
        let restoreNicknameFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard allowProfile else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: restore_nickname requires @permission profile")
                return .bool(false)
            }
            guard let self else { return .bool(false) }
            logCapture?("[restore_nickname]")
            if isSandboxTest { return .bool(true) }
            return .bool(self.restoreOriginalNickname(pluginId: pluginId))
        }
        let setUsernameFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard allowProfile else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: set_username requires @permission profile")
                return .bool(false)
            }
            guard let self else { return .bool(false) }
            let username = args.first?.asString ?? ""
            logCapture?("[set_username] \(username)")
            if isSandboxTest { return .bool(true) }
            return .bool(self.requestSetUsername(username, pluginId: pluginId))
        }
        let setBioFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard allowProfile else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: set_bio requires @permission profile")
                return .bool(false)
            }
            guard let self else { return .bool(false) }
            let bio = args.first?.asString ?? ""
            logCapture?("[set_bio] \(bio)")
            if isSandboxTest { return .bool(true) }
            return .bool(self.requestSetBio(bio, pluginId: pluginId))
        }
        let formatNickFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .string("") }
            let tpl = args.first?.asString ?? "{name} | ⌚ {time}"
            let style = args.count > 1 ? args[1].asString : "normal"
            let baseFirst = args.count > 2 ? args[2].asString : nil
            let pair = self.formatNicknameTemplate(tpl, baseFirstName: baseFirst, style: style)
            return .string(pair.lastName.isEmpty ? pair.firstName : "\(pair.firstName) \(pair.lastName)")
        }
        let applyNickTemplateFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard allowProfile else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: apply_nick_template requires @permission profile")
                return .bool(false)
            }
            guard let self else { return .bool(false) }
            let tpl = args.first?.asString ?? self.nickClockTemplate
            let style = args.count > 1 ? args[1].asString : self.nickClockStyle
            let baseFirst = args.count > 2 ? args[2].asString : nil
            let pair = self.formatNicknameTemplate(tpl, baseFirstName: baseFirst, style: style)
            logCapture?("[apply_nick_template] \(pair.firstName)")
            if isSandboxTest { return .bool(true) }
            return .bool(self.requestSetNickname(firstName: pair.firstName, lastName: pair.lastName, pluginId: pluginId))
        }

        // Background & Event Bus API
        let setIntervalFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .bool(false) }
            let sec = Int(args.first?.asInt ?? 30)
            let clamped = min(3600, max(5, sec))
            logCapture?("[set_interval] \(clamped)s")
            if !isSandboxTest {
                self.lock.lock()
                self.runtimeIntervalsByPlugin[pluginId] = clamped
                if let idx = self.descriptors.firstIndex(where: { $0.id == pluginId }) {
                    self.descriptors[idx].backgroundEnabled = true
                    self.descriptors[idx].backgroundInterval = clamped
                    self.persistLocked()
                }
                self.syncBackgroundSchedulerLocked()
                self.lock.unlock()
                self.postBackgroundStateChanged()
            }
            return .bool(true)
        }
        let stopIntervalFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard let self else { return .bool(false) }
            logCapture?("[stop_interval]")
            if !isSandboxTest {
                self.lock.lock()
                self.runtimeIntervalsByPlugin.removeValue(forKey: pluginId)
                if let idx = self.descriptors.firstIndex(where: { $0.id == pluginId }) {
                    self.descriptors[idx].backgroundEnabled = false
                    self.persistLocked()
                }
                self.syncBackgroundSchedulerLocked()
                self.lock.unlock()
                self.postBackgroundStateChanged()
            }
            return .bool(true)
        }
        let getBgStatusFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard let self else { return .table(FullGramPluginTableBox()) }
            self.lock.lock()
            let desc = self.descriptors.first(where: { $0.id == pluginId })
            let interval = self.runtimeIntervalsByPlugin[pluginId] ?? desc?.backgroundInterval ?? 30
            let ticks = self.tickCountByPlugin[pluginId] ?? 0
            let snap = self.deviceSnapshot
            let sysBg = self.isBackgroundExecutionEnabled
            self.lock.unlock()
            return .table(FullGramPluginTableBox(dict: [
                "system_enabled": .bool(sysBg),
                "plugin_enabled": .bool(desc?.backgroundEnabled ?? false),
                "interval": .int(Int64(interval)),
                "tick_count": .int(ticks),
                "app_state": .string(snap.appState),
                "in_background": .bool(snap.isBackground)
            ]))
        }
        let onEventFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self, weak commandsBox] args in
            guard let self, let commandsBox, args.count >= 2, case let .function(fn) = args[1] else { return .bool(false) }
            let eventName = args[0].asString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !eventName.isEmpty else { return .bool(false) }
            self.lock.lock()
            var list = commandsBox.eventListeners[eventName] ?? []
            list.append(fn)
            commandsBox.eventListeners[eventName] = list
            self.lock.unlock()
            return .bool(true)
        }
        let emitEventFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self, !isSandboxTest else { return .int(0) }
            let eventName = args.first?.asString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !eventName.isEmpty else { return .int(0) }
            let payload = args.count > 1 ? args[1] : .nil
            self.lock.lock()
            let plugins = self.cachedOrderedPlugins
            var targets: [(FullGramLoadedPlugin, [([FullGramPluginValue]) throws -> FullGramPluginValue])] = []
            for p in plugins {
                if let listeners = p.eventListeners[eventName], !listeners.isEmpty {
                    targets.append((p, listeners))
                }
            }
            self.lock.unlock()
            var count: Int64 = 0
            for (p, listeners) in targets {
                for fn in listeners {
                    do {
                        _ = try self.invokeCallable(fn, on: p, args: [payload])
                        count += 1
                    } catch {
                        self.appendLog(pluginId: p.descriptor.id, message: "Event '\(eventName)' error: \(error.localizedDescription)")
                    }
                }
            }
            return .int(count)
        }

        // Chat & Message API
        let registerCmdFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self, weak commandsBox] args in
            guard let self, let commandsBox, args.count >= 2, case let .function(fn) = args[1] else { return .nil }
            let raw = args[0].asString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cmd = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
            if !cmd.isEmpty {
                self.lock.lock()
                commandsBox.registeredCommands[cmd] = fn
                commandsBox.hasCommandHook = true
                self.lock.unlock()
            }
            return .nil
        }
        let getChatStatsFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard allowChat else {
                self?.appendLog(pluginId: pluginId, message: "BLOCKED: get_chat_stats requires @permission chat")
                return .nil
            }
            if let stats = Thread.current.threadDictionary[FullGramPluginManager.chatStatsThreadKey] as? [String: FullGramPluginValue] {
                return .table(FullGramPluginTableBox(dict: stats))
            }
            return .nil
        }
        let getActiveChatFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard let self else { return .nil }
            guard allowChat else {
                self.appendLog(pluginId: pluginId, message: "BLOCKED: get_active_chat requires @permission chat")
                return .nil
            }
            self.lock.lock()
            let fn = self.bridgeActiveChatInfo
            self.lock.unlock()
            if let info = fn?() {
                return .table(FullGramPluginTableBox(dict: info))
            }
            return .nil
        }
        let sendMessageFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .bool(false) }
            guard allowChat else {
                self.appendLog(pluginId: pluginId, message: "BLOCKED: send_message requires @permission chat")
                return .bool(false)
            }
            self.vmLock.lock()
            let insideRender = self.renderHookDepth > 0
            self.vmLock.unlock()
            guard !insideRender else { return .bool(false) }

            let text = args.first?.asString ?? ""
            guard !text.isEmpty else { return .bool(false) }
            let peerId = args.count > 1 ? args[1].asInt : nil
            logCapture?("[send_message] \(text)")
            if isSandboxTest { return .bool(true) }

            self.lock.lock()
            let bridge = self.bridgeSendMessage
            self.lock.unlock()
            if let bridge {
                return .bool(bridge(peerId, text))
            }
            var info: [String: Any] = ["text": text, "pluginId": pluginId]
            if let peerId { info["peerId"] = peerId }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: FullGramPluginNotifications.sendMessageRequested, object: nil, userInfo: info)
            }
            return .bool(true)
        }
        let setDraftFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .bool(false) }
            guard allowChat else {
                self.appendLog(pluginId: pluginId, message: "BLOCKED: set_draft requires @permission chat")
                return .bool(false)
            }
            let text = args.first?.asString ?? ""
            let peerId = args.count > 1 ? args[1].asInt : nil
            logCapture?("[set_draft] \(text)")
            if isSandboxTest { return .bool(true) }
            self.lock.lock()
            let bridge = self.bridgeSetDraft
            self.lock.unlock()
            if let bridge {
                return .bool(bridge(peerId, text))
            }
            var info: [String: Any] = ["text": text, "pluginId": pluginId]
            if let peerId { info["peerId"] = peerId }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: FullGramPluginNotifications.setDraftRequested, object: nil, userInfo: info)
            }
            return .bool(true)
        }

        // Network API
        let extractHeaders: (FullGramPluginValue?) -> [String: String] = { val in
            var dict: [String: String] = [:]
            if case let .table(box)? = val {
                for (k, v) in box.mapPart {
                    dict[k] = v.asString
                }
            }
            return dict
        }
        let httpGetFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .nil }
            guard allowNetwork else {
                self.appendLog(pluginId: pluginId, message: "BLOCKED: http_get requires @permission net")
                return .nil
            }
            let url = args.first?.asString ?? ""
            let headers = args.count > 1 ? extractHeaders(args[1]) : [:]
            let res = self.performSyncHTTPRequest(urlString: url, method: "GET", headers: headers, pluginId: pluginId)
            return res.body.map { .string($0) } ?? .nil
        }
        let httpPostFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .nil }
            guard allowNetwork else {
                self.appendLog(pluginId: pluginId, message: "BLOCKED: http_post requires @permission net")
                return .nil
            }
            let url = args.first?.asString ?? ""
            let body: String? = args.count > 1 ? (args[1].asString == "nil" ? nil : args[1].asString) : nil
            let headers = args.count > 2 ? extractHeaders(args[2]) : [:]
            let res = self.performSyncHTTPRequest(urlString: url, method: "POST", body: body, headers: headers, pluginId: pluginId)
            return res.body.map { .string($0) } ?? .nil
        }
        let httpRequestFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self, case let .table(box)? = args.first else {
                return .table(FullGramPluginTableBox(dict: ["ok": .bool(false), "status": .int(0), "error": .string("Invalid spec")]))
            }
            guard allowNetwork else {
                self.appendLog(pluginId: pluginId, message: "BLOCKED: http_request requires @permission net")
                return .table(FullGramPluginTableBox(dict: ["ok": .bool(false), "status": .int(0), "error": .string("Missing @permission net")]))
            }
            let url = box.get(key: .string("url")).asString
            let method = box.get(key: .string("method"))
            let methodStr = (method.isTruthy ? method.asString : "GET")
            let bodyVal = box.get(key: .string("body"))
            let bodyStr: String? = {
                if case .nil = bodyVal { return nil }
                if case let .table(b) = bodyVal {
                    let obj = b.toJSONObject()
                    if JSONSerialization.isValidJSONObject(obj),
                       let data = try? JSONSerialization.data(withJSONObject: obj),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                }
                return bodyVal.asString
            }()
            let headers = extractHeaders(box.get(key: .string("headers")))
            let timeout = box.get(key: .string("timeout")).asDouble ?? 8.0
            let res = self.performSyncHTTPRequest(urlString: url, method: methodStr, body: bodyStr, headers: headers, timeout: timeout, pluginId: pluginId)
            return .table(FullGramPluginTableBox(dict: [
                "ok": .bool((200 ..< 300).contains(res.status)),
                "status": .int(Int64(res.status)),
                "body": res.body.map { .string($0) } ?? .nil,
                "error": res.error.map { .string($0) } ?? .nil
            ]))
        }

        // Crypto & Encoding API
        let base64EncodeFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let data = (args.first?.asString ?? "").data(using: .utf8) ?? Data()
            return .string(data.base64EncodedString())
        }
        let base64DecodeFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            guard let data = Data(base64Encoded: args.first?.asString ?? ""),
                  let str = String(data: data, encoding: .utf8) else { return .nil }
            return .string(str)
        }
        let urlEncodeFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let s = args.first?.asString ?? ""
            return .string(s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)
        }
        let urlDecodeFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let s = args.first?.asString ?? ""
            return .string(s.removingPercentEncoding ?? s)
        }
        let sha256Fn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let data = Data((args.first?.asString ?? "").utf8)
            let digest = SHA256.hash(data: data)
            return .string(digest.map { String(format: "%02x", $0) }.joined())
        }
        let uuidFn: ([FullGramPluginValue]) -> FullGramPluginValue = { _ in
            return .string(UUID().uuidString)
        }

        // Namespaced modules (Plugin API v2.0)
        let profileNamespace = FullGramPluginTableBox(dict: [
            "get": .function(getProfileFn),
            "set_name": .function(setNicknameFn),
            "set_nickname": .function(setNicknameFn),
            "restore_name": .function(restoreNicknameFn),
            "restore_nickname": .function(restoreNicknameFn),
            "set_username": .function(setUsernameFn),
            "set_bio": .function(setBioFn),
            "format_nick": .function(formatNickFn),
            "apply_template": .function(applyNickTemplateFn)
        ])

        let timeNamespace = FullGramPluginTableBox(dict: [
            "now": .function(getTimeFn),
            "get": .function(getTimeFn),
            "format": .function(formatTimeFn),
            "stylize": .function(stylizeTimeFn),
            "timestamp": .function { _ in .double(Date().timeIntervalSince1970) },
            "unix_ms": .function { _ in .int(Int64(Date().timeIntervalSince1970 * 1000.0)) }
        ])

        let deviceNamespace = FullGramPluginTableBox(dict: [
            "info": .function(getDeviceInfoFn),
            "battery": .function(getBatteryFn),
            "haptic": .function(hapticFn),
            "app_state": .function { [weak self] _ in .string(self?.currentDeviceSnapshot().appState ?? "foreground") }
        ])

        let backgroundNamespace = FullGramPluginTableBox(dict: [
            "set_interval": .function(setIntervalFn),
            "stop_interval": .function(stopIntervalFn),
            "status": .function(getBgStatusFn),
            "on": .function(onEventFn),
            "emit": .function(emitEventFn)
        ])

        let chatNamespace = FullGramPluginTableBox(dict: [
            "send": .function(sendMessageFn),
            "set_draft": .function(setDraftFn),
            "active": .function(getActiveChatFn),
            "stats": .function(getChatStatsFn)
        ])

        let storageNamespace = FullGramPluginTableBox(dict: [
            "get": .function(storageGetFn),
            "set": .function(storageSetFn),
            "delete": .function(storageDeleteFn),
            "keys": .function(storageKeysFn),
            "clear": .function(storageClearFn),
            "shared_get": .function(sharedGetFn),
            "shared_set": .function(sharedSetFn)
        ])

        let netNamespace = FullGramPluginTableBox(dict: [
            "get": .function(httpGetFn),
            "post": .function(httpPostFn),
            "request": .function(httpRequestFn)
        ])

        let cryptoNamespace = FullGramPluginTableBox(dict: [
            "sha256": .function(sha256Fn),
            "base64_encode": .function(base64EncodeFn),
            "base64_decode": .function(base64DecodeFn),
            "url_encode": .function(urlEncodeFn),
            "url_decode": .function(urlDecodeFn),
            "uuid": .function(uuidFn)
        ])

        let uiNamespace = FullGramPluginTableBox(dict: [
            "log": .function(logFn),
            "toast": .function(toastFn),
            "alert": .function(alertFn),
            "open": .function(openUIFn),
            "notify": .function(toastFn),
            "clipboard_get": .function(clipboardGetFn),
            "clipboard_set": .function(clipboardSetFn)
        ])

        return [
            "api_version": .string("2.0"),
            "version": .string("2.0.0"),

            // Namespaced API v2.0 modules
            "profile": .table(profileNamespace),
            "time": .table(timeNamespace),
            "device": .table(deviceNamespace),
            "background": .table(backgroundNamespace),
            "chat": .table(chatNamespace),
            "storage": .table(storageNamespace),
            "net": .table(netNamespace),
            "crypto": .table(cryptoNamespace),
            "ui": .table(uiNamespace),

            // Flat API (v1 compatible + v2 extensions)
            "log": .function(logFn),
            "toast": .function(toastFn),
            "alert": .function(alertFn),
            "open_ui": .function(openUIFn),
            "system_notify": .function(toastFn),
            "clipboard_set": .function(clipboardSetFn),
            "clipboard_get": .function(clipboardGetFn),
            "haptic": .function(hapticFn),

            "storage_get": .function(storageGetFn),
            "storage_set": .function(storageSetFn),
            "storage_delete": .function(storageDeleteFn),
            "storage_keys": .function(storageKeysFn),
            "storage_clear": .function(storageClearFn),
            "shared_get": .function(sharedGetFn),
            "shared_set": .function(sharedSetFn),

            "get_time": .function(getTimeFn),
            "format_time": .function(formatTimeFn),
            "stylize_time": .function(stylizeTimeFn),
            "get_device_info": .function(getDeviceInfoFn),
            "get_battery": .function(getBatteryFn),

            "get_profile": .function(getProfileFn),
            "set_nickname": .function(setNicknameFn),
            "set_name": .function(setNicknameFn),
            "restore_nickname": .function(restoreNicknameFn),
            "set_username": .function(setUsernameFn),
            "set_bio": .function(setBioFn),
            "format_nick": .function(formatNickFn),
            "apply_nick_template": .function(applyNickTemplateFn),

            "set_interval": .function(setIntervalFn),
            "stop_interval": .function(stopIntervalFn),
            "get_background_status": .function(getBgStatusFn),
            "on_event": .function(onEventFn),
            "emit_event": .function(emitEventFn),

            "register_command": .function(registerCmdFn),
            "get_chat_stats": .function(getChatStatsFn),
            "get_active_chat": .function(getActiveChatFn),
            "send_message": .function(sendMessageFn),
            "set_draft": .function(setDraftFn),

            "http_get": .function(httpGetFn),
            "http_post": .function(httpPostFn),
            "http_request": .function(httpRequestFn),

            "base64_encode": .function(base64EncodeFn),
            "base64_decode": .function(base64DecodeFn),
            "url_encode": .function(urlEncodeFn),
            "url_decode": .function(urlDecodeFn),
            "sha256": .function(sha256Fn),
            "uuid": .function(uuidFn)
        ]
    }

    private func compile(descriptor: FullGramPluginDescriptor) -> FullGramLoadedPlugin {
        let holder = FullGramLoadedPlugin(descriptor: descriptor)
        let hostAPI = self.makeHostAPI(pluginId: descriptor.id, commandsBox: holder)

        let inspectBackgroundHook: ((String) -> Bool) -> String? = { hasFn in
            for candidate in ["on_background_tick", "on_tick", "on_timer"] {
                if hasFn(candidate) { return candidate }
            }
            return nil
        }

        do {
            switch descriptor.language {
            case .lua:
                let vm = FullGramLuaVM(hostAPI: hostAPI) { [weak self] msg in
                    self?.appendLog(pluginId: descriptor.id, message: msg)
                }
                try vm.load(code: descriptor.code)
                holder.luaVM = vm
                holder.hasOutgoingHook = vm.hasFunction("on_outgoing_message")
                holder.hasRenderHook = vm.hasFunction("on_render_message")
                holder.hasCommandHook = holder.hasCommandHook || vm.hasFunction("on_command")
                holder.hasMessageActionHook = vm.hasFunction("on_message_action")
                holder.backgroundHookName = inspectBackgroundHook { vm.hasFunction($0) }
                holder.hasBackgroundHook = holder.backgroundHookName != nil
                holder.hasAppStateHook = vm.hasFunction("on_app_state")
                holder.hasIncomingHook = vm.hasFunction("on_incoming_message")
                holder.hasLoadHook = vm.hasFunction("on_load")
                holder.hasUnloadHook = vm.hasFunction("on_unload")
            case .python:
                let vm = FullGramPythonVM(hostAPI: hostAPI) { [weak self] msg in
                    self?.appendLog(pluginId: descriptor.id, message: msg)
                }
                try vm.load(code: descriptor.code)
                holder.pythonVM = vm
                holder.hasOutgoingHook = vm.hasFunction("on_outgoing_message")
                holder.hasRenderHook = vm.hasFunction("on_render_message")
                holder.hasCommandHook = holder.hasCommandHook || vm.hasFunction("on_command")
                holder.hasMessageActionHook = vm.hasFunction("on_message_action")
                holder.backgroundHookName = inspectBackgroundHook { vm.hasFunction($0) }
                holder.hasBackgroundHook = holder.backgroundHookName != nil
                holder.hasAppStateHook = vm.hasFunction("on_app_state")
                holder.hasIncomingHook = vm.hasFunction("on_incoming_message")
                holder.hasLoadHook = vm.hasFunction("on_load")
                holder.hasUnloadHook = vm.hasFunction("on_unload")
            case .rust:
                let vm = FullGramRustVM(hostAPI: hostAPI) { [weak self] msg in
                    self?.appendLog(pluginId: descriptor.id, message: msg)
                }
                try vm.load(code: descriptor.code)
                holder.rustVM = vm
                holder.hasOutgoingHook = vm.hasFunction("on_outgoing_message")
                holder.hasRenderHook = vm.hasFunction("on_render_message")
                holder.hasCommandHook = holder.hasCommandHook || vm.hasFunction("on_command")
                holder.hasMessageActionHook = vm.hasFunction("on_message_action")
                holder.backgroundHookName = inspectBackgroundHook { vm.hasFunction($0) }
                holder.hasBackgroundHook = holder.backgroundHookName != nil
                holder.hasAppStateHook = vm.hasFunction("on_app_state")
                holder.hasIncomingHook = vm.hasFunction("on_incoming_message")
                holder.hasLoadHook = vm.hasFunction("on_load")
                holder.hasUnloadHook = vm.hasFunction("on_unload")
            }
        } catch {
            holder.lastError = error.localizedDescription
            self.appendLog(pluginId: descriptor.id, message: "ERROR: \(error.localizedDescription)")
        }
        return holder
    }

    public func hasMessageActionPlugins() -> Bool {
        self.ensureLoaded()
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.isSystemEnabled && self.loaded.values.contains(where: { $0.hasMessageActionHook })
    }

    public func availableCommands() -> [(command: String, description: String, pluginName: String)] {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled else {
            self.lock.unlock()
            return []
        }
        let active = self.descriptors.compactMap { desc -> (FullGramPluginDescriptor, FullGramLoadedPlugin, [String])? in
            guard let holder = self.loaded[desc.id] else { return nil }
            return (desc, holder, holder.registeredCommands.keys.sorted())
        }
        self.lock.unlock()

        var results: [(command: String, description: String, pluginName: String)] = []
        var seen = Set<String>()
        let regex = Self.commandHintRegex
        let plugRegex = Self.plugSubcommandRegex

        for (desc, _, commands) in active {
            for cmd in commands {
                if seen.insert(cmd).inserted {
                    results.append((cmd, desc.description, desc.name))
                }
            }
            if let plugRegex {
                let ns = desc.code as NSString
                for m in plugRegex.matches(in: desc.code, range: NSRange(location: 0, length: ns.length)) {
                    let sub = ns.substring(with: m.range(at: 1)).lowercased()
                    let fullCmd = "plug \(sub)"
                    if seen.insert(fullCmd).inserted {
                        results.append((fullCmd, desc.description, desc.name))
                    }
                }
            }
            if let regex {
                let ns = desc.code as NSString
                for m in regex.matches(in: desc.code, range: NSRange(location: 0, length: ns.length)) {
                    let cmd = ns.substring(with: m.range(at: 1)).lowercased()
                    if cmd == "plug" { continue }
                    if seen.insert(cmd).inserted {
                        results.append((cmd, desc.description, desc.name))
                    }
                }
            }
        }
        return results
    }

    public func runMessageAction(pluginId: String? = nil, text: String, peerId: Int64) -> String? {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled else {
            self.lock.unlock()
            return nil
        }
        let targets = self.descriptors.compactMap { desc -> FullGramLoadedPlugin? in
            if let pluginId, desc.id != pluginId { return nil }
            return self.loaded[desc.id]
        }
        self.lock.unlock()

        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        for plugin in targets {
            let ctx = FullGramPluginTableBox(dict: [
                "text": .string(text),
                "peer_id": .int(peerId)
            ])
            do {
                if let lua = plugin.luaVM, lua.hasFunction("on_message_action") {
                    let res = try lua.callFunction("on_message_action", args: [.table(ctx)])
                    if case let .string(out) = res, !out.isEmpty { return out }
                } else if let py = plugin.pythonVM, py.hasFunction("on_message_action") {
                    let res = try py.callFunction("on_message_action", args: [.table(ctx)])
                    if case let .string(out) = res, !out.isEmpty { return out }
                } else if let rs = plugin.rustVM, rs.hasFunction("on_message_action") {
                    let res = try rs.callFunction("on_message_action", args: [.table(ctx)])
                    if case let .string(out) = res, !out.isEmpty { return out }
                }
            } catch {
                self.appendLog(pluginId: plugin.descriptor.id, message: "Action error: \(error.localizedDescription)")
            }
        }
        return nil
    }

    /// Invokes `on_ui_event(ctx)` inside a Lua or Python plugin for two-way graphical UI interaction.
    public func dispatchUIEvent(
        pluginId: String,
        action: String,
        payload: [String: FullGramPluginValue] = [:]
    ) -> FullGramPluginValue {
        self.ensureLoaded()
        self.lock.lock()
        let holder = self.loaded[pluginId]
        self.lock.unlock()
        guard let holder else { return .nil }

        var dict = payload
        dict["action"] = .string(action)
        let ctx = FullGramPluginTableBox(dict: dict)
        self.vmLock.lock()
        defer { self.vmLock.unlock() }
        do {
            if let lua = holder.luaVM, lua.hasFunction("on_ui_event") {
                return try lua.callFunction("on_ui_event", args: [.table(ctx)])
            } else if let py = holder.pythonVM, py.hasFunction("on_ui_event") {
                return try py.callFunction("on_ui_event", args: [.table(ctx)])
            } else if let rs = holder.rustVM, rs.hasFunction("on_ui_event") {
                return try rs.callFunction("on_ui_event", args: [.table(ctx)])
            }
        } catch {
            self.appendLog(pluginId: pluginId, message: "UI event error: \(error.localizedDescription)")
        }
        return .nil
    }

    // MARK: - Execution Hooks

    public func processOutgoingMessage(
        text: String,
        peerId: Int64,
        isGroup: Bool = false,
        isChannel: Bool = false,
        chatStats: [String: FullGramPluginValue]? = nil
    ) -> FullGramPluginOutgoingDecision {
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled && !self.cachedOrderedPlugins.isEmpty else {
            self.lock.unlock()
            return .pass
        }
        let orderedPlugins = self.cachedOrderedPlugins
        self.lock.unlock()

        if let chatStats {
            Thread.current.threadDictionary[FullGramPluginManager.chatStatsThreadKey] = chatStats
        }
        defer {
            Thread.current.threadDictionary.removeObject(forKey: FullGramPluginManager.chatStatsThreadKey)
        }

        var currentText = text
        var didModify = false

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var commandName: String?
        var commandArgs: String = ""
        if trimmed.hasPrefix(".") && trimmed.count > 1 {
            let withoutDot = String(trimmed.dropFirst())
            if let spaceIdx = withoutDot.firstIndex(where: { $0.isWhitespace }) {
                commandName = String(withoutDot[..<spaceIdx]).lowercased()
                commandArgs = String(withoutDot[withoutDot.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            } else {
                commandName = withoutDot.lowercased()
            }
        }

        let subcommand: String = {
            guard !commandArgs.isEmpty else { return "" }
            if let sp = commandArgs.firstIndex(where: { $0.isWhitespace }) {
                return String(commandArgs[..<sp]).lowercased()
            }
            return commandArgs.lowercased()
        }()

        self.vmLock.lock()
        defer { self.vmLock.unlock() }

        for plugin in orderedPlugins {
            if let cmd = commandName, plugin.hasCommandHook {
                var ctxDict: [String: FullGramPluginValue] = [
                    "command": .string(cmd),
                    "subcommand": .string(subcommand),
                    "args": .string(commandArgs),
                    "text": .string(currentText),
                    "peer_id": .int(peerId),
                    "is_group": .bool(isGroup),
                    "is_channel": .bool(isChannel)
                ]
                if let chatStats {
                    ctxDict["chat_stats"] = .table(FullGramPluginTableBox(dict: chatStats))
                }
                let ctxTable = FullGramPluginTableBox(dict: ctxDict)
                do {
                    var result: FullGramPluginValue = .nil
                    if let registeredFn = plugin.registeredCommands[cmd] {
                        result = try self.invokeCallable(registeredFn, on: plugin, args: [.table(ctxTable)])
                    } else if let lua = plugin.luaVM, lua.hasFunction("on_command") {
                        result = try lua.callFunction("on_command", args: [.table(ctxTable)])
                    } else if let py = plugin.pythonVM, py.hasFunction("on_command") {
                        result = try py.callFunction("on_command", args: [.table(ctxTable)])
                    } else if let rs = plugin.rustVM, rs.hasFunction("on_command") {
                        result = try rs.callFunction("on_command", args: [.table(ctxTable)])
                    }
                    switch self.interpretDecision(result) {
                    case .pass:
                        break
                    case let .replaceText(newText):
                        currentText = newText
                        didModify = true
                        commandName = nil
                    case let .cancel(toast):
                        return .cancel(toast: toast)
                    }
                } catch {
                    self.appendLog(pluginId: plugin.descriptor.id, message: "Command error: \(error.localizedDescription)")
                }
            }

            if plugin.hasOutgoingHook {
                let ctxTable = FullGramPluginTableBox(dict: [
                    "text": .string(currentText),
                    "peer_id": .int(peerId),
                    "is_group": .bool(isGroup),
                    "is_channel": .bool(isChannel)
                ])
                do {
                    let result: FullGramPluginValue
                    if let lua = plugin.luaVM {
                        result = try lua.callFunction("on_outgoing_message", args: [.table(ctxTable)])
                    } else if let py = plugin.pythonVM {
                        result = try py.callFunction("on_outgoing_message", args: [.table(ctxTable)])
                    } else if let rs = plugin.rustVM {
                        result = try rs.callFunction("on_outgoing_message", args: [.table(ctxTable)])
                    } else {
                        continue
                    }
                    switch self.interpretDecision(result) {
                    case .pass:
                        break
                    case let .replaceText(newText):
                        if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            currentText = newText
                            didModify = true
                        }
                    case let .cancel(toast):
                        return .cancel(toast: toast)
                    }
                } catch {
                    self.appendLog(pluginId: plugin.descriptor.id, message: "Outgoing hook error: \(error.localizedDescription)")
                }
            }
        }

        return didModify ? .replaceText(currentText) : .pass
    }

    public func processRenderMessage(
        text: String,
        peerId: Int64,
        isIncoming: Bool,
        messageId: Int32
    ) -> String {
        guard !text.isEmpty else { return text }
        self.ensureLoaded()
        self.lock.lock()
        guard self.isSystemEnabled && self.hasRenderHooks && !self.cachedRenderPlugins.isEmpty else {
            self.lock.unlock()
            return text
        }
        let renderPlugins = self.cachedRenderPlugins
        self.lock.unlock()

        self.vmLock.lock()
        self.renderHookDepth += 1
        defer {
            self.renderHookDepth = max(0, self.renderHookDepth - 1)
            self.vmLock.unlock()
        }

        var currentText = text
        for plugin in renderPlugins {
            let ctxTable = FullGramPluginTableBox(dict: [
                "text": .string(currentText),
                "peer_id": .int(peerId),
                "is_incoming": .bool(isIncoming),
                "message_id": .int(Int64(messageId))
            ])
            do {
                let result: FullGramPluginValue
                if let lua = plugin.luaVM {
                    result = try lua.callFunction("on_render_message", args: [.table(ctxTable)])
                } else if let py = plugin.pythonVM {
                    result = try py.callFunction("on_render_message", args: [.table(ctxTable)])
                } else if let rs = plugin.rustVM {
                    result = try rs.callFunction("on_render_message", args: [.table(ctxTable)])
                } else {
                    continue
                }
                if case let .string(updated) = result {
                    currentText = updated
                }
            } catch {
                self.appendLog(pluginId: plugin.descriptor.id, message: "Render hook error: \(error.localizedDescription)")
            }
        }
        return currentText
    }

    public func testExecute(
        code: String,
        language: FullGramPluginLanguage,
        sampleInput: String = ".shrug проверка"
    ) -> (output: String, logs: [String], error: String?) {
        var capturedLogs: [String] = []
        let meta = FullGramPluginMetadata.parse(from: code, fallbackName: "Test", language: language)
        let holder = FullGramLoadedPlugin(descriptor: FullGramPluginDescriptor(id: "__test__", name: "Test", language: language, code: code, permissions: meta.permissions))
        let hostAPI = self.makeHostAPI(pluginId: "__test__", commandsBox: holder, isSandboxTest: true) { line in
            capturedLogs.append(line)
        }

        do {
            let trimmed = sampleInput.trimmingCharacters(in: .whitespacesAndNewlines)
            var cmd = ""
            var argsStr = ""
            if trimmed.hasPrefix(".") && trimmed.count > 1 {
                let withoutDot = String(trimmed.dropFirst())
                if let sp = withoutDot.firstIndex(where: { $0.isWhitespace }) {
                    cmd = String(withoutDot[..<sp]).lowercased()
                    argsStr = String(withoutDot[withoutDot.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    cmd = withoutDot.lowercased()
                }
            }
            let subcmd = argsStr.split(separator: " ").first.map { String($0).lowercased() } ?? ""
            let ctxTable = FullGramPluginTableBox(dict: [
                "text": .string(sampleInput),
                "command": .string(cmd),
                "subcommand": .string(subcmd),
                "args": .string(argsStr),
                "peer_id": .int(0),
                "is_group": .bool(false),
                "is_channel": .bool(false)
            ])
            switch language {
            case .lua:
                let vm = FullGramLuaVM(hostAPI: hostAPI) { line in
                    capturedLogs.append(line)
                }
                try vm.load(code: code)
                var resultText = ""
                if !cmd.isEmpty {
                    if let fn = holder.registeredCommands[cmd] {
                        resultText = try vm.invoke(fn, args: [.table(ctxTable)]).asString
                    } else if vm.hasFunction("on_command") {
                        resultText = try vm.callFunction("on_command", args: [.table(ctxTable)]).asString
                    }
                }
                if resultText.isEmpty && vm.hasFunction("on_outgoing_message") {
                    resultText = try vm.callFunction("on_outgoing_message", args: [.table(ctxTable)]).asString
                }
                return (resultText, capturedLogs, nil)
            case .python:
                let vm = FullGramPythonVM(hostAPI: hostAPI) { line in
                    capturedLogs.append(line)
                }
                try vm.load(code: code)
                var resultText = ""
                if !cmd.isEmpty {
                    if let fn = holder.registeredCommands[cmd] {
                        resultText = try vm.invoke(fn, args: [.table(ctxTable)]).asString
                    } else if vm.hasFunction("on_command") {
                        resultText = try vm.callFunction("on_command", args: [.table(ctxTable)]).asString
                    }
                }
                if resultText.isEmpty && vm.hasFunction("on_outgoing_message") {
                    resultText = try vm.callFunction("on_outgoing_message", args: [.table(ctxTable)]).asString
                }
                return (resultText, capturedLogs, nil)
            case .rust:
                let vm = FullGramRustVM(hostAPI: hostAPI) { line in
                    capturedLogs.append(line)
                }
                try vm.load(code: code)
                var resultText = ""
                if !cmd.isEmpty {
                    if let fn = holder.registeredCommands[cmd] {
                        resultText = try vm.invoke(fn, args: [.table(ctxTable)]).asString
                    } else if vm.hasFunction("on_command") {
                        resultText = try vm.callFunction("on_command", args: [.table(ctxTable)]).asString
                    }
                }
                if resultText.isEmpty && vm.hasFunction("on_outgoing_message") {
                    resultText = try vm.callFunction("on_outgoing_message", args: [.table(ctxTable)]).asString
                }
                return (resultText, capturedLogs, nil)
            }
        } catch {
            return ("", capturedLogs, error.localizedDescription)
        }
    }

    public func testBackgroundTick(
        code: String,
        language: FullGramPluginLanguage
    ) -> (output: String, logs: [String], error: String?) {
        var capturedLogs: [String] = []
        let meta = FullGramPluginMetadata.parse(from: code, fallbackName: "BgTest", language: language)
        let hasProfilePerm = meta.permissions.contains {
            let p = $0.lowercased()
            return p == "profile" || p == "all" || p == "*"
        }
        let holder = FullGramLoadedPlugin(descriptor: FullGramPluginDescriptor(id: "__test_bg__", name: "BgTest", language: language, code: code, permissions: meta.permissions))
        let hostAPI = self.makeHostAPI(pluginId: "__test_bg__", commandsBox: holder, isSandboxTest: true) { line in
            capturedLogs.append(line)
        }
        let snap = self.currentDeviceSnapshot()
        let ctx = FullGramPluginTableBox(dict: [
            "tick": .int(1),
            "interval": .int(30),
            "in_background": .bool(snap.isBackground),
            "app_state": .string(snap.appState),
            "time": .table(FullGramPluginTableBox(dict: FullGramPluginTimeHelper.buildPhoneTimeDict())),
            "profile": self.currentProfile().toPluginValue(includePhone: hasProfilePerm),
            "device": .table(FullGramPluginTableBox(dict: self.buildDeviceInfoDict()))
        ])

        do {
            let candidates = ["on_background_tick", "on_tick", "on_timer"]
            switch language {
            case .lua:
                let vm = FullGramLuaVM(hostAPI: hostAPI) { line in capturedLogs.append(line) }
                try vm.load(code: code)
                for name in candidates where vm.hasFunction(name) {
                    let res = try vm.callFunction(name, args: [.table(ctx)])
                    return (res.asString, capturedLogs, nil)
                }
                return ("", capturedLogs, "Функция on_background_tick(ctx) не найдена в плагине.")
            case .python:
                let vm = FullGramPythonVM(hostAPI: hostAPI) { line in capturedLogs.append(line) }
                try vm.load(code: code)
                for name in candidates where vm.hasFunction(name) {
                    let res = try vm.callFunction(name, args: [.table(ctx)])
                    return (res.asString, capturedLogs, nil)
                }
                return ("", capturedLogs, "Функция on_background_tick(ctx) не найдена в плагине.")
            case .rust:
                let vm = FullGramRustVM(hostAPI: hostAPI) { line in capturedLogs.append(line) }
                try vm.load(code: code)
                for name in candidates where vm.hasFunction(name) {
                    let res = try vm.callFunction(name, args: [.table(ctx)])
                    return (res.asString, capturedLogs, nil)
                }
                return ("", capturedLogs, "Функция on_background_tick(ctx) не найдена в плагине.")
            }
        } catch {
            return ("", capturedLogs, error.localizedDescription)
        }
    }

    private func interpretDecision(_ value: FullGramPluginValue) -> FullGramPluginOutgoingDecision {
        switch value {
        case .nil:
            return .pass
        case let .string(s):
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .pass
            }
            return .replaceText(s)
        case let .table(box):
            let cancelVal = box.get(key: .string("cancel"))
            let toastVal = box.get(key: .string("toast"))
            let toastStr: String? = {
                if case let .string(s) = toastVal, !s.isEmpty { return s }
                return nil
            }()
            if cancelVal.isTruthy {
                return .cancel(toast: toastStr)
            }
            if case let .string(newText) = box.get(key: .string("text")) {
                if let toastStr {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: FullGramPluginNotifications.toastRequested, object: nil, userInfo: ["text": toastStr])
                    }
                }
                if newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .pass
                }
                return .replaceText(newText)
            }
            return .pass
        default:
            return .pass
        }
    }

    // MARK: - Remote Plugin Market

    public func fetchRemoteCatalog(urlString: String? = nil, completion: @escaping @Sendable (Result<FullGramRemoteCatalog, Error>) -> Void) {
        let targetString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveString = (targetString?.isEmpty == false) ? targetString! : self.catalogURL
        guard let url = URL(string: effectiveString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !Self.isBlockedHost(host) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramPlugins", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес каталога плагинов."])))
            }
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Self.pluginHTTPSession.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ..< 300).contains(status), let data, data.count <= 2_097_152 else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FullGramPlugins", code: status, userInfo: [NSLocalizedDescriptionKey: "Сервер вернул код \(status) или слишком большой каталог."])))
                }
                return
            }
            do {
                let catalog = try JSONDecoder().decode(FullGramRemoteCatalog.self, from: data)
                DispatchQueue.main.async { completion(.success(catalog)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    public func installRemotePlugin(
        _ item: FullGramRemotePluginItem,
        enableImmediately: Bool,
        completion: @escaping @Sendable (Result<FullGramPluginDescriptor, Error>) -> Void
    ) {
        if let inlineCode = item.code, !inlineCode.isEmpty {
            let saved = self.savePlugin(id: item.id, name: item.name, language: item.language, code: inlineCode, enabled: enableImmediately)
            DispatchQueue.main.async { completion(.success(saved)) }
            return
        }
        guard let rawUrl = item.url,
              let url = URL(string: rawUrl),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !Self.isBlockedHost(host) else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramPlugins", code: 400, userInfo: [NSLocalizedDescriptionKey: "У плагина отсутствует корректная ссылка на скрипт."])))
            }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Self.pluginHTTPSession.dataTask(with: req) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ..< 300).contains(status),
                  let data,
                  data.count <= 1_048_576,
                  let scriptCode = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FullGramPlugins", code: status, userInfo: [NSLocalizedDescriptionKey: "Не удалось скачать скрипт плагина (HTTP \(status))."])))
                }
                return
            }
            let saved = self.savePlugin(id: item.id, name: item.name, language: item.language, code: scriptCode, enabled: enableImmediately)
            DispatchQueue.main.async { completion(.success(saved)) }
        }.resume()
    }
}
