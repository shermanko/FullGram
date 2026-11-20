import Foundation
import UIKit

/// FullGram per-device power saving profiles (Phone / Tablet / Mac).
public enum FullGramPowerSaving {
    public enum DeviceKind: String, CaseIterable, Sendable {
        case phone
        case tablet
        case laptop

        public static let current: DeviceKind = {
            if ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp {
                return .laptop
            }
            var size = 0
            sysctlbyname("hw.machine", nil, &size, nil, 0)
            if size > 0 {
                var machine = [CChar](repeating: 0, count: size)
                if sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 {
                    let model = String(cString: machine)
                    if model.hasPrefix("iPad") {
                        return .tablet
                    }
                    if model.hasPrefix("iPhone") || model.hasPrefix("iPod") {
                        return .phone
                    }
                }
            }
            if Thread.isMainThread {
                return MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone }
            }
            return .phone
        }()

        public var title: String {
            switch self {
            case .phone: return "Телефон"
            case .tablet: return "Планшет"
            case .laptop: return "Ноутбук (Mac)"
            }
        }
    }

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

        public static func defaults(for kind: DeviceKind) -> Profile {
            switch kind {
            case .phone:
                return Profile(
                    mode: .telegram,
                    threshold: 20,
                    followLowPowerMode: true,
                    onBatteryOnly: false,
                    limits: Set(Limit.allCases)
                )
            case .tablet:
                return Profile(
                    mode: .telegram,
                    threshold: 15,
                    followLowPowerMode: true,
                    onBatteryOnly: false,
                    limits: [.autoplayVideo, .autoplayGif, .loopStickers, .loopEmoji, .backgroundDownloads]
                )
            case .laptop:
                return Profile(
                    mode: .telegram,
                    threshold: 25,
                    followLowPowerMode: true,
                    onBatteryOnly: true,
                    limits: [.autoplayVideo, .autoplayGif, .translucency, .backgroundDownloads]
                )
            }
        }
    }

    public static let didChangeNotification = Notification.Name("FullGram.PowerSavingDidChange")

    private static func key(_ kind: DeviceKind, _ suffix: String) -> String {
        return "fullgram.powerSaving.\(kind.rawValue).\(suffix)"
    }

    public static func profile(for kind: DeviceKind = .current) -> Profile {
        let d = UserDefaults.standard
        let def = Profile.defaults(for: kind)
        let modeRaw = d.object(forKey: key(kind, "mode")) as? Int ?? def.mode.rawValue
        let mode = Mode(rawValue: modeRaw) ?? def.mode
        let threshold = d.object(forKey: key(kind, "threshold")) as? Int ?? def.threshold
        let followLPM = d.object(forKey: key(kind, "followLPM")) as? Bool ?? def.followLowPowerMode
        let onBattery = d.object(forKey: key(kind, "onBattery")) as? Bool ?? def.onBatteryOnly
        var limits = def.limits
        if let rawLimits = d.stringArray(forKey: key(kind, "limits")) {
            limits = Set(rawLimits.compactMap { Limit(rawValue: $0) })
        }
        return Profile(
            mode: mode,
            threshold: threshold,
            followLowPowerMode: followLPM,
            onBatteryOnly: onBattery,
            limits: limits
        )
    }

    public static func setProfile(_ profile: Profile, for kind: DeviceKind = .current) {
        let d = UserDefaults.standard
        d.set(profile.mode.rawValue, forKey: key(kind, "mode"))
        d.set(min(95, max(5, profile.threshold)), forKey: key(kind, "threshold"))
        d.set(profile.followLowPowerMode, forKey: key(kind, "followLPM"))
        d.set(profile.onBatteryOnly, forKey: key(kind, "onBattery"))
        d.set(profile.limits.map(\.rawValue).sorted(), forKey: key(kind, "limits"))
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func reset(for kind: DeviceKind = .current) {
        let d = UserDefaults.standard
        for suffix in ["mode", "threshold", "followLPM", "onBattery", "limits"] {
            d.removeObject(forKey: key(kind, suffix))
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func isSavingActive(
        for kind: DeviceKind = .current,
        batteryLevel: Float? = nil,
        isCharging: Bool? = nil,
        isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    ) -> Bool? {
        let p = self.profile(for: kind)
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
            if p.onBatteryOnly, let isCharging, !isCharging {
                return true
            }
            if let batteryLevel, batteryLevel >= 0.0 {
                let pct = Int((batteryLevel * 100.0).rounded())
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
        let kind = DeviceKind.current
        let p = self.profile(for: kind)
        guard let active = self.isSavingActive(
            for: kind,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            isLowPowerMode: isSystemLowPowerMode
        ) else {
            return isSystemLowPowerMode ? EnergyUsageSettings.powerSavingDefault : base
        }
        guard active else {
            return base
        }
        var result = EnergyUsageSettings.default
        result.fullTranslucency = !p.limits.contains(.translucency)
        result.autoplayVideo = !p.limits.contains(.autoplayVideo)
        result.autoplayGif = !p.limits.contains(.autoplayGif)
        result.loopStickers = !p.limits.contains(.loopStickers)
        result.loopEmoji = !p.limits.contains(.loopEmoji)
        result.autodownloadInBackground = !p.limits.contains(.backgroundDownloads)
        result.extendBackgroundWork = !p.limits.contains(.backgroundWork)
        return result
    }
}
