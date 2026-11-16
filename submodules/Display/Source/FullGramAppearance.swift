import Foundation
import UIKit
import UIKitRuntimeUtils

/// Шрифты, которые лежат в самом приложении (UIAppFonts) и системные гарнитуры iOS.
public enum FullGramFonts {
    public struct Option {
        public let id: String
        public let title: String
        /// PostScript-имя; nil — системный шрифт Telegram.
        public let postScriptName: String?
        public let sample: String
    }

    public static let options: [Option] = [
        Option(id: "system", title: "Системный (SF Pro)", postScriptName: nil, sample: "Привет, Hello 123"),
        Option(id: "jetbrains", title: "JetBrains Mono", postScriptName: "JetBrainsMono-Regular", sample: "Привет, Hello 123"),
        Option(id: "minecraft", title: "Minecraft", postScriptName: "Monocraft", sample: "Привет, Hello 123"),
        Option(id: "dreamfont", title: "DreamFont", postScriptName: "DreamFont-Regular", sample: "Привет, Hello 123"),
        Option(id: "inkitalic", title: "Ink Italic", postScriptName: "InkItalic-Regular", sample: "Привет, Hello 123"),
        Option(id: "narrowx", title: "NARROW X", postScriptName: "NARROWX-Regular", sample: "Привет, Hello 123"),
        Option(id: "slicecut", title: "Slice Cut", postScriptName: "SliceCut-Regular", sample: "Привет, Hello 123"),
        Option(id: "georgia", title: "Georgia (с засечками)", postScriptName: "Georgia", sample: "Привет, Hello 123"),
        Option(id: "menlo", title: "Menlo (моноширинный)", postScriptName: "Menlo-Regular", sample: "Привет, Hello 123"),
        Option(id: "avenir", title: "Avenir Next", postScriptName: "AvenirNext-Regular", sample: "Привет, Hello 123")
    ]

    public static let didChangeNotification = Notification.Name("FullGram.FontChanged")
    private static let key = "fullgram.appearance.fontId"

    public static var selectedId: String {
        get { return UserDefaults.standard.string(forKey: key) ?? "system" }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Шрифты кэшируются в Font, поэтому выбор действует с момента запуска.
    public static let launchFontName: String? = {
        let id = UserDefaults.standard.string(forKey: "fullgram.appearance.fontId") ?? "system"
        guard let name = options.first(where: { $0.id == id })?.postScriptName, UIFont(name: name, size: 12.0) != nil else {
            return nil
        }
        return name
    }()

    public static var needsRelaunch: Bool {
        let id = selectedId
        let current = options.first(where: { $0.id == id })?.postScriptName
        return current != launchFontName
    }
}

/// «Замедление анимаций»: множитель длительности всех анимаций (1 = выкл).
public enum FullGramAnimationSpeed {
    public static let steps: [Double] = [1.0, 2.0, 3.0, 5.0, 10.0]
    private static let key = "fullgram.appearance.slowMotion"

    public static var factor: Double {
        get {
            let value = UserDefaults.standard.double(forKey: key)
            return value >= 1.0 ? value : 1.0
        }
        set {
            UserDefaults.standard.set(max(1.0, min(20.0, newValue)), forKey: key)
            fullGramSetAnimationSlowMotionFactor(FullGramAnimationSpeed.factor)
        }
    }

    public static func applyAtLaunch() {
        fullGramSetAnimationSlowMotionFactor(FullGramAnimationSpeed.factor)
    }
}

/// Тема: пользовательские цвета поверх выбранной темы. Хранится в UserDefaults ("fullgram.theme.*").
public enum FullGramThemeColors {
    public static let didChangeNotification = Notification.Name("FullGram.ThemeColorsChanged")

    public enum Slot: String, CaseIterable {
        case accent
        case outgoingBubble
        case outgoingText
        case incomingBubble
        case incomingText
        case wallpaper
        case wallpaperSecond
        case listBackground
        case chatTitle

