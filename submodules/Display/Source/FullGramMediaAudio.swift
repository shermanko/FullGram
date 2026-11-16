import Foundation

public enum FullGramVoiceMode: String, CaseIterable {
    case off
    case low
    case robot
    case cartoon
    case trippy

    public static let defaultsKey = "fullgram.media.voiceMode"
    public static var current: FullGramVoiceMode {
        get { return UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    public func title(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Выключен" : "Off"
        case .low: return ru ? "Низкий голос" : "Low voice"
        case .robot: return ru ? "Робот" : "Robot"
        case .cartoon: return ru ? "Мультяшный" : "Cartoon"
        case .trippy: return ru ? "Наркоманский" : "Floating"
        }
    }

    public func subtitle(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Обычный голос без изменений" : "Original voice without effects"
        case .low: return ru ? "Пониженный тембр голоса" : "Deep lowered pitch"
        case .robot: return ru ? "Металлический роботизированный голос" : "Metallic ring-modulated voice"
        case .cartoon: return ru ? "Высокий мультяшный голос" : "High cartoon pitch"
        case .trippy: return ru ? "Голос постоянно плавает от высокого к низкому" : "Pitch continuously floats between high and low"
        }
    }
}

public enum FullGramBleepSound: String, CaseIterable {
    case off
    case bell
    case silence
    case dolphin

    public static let defaultsKey = "fullgram.media.bleepSound"
    public static var current: FullGramBleepSound {
        get { return UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    public var isEnabled: Bool {
        return self != .off
    }

    public func title(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Выключено" : "Off"
        case .bell: return ru ? "Звон" : "Chime"
        case .silence: return ru ? "Пустота" : "Silence"
        case .dolphin: return ru ? "Дельфинячий писк" : "Dolphin chirp"
        }
    }

    public func subtitle(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Без запикивания матов" : "No profanity censoring"
        case .bell: return ru ? "Чистый звон вместо мата" : "Clean chime over profanity"
        case .silence: return ru ? "Тишина вместо мата" : "Mute profanity"
        case .dolphin: return ru ? "Писк дельфина из Губки Боба" : "SpongeBob dolphin chirp"
        }
    }
}

public enum FullGramRoundMask: String, CaseIterable {
    case off
    case pixelate
    case blur
    case emoji
    case mascot

    public static let defaultsKey = "fullgram.media.roundMask"
    public static var current: FullGramRoundMask {
        get { return UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    public func title(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Выключено" : "Off"
        case .pixelate: return ru ? "Пикселизация" : "Pixelate"
        case .blur: return ru ? "Размытие" : "Blur"
        case .emoji: return ru ? "Эмодзи" : "Emoji"
        case .mascot: return ru ? "Маскот" : "Mascot"
        }
    }
}

public enum FullGramRoundVideoSettings {
    public static let resolutionKey = "fullgram.media.roundResolution"
    public static let fpsKey = "fullgram.media.roundFps"

    public static let availableResolutions: [Int] = [400, 480, 560, 640]
    public static let availableFps: [Int] = [24, 30, 60]

    public static var resolution: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: resolutionKey)
            return availableResolutions.contains(value) ? value : 480
        }
        set {
            let clamped = availableResolutions.contains(newValue) ? newValue : 480
            UserDefaults.standard.set(clamped, forKey: resolutionKey)
        }
    }

    public static var fps: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: fpsKey)
            return availableFps.contains(value) ? value : 30
        }
        set {
            let clamped = availableFps.contains(newValue) ? newValue : 30
            UserDefaults.standard.set(clamped, forKey: fpsKey)
        }
    }
}

public enum FullGramPlayerTextStyle: String, CaseIterable {
    case karaoke

    /// Karaoke animation is enabled by default with no user-facing toggle.
    public static var current: FullGramPlayerTextStyle {
        return .karaoke
    }
}

public struct FullGramLyricsProviderSettings {
    public static let lrclibKey = "fullgram.media.lyrics.lrclib"
    public static let lyricsOvhKey = "fullgram.media.lyrics.lyricsOvh"
    public static let neteaseKey = "fullgram.media.lyrics.netease"

    public static var useLrclib: Bool {
        get { return UserDefaults.standard.object(forKey: lrclibKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: lrclibKey) }
    }

    public static var useLyricsOvh: Bool {
        get { return UserDefaults.standard.object(forKey: lyricsOvhKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: lyricsOvhKey) }
    }

    public static var useNetEase: Bool {
        get { return UserDefaults.standard.object(forKey: neteaseKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: neteaseKey) }
    }
}

public struct FullGramMixerPreset: Equatable {
    public let id: String
    public let titleRu: String
    public let titleEn: String
    public let gains: [Float]

    public func title(_ ru: Bool) -> String {
        return ru ? self.titleRu : self.titleEn
    }
}

public enum FullGramMixer {
    public static let didChangeNotification = Notification.Name("FullGram.MixerChanged")
    public static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let gainRange: ClosedRange<Float> = -12.0 ... 12.0

    public static let presets: [FullGramMixerPreset] = [
        FullGramMixerPreset(id: "flat", titleRu: "Дефолт", titleEn: "Default", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        FullGramMixerPreset(id: "bass", titleRu: "Басы", titleEn: "Bass", gains: [7.5, 6.0, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0]),
        FullGramMixerPreset(id: "vocal", titleRu: "Вокал", titleEn: "Vocal", gains: [-2.0, -1.5, 0, 1.5, 3.5, 4.5, 4.0, 2.0, 0, -1.0]),
        FullGramMixerPreset(id: "rock", titleRu: "Рок", titleEn: "Rock", gains: [5.0, 4.0, 2.0, -1.0, -2.0, 0.5, 3.0, 4.5, 5.0, 4.5])
    ]

    private static let enabledKey = "fullgram.media.mixer.enabled"
    private static let gainsKey = "fullgram.media.mixer.gains"
    private static let presetKey = "fullgram.media.mixer.preset"

    public static var isEnabled: Bool {
        get { return UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var presetId: String? {
        get { return UserDefaults.standard.string(forKey: presetKey) ?? "flat" }
        set { UserDefaults.standard.set(newValue, forKey: presetKey) }
    }

    public static var gains: [Float] {
        get {
            guard let stored = UserDefaults.standard.array(forKey: gainsKey) as? [NSNumber], stored.count == frequencies.count else {
                return presets[0].gains
            }
            return stored.map { min(gainRange.upperBound, max(gainRange.lowerBound, $0.floatValue)) }
        }
        set {
            let clamped = newValue.prefix(frequencies.count).map { min(gainRange.upperBound, max(gainRange.lowerBound, $0)) }
            let padded = clamped + Array(repeating: Float(0.0), count: max(0, frequencies.count - clamped.count))
            UserDefaults.standard.set(padded.map { NSNumber(value: $0) }, forKey: gainsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var headroomCompensation: Float {
        guard isEnabled else { return 0.0 }
        let peak = gains.max() ?? 0.0
        return peak > 1.0 ? -(peak * 0.55) : 0.0
    }

    public static func apply(preset: FullGramMixerPreset) {
        presetId = preset.id
        isEnabled = preset.id != "flat"
        gains = preset.gains
    }
}
