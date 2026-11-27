import Foundation
import UIKit

/// FullGram configurable Night Look for the music player.
public enum FullGramPlayerNightLook {
    public enum Mode: Int, CaseIterable, Sendable {
        case schedule = 0
        case always = 1

        public var title: String {
            switch self {
            case .schedule: return "По расписанию"
            case .always: return "Всегда"
            }
        }
    }

    public enum Strength: Int, CaseIterable, Sendable {
        case soft = 0
        case medium = 1
        case strong = 2

        public var title: String {
            switch self {
            case .soft: return "Слабо"
            case .medium: return "Средне"
            case .strong: return "Сильно"
            }
        }

        public var dimAlpha: CGFloat {
            switch self {
            case .soft: return 0.24
            case .medium: return 0.42
            case .strong: return 0.60
            }
        }
    }

    public enum Tint: Int, CaseIterable, Sendable {
        case warm = 0
        case neutral = 1

        public var title: String {
            switch self {
            case .warm: return "Тёплый"
            case .neutral: return "Нейтральный"
            }
        }

        public var baseColor: UIColor {
            switch self {
            case .warm: return UIColor(red: 0.14, green: 0.08, blue: 0.03, alpha: 1.0)
            case .neutral: return UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1.0)
            }
        }
    }

    public static let didChangeNotification = Notification.Name("FullGram.PlayerNightLookDidChange")

    private static let enabledKey = "fullgram.player.nightLook.enabled"
    private static let modeKey = "fullgram.player.nightLook.mode"
    private static let startHourKey = "fullgram.player.nightLook.startHour"
    private static let endHourKey = "fullgram.player.nightLook.endHour"
    private static let strengthKey = "fullgram.player.nightLook.strength"
    private static let tintKey = "fullgram.player.nightLook.tint"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: modeKey)) ?? .schedule }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: modeKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var startHour: Int {
        get {
            let v = UserDefaults.standard.object(forKey: startHourKey) as? Int ?? 22
            return ((v % 24) + 24) % 24
        }
        set {
            UserDefaults.standard.set(((newValue % 24) + 24) % 24, forKey: startHourKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var endHour: Int {
        get {
            let v = UserDefaults.standard.object(forKey: endHourKey) as? Int ?? 7
            return ((v % 24) + 24) % 24
        }
        set {
            UserDefaults.standard.set(((newValue % 24) + 24) % 24, forKey: endHourKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var strength: Strength {
        get { Strength(rawValue: UserDefaults.standard.object(forKey: strengthKey) as? Int ?? Strength.medium.rawValue) ?? .medium }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: strengthKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var tint: Tint {
        get { Tint(rawValue: UserDefaults.standard.object(forKey: tintKey) as? Int ?? Tint.warm.rawValue) ?? .warm }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: tintKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    private static func postChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
        }
    }

    public static func reset() {
        let d = UserDefaults.standard
        for k in [enabledKey, modeKey, startHourKey, endHourKey, strengthKey, tintKey] {
            d.removeObject(forKey: k)
        }
        self.postChange()
    }

    public static func isNightHour(_ hour: Int, start: Int = FullGramPlayerNightLook.startHour, end: Int = FullGramPlayerNightLook.endHour) -> Bool {
        let h = ((hour % 24) + 24) % 24
        let s = ((start % 24) + 24) % 24
        let e = ((end % 24) + 24) % 24
        if s == e {
            return true
        } else if s < e {
            return h >= s && h < e
        } else {
            return h >= s || h < e
        }
    }

    public static func isCurrentlyActive(date: Date = Date()) -> Bool {
        guard self.isEnabled else { return false }
        switch self.mode {
        case .always:
            return true
        case .schedule:
            let hour = Calendar.current.component(.hour, from: date)
            return self.isNightHour(hour)
        }
    }

    public static func activeOverlayColor(date: Date = Date()) -> UIColor? {
        guard self.isCurrentlyActive(date: date) else { return nil }
        return self.tint.baseColor.withAlphaComponent(self.strength.dimAlpha)
    }
}