        public var titleRu: String {
            switch self {
            case .accent: return "Основной цвет"
            case .outgoingBubble: return "Мои сообщения"
            case .outgoingText: return "Текст моих сообщений"
            case .incomingBubble: return "Входящие сообщения"
            case .incomingText: return "Текст входящих"
            case .wallpaper: return "Фон чата"
            case .wallpaperSecond: return "Фон чата (второй цвет)"
            case .listBackground: return "Фон списков"
            case .chatTitle: return "Названия чатов"
            }
        }
    }

    public struct Preset {
        public let id: String
        public let title: String
        public let colors: [Slot: String]
    }

    private static func key(_ slot: Slot) -> String { return "fullgram.theme." + slot.rawValue }

    public private(set) static var revision: Int = 0

    public static func hex(_ slot: Slot) -> String? {
        let value = UserDefaults.standard.string(forKey: key(slot)) ?? ""
        return value.isEmpty ? nil : value
    }

    public static func parse(_ text: String) -> UInt32? {
        var hex = text.trimmingCharacters(in: CharacterSet(charactersIn: "# \n"))
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return value
    }

    public static func rgb(_ slot: Slot) -> UInt32? {
        return hex(slot).flatMap(parse)
    }

    public static func color(_ slot: Slot) -> UIColor? {
        return rgb(slot).map { UIColor(rgb: $0) }
    }

    public static func set(_ slot: Slot, hex: String?) {
        if let hex, let value = parse(hex) {
            UserDefaults.standard.set(String(format: "#%06X", value), forKey: key(slot))
        } else {
            UserDefaults.standard.removeObject(forKey: key(slot))
        }
        changed()
    }

    public static var hasColors: Bool {
        return Slot.allCases.contains(where: { hex($0) != nil })
    }

    public static var selectedPresetId: String? {
        return UserDefaults.standard.string(forKey: "fullgram.theme.presetId")
    }

    public static func apply(_ preset: Preset) {
        for slot in Slot.allCases {
            if let value = preset.colors[slot] {
                UserDefaults.standard.set(value, forKey: key(slot))
            } else {
                UserDefaults.standard.removeObject(forKey: key(slot))
            }
        }
        UserDefaults.standard.set(preset.id, forKey: "fullgram.theme.presetId")
        changed()
    }

    public static func reset() {
        for slot in Slot.allCases {
            UserDefaults.standard.removeObject(forKey: key(slot))
        }
        UserDefaults.standard.removeObject(forKey: "fullgram.theme.presetId")
        changed()
    }

    public static func markCustom() {
        UserDefaults.standard.set("custom", forKey: "fullgram.theme.presetId")
    }

