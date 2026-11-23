import Foundation
import UIKit
import CryptoKit

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

    public func toPluginValue() -> FullGramPluginValue {
        return .table(FullGramPluginTableBox(dict: [
            "id": .int(self.peerId),
            "peer_id": .int(self.peerId),
            "first_name": .string(self.firstName),
            "last_name": .string(self.lastName),
            "full_name": .string(self.fullName),
            "name": .string(self.fullName),
            "username": .string(self.username),
            "bio": .string(self.bio),
            "phone": .string(self.phone),
            "original_first_name": .string(self.originalFirstName),
            "original_last_name": .string(self.originalLastName),
            "updated_at": .double(self.updatedAt)
        ]))
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

        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.timeZone = tz
        df.dateFormat = "EEEE"
        let weekdayName = df.string(from: date).capitalized
        df.dateFormat = "EEE"
        let weekdayShort = df.string(from: date).capitalized
        df.dateFormat = "MMMM"
        let monthName = df.string(from: date).capitalized

        let offsetSec = tz.secondsFromGMT(for: date)
        let sign = offsetSec >= 0 ? "+" : "-"
        let absOff = abs(offsetSec)
        let offsetStr = String(format: "%@%02d:%02d", sign, absOff / 3600, (absOff % 3600) / 60)

        let jFmt = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? "HH"
        let is24h = !jFmt.contains("a")
        let iso = ISO8601DateFormatter().string(from: date)

        return [
            "timestamp": .double(date.timeIntervalSince1970),
            "unix": .int(Int64(date.timeIntervalSince1970)),
            "unix_ms": .int(Int64(date.timeIntervalSince1970 * 1000.0)),
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

    public static func formatTime(format: String?, timestamp: Double?, style: String?) -> String {
        let date = timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date()
        let df = DateFormatter()
        df.locale = Locale.current
        df.timeZone = TimeZone.current
        df.dateFormat = (format?.isEmpty == false) ? format! : "dd.MM.yyyy HH:mm:ss"
        let rendered = df.string(from: date)
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

private final class FullGramLoadedPlugin {
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

public final class FullGramPluginManager {
    public static let shared = FullGramPluginManager()
    public static let officialCatalogURL = "https://fullgram.korsakovx.workers.dev/plugins.json"

    private struct DeviceSnapshot {
        var model: String = UIDevice.current.model
        var systemName: String = UIDevice.current.systemName
        var systemVersion: String = UIDevice.current.systemVersion
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

    private var descriptors: [FullGramPluginDescriptor] = []
    private var loaded: [String: FullGramLoadedPlugin] = [:]
    private var cachedOrderedPlugins: [FullGramLoadedPlugin] = []
    private var cachedRenderPlugins: [FullGramLoadedPlugin] = []
    private var logsByPlugin: [String: [String]] = [:]
    private var cachedSystemEnabled: Bool?
    private var cachedBackgroundEnabled: Bool?
    private var hasRenderHooks: Bool = false
    private var didInitialize = false
    private var isInsideRenderHook = false

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

    private func ensureLoaded() {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.didInitialize else { return }
        self.didInitialize = true

        self.registerLifecycleObserversIfNeeded()

        if let data = try? Data(contentsOf: self.manifestURL),
           let decoded = try? JSONDecoder().decode([FullGramPluginDescriptor].self, from: data) {
            var restored: [FullGramPluginDescriptor] = []
            for var item in decoded {
                let scriptURL = self.pluginsDirectoryURL.appendingPathComponent("\(item.id).\(item.language.fileExtension)")
                if let diskCode = try? String(contentsOf: scriptURL, encoding: .utf8), !diskCode.isEmpty {
                    item.code = diskCode
                }
                restored.append(item)
            }
            self.descriptors = restored
        }

        let starters = Self.defaultStarterPlugins()
        if self.descriptors.isEmpty {
            self.descriptors = starters
            self.persistLocked()
        } else {
            var existingIds = Set(self.descriptors.map { $0.id })
            var changed = false
            for starter in starters {
                if !existingIds.contains(starter.id) {
                    self.descriptors.append(starter)
                    existingIds.insert(starter.id)
                    changed = true
                } else if let idx = self.descriptors.firstIndex(where: { $0.id == starter.id }),
                          self.descriptors[idx].version != starter.version {
                    let wasEnabled = self.descriptors[idx].isEnabled
                    var updated = starter
                    updated.isEnabled = wasEnabled
                    self.descriptors[idx] = updated
                    changed = true
                }
            }
            if changed {
                self.persistLocked()
            }
        }
        self.reloadRuntimeLocked()
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
        self.reloadRuntimeLocked()
        self.lock.unlock()

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
        if let idx = self.descriptors.firstIndex(where: { $0.id == id }) {
            self.descriptors[idx].isEnabled = enabled
            self.persistLocked()
            self.reloadRuntimeLocked()
        }
        self.lock.unlock()
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
        self.lock.lock()
        if let idx = self.descriptors.firstIndex(where: { $0.id == id }) {
            if let old = self.loaded[id], old.hasUnloadHook {
                self.invokeLifecycleHook(plugin: old, name: "on_unload", args: [])
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
        self.postPluginsDidChange()
    }

    public func importPlugin(from url: URL, preferredFileName: String? = nil) throws -> FullGramPluginDescriptor {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let code = try String(contentsOf: url, encoding: .utf8)
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
        self.reloadRuntimeLocked()
        self.lock.unlock()
    }

    private func reloadRuntimeLocked() {
        for old in self.cachedOrderedPlugins where old.hasUnloadHook {
            self.invokeLifecycleHook(plugin: old, name: "on_unload", args: [])
        }
        self.loaded.removeAll()
        self.cachedOrderedPlugins.removeAll()
        self.cachedRenderPlugins.removeAll()
        self.hasRenderHooks = false
        guard self.isSystemEnabled else {
            self.syncBackgroundSchedulerLocked()
            return
        }

        var anyRender = false
        for descriptor in self.descriptors where descriptor.isEnabled {
            let runtime = self.compile(descriptor: descriptor)
            if runtime.hasRenderHook {
                anyRender = true
                self.cachedRenderPlugins.append(runtime)
            }
            self.loaded[descriptor.id] = runtime
            self.cachedOrderedPlugins.append(runtime)
        }
        self.hasRenderHooks = anyRender

        for plugin in self.cachedOrderedPlugins where plugin.hasLoadHook {
            self.invokeLifecycleHook(plugin: plugin, name: "on_load", args: [])
        }
        self.syncBackgroundSchedulerLocked()
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

        let timeTable = FullGramPluginTableBox(dict: FullGramPluginTimeHelper.buildPhoneTimeDict())
        let ctx = FullGramPluginTableBox(dict: [
            "state": .string(state),
            "in_background": .bool(state == "background"),
            "time": .table(timeTable)
        ])
        for plugin in targets {
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
            let profileVal = self.currentProfile().toPluginValue()
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

        let ctx = FullGramPluginTableBox(dict: [
            "text": .string(text),
            "peer_id": .int(peerId),
            "sender_name": .string(senderName),
            "timestamp": .int(Int64(timestamp)),
            "is_group": .bool(isGroup),
            "is_channel": .bool(isChannel),
            "time": .table(FullGramPluginTableBox(dict: FullGramPluginTimeHelper.buildPhoneTimeDict()))
        ])
        self.backgroundQueue.async { [weak self] in
            guard let self else { return }
            for plugin in targets {
                self.invokeLifecycleHook(plugin: plugin, name: "on_incoming_message", args: [.table(ctx)])
            }
        }
    }

    private static let chatStatsThreadKey = "FullGram.Plugin.ChatStats"

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
              scheme == "https" || scheme == "http" else {
            return (0, nil, "Invalid URL")
        }
        if Thread.isMainThread {
            self.appendLog(pluginId: pluginId, message: "WARN: \(method) \(urlString) blocked on main thread")
            return (0, nil, "Network calls are blocked on main thread")
        }
        self.vmLock.lock()
        let insideRender = self.isInsideRenderHook
        self.vmLock.unlock()
        if insideRender {
            self.appendLog(pluginId: pluginId, message: "BLOCKED: network call forbidden inside on_render_message")
            return (0, nil, "Network calls forbidden in on_render_message")
        }

        let sem = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var respBody: String?
        var respStatus = 0
        var respError: String?

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

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            boxLock.lock()
            respStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                respError = error.localizedDescription
            } else if let data, data.count <= 1_048_576 {
                respBody = String(data: data, encoding: .utf8)
            }
            boxLock.unlock()
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + min(21.0, max(1.5, timeout + 0.5))) == .timedOut {
            task.cancel()
            return (0, nil, "Request timed out")
        }
        boxLock.lock()
        let result = (respStatus, respBody, respError)
        boxLock.unlock()
        return result
    }

    private func makeHostAPI(
        pluginId: String,
        commandsBox: FullGramLoadedPlugin?,
        isSandboxTest: Bool = false,
        logCapture: ((String) -> Void)? = nil
    ) -> [String: FullGramPluginValue] {
        let storagePrefix = "fullgram.plugin.store.\(pluginId)."
        let sharedPrefix = "fullgram.plugin.shared."

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

        let clipboardSetFn: ([FullGramPluginValue]) -> FullGramPluginValue = { args in
            let text = args.first?.asString ?? ""
            if !isSandboxTest {
                DispatchQueue.main.async {
                    UIPasteboard.general.string = text
                }
            }
            return .bool(true)
        }

        let clipboardGetFn: ([FullGramPluginValue]) -> FullGramPluginValue = { _ in
            if Thread.isMainThread {
                return .string(UIPasteboard.general.string ?? "")
            }
            var val = ""
            DispatchQueue.main.sync {
                val = UIPasteboard.general.string ?? ""
            }
            return .string(val)
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
            return self?.currentProfile().toPluginValue() ?? .table(FullGramPluginTableBox())
        }
        let setNicknameFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self, let first = args.first?.asString else { return .bool(false) }
            let last = args.count > 1 ? (args[1].asString == "nil" ? "" : args[1].asString) : ""
            logCapture?("[set_nickname] \(first) \(last)")
            if isSandboxTest { return .bool(true) }
            return .bool(self.requestSetNickname(firstName: first, lastName: last, pluginId: pluginId))
        }
        let restoreNicknameFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard let self else { return .bool(false) }
            logCapture?("[restore_nickname]")
            if isSandboxTest { return .bool(true) }
            return .bool(self.restoreOriginalNickname(pluginId: pluginId))
        }
        let setUsernameFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .bool(false) }
            let username = args.first?.asString ?? ""
            logCapture?("[set_username] \(username)")
            if isSandboxTest { return .bool(true) }
            return .bool(self.requestSetUsername(username, pluginId: pluginId))
        }
        let setBioFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
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
        let onEventFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak commandsBox] args in
            guard args.count >= 2, case let .function(fn) = args[1] else { return .bool(false) }
            let eventName = args[0].asString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !eventName.isEmpty else { return .bool(false) }
            var list = commandsBox?.eventListeners[eventName] ?? []
            list.append(fn)
            commandsBox?.eventListeners[eventName] = list
            return .bool(true)
        }
        let emitEventFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .int(0) }
            let eventName = args.first?.asString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !eventName.isEmpty else { return .int(0) }
            let payload = args.count > 1 ? args[1] : .nil
            self.lock.lock()
            let plugins = self.cachedOrderedPlugins
            self.lock.unlock()
            var count: Int64 = 0
            for p in plugins {
                if let listeners = p.eventListeners[eventName] {
                    for fn in listeners {
                        do {
                            _ = try fn([payload])
                            count += 1
                        } catch {
                            self.appendLog(pluginId: p.descriptor.id, message: "Event '\(eventName)' error: \(error.localizedDescription)")
                        }
                    }
                }
            }
            return .int(count)
        }

        // Chat & Message API
        let registerCmdFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak commandsBox] args in
            guard args.count >= 2, case let .function(fn) = args[1] else { return .nil }
            let raw = args[0].asString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cmd = raw.hasPrefix(".") ? String(raw.dropFirst()) : raw
            if !cmd.isEmpty {
                commandsBox?.registeredCommands[cmd] = fn
                commandsBox?.hasCommandHook = true
            }
            return .nil
        }
        let getChatStatsFn: ([FullGramPluginValue]) -> FullGramPluginValue = { _ in
            if let stats = Thread.current.threadDictionary[FullGramPluginManager.chatStatsThreadKey] as? [String: FullGramPluginValue] {
                return .table(FullGramPluginTableBox(dict: stats))
            }
            return .nil
        }
        let getActiveChatFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] _ in
            guard let self else { return .nil }
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
            self.vmLock.lock()
            let insideRender = self.isInsideRenderHook
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
            let url = args.first?.asString ?? ""
            let headers = args.count > 1 ? extractHeaders(args[1]) : [:]
            let res = self.performSyncHTTPRequest(urlString: url, method: "GET", headers: headers, pluginId: pluginId)
            return res.body.map { .string($0) } ?? .nil
        }
        let httpPostFn: ([FullGramPluginValue]) -> FullGramPluginValue = { [weak self] args in
            guard let self else { return .nil }
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
        let active = self.descriptors.compactMap { desc -> (FullGramPluginDescriptor, FullGramLoadedPlugin)? in
            guard let holder = self.loaded[desc.id] else { return nil }
            return (desc, holder)
        }
        self.lock.unlock()

        var results: [(command: String, description: String, pluginName: String)] = []
        var seen = Set<String>()
        let regex = Self.commandHintRegex
        let plugRegex = Self.plugSubcommandRegex

        for (desc, holder) in active {
            for cmd in holder.registeredCommands.keys.sorted() {
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

        let ctx = FullGramPluginTableBox(dict: [
            "text": .string(text),
            "peer_id": .int(peerId)
        ])
        for plugin in targets {
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
                        result = try registeredFn([.table(ctxTable)])
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
        self.isInsideRenderHook = true
        defer {
            self.isInsideRenderHook = false
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
        let holder = FullGramLoadedPlugin(descriptor: FullGramPluginDescriptor(id: "__test__", name: "Test", language: language, code: code))
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
                        resultText = try fn([.table(ctxTable)]).asString
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
                        resultText = try fn([.table(ctxTable)]).asString
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
                        resultText = try fn([.table(ctxTable)]).asString
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
        let holder = FullGramLoadedPlugin(descriptor: FullGramPluginDescriptor(id: "__test_bg__", name: "BgTest", language: language, code: code))
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
            "profile": self.currentProfile().toPluginValue(),
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

    // MARK: - Built-in Starter Plugins

    private static func defaultStarterPlugins() -> [FullGramPluginDescriptor] {
        let luaCommands = """
-- @name Быстрые команды
-- @id fg_quick_commands
-- @version 1.0
-- @author FullGram
-- @description Команды .shrug, .lenny, .flip и .hug в любом чате

function on_command(ctx)
    local cmd = ctx.command
    local args = ctx.args
    if cmd == "shrug" then
        local tail = args ~= "" and (args .. " ") or ""
        return tail .. "¯\\\\_(ツ)_/¯"
    elseif cmd == "lenny" then
        local tail = args ~= "" and (args .. " ") or ""
        return tail .. "( ͡° ͜ʖ ͡°)"
    elseif cmd == "flip" then
        return "(╯°□°)╯︵ ┻━┻"
    elseif cmd == "unflip" then
        return "┬─┬ノ( º _ ºノ)"
    elseif cmd == "hug" then
        return "(づ｡◕‿‿◕｡)づ " .. args
    end
    return nil
end
"""

        let luaCalc = """
-- @name Калькулятор и рандом
-- @id fg_inline_calc
-- @version 1.0
-- @author FullGram
-- @description Команды .roll [макс] и .calc [число +-*/ число]

function on_command(ctx)
    if ctx.command == "roll" then
        local limit = tonumber(ctx.args) or 100
        if limit < 2 then limit = 100 end
        local val = math.random(1, limit)
        return "🎲 Выпало: " .. tostring(val) .. " (из " .. tostring(limit) .. ")"
    elseif ctx.command == "calc" then
        local a = string.match(ctx.args, "^%s*(-?[%d%.]+)")
        local op = string.match(ctx.args, "([%+%-%*/])")
        local b = string.match(ctx.args, "([%d%.]+)%s*$")
        if a and op and b then
            local x = tonumber(a)
            local y = tonumber(b)
            local res = 0
            if op == "+" then res = x + y
            elseif op == "-" then res = x - y
            elseif op == "*" then res = x * y
            elseif op == "/" and y ~= 0 then res = x / y
            end
            return ctx.args .. " = " .. tostring(res)
        end
        return { cancel = true, toast = "Формат: .calc 125 * 4" }
    end
    return nil
end
"""

        let pyFormatter = """
# @name Текст-мастер (Python)
# @id fg_python_formatter
# @version 1.0
# @author FullGram
# @description Команды .upper, .lower, .reverse и .mock на Python 3

def on_command(ctx):
    cmd = ctx["command"]
    args = ctx["args"]
    if not args:
        return None
    if cmd == "upper":
        return args.upper()
    elif cmd == "lower":
        return args.lower()
    elif cmd == "mock":
        out = ""
        for idx, ch in enumerate(args):
            out = out + (ch.upper() if idx % 2 == 0 else ch.lower())
        return out
    elif cmd == "count":
        fullgram.toast(f"Символов: {len(args)}, слов: {len(args.split())}")
        return {"cancel": True, "toast": f"Символов: {len(args)}, слов: {len(args.split())}"}
    return None
"""

        let pyCounter = """
# @name Счётчик сообщений (Python)
# @id fg_message_counter
# @version 1.0
# @author FullGram
# @description Считает отправленные сообщения; команда .stats показывает счётчик

import fullgram

def on_outgoing_message(ctx):
    count = int(fullgram.storage_get("sent_count", 0)) + 1
    fullgram.storage_set("sent_count", count)
    return None

def on_command(ctx):
    if ctx["command"] == "stats":
        count = int(fullgram.storage_get("sent_count", 0))
        return {"cancel": True, "toast": f"Отправлено сообщений: {count}"}
    return None
"""

        return [
            FullGramPluginDescriptor(
                id: "fg_quick_commands",
                name: "Быстрые команды",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Команды .shrug, .lenny, .flip, .unflip, .hug в любом чате",
                code: luaCommands,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_inline_calc",
                name: "Калькулятор и рандом",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Команды .roll [макс] и .calc [пример]",
                code: luaCalc,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_python_formatter",
                name: "Текст-мастер (Python)",
                language: .python,
                version: "1.0",
                author: "FullGram",
                description: "Команды .upper, .lower, .mock и .count на Python 3",
                code: pyFormatter,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_message_counter",
                name: "Счётчик сообщений (Python)",
                language: .python,
                version: "1.0",
                author: "FullGram",
                description: "Считает отправленные сообщения; команда .stats",
                code: pyCounter,
                isEnabled: false,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_chat_info",
                name: "1. Информация о чате",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Команда .plug info-chat: дата первого и последнего сообщения, частые и редкие слова, количество мата, голосовых и видеокружков.",
                code: Self.chatInfoPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_snippets",
                name: "Быстрые шаблоны (.tpl)",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Шаблоны ответов: .tpl add <ключ> <текст>, .tpl <ключ>, .tpl list",
                code: Self.snippetsPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_notes",
                name: "Быстрые заметки (.note)",
                language: .lua,
                version: "1.0",
                author: "FullGram",
                description: "Личные заметки: .note add <текст>, .note list, .note clear",
                code: Self.notesPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_layout_fixer",
                name: "Исправление раскладки (.fix)",
                language: .python,
                version: "1.0",
                author: "FullGram",
                description: "Команда .fix <текст>: переводит раскладку (по умолчанию Рус → Англ, направление меняется во вкладке Плагины).",
                code: Self.layoutFixerPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_casino",
                name: "PARIMATCH · BETON Казино (.casino / .zeus / .crash)",
                language: .lua,
                version: "5.1",
                author: "FullGram",
                description: "HD 60fps графическое казино в стиле Parimatch & Beton: Gates of Olympus, Aviator Live, 3D Рулетка, Beton Mines.",
                code: Self.casinoPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_anti_typos",
                name: "Анти-опечатки",
                language: .python,
                version: "2.0",
                author: "FullGram",
                description: "Автоматически исправляет частые клавиатурные опечатки, двойные заглавные буквы и лишние пробелы перед знаками препинания.",
                code: Self.antiTyposPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_deadlines",
                name: "Дедлайны (.dl / .deadline)",
                language: .python,
                version: "2.0",
                author: "FullGram",
                description: "Управление сроками: .dl add <срок> | <задача>, .dl list, .dl done <№>, .dl send, .dl clear.",
                code: Self.deadlinesPluginCode(),
                isEnabled: true,
                isBuiltIn: true
            ),
            FullGramPluginDescriptor(
                id: "fg_nick_clock",
                name: "Живой Ник и Часы (.nick / .time)",
                language: .lua,
                version: "2.0",
                author: "FullGram",
                description: "Управление ником в Telegram, часы со временем телефона в нике и работа в фоне (.nick, .time).",
                code: Self.nickClockPluginCode(),
                isEnabled: true,
                isBuiltIn: true,
                backgroundEnabled: true,
                backgroundInterval: 30
            )
        ]
    }

    private static func nickClockPluginCode() -> String {
        return """
-- @name Живой Ник и Часы (.nick / .time)
-- @id fg_nick_clock
-- @version 2.0
-- @author FullGram
-- @background true
-- @interval 30
-- @description Управление ником в Telegram, часы со временем телефона в нике и фоновый тик (.nick, .time)

function on_background_tick(ctx)
    local clock_on = fullgram.storage_get("clock_enabled", false)
    if clock_on == true then
        local tpl = tostring(fullgram.storage_get("clock_template", "{name} | ⌚ {time}"))
        local style = tostring(fullgram.storage_get("clock_style", "bold"))
        local base_first = tostring(fullgram.storage_get("base_first_name", ""))
        local formatted = fullgram.profile.format_nick(tpl, style, base_first)
        fullgram.profile.set_name(formatted)
    end
    local bio_on = fullgram.storage_get("bio_enabled", false)
    if bio_on == true then
        local bio_tpl = tostring(fullgram.storage_get("bio_template", "⌚ {time} • 📅 {date} • 🔋 {battery}%"))
        local bio_text = fullgram.profile.format_nick(bio_tpl, "normal")
        fullgram.profile.set_bio(bio_text)
    end
end

function on_command(ctx)
    local cmd = ctx.command
    local args = tostring(ctx.args or "")

    if cmd == "time" then
        local t = fullgram.time.now()
        local dev = fullgram.device.info()
        local msg = t.clock_emoji .. " Время на телефоне: " .. tostring(t.hms)
            .. "\\n📅 Дата: " .. tostring(t.date) .. " (" .. tostring(t.weekday_name) .. ")"
            .. "\\n🌍 Пояс: " .. tostring(t.timezone) .. " (UTC" .. tostring(t.utc_offset_str) .. ")"
            .. "\\n🔋 Батарея: " .. tostring(dev.battery_level) .. "%"
        if string.lower(args) == "send" then
            return msg
        end
        return { cancel = true, toast = t.clock_emoji .. " " .. tostring(t.hms) .. " • " .. tostring(t.date) .. " • 🔋 " .. tostring(dev.battery_level) .. "%" }
    end

    if cmd ~= "nick" then
        return nil
    end

    if args == "" or string.lower(args) == "ui" then
        fullgram.open_ui({ kind = "nick_clock", title = "⌚ Живой Ник и Часы" })
        return { cancel = true }
    end

    local lower = string.lower(args)
    if lower == "reset" or lower == "restore" then
        fullgram.storage_set("clock_enabled", false)
        fullgram.storage_set("bio_enabled", false)
        fullgram.profile.restore_name()
        return { cancel = true, toast = "Исходный ник восстановлен!" }
    end

    if string.sub(lower, 1, 8) == "clock on" then
        local tpl = string.sub(args, 9)
        tpl = string.gsub(tpl, "^%s+", "")
        if tpl == "" then
            tpl = tostring(fullgram.storage_get("clock_template", "{name} | ⌚ {time}"))
        else
            fullgram.storage_set("clock_template", tpl)
        end
        local prof = fullgram.profile.get()
        if tostring(fullgram.storage_get("base_first_name", "")) == "" and prof.original_first_name ~= "" then
            fullgram.storage_set("base_first_name", prof.original_first_name)
        end
        fullgram.storage_set("clock_enabled", true)
        local style = tostring(fullgram.storage_get("clock_style", "bold"))
        local base_first = tostring(fullgram.storage_get("base_first_name", ""))
        local next_nick = fullgram.profile.format_nick(tpl, style, base_first)
        fullgram.profile.set_name(next_nick)
        fullgram.background.set_interval(tonumber(fullgram.storage_get("clock_interval", 30)) or 30)
        return { cancel = true, toast = "⌚ Часы в нике включены: " .. next_nick }
    end

    if lower == "clock off" then
        fullgram.storage_set("clock_enabled", false)
        fullgram.profile.restore_name()
        return { cancel = true, toast = "Часы в нике выключены, ник восстановлен." }
    end

    if string.sub(lower, 1, 6) == "style " then
        local st = string.gsub(string.sub(lower, 7), "%s+", "")
        fullgram.storage_set("clock_style", st)
        if fullgram.storage_get("clock_enabled", false) == true then
            local tpl = tostring(fullgram.storage_get("clock_template", "{name} | ⌚ {time}"))
            local base_first = tostring(fullgram.storage_get("base_first_name", ""))
            fullgram.profile.set_name(fullgram.profile.format_nick(tpl, st, base_first))
        end
        return { cancel = true, toast = "Стиль часов: " .. st }
    end

    if string.sub(lower, 1, 9) == "interval " then
        local sec = tonumber(string.match(args, "(%d+)")) or 30
        if sec < 10 then sec = 10 end
        fullgram.storage_set("clock_interval", sec)
        fullgram.background.set_interval(sec)
        return { cancel = true, toast = "Интервал обновления: " .. tostring(sec) .. " сек." }
    end

    if string.sub(lower, 1, 4) == "bio " then
        local raw_bio = string.sub(args, 5)
        local formatted_bio = fullgram.profile.format_nick(raw_bio, "normal")
        fullgram.profile.set_bio(formatted_bio)
        return { cancel = true, toast = "Био обновлено: " .. formatted_bio }
    end

    local raw_name = args
    if string.sub(lower, 1, 4) == "set " then
        raw_name = string.sub(args, 5)
    end
    local sep = string.find(raw_name, "|", 1, true)
    if sep then
        local first = string.gsub(string.sub(raw_name, 1, sep - 1), "^%s*(.-)%s*$", "%1")
        local last = string.gsub(string.sub(raw_name, sep + 1), "^%s*(.-)%s*$", "%1")
        local rendered_first = fullgram.profile.format_nick(first, tostring(fullgram.storage_get("clock_style", "bold")), first)
        fullgram.profile.set_name(rendered_first, last)
        return { cancel = true, toast = "Ник обновлён: " .. rendered_first .. (last ~= "" and (" " .. last) or "") }
    else
        local rendered = fullgram.profile.format_nick(raw_name, tostring(fullgram.storage_get("clock_style", "bold")), raw_name)
        fullgram.profile.set_name(rendered, "")
        return { cancel = true, toast = "Ник обновлён: " .. rendered }
    end
end
"""
    }

    private static func layoutFixerPluginCode() -> String {
        return """
# @name Исправление раскладки (.fix)
# @id fg_layout_fixer
# @version 1.0
# @author FullGram
# @description Команда .fix <текст>: переводит раскладку (по умолчанию Рус → Англ, меняется во вкладке Плагины)

import fullgram

RU_CHARS = "йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ"
EN_CHARS = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:\\"ZXCVBNM<>~"

def convert_text(text, direction):
    out = ""
    for ch in text:
        if direction == "ru2en":
            idx = RU_CHARS.find(ch)
            out = out + (EN_CHARS[idx] if idx >= 0 else ch)
        elif direction == "en2ru":
            idx = EN_CHARS.find(ch)
            out = out + (RU_CHARS[idx] if idx >= 0 else ch)
    return out

def on_command(ctx):
    if ctx["command"] != "fix":
        return None
    raw = str(ctx["args"]).strip()
    if not raw:
        mode = str(fullgram.storage_get("mode", "ru2en"))
        return {"cancel": True, "toast": f"Формат: .fix <текст> (режим: {mode})"}

    lower_raw = raw.lower()
    if lower_raw == "mode ru2en":
        fullgram.storage_set("mode", "ru2en")
        return {"cancel": True, "toast": "Раскладка .fix: Русский → Английский"}
    elif lower_raw == "mode en2ru":
        fullgram.storage_set("mode", "en2ru")
        return {"cancel": True, "toast": "Раскладка .fix: Английский → Русский"}
    elif lower_raw == "mode auto":
        fullgram.storage_set("mode", "auto")
        return {"cancel": True, "toast": "Раскладка .fix: Авто (Рус ↔ Англ)"}

    mode = str(fullgram.storage_get("mode", "ru2en"))
    direction = mode
    if mode == "auto":
        ru_count = 0
        en_count = 0
        for ch in raw:
            if RU_CHARS.find(ch) >= 0:
                ru_count = ru_count + 1
            elif EN_CHARS.find(ch) >= 0:
                en_count = en_count + 1
        direction = "ru2en" if ru_count >= en_count else "en2ru"

    return convert_text(raw, direction)
"""
    }

    private static func casinoPluginCode() -> String {
        return """
-- @name BetKing Казино (.casino / .zeus / .crash)
-- @id fg_casino
-- @version 5.0
-- @author FullGram
-- @description Анимированный BetKing GUI (Зевс, Собаки, Слоты 777, Live Краш с ракетой, Рулетка, 3D Монетка, Ante Bet, Buy Bonus). Без спама в чат!

function get_num(key, def)
    local v = tonumber(fullgram.storage_get(key, def))
    if v == nil then return def end
    return v
end

function get_balance()
    return math.max(0, math.floor(get_num("balance", 1000) + 0.5))
end

function set_balance(val)
    local b = math.max(0, math.floor((tonumber(val) or 0) + 0.5))
    fullgram.storage_set("balance", b)
    local best = get_num("best_balance", 1000)
    if b > best then
        fullgram.storage_set("best_balance", b)
    end
    return b
end

function fmt2(x)
    local n = math.floor((tonumber(x) or 0) * 100 + 0.5)
    local whole = math.floor(n / 100)
    local frac = n % 100
    local fstr = (frac < 10) and ("0" .. tostring(frac)) or tostring(frac)
    return tostring(whole) .. "." .. fstr
end

function fmt_signed(delta)
    if delta >= 0 then
        return "+" .. tostring(delta)
    end
    return tostring(delta)
end

function add_session(wagered, returned, won)
    fullgram.storage_set("sess_rounds", get_num("sess_rounds", 0) + 1)
    fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + wagered)
    fullgram.storage_set("sess_returned", get_num("sess_returned", 0) + returned)
    if won then
        fullgram.storage_set("sess_wins", get_num("sess_wins", 0) + 1)
    end
end

function pick_weighted(tbl)
    local total = 0
    for i = 1, #tbl do
        total = total + tbl[i][2]
    end
    if total <= 0 then return tbl[1][1] end
    local roll = math.random(0, total - 1)
    for i = 1, #tbl do
        local w = tbl[i][2]
        if roll < w then
            return tbl[i][1]
        end
        roll = roll - w
    end
    return tbl[1][1]
end

function pick_zeus_orb()
    local roll = math.random(0, 999)
    if roll < 480 then return 2 end
    if roll < 720 then return 3 end
    if roll < 860 then return 5 end
    if roll < 940 then return 10 end
    if roll < 980 then return 25 end
    if roll < 995 then return 50 end
    return 100
end

function is_red_pocket(num)
    local reds = {1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36}
    for i = 1, #reds do
        if reds[i] == num then return true end
    end
    return false
end

function parse_bet(raw_str, bal)
    local num = tonumber(string.match(tostring(raw_str or ""), "(%d+)"))
    local bet = num or 100
    if bet < 10 then bet = 10 end
    if bal > 0 and bet > bal then bet = bal end
    return math.floor(bet + 0.5)
end

function ensure_playable_balance()
    local bal = get_balance()
    if bal < 10 then
        bal = set_balance(500)
        return bal, true
    end
    return bal, false
end

function status_header()
    local bal = get_balance()
    local best = math.floor(get_num("best_balance", 1000) + 0.5)
    local ante = (get_num("ante_bet", 0) == 1)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)
    local rounds = math.floor(get_num("sess_rounds", 0) + 0.5)
    local wins = math.floor(get_num("sess_wins", 0) + 0.5)
    local wag = get_num("sess_wagered", 0)
    local ret = get_num("sess_returned", 0)
    local win_pct = (rounds > 0) and fmt2((wins / rounds) * 100) or "0.00"
    local sess_rtp = (wag > 0) and fmt2((ret / wag) * 100) or "—"
    local line = "💰 Баланс: " .. tostring(bal) .. " 🪙 | 🏆 Рекорд: " .. tostring(best) .. " 🪙"
    line = line .. "\\n⚡ Ante Bet (+25%): " .. (ante and "ВКЛ" or "ВЫКЛ")
    if fs > 0 then
        line = line .. " | 🎁 FS: " .. tostring(fs) .. " (x" .. tostring(gmult) .. ")"
    end
    line = line .. "\\n📊 Сессия: " .. tostring(rounds) .. " раунд. · Побед " .. win_pct .. "% · RTP " .. sess_rtp .. "%"
    return line
end

function play_zeus(raw_arg)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local is_fs = (fs > 0)
    local bal, refilled = ensure_playable_balance()
    local ante = (get_num("ante_bet", 0) == 1)
    local base_bet = is_fs and math.floor(get_num("bonus_bet", 100) + 0.5) or parse_bet(raw_arg, bal)
    local spin_cost = is_fs and 0 or math.min(bal, ante and math.floor(base_bet * 1.25 + 0.5) or base_bet)

    local weights = (ante or is_fs)
        and {{"💎", 26}, {"⏳", 21}, {"🏆", 17}, {"💍", 14}, {"👑", 10}, {"⚡", 12}}
        or  {{"💎", 30}, {"⏳", 23}, {"🏆", 18}, {"💍", 14}, {"👑", 9},  {"⚡", 6}}

    if not is_fs then
        bal = set_balance(bal - spin_cost)
    else
        fs = fs - 1
        fullgram.storage_set("free_spins", fs)
    end

    local grid = {}
    local counts = {}
    for i = 1, 15 do
        local s = pick_weighted(weights)
        grid[i] = s
        counts[s] = (counts[s] or 0) + 1
    end

    local bolts = counts["⚡"] or 0
    local sym_base = { ["💎"] = 0.4, ["⏳"] = 0.6, ["🏆"] = 0.9, ["💍"] = 1.3, ["👑"] = 2.2 }
    local syms = {"💎", "⏳", "🏆", "💍", "👑"}
    local best_pay = 0.0
    local best_sym = nil
    for i = 1, #syms do
        local s = syms[i]
        local cnt = counts[s] or 0
        if cnt >= 6 then
            local cand = sym_base[s] * (1.0 + (cnt - 6) * 0.65)
            if cand > best_pay then
                best_pay = cand
                best_sym = s
            end
        end
    end

    local mult = 0.0
    local status = "❌ Пустой спин"
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)

    if best_pay > 0.0 then
        local orb = (bolts > 0 or is_fs) and pick_zeus_orb() or 1
        if is_fs and orb > 1 then
            gmult = gmult + orb
            fullgram.storage_set("bonus_mult", gmult)
        end
        local eff_orb = is_fs and math.max(1, gmult) or orb
        mult = best_pay * eff_orb
        if eff_orb >= 25 then
            status = "🔥 MAX ОРБ ЗЕВСА x" .. tostring(eff_orb) .. "!"
        elseif eff_orb > 1 then
            status = "⚡ МОЛНИЯ ЗЕВСА x" .. tostring(eff_orb) .. "!"
        else
            status = "👑 СЫГРОВКА " .. best_sym .. " x" .. fmt2(mult) .. "!"
        end
    end

    if bolts >= 4 and not is_fs then
        fullgram.storage_set("bonus_bet", base_bet)
        fullgram.storage_set("free_spins", fs + 10)
        fullgram.storage_set("bonus_mult", 1)
        if mult < 3.0 then mult = 3.0 end
        status = "⚡ 4+ SCATTER! БОНУС 10 ФРИСПИНОВ!"
    elseif bolts >= 4 and is_fs then
        fullgram.storage_set("free_spins", fs + 5)
        status = "⚡ РЕТРИГГЕР +5 ФРИСПИНОВ!"
    end

    local payout = math.floor(base_bet * mult + 0.5)
    bal = set_balance(bal + payout)
    add_session(spin_cost, payout, payout > spin_cost)
    local net = payout - spin_cost

    local r1 = grid[1] .. " " .. grid[2] .. " " .. grid[3] .. " " .. grid[4] .. " " .. grid[5]
    local r2 = grid[6] .. " " .. grid[7] .. " " .. grid[8] .. " " .. grid[9] .. " " .. grid[10]
    local r3 = grid[11] .. " " .. grid[12] .. " " .. grid[13] .. " " .. grid[14] .. " " .. grid[15]
    local fs_left = math.floor(get_num("free_spins", 0) + 0.5)
    local tag = is_fs and ("🎁 ФРИСПИН (ост. " .. tostring(fs_left) .. ")") or ("Ставка: " .. tostring(spin_cost) .. " 🪙")
    local note = refilled and "\\n🎁 Фрибет +500 🪙 на старте" or ""

    return "⚡ GATES OF OLYMPUS (RTP 96.50%) | " .. tag .. "\\n"
        .. r1 .. "\\n" .. r2 .. "\\n" .. r3 .. "\\n"
        .. status .. " (выплата " .. tostring(payout) .. " 🪙, " .. fmt_signed(net) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_dogs(raw_arg)
    local fs = math.floor(get_num("free_spins", 0) + 0.5)
    local is_fs = (fs > 0)
    local bal, refilled = ensure_playable_balance()
    local ante = (get_num("ante_bet", 0) == 1)
    local base_bet = is_fs and math.floor(get_num("bonus_bet", 100) + 0.5) or parse_bet(raw_arg, bal)
    local spin_cost = is_fs and 0 or math.min(bal, ante and math.floor(base_bet * 1.25 + 0.5) or base_bet)

    local weights = (ante or is_fs)
        and {{"🦴", 23}, {"🐾", 20}, {"🎾", 17}, {"💎", 14}, {"🐶", 11}, {"🏠", 15}}
        or  {{"🦴", 27}, {"🐾", 22}, {"🎾", 18}, {"💎", 14}, {"🐶", 11}, {"🏠", 8}}

    if not is_fs then
        bal = set_balance(bal - spin_cost)
    else
        fs = fs - 1
        fullgram.storage_set("free_spins", fs)
    end

    local grid = {}
    local kennels = 0
    local dogs_cnt = 0
    for i = 1, 15 do
        local s = pick_weighted(weights)
        grid[i] = s
        if s == "🏠" then kennels = kennels + 1 end
        if s == "🐶" then dogs_cnt = dogs_cnt + 1 end
    end

    local line_w = { ["🦴"] = 0.4, ["🐾"] = 0.6, ["🎾"] = 0.85, ["💎"] = 1.4, ["🐶"] = 2.4 }
    local line_sum = 0.0
    for r = 0, 2 do
        local anchor = "🐶"
        for c = 1, 5 do
            local sym = grid[r * 5 + c]
            if sym ~= "🏠" then
                anchor = sym
                break
            end
        end
        local streak = 0
        for c = 1, 5 do
            local sym = grid[r * 5 + c]
            if sym == anchor or sym == "🏠" then
                streak = streak + 1
            else
                break
            end
        end
        if streak >= 3 then
            line_sum = line_sum + (line_w[anchor] or 0.6) * (streak - 1)
        end
    end

    local mult = 0.0
    local status = "❌ Пустой спин"
    local gmult = math.floor(get_num("bonus_mult", 1) + 0.5)

    if line_sum > 0.0 then
        local km = 1
        if kennels > 0 then
            local sum_w = 0
            local cap = math.min(kennels, 4)
            for i = 1, cap do
                sum_w = sum_w + ((math.random(0, 9) < 7) and 2 or 3)
            end
            km = math.max(1, sum_w)
        end
        if is_fs and kennels > 0 then
            gmult = math.min(27, gmult + km)
            fullgram.storage_set("bonus_mult", gmult)
            km = gmult
        end
        mult = line_sum * km
        status = (km > 1) and ("🐶 БУДКИ x" .. tostring(km) .. " · ЗАНОС!") or "🐶 ЛИНИЯ СЫГРАЛА!"
    elseif dogs_cnt >= 5 then
        mult = 2.5
        status = "🐶 СТАЯ СОБАК x2.5!"
    end

    if kennels >= 4 and not is_fs then
        fullgram.storage_set("bonus_bet", base_bet)
        fullgram.storage_set("free_spins", fs + 10)
        fullgram.storage_set("bonus_mult", 1)
        if mult < 2.0 then mult = 2.0 end
        status = "🏠 БОНУС 10 ФРИСПИНОВ СОБАК!"
    elseif kennels >= 4 and is_fs then
        fullgram.storage_set("free_spins", fs + 5)
        status = "🏠 РЕТРИГГЕР +5 ФРИСПИНОВ!"
    end

    local payout = math.floor(base_bet * mult + 0.5)
    bal = set_balance(bal + payout)
    add_session(spin_cost, payout, payout > spin_cost)
    local net = payout - spin_cost

    local r1 = grid[1] .. " " .. grid[2] .. " " .. grid[3] .. " " .. grid[4] .. " " .. grid[5]
    local r2 = grid[6] .. " " .. grid[7] .. " " .. grid[8] .. " " .. grid[9] .. " " .. grid[10]
    local r3 = grid[11] .. " " .. grid[12] .. " " .. grid[13] .. " " .. grid[14] .. " " .. grid[15]
    local fs_left = math.floor(get_num("free_spins", 0) + 0.5)
    local tag = is_fs and ("🎁 ФРИСПИН (ост. " .. tostring(fs_left) .. ")") or ("Ставка: " .. tostring(spin_cost) .. " 🪙")
    local note = refilled and "\\n🎁 Фрибет +500 🪙 на старте" or ""

    return "🐶 THE DOG HOUSE (RTP 96.51%) | " .. tag .. "\\n"
        .. r1 .. "\\n" .. r2 .. "\\n" .. r3 .. "\\n"
        .. status .. " (выплата " .. tostring(payout) .. " 🪙, " .. fmt_signed(net) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_classic(raw_arg)
    local bal, refilled = ensure_playable_balance()
    local bet = parse_bet(raw_arg, bal)
    local weights = {{"🍒", 36}, {"🍋", 26}, {"🔔", 18}, {"💎", 13}, {"7️⃣", 7}}
    local s1 = pick_weighted(weights)
    local s2 = pick_weighted(weights)
    local s3 = pick_weighted(weights)

    local sevens = ((s1 == "7️⃣") and 1 or 0) + ((s2 == "7️⃣") and 1 or 0) + ((s3 == "7️⃣") and 1 or 0)
    local diamonds = ((s1 == "💎") and 1 or 0) + ((s2 == "💎") and 1 or 0) + ((s3 == "💎") and 1 or 0)

    local mult = 0.0
    local status = "❌ Мимо!"
    if s1 == s2 and s2 == s3 then
        if s1 == "7️⃣" then mult = 50.0; status = "🔥 МЕГА ДЖЕКПОТ 777 (x50)!"
        elseif s1 == "💎" then mult = 15.0; status = "💎 АЛМАЗНЫЙ ДЖЕКПОТ (x15)!"
        elseif s1 == "🔔" then mult = 8.0; status = "🔔 3 КОЛОКОЛА (x8)!"
        elseif s1 == "🍋" then mult = 5.0; status = "🍋 3 ЛИМОНА (x5)!"
        else mult = 3.0; status = "🍒 3 ВИШНИ (x3)!"
        end
    elseif sevens == 2 then
        mult = 3.0; status = "7️⃣ Две Семёрки (x3)!"
    elseif diamonds == 2 then
        mult = 2.0; status = "💎 Два Алмаза (x2)!"
    elseif s1 == s2 or s2 == s3 or s1 == s3 then
        mult = 1.2; status = "✨ Пара (x1.2)!"
    end

    local payout = math.floor(bet * mult + 0.5)
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, delta > 0)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""

    return "🎰 3 БАРАБАНА (RTP 96.20%) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. "┏━━━━━━━━━━━┓\\n┃  " .. s1 .. " │ " .. s2 .. " │ " .. s3 .. "  ┃\\n┗━━━━━━━━━━━┛\\n"
        .. status .. " (" .. fmt_signed(delta) .. " 🪙)" .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_crash(raw_arg, default_target)
    local bal, refilled = ensure_playable_balance()
    local s = tostring(raw_arg or "")
    local target = default_target or 2.0
    local bet = 100

    local n1 = string.match(s, "^%s*([%d%.]+)%s+%d+")
    local n2 = string.match(s, "^%s*[%d%.]+%s+(%d+)")
    if n1 and n2 then
        target = tonumber(n1) or target
        bet = tonumber(n2) or bet
    else
        local with_x = string.match(s, "([%d%.]+)[xXхХ]")
        if with_x then
            target = tonumber(with_x) or target
        else
            local single = tonumber(string.match(s, "([%d%.]+)"))
            if single then
                if string.find(s, ".", 1, true) then
                    target = single
                else
                    bet = single
                end
            end
        end
    end
    if target < 1.05 then target = 1.05 end
    if target > 100.0 then target = 100.0 end
    if bet < 10 then bet = 10 end
    if bet > bal then bet = bal end
    bet = math.floor(bet + 0.5)

    local crash_pt = 1.00
    if math.random(0, 99) >= 3 then
        local u = math.random(1, 990) / 1000.0
        crash_pt = math.min(100.0, math.max(1.03, 0.97 / (1.0 - u)))
    end

    local won = (crash_pt >= target)
    local payout = won and math.floor(bet * target + 0.5) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""

    local res_line = won
        and ("✅ Забрал на " .. fmt2(target) .. "x (краш был " .. fmt2(crash_pt) .. "x): +" .. tostring(delta) .. " 🪙")
        or  ("💥 КРАШ на " .. fmt2(crash_pt) .. "x (цель " .. fmt2(target) .. "x): " .. tostring(delta) .. " 🪙")

    return "🚀 CRASH (RTP 97.00% · 3% инста-краш) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. res_line .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_roulette(choice_arg, bet_arg)
    local bal, refilled = ensure_playable_balance()
    local c = string.lower(tostring(choice_arg or "red"))
    local bet = parse_bet(bet_arg, bal)
    local num = math.random(0, 36)

    local color = "black"
    local badge = "⚫️ Чёрное"
    if num == 0 then
        color = "green"
        badge = "🟢 Зеро (0)"
    elseif is_red_pocket(num) then
        color = "red"
        badge = "🔴 Красное"
    end

    local exact_num = tonumber(c)
    local won = false
    local mult = 2
    local bet_label = "🔴 Красное"
    if exact_num ~= nil and exact_num >= 0 and exact_num <= 36 then
        mult = 36
        bet_label = "🎯 Число [" .. tostring(exact_num) .. "]"
        won = (num == exact_num)
    elseif c == "green" or c == "0" or c == "зеро" or c == "зеленое" then
        mult = 36
        bet_label = "🟢 Зеро [0]"
        won = (color == "green")
    elseif c == "black" or c == "черное" or c == "ч" then
        mult = 2
        bet_label = "⚫️ Чёрное"
        won = (color == "black")
    else
        mult = 2
        bet_label = "🔴 Красное"
        won = (color == "red")
    end

    local payout = won and (bet * mult) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""
    local outcome = won
        and ("✅ Выигрыш x" .. tostring(mult) .. ": +" .. tostring(delta) .. " 🪙!")
        or  ("❌ Мимо: " .. tostring(delta) .. " 🪙")

    return "🎡 ЕВРОПЕЙСКАЯ РУЛЕТКА (RTP 97.30%) | " .. bet_label .. " · " .. tostring(bet) .. " 🪙\\n"
        .. "Выпало: " .. badge .. " [" .. tostring(num) .. "]\\n"
        .. outcome .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function play_coin(side_arg, bet_arg)
    local bal, refilled = ensure_playable_balance()
    local bet = parse_bet(bet_arg, bal)
    local pick_tails = (string.find(string.lower(tostring(side_arg or "")), "реш") ~= nil)
        or (string.find(string.lower(tostring(side_arg or "")), "tail") ~= nil)
    local won = (math.random(0, 99) < 49)
    local landed_tails = false
    if pick_tails then
        landed_tails = won
    else
        landed_tails = not won
    end
    local landed_str = landed_tails and "🪙 Решка" or "🦅 Орёл"

    local payout = won and (bet * 2) or 0
    local delta = payout - bet
    bal = set_balance(bal + delta)
    add_session(bet, payout, won)
    local note = refilled and "\\n🎁 Фрибет +500 🪙" or ""
    local res = won and ("✅ Победа (49% шанс, x2): +" .. tostring(delta) .. " 🪙!") or ("❌ Не угадали: " .. tostring(delta) .. " 🪙")

    return "🪙 МОНЕТКА (RTP 98.00%) | Ставка: " .. tostring(bet) .. " 🪙\\n"
        .. "Выпал: " .. landed_str .. "\\n"
        .. res .. note .. "\\n"
        .. "💰 Баланс: " .. tostring(bal) .. " 🪙"
end

function rtp_summary()
    return "📊 ЧЕСТНЫЕ ШАНСЫ И RTP КАЗИНО:\\n"
        .. "• ⚡ Gates of Olympus — RTP 96.50% (орбы x2..x100, 4+ ⚡ = 10 FS)\\n"
        .. "• 🐶 The Dog House — RTP 96.51% (линии + будки Wild x2/x3, до x27 в FS)\\n"
        .. "• 🎰 3 Барабана — RTP 96.20% (777: x50, 💎: x15, 🔔: x8, пара: x1.2)\\n"
        .. "• 🚀 Crash — RTP 97.00% (3% краш на 1.00x, хвост до x100)\\n"
        .. "• 🎡 Рулетка (37 сект.) — RTP 97.30% (🔴/⚫️ 48.65% x2, 🟢 2.70% x36)\\n"
        .. "• 🪙 Монетка — RTP 98.00% (49.0% победа, x2)\\n"
        .. "ℹ️ Выдача баланса (.setbal <сумма>) НЕ меняет шансы.\\n\\n"
        .. status_header()
end

function handle_set_balance(raw)
    local s = tostring(raw or "")
    local add_num = tonumber(string.match(s, "^%s*%+%s*(%d+)"))
    if add_num ~= nil then
        local nb = set_balance(get_balance() + add_num)
        return "💰 Добавлено +" .. tostring(add_num) .. " 🪙!\\nБаланс: " .. tostring(nb) .. " 🪙 (шансы те же)"
    end
    local exact = tonumber(string.match(s, "(%d+)"))
    if exact ~= nil then
        local nb = set_balance(exact)
        return "💰 Баланс установлен: " .. tostring(nb) .. " 🪙\\n(шансы и RTP без изменений!)"
    end
    local nb = set_balance(get_balance() + 10000)
    return "🎁 Начислено +10000 🪙!\\nБаланс: " .. tostring(nb) .. " 🪙\\n(введите любое число в поле для точной выдачи)"
end

function open_casino_ui(game_id)
    local g = game_id or "lobby"
    if g == "zeus" or g == "olympus" then g = "olympus"
    elseif g == "crash" or g == "aviator" then g = "aviator"
    elseif g == "roulette" then g = "roulette"
    elseif g == "mines" then g = "mines"
    else g = "lobby" end
    fullgram.open_ui({
        kind = "webview",
        url = "https://fullgram.korsakovx.workers.dev/casino?game=" .. g,
        title = "PARIMATCH · BETON"
    })
end

function on_ui_event(ctx)
    local act = tostring(ctx.action or "")
    local inp = tostring(ctx.input or "")

    if act == "bonus" then
        local nb = set_balance(get_balance() + 1000)
        return { balance = nb, best_balance = get_num("best_balance", 1000), text = "🎁 +1000 🪙!\\n" .. status_header() }
    elseif act == "spin_zeus" then
        return play_zeus(inp)
    elseif act == "spin_dogs" then
        return play_dogs(inp)
    elseif act == "spin_classic" then
        return play_classic(inp)
    elseif act == "spin_crash" then
        return play_crash(inp, 2.0)
    elseif act == "spin_red" then
        return play_roulette("red", inp)
    elseif act == "spin_black" then
        return play_roulette("black", inp)
    elseif act == "spin_green" then
        return play_roulette("green", inp)
    elseif act == "spin_coin" then
        return play_coin("eagle", inp)
    elseif act == "toggle_ante" then
        if get_num("free_spins", 0) > 0 then
            return "⚠️ Нельзя менять Ante Bet во время фриспинов!\\n" .. status_header()
        end
        local cur = (get_num("ante_bet", 0) == 1) and 0 or 1
        fullgram.storage_set("ante_bet", cur)
        return (cur == 1 and "⚡ Ante Bet ВКЛ (+25% к ставке, x2 шанс бонуса)" or "⚡ Ante Bet ВЫКЛ") .. "\\n\\n" .. status_header()
    elseif act == "buy_bonus" then
        local bal = get_balance()
        local bet = parse_bet(inp, bal)
        local cost = bet * 100
        if bal < cost then
            return "❌ Нужно " .. tostring(cost) .. " 🪙 для покупки бонуса (x100 ставки).\\nВы можете выдать себе баланс кнопкой «💰 Выдать баланс»!\\n\\n" .. status_header()
        end
        set_balance(bal - cost)
        fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + cost)
        fullgram.storage_set("bonus_bet", bet)
        fullgram.storage_set("free_spins", get_num("free_spins", 0) + 10)
        fullgram.storage_set("bonus_mult", 1)
        return "🎁 БОНУС КУПЛЕН! 10 ФРИСПИНОВ по ставке " .. tostring(bet) .. " 🪙!\\nЖмите «⚡ Зевс» или «🐶 Собаки»!\\n\\n" .. status_header()
    elseif act == "set_balance" then
        return handle_set_balance(inp) .. "\\n\\n" .. status_header()
    elseif act == "rtp_info" then
        return rtp_summary()
    end

    return status_header()
end

function on_command(ctx)
    local aliases = { roul = "roulette", givebal = "setbal", balance = "bal", odds = "rtp" }
    local cmd = aliases[ctx.command] or ctx.command
    local args = tostring(ctx.args or "")

    if cmd == "casino" then
        open_casino_ui(args ~= "" and args or "zeus")
        return { cancel = true }
    elseif cmd == "zeus" then
        open_casino_ui("zeus")
        return { cancel = true }
    elseif cmd == "dogs" then
        open_casino_ui("dogs")
        return { cancel = true }
    elseif cmd == "slots" then
        open_casino_ui("slots777")
        return { cancel = true }
    elseif cmd == "crash" then
        open_casino_ui("crash")
        return { cancel = true }
    elseif cmd == "roulette" then
        open_casino_ui("roulette")
        return { cancel = true }
    elseif cmd == "coin" then
        open_casino_ui("coin")
        return { cancel = true }
    elseif cmd == "setbal" then
        local exact = tonumber(string.match(args, "(%d+)"))
        if exact == nil then
            return { cancel = true, toast = "Формат: .setbal <сумма> (например: .setbal 100000)" }
        end
        local nb = set_balance(exact)
        return { cancel = true, toast = "💰 Баланс установлен: " .. tostring(nb) .. " 🪙 (шансы не изменены)" }
    elseif cmd == "bal" then
        local lower = string.lower(args)
        if string.sub(lower, 1, 4) == "set " then
            local exact = tonumber(string.match(args, "(%d+)"))
            if exact ~= nil then
                local nb = set_balance(exact)
                return { cancel = true, toast = "💰 Баланс: " .. tostring(nb) .. " 🪙 (шансы прежние)" }
            end
        elseif string.sub(lower, 1, 4) == "add " or string.sub(lower, 1, 1) == "+" then
            local add_v = tonumber(string.match(args, "(%d+)"))
            if add_v ~= nil then
                local nb = set_balance(get_balance() + add_v)
                return { cancel = true, toast = "💰 +" .. tostring(add_v) .. " 🪙 → Баланс: " .. tostring(nb) .. " 🪙" }
            end
        elseif lower == "bonus" then
            local nb = set_balance(get_balance() + 1000)
            return { cancel = true, toast = "🎁 +1000 🪙 → Баланс: " .. tostring(nb) .. " 🪙" }
        end
        return status_header()
    elseif cmd == "ante" then
        local cur = (get_num("ante_bet", 0) == 1) and 0 or 1
        fullgram.storage_set("ante_bet", cur)
        return { cancel = true, toast = cur == 1 and "⚡ Ante Bet ВКЛ (+25%, x2 шанс бонуса)" or "⚡ Ante Bet ВЫКЛ" }
    elseif cmd == "buybonus" then
        local bal = get_balance()
        local bet = parse_bet(args, bal)
        local cost = bet * 100
        if bal < cost then
            return { cancel = true, toast = "Нужно " .. tostring(cost) .. " 🪙 (можно выдать: .setbal " .. tostring(cost) .. ")" }
        end
        set_balance(bal - cost)
        fullgram.storage_set("sess_wagered", get_num("sess_wagered", 0) + cost)
        fullgram.storage_set("bonus_bet", bet)
        fullgram.storage_set("free_spins", get_num("free_spins", 0) + 10)
        fullgram.storage_set("bonus_mult", 1)
        return { cancel = true, toast = "🎁 Куплено 10 фриспинов по ставке " .. tostring(bet) .. " 🪙! Играйте .zeus или .dogs" }
    elseif cmd == "rtp" then
        return rtp_summary()
    end

    return nil
end
"""
    }

    private static func antiTyposPluginCode() -> String {
        return """
# @name Анти-опечатки
# @id fg_anti_typos
# @version 2.0
# @author FullGram
# @description Автоматически исправляет клавиатурные опечатки, двойные заглавные буквы и пробелы у знаков препинания (без сленг-макросов)

import re

TYPOS = {
    "привте": "привет",
    "првиет": "привет",
    "спсаибо": "спасибо",
    "спаисбо": "спасибо",
    "пожалусйта": "пожалуйста",
    "пожалйста": "пожалуйста",
    "сегодян": "сегодня",
    "сейчса": "сейчас",
    "хороош": "хорошо",
    "хоршо": "хорошо",
    "вообщше": "вообще",
    "вобще": "вообще",
    "кстти": "кстати",
    "кстаит": "кстати",
    "почмеу": "почему",
    "ничгео": "ничего",
    "коненчо": "конечно",
    "протсо": "просто",
    "толкьо": "только",
    "склько": "сколько",
    "извиин": "извини",
    "поянл": "понял",
    "будте": "будет",
    "можте": "может",
    "делате": "делает",
    "нраивтся": "нравится",
    "смотир": "смотри",
    "каежтся": "кажется"
}

def fix_word(w):
    if len(w) >= 3 and w[0] == w[0].upper() and w[1] == w[1].upper() and w[2] == w[2].lower() and w[0] != w[0].lower():
        w = w[0] + w[1:].lower()
    low = w.lower()
    if low in TYPOS:
        fixed = TYPOS[low]
        if w[0] == w[0].upper() and w[0] != w[0].lower():
            return fixed[0].upper() + fixed[1:]
        return fixed
    return w

def clean_line(line):
    if not line:
        return line
    out = re.sub(r"[ \\t]{2,}", " ", line)
    for p in [",", ".", ":", ";", "!", "?"]:
        out = out.replace(" " + p, p)
    words = out.split(" ")
    res = []
    for w in words:
        if not w:
            continue
        punct = ""
        core = w
        if len(w) > 1 and w[-1] in ",.!?:;":
            punct = w[-1]
            core = w[:-1]
        res = res + [fix_word(core) + punct]
    if len(res) == 0:
        return line
    return " ".join(res)

def clean_text(text):
    if not text or text.startswith("."):
        return text
    lines = text.split("\\n")
    fixed_lines = []
    for ln in lines:
        fixed_lines = fixed_lines + [clean_line(ln)]
    result = "\\n".join(fixed_lines)
    if not result:
        return text
    return result

def on_outgoing_message(ctx):
    original = str(ctx["text"])
    if not original or original.startswith("."):
        return None
    fixed = clean_text(original)
    if fixed and fixed != original:
        return fixed
    return None

def on_command(ctx):
    if ctx["command"] == "typo":
        sample = str(ctx["args"]).strip()
        if sample:
            return clean_text(sample)
        return {"cancel": True, "toast": "Анти-опечатки активны! Проверьте: .typo ПРивте , сегодян хороош"}
    return None
"""
    }

    private static func deadlinesPluginCode() -> String {
        return """
# @name Дедлайны (.dl / .deadline)
# @id fg_deadlines
# @version 2.0
# @author FullGram
# @description Управление сроками: .dl add <срок> | <задача>, .dl list, .dl done <№>, .dl send, .dl clear

import fullgram
import json

def load_items():
    raw = str(fullgram.storage_get("dl_json", "[]"))
    data = json.loads(raw)
    if data:
        return data
    return []

def save_items(items):
    fullgram.storage_set("dl_json", json.dumps(items))

def format_list(items):
    if len(items) == 0:
        return "⏰ Дедлайнов пока нет.\\nДобавьте: .dl add Завтра 18:00 | Сдать проект"
    lines = ["⏰ Список дедлайнов FullGram:", "━━━━━━━━━━━━━━━━━━━━"]
    for idx, item in enumerate(items):
        status = "✅" if item.get("done", False) else "⏳"
        due = item.get("due", "Без срока")
        task = item.get("task", "")
        num = idx + 1
        lines = lines + [f"{num}. {status} [{due}] — {task}"]
    return "\\n".join(lines)

def on_command(ctx):
    cmd = ctx["command"]
    if cmd != "dl" and cmd != "deadline":
        return None

    raw = str(ctx["args"]).strip()
    items = load_items()

    if not raw or raw == "list" or raw == "ui":
        fullgram.open_ui({"kind": "deadlines", "title": "Дедлайны FullGram"})
        return {"cancel": True}

    if raw == "send":
        return format_list(items)

    if raw == "clear":
        save_items([])
        return {"cancel": True, "toast": "Все дедлайны очищены."}

    if raw.startswith("done "):
        idx_str = raw[5:].strip()
        idx = int(idx_str) - 1
        if idx >= 0 and idx < len(items):
            cur = items[idx]
            updated = []
            for i, it in enumerate(items):
                if i == idx:
                    updated = updated + [{"due": cur.get("due", ""), "task": cur.get("task", ""), "done": True}]
                else:
                    updated = updated + [it]
            save_items(updated)
            return {"cancel": True, "toast": f"✅ Дедлайн №{idx + 1} выполнен!"}
        return {"cancel": True, "toast": "Неверный номер дедлайна."}

    if raw.startswith("del "):
        idx_str = raw[4:].strip()
        idx = int(idx_str) - 1
        if idx >= 0 and idx < len(items):
            updated = []
            for i, it in enumerate(items):
                if i != idx:
                    updated = updated + [it]
            save_items(updated)
            return {"cancel": True, "toast": f"🗑 Дедлайн №{idx + 1} удалён."}
        return {"cancel": True, "toast": "Неверный номер дедлайна."}

    body = raw[4:].strip() if raw.startswith("add ") else raw
    due = "Срочно"
    task = body
    if "|" in body:
        parts = body.split("|")
        due = parts[0].strip()
        task = parts[1].strip()
    else:
        words = body.split(" ")
        if len(words) >= 2:
            due = words[0]
            task = " ".join(words[1:])

    new_list = items + [{"due": due, "task": task, "done": False}]
    save_items(new_list)
    return {"cancel": True, "toast": f"⏰ Дедлайн добавлен: [{due}] {task}"}
"""
    }

    private static func snippetsPluginCode() -> String {
        return """
-- @name Быстрые шаблоны (.tpl)
-- @id fg_snippets
-- @version 1.0
-- @author FullGram
-- @description Шаблоны ответов: .tpl add <ключ> <текст>, .tpl <ключ>, .tpl list

function on_command(ctx)
    if ctx.command ~= "tpl" then return nil end
    local raw = tostring(ctx.args or "")
    if raw == "" or raw == "list" then
        local keys = tostring(fullgram.storage_get("tpl_keys", ""))
        if keys == "" then
            return { cancel = true, toast = "Шаблонов нет. Добавьте: .tpl add привет Привет! Как дела?" }
        end
        return { cancel = true, toast = "Шаблоны: " .. keys }
    end

    local space1 = string.find(raw, " ")
    local sub = space1 and string.sub(raw, 1, space1 - 1) or raw
    local rest = space1 and string.sub(raw, space1 + 1) or ""

    if sub == "add" and rest ~= "" then
        local space2 = string.find(rest, " ")
        if not space2 then
            return { cancel = true, toast = "Формат: .tpl add <ключ> <текст>" }
        end
        local key = string.lower(string.sub(rest, 1, space2 - 1))
        local body = string.sub(rest, space2 + 1)
        fullgram.storage_set("tpl_" .. key, body)
        local keys = tostring(fullgram.storage_get("tpl_keys", ""))
        if not string.find(keys, key, 1, true) then
            keys = (keys == "") and key or (keys .. ", " .. key)
            fullgram.storage_set("tpl_keys", keys)
        end
        return { cancel = true, toast = "Шаблон «" .. key .. "» сохранён!" }
    end

    local saved = fullgram.storage_get("tpl_" .. string.lower(sub), "")
    if saved ~= nil and saved ~= "" then
        return tostring(saved)
    end
    return { cancel = true, toast = "Шаблон «" .. sub .. "» не найден." }
end
"""
    }

    private static func notesPluginCode() -> String {
        return """
-- @name Быстрые заметки (.note)
-- @id fg_notes
-- @version 1.0
-- @author FullGram
-- @description Личные заметки: .note add <текст>, .note list, .note clear

function on_command(ctx)
    if ctx.command ~= "note" then return nil end
    local raw = tostring(ctx.args or "")
    local saved = tostring(fullgram.storage_get("notes_list", ""))

    if raw == "" or raw == "list" then
        if saved == "" then
            return { cancel = true, toast = "Заметок пока нет. Добавьте: .note add <текст>" }
        end
        return { cancel = true, toast = "📝 Заметки:\\n" .. saved }
    end

    if raw == "clear" then
        fullgram.storage_set("notes_list", "")
        return { cancel = true, toast = "Все заметки очищены." }
    end

    local text = raw
    if string.sub(raw, 1, 4) == "add " then
        text = string.sub(raw, 5)
    end
    if text == "" then
        return { cancel = true, toast = "Укажите текст заметки." }
    end
    local updated = (saved == "") and ("• " .. text) or (saved .. "\\n• " .. text)
    fullgram.storage_set("notes_list", updated)
    return { cancel = true, toast = "Заметка сохранена!" }
end
"""
    }

    private static func chatInfoPluginCode() -> String {
        return """
-- @name 1. Информация о чате
-- @id fg_chat_info
-- @version 1.0
-- @author FullGram
-- @description Команда .plug info-chat: подробная статистика чата (даты первого и последнего сообщения, частые и редкие слова, маты, ГС и кружки).

function on_command(ctx)
    local is_plug_info = (ctx.command == "plug" and ctx.subcommand == "info-chat")
    local is_alias = (ctx.command == "info-chat")
    if not is_plug_info and not is_alias then
        return nil
    end

    local stats = fullgram.get_chat_stats()
    if stats == nil then
        return { cancel = true, toast = "Откройте чат с сообщениями для анализа" }
    end

    local title = stats.title or "Чат"
    local top_line = "нет данных"
    if stats.top_words and #stats.top_words > 0 then
        local parts = {}
        for i = 1, #stats.top_words do
            local item = stats.top_words[i]
            table.insert(parts, tostring(i) .. ". " .. tostring(item.word) .. " (" .. tostring(item.count) .. ")")
        end
        top_line = table.concat(parts, " • ")
    end

    local rare_line = "нет данных"
    if stats.rare_words and #stats.rare_words > 0 then
        local rparts = {}
        for i = 1, #stats.rare_words do
            table.insert(rparts, tostring(stats.rare_words[i].word))
        end
        rare_line = table.concat(rparts, ", ")
    end

    local report = "📊 Информация о чате «" .. tostring(title) .. "»\\n"
        .. "━━━━━━━━━━━━━━━━━━━━\\n"
        .. "🕒 Первое сообщение: " .. tostring(stats.first_date or "—") .. "\\n"
        .. "🕓 Последнее сообщение: " .. tostring(stats.last_date or "—") .. "\\n"
        .. "💬 Проанализировано: " .. tostring(stats.analyzed_count or 0) .. " сообщ.\\n\\n"
        .. "🔥 Частые слова:\\n" .. top_line .. "\\n\\n"
        .. "💎 Самые редкие слова:\\n" .. rare_line .. "\\n\\n"
        .. "🤬 Слов мата: " .. tostring(stats.profanity_count or 0) .. "\\n"
        .. "🎤 Голосовых сообщений: " .. tostring(stats.voice_count or 0) .. "\\n"
        .. "⭕️ Видеокружков: " .. tostring(stats.round_count or 0) .. "\\n"
        .. "━━━━━━━━━━━━━━━━━━━━"

    return report
end
"""
    }

    // MARK: - Remote Plugin Market

    public func fetchRemoteCatalog(urlString: String? = nil, completion: @escaping (Result<FullGramRemoteCatalog, Error>) -> Void) {
        let targetString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveString = (targetString?.isEmpty == false) ? targetString! : self.catalogURL
        guard let url = URL(string: effectiveString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramPlugins", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес каталога плагинов."])))
            }
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, response, error in
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
        completion: @escaping (Result<FullGramPluginDescriptor, Error>) -> Void
    ) {
        if let inlineCode = item.code, !inlineCode.isEmpty {
            let saved = self.savePlugin(id: item.id, name: item.name, language: item.language, code: inlineCode, enabled: enableImmediately)
            DispatchQueue.main.async { completion(.success(saved)) }
            return
        }
        guard let rawUrl = item.url,
              let url = URL(string: rawUrl),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramPlugins", code: 400, userInfo: [NSLocalizedDescriptionKey: "У плагина отсутствует корректная ссылка на скрипт."])))
            }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, response, error in
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
