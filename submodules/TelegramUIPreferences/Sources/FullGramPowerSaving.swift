import Foundation

/// FullGram power saving settings.
public enum FullGramPowerSaving {
    public enum Mode: Int, CaseIterable, Sendable {
        case telegram = 0
        case off = 1
        case battery = 2
        case always = 3

        public var title: String {
            switch self {
            case .telegram: return "Как в Telegram"
            case .off: return "Никогда"
            case .battery: return "При низком заряде"
            case .always: return "Всегда"
            }
        }
    }

    public enum Limit: String, CaseIterable, Sendable {
        case autoplayVideo
        case autoplayGif
        case loopStickers
        case loopEmoji
        case translucency
        case backgroundWork
        case backgroundDownloads

        public var title: String {
            switch self {
            case .autoplayVideo: return "Автовоспроизведение видео"
            case .autoplayGif: return "Автовоспроизведение GIF"
            case .loopStickers: return "Анимация стикеров"
            case .loopEmoji: return "Анимация эмодзи"
            case .translucency: return "Размытие и стекло"
            case .backgroundWork: return "Работа в фоне"
            case .backgroundDownloads: return "Загрузки в фоне"
            }
        }
    }

    public struct Profile: Equatable, Sendable {
        public var mode: Mode
        public var threshold: Int
        public var followLowPowerMode: Bool
        public var onBatteryOnly: Bool
        public var limits: Set<Limit>

        public init(
            mode: Mode,
            threshold: Int,
            followLowPowerMode: Bool,
            onBatteryOnly: Bool,
            limits: Set<Limit>
        ) {
            self.mode = mode
            self.threshold = min(95, max(5, threshold))
            self.followLowPowerMode = followLowPowerMode
            self.onBatteryOnly = onBatteryOnly
            self.limits = limits
        }

        public static let `default` = Profile(
            mode: .telegram,
            threshold: 20,
            followLowPowerMode: true,
            onBatteryOnly: false,
            limits: Set(Limit.allCases)
        )
    }

    public static let didChangeNotification = Notification.Name("FullGram.PowerSavingDidChange")

    private static let cacheLock = NSLock()
    private static nonisolated(unsafe) var cachedProfile: Profile?

    private static func key(_ suffix: String) -> String {
        return "fullgram.powerSaving.\(suffix)"
    }

    public static func profile() -> Profile {
        self.cacheLock.lock()
        defer { self.cacheLock.unlock() }
        if let cached = self.cachedProfile {
            return cached
        }

        let d = UserDefaults.standard
        let def = Profile.default
        let modeRaw = d.object(forKey: key("mode")) as? Int ?? def.mode.rawValue
        let mode = Mode(rawValue: modeRaw) ?? def.mode
        let threshold = d.object(forKey: key("threshold")) as? Int ?? def.threshold
        let followLPM = d.object(forKey: key("followLPM")) as? Bool ?? def.followLowPowerMode
        let onBattery = d.object(forKey: key("onBattery")) as? Bool ?? def.onBatteryOnly
        var limits = def.limits
        if let rawLimits = d.stringArray(forKey: key("limits")) {
            limits = Set(rawLimits.compactMap { Limit(rawValue: $0) })
        }
        let resolved = Profile(
            mode: mode,
            threshold: threshold,
            followLowPowerMode: followLPM,
            onBatteryOnly: onBattery,
            limits: limits
        )
        self.cachedProfile = resolved
        return resolved
    }

    public static func setProfile(_ profile: Profile) {
        let normalized = Profile(
            mode: profile.mode,
            threshold: min(95, max(5, profile.threshold)),
            followLowPowerMode: profile.followLowPowerMode,
            onBatteryOnly: profile.onBatteryOnly,
            limits: profile.limits
        )
        self.cacheLock.lock()
        self.cachedProfile = normalized
        let d = UserDefaults.standard
        d.set(normalized.mode.rawValue, forKey: key("mode"))
        d.set(normalized.threshold, forKey: key("threshold"))
        d.set(normalized.followLowPowerMode, forKey: key("followLPM"))
        d.set(normalized.onBatteryOnly, forKey: key("onBattery"))
        d.set(normalized.limits.map(\.rawValue).sorted(), forKey: key("limits"))
        self.cacheLock.unlock()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func reset() {
        self.cacheLock.lock()
        self.cachedProfile = nil
        let d = UserDefaults.standard
        for suffix in ["mode", "threshold", "followLPM", "onBattery", "limits"] {
            d.removeObject(forKey: key(suffix))
            for device in ["phone", "tablet", "mac"] {
                d.removeObject(forKey: "fullgram.powerSaving.\(device).\(suffix)")
            }
        }
        self.cacheLock.unlock()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func isSavingActive(
        batteryLevel: Float? = nil,
        isCharging: Bool? = nil,
        isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) -> Bool? {
        let p = self.profile()
        switch p.mode {
        case .telegram:
            return nil
        case .off:
            return false
        case .always:
            return true
        case .battery:
            if p.followLowPowerMode && isLowPowerMode {
                return true
            }
            if p.onBatteryOnly, isCharging == true {
                return false
            }
            if let batteryLevel, batteryLevel.isFinite, batteryLevel >= 0.0 {
                let clamped = min(1.0, max(0.0, batteryLevel))
                let pct = Int((clamped * 100.0).rounded())
                if pct <= p.threshold {
                    return true
                }
            }
            return false
        }
    }

    public static func apply(
        to base: EnergyUsageSettings,
        isSystemLowPowerMode: Bool,
        batteryLevel: Float? = nil,
        isCharging: Bool? = nil
    ) -> EnergyUsageSettings {
        let p = self.profile()
        guard let active = self.isSavingActive(
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            isLowPowerMode: isSystemLowPowerMode
        ) else {
            return isSystemLowPowerMode ? EnergyUsageSettings.powerSavingDefault : base
        }
        guard active else {
            return base
        }
        var result = base
        if p.limits.contains(.translucency) { result.fullTranslucency = false }
        if p.limits.contains(.autoplayVideo) { result.autoplayVideo = false }
        if p.limits.contains(.autoplayGif) { result.autoplayGif = false }
        if p.limits.contains(.loopStickers) { result.loopStickers = false }
        if p.limits.contains(.loopEmoji) { result.loopEmoji = false }
        if p.limits.contains(.backgroundDownloads) { result.autodownloadInBackground = false }
        if p.limits.contains(.backgroundWork) { result.extendBackgroundWork = false }
        return result
    }
}