    private static func changed() {
        revision += 1
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Темы по цвету. AMOLED удалена: за неё отвечает отдельный переключатель «OLED режим».
    public static let presets: [Preset] = [
        Preset(id: "mono-dark", title: "Чёрно-белая (тёмная)", colors: [.accent: "#FFFFFF", .outgoingBubble: "#FFFFFF", .outgoingText: "#000000", .incomingBubble: "#1C1C1E", .incomingText: "#FFFFFF", .wallpaper: "#000000", .listBackground: "#000000", .chatTitle: "#FFFFFF"]),
        Preset(id: "mono-light", title: "Чёрно-белая (светлая)", colors: [.accent: "#000000", .outgoingBubble: "#000000", .outgoingText: "#FFFFFF", .incomingBubble: "#F2F2F2", .incomingText: "#000000", .wallpaper: "#FFFFFF", .listBackground: "#FFFFFF", .chatTitle: "#000000"]),
        Preset(id: "gray", title: "Серая", colors: [.accent: "#8E8E93", .outgoingBubble: "#2C2C2E", .outgoingText: "#FFFFFF", .incomingBubble: "#1C1C1E", .incomingText: "#FFFFFF", .wallpaper: "#000000", .listBackground: "#000000", .chatTitle: "#FFFFFF"]),
        Preset(id: "light-blue", title: "Светло-голубая", colors: [.accent: "#007AFF", .outgoingBubble: "#E1F0FF", .outgoingText: "#000000", .incomingBubble: "#FFFFFF", .incomingText: "#000000", .wallpaper: "#F2F2F7", .chatTitle: "#000000"]),
        Preset(id: "blue", title: "Синяя", colors: [.accent: "#0A84FF", .outgoingBubble: "#0A5BD8", .outgoingText: "#FFFFFF", .incomingBubble: "#14233F", .incomingText: "#E3EEFF", .wallpaper: "#06101F", .wallpaperSecond: "#0D2244", .listBackground: "#06101F"]),
        Preset(id: "purple", title: "Фиолетовая", colors: [.accent: "#BF5AF2", .outgoingBubble: "#7B3FD1", .outgoingText: "#FFFFFF", .incomingBubble: "#25183B", .incomingText: "#F1E7FF", .wallpaper: "#110A1E", .wallpaperSecond: "#2A1446", .listBackground: "#110A1E"]),
        Preset(id: "pink", title: "Розовая", colors: [.accent: "#FF6FA8", .outgoingBubble: "#FFC1DA", .outgoingText: "#3A0A1F", .wallpaper: "#FFF0F6", .wallpaperSecond: "#FFD6E8"]),
        Preset(id: "cyan", title: "Голубая", colors: [.accent: "#1E88E5", .outgoingBubble: "#BBDEFB", .outgoingText: "#0D2A4A", .wallpaper: "#E3F2FD", .wallpaperSecond: "#B3E5FC"]),
        Preset(id: "green", title: "Зелёная", colors: [.accent: "#2E7D32", .outgoingBubble: "#C8E6C9", .outgoingText: "#0F2E12", .wallpaper: "#E8F5E9", .wallpaperSecond: "#DCEDC8"]),
        Preset(id: "orange", title: "Оранжевая", colors: [.accent: "#FF7043", .outgoingBubble: "#FFCCBC", .outgoingText: "#3E1408", .wallpaper: "#FFF3E0", .wallpaperSecond: "#FFE0B2"]),
        Preset(id: "violet", title: "Сиреневая", colors: [.accent: "#8E5CF7", .outgoingBubble: "#5B3FA8", .outgoingText: "#FFFFFF", .incomingBubble: "#2A2140", .incomingText: "#EDE7FF", .wallpaper: "#140F22", .wallpaperSecond: "#24183D"]),
        Preset(id: "turquoise", title: "Бирюзовая", colors: [.accent: "#00E5FF", .outgoingBubble: "#003B46", .outgoingText: "#B2FBFF", .incomingBubble: "#1A1A1A", .incomingText: "#E0E0E0", .wallpaper: "#000000", .wallpaperSecond: "#001A1F"]),
        Preset(id: "dark-green", title: "Тёмно-зелёная", colors: [.accent: "#00FF41", .outgoingBubble: "#003B00", .outgoingText: "#00FF41", .incomingBubble: "#0D0D0D", .incomingText: "#33FF66", .wallpaper: "#000000", .chatTitle: "#00FF41"]),
        Preset(id: "red", title: "Красная", colors: [.accent: "#FF3B30", .outgoingBubble: "#C62828", .outgoingText: "#FFFFFF", .incomingBubble: "#2A1414", .incomingText: "#FFE5E3", .wallpaper: "#140808", .wallpaperSecond: "#2E1010", .listBackground: "#140808", .chatTitle: "#FF6B62"]),
        Preset(id: "gold", title: "Золотая", colors: [.accent: "#FFC107", .outgoingBubble: "#B8860B", .outgoingText: "#FFFFFF", .incomingBubble: "#2B2410", .incomingText: "#FFF3C4", .wallpaper: "#14100A", .wallpaperSecond: "#2A2008", .listBackground: "#14100A", .chatTitle: "#FFD54F"])
    ]
}
