import Foundation

// MARK: - 1. Система шумоподавления и Студийный микрофон

public enum FullGramNoiseReductionMode: String, CaseIterable {
    case off
    case soft
    case studio
    case aggressive

    public static let defaultsKey = "fullgram.media.noiseReductionMode"
    public static var current: FullGramNoiseReductionMode {
        get { return UserDefaults.standard.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    public var isEnabled: Bool {
        return self != .off
    }

    public func title(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Выключено" : "Off"
        case .soft: return ru ? "Мягкое (Улица / Ветер)" : "Soft (Street / Wind)"
        case .studio: return ru ? "Студийный микрофон" : "Studio Mic"
        case .aggressive: return ru ? "Максимальное (Полная тишина фона)" : "Maximum (Full Noise Gate)"
        }
    }

    public func subtitle(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Без фильтрации фонового шума" : "No background noise filtering"
        case .soft: return ru ? "Убирает гул ветра и кондиционера без изменения голоса" : "Removes low rumble and wind noise"
        case .studio: return ru ? "Шумодав + авто-выравнивание громкости + тёплый радио-голос" : "Noise suppression + auto-leveler + broadcast warmth"
        case .aggressive: return ru ? "Агрессивно отсекает клавиатуру, улицу и посторонние звуки" : "Aggressively gates keyboard and background chatter"
        }
    }
}

// MARK: - 2. Изменение голоса + Конструктор своего голоса

public enum FullGramVoiceMode: String, CaseIterable {
    case off
    case low
    case robot
    case cartoon
    case trippy
    case custom

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
        case .custom: return ru ? "🎛 Свой голос (Конструктор)" : "🎛 Custom Voice"
        }
    }

    public func subtitle(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Обычный голос без изменений" : "Original voice without effects"
        case .low: return ru ? "Пониженный тембр голоса" : "Deep lowered pitch"
        case .robot: return ru ? "Металлический роботизированный голос" : "Metallic ring-modulated voice"
        case .cartoon: return ru ? "Высокий мультяшный голос" : "High cartoon pitch"
        case .trippy: return ru ? "Голос постоянно плавает от высокого к низкому" : "Pitch continuously floats between high and low"
        case .custom: return ru ? "Ручная настройка тона, эха и тембра" : "Custom pitch, echo, and warmth"
        }
    }
}

public enum FullGramCustomVoiceSettings {
    private static let pitchKey = "fullgram.media.customVoice.pitch"
    private static let echoKey = "fullgram.media.customVoice.echo"
    private static let warmthKey = "fullgram.media.customVoice.warmth"

    /// Pitch multiplier: 0.55 (deep bass) ... 1.0 (normal) ... 1.65 (chipmunk)
    public static var pitch: Float {
        get {
            guard UserDefaults.standard.object(forKey: pitchKey) != nil else { return 1.0 }
            return min(1.65, max(0.55, UserDefaults.standard.float(forKey: pitchKey)))
        }
        set {
            UserDefaults.standard.set(min(1.65, max(0.55, newValue)), forKey: pitchKey)
        }
    }

    /// Room echo / slapback reverb mix: 0.0 (dry) ... 0.70 (cathedral echo)
    public static var echo: Float {
        get {
            guard UserDefaults.standard.object(forKey: echoKey) != nil else { return 0.0 }
            return min(0.70, max(0.0, UserDefaults.standard.float(forKey: echoKey)))
        }
        set {
            UserDefaults.standard.set(min(0.70, max(0.0, newValue)), forKey: echoKey)
        }
    }

    /// Vocal warmth / bass-treble tilt: -1.0 (crisp radio) ... 0.0 (neutral) ... +1.0 (warm velvet bass)
    public static var warmth: Float {
        get {
            guard UserDefaults.standard.object(forKey: warmthKey) != nil else { return 0.0 }
            return min(1.0, max(-1.0, UserDefaults.standard.float(forKey: warmthKey)))
        }
        set {
            UserDefaults.standard.set(min(1.0, max(-1.0, newValue)), forKey: warmthKey)
        }
    }

    public static func reset() {
        pitch = 1.0
        echo = 0.0
        warmth = 0.0
    }

    public static func pitchFormatted() -> String {
        let semitones = Int(round(12.0 * log2(Double(pitch))))
        if semitones == 0 {
            return String(format: "%.2fx (Норма)", pitch)
        }
        return String(format: "%.2fx (%+d пт)", pitch, semitones)
    }

    public static func echoFormatted() -> String {
        let pct = Int((echo * 100.0).rounded())
        return pct == 0 ? "Выкл (0%)" : "\(pct)%"
    }

    public static func warmthFormatted() -> String {
        let pct = Int((warmth * 100.0).rounded())
        if pct == 0 { return "Нейтральный (0)" }
        return pct > 0 ? "Тёплый бас (+\(pct)%)" : "Яркий радио (\(pct)%)"
    }
}

// MARK: - 3. Запикивание матов + Кастомный звук

public enum FullGramBleepSound: String, CaseIterable {
    case off
    case bell
    case silence
    case dolphin
    case duck
    case custom

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
        case .dolphin: return ru ? "🐬 Дельфин" : "🐬 Dolphin"
        case .duck: return ru ? "🦆 Утка" : "🦆 Duck"
        case .custom: return ru ? "🎵 Свой звук" : "🎵 Custom sound"
        }
    }

    public func subtitle(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Без запикивания матов" : "No profanity censoring"
        case .bell: return ru ? "Чистый звон вместо мата" : "Clean chime over profanity"
        case .silence: return ru ? "Тишина вместо мата" : "Mute profanity"
        case .dolphin: return ru ? "Оригинальный звук дельфина" : "Dolphin sound clip"
        case .duck: return ru ? "Оригинальный кряк утки" : "Duck quack sound clip"
        case .custom: return ru ? "Ваш записанный или загруженный звук" : "Your recorded or imported audio clip"
        }
    }
}

/// Manages user-recorded or imported custom bleep sound stored on disk (`fullgram_custom_bleep.wav`).
public final class FullGramCustomBleepStore {
    public static let shared = FullGramCustomBleepStore()
    private let lock = NSLock()
    private var cachedNormalized48k: [Float]?
    private static let customNameKey = "fullgram.media.customBleep.name"

    private init() {}

    public var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_custom_bleep.wav")
    }

    public var hasCustomSound: Bool {
        return FileManager.default.fileExists(atPath: self.fileURL.path)
    }

    public var customSoundName: String {
        get {
            if let name = UserDefaults.standard.string(forKey: Self.customNameKey), !name.isEmpty {
                return name
            }
            return self.hasCustomSound ? "Записанный звук" : "Не выбран"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.customNameKey)
        }
    }

    public func saveCustomSamples(_ samples: [Int16], sampleRate: Double, name: String) -> Bool {
        guard !samples.isEmpty, sampleRate > 0 else { return false }
        // Trim leading/trailing silence and cap to 1.8 seconds
        let threshold: Int16 = 350
        let firstIdx = samples.firstIndex(where: { abs(Int($0)) > Int(threshold) }) ?? 0
        let lastIdx = samples.lastIndex(where: { abs(Int($0)) > Int(threshold) }) ?? (samples.count - 1)
        let slice = firstIdx < lastIdx ? Array(samples[firstIdx ... lastIdx]) : samples
        let maxSamples = max(1, Int(sampleRate * 1.8))
        let clipped = slice.count > maxSamples ? Array(slice.prefix(maxSamples)) : slice

        // Normalize peak amplitude so the custom bleep is always clearly audible
        var maxPeak = 1
        for s in clipped {
            let a = abs(Int(s))
            if a > maxPeak { maxPeak = a }
        }
        let gain = min(4.5, 27000.0 / Double(maxPeak))
        let normalized = clipped.map { Int16(max(-32767.0, min(32767.0, Double($0) * gain))) }

        guard FullGramVoiceDSP.writeWAV16Mono(samples: normalized, sampleRate: Int(sampleRate.rounded()), to: self.fileURL) else {
            return false
        }
        self.customSoundName = name
        self.lock.lock()
        self.cachedNormalized48k = nil
        self.lock.unlock()
        return true
    }

    public func importAudioFile(from sourceURL: URL) -> Bool {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        guard let loaded = FullGramVoiceDSP.readWAV16Mono(from: sourceURL), !loaded.samples.isEmpty else {
            return false
        }
        return self.saveCustomSamples(loaded.samples, sampleRate: loaded.sampleRate, name: sourceURL.lastPathComponent)
    }

    public func sampleAt(index: Int, totalSamples: Int, sampleRate: Double) -> Float? {
        let buf = self.loadNormalized48k()
        guard !buf.isEmpty else { return nil }
        // Map requested sampleRate index onto the 48kHz cached custom sound (looping if profanity is longer)
        let pos48k = Int((Double(index) / max(1.0, sampleRate)) * 48000.0) % buf.count
        return buf[max(0, min(buf.count - 1, pos48k))]
    }

    private func loadNormalized48k() -> [Float] {
        self.lock.lock()
        if let cached = self.cachedNormalized48k {
            self.lock.unlock()
            return cached
        }
        self.lock.unlock()

        guard self.hasCustomSound,
              let loaded = FullGramVoiceDSP.readWAV16Mono(from: self.fileURL),
              !loaded.samples.isEmpty else {
            return []
        }
        let src = loaded.samples
        let srcRate = max(8000.0, loaded.sampleRate)
        let outCount = max(1, Int((Double(src.count) * (48000.0 / srcRate)).rounded()))
        var out = [Float](repeating: 0.0, count: outCount)
        for i in 0 ..< outCount {
            let srcPos = Double(i) * (srcRate / 48000.0)
            let idx = min(src.count - 1, max(0, Int(srcPos)))
            out[i] = Float(src[idx]) / 32768.0
        }

        self.lock.lock()
        self.cachedNormalized48k = out
        self.lock.unlock()
        return out
    }
}

// MARK: - 4. Авто-резюме голосовых сообщений (Суть ГС)

public enum FullGramVoiceSummaryMode: String, CaseIterable {
    case off
    case summaryAndText
    case summaryOnly

    public static let defaultsKey = "fullgram.media.voiceSummaryMode"
    public static var current: FullGramVoiceSummaryMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let val = Self(rawValue: raw) else {
                return .summaryAndText
            }
            return val
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    public func title(_ ru: Bool) -> String {
        switch self {
        case .off: return ru ? "Выключено (только текст)" : "Off (full text only)"
        case .summaryAndText: return ru ? "⚡️ Суть ГС + Полный текст" : "⚡️ Summary + Full text"
        case .summaryOnly: return ru ? "⚡️ Только суть (коротко)" : "⚡️ Summary only (TL;DR)"
        }
    }
}

// MARK: - 5. Авто-ответчик без Telegram Premium (AFK Mode)

public final class FullGramAutoResponderSettings {
    public static let shared = FullGramAutoResponderSettings()
    public static let didChangeNotification = Notification.Name("FullGram.AutoResponderChanged")

    public enum Mode: String, CaseIterable {
        case off
        case busy
        case sleeping
        case driving
        case aiSmart
        case custom

        public func title(_ ru: Bool) -> String {
            switch self {
            case .off: return ru ? "Выключен" : "Off"
            case .busy: return ru ? "💼 Занят" : "💼 Busy"
            case .sleeping: return ru ? "🌙 Сплю" : "🌙 Sleeping"
            case .driving: return ru ? "🚗 За рулём" : "🚗 Driving"
            case .aiSmart: return ru ? "✨ Умный ИИ-автоответ" : "✨ Smart AI Reply"
            case .custom: return ru ? "✏️ Свой текст" : "✏️ Custom message"
            }
        }

        public var defaultTemplate: String {
            switch self {
            case .off:
                return ""
            case .busy:
                return "🤖 [Авто-ответ FullGram]: Сейчас занят, прочитаю и отвечу, как только освобожусь!"
            case .sleeping:
                return "🌙 [Авто-ответ FullGram]: Сейчас сплю, отвечу сразу после пробуждения."
            case .driving:
                return "🚗 [Авто-ответ FullGram]: Сейчас за рулём / в дороге, напишу чуть позже."
            case .aiSmart:
                return "✨ [ИИ-автоответчик FullGram]: Сейчас не у телефона, скоро вернусь и отвечу."
            case .custom:
                return "🤖 [Авто-ответ FullGram]: Сейчас не могу ответить, напишу позже!"
            }
        }
    }

    private let modeKey = "fullgram.autoResponder.mode"
    private let customTextKey = "fullgram.autoResponder.customText"
    private let cooldownKey = "fullgram.autoResponder.cooldownSec"
    private let groupsMentionKey = "fullgram.autoResponder.groupsMention"
    private let enabledSinceKey = "fullgram.autoResponder.enabledSince"
    private let sentCountKey = "fullgram.autoResponder.sentCount"

    private let lock = NSLock()
    private var lastRepliedByPeer: [Int64: TimeInterval] = [:]

    private init() {
        if UserDefaults.standard.integer(forKey: self.enabledSinceKey) == 0 {
            UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: self.enabledSinceKey)
        }
    }

    public var mode: Mode {
        get {
            return UserDefaults.standard.string(forKey: self.modeKey).flatMap(Mode.init(rawValue:)) ?? .off
        }
        set {
            let previous = self.mode
            UserDefaults.standard.set(newValue.rawValue, forKey: self.modeKey)
            if previous == .off && newValue != .off {
                self.enabledSinceTimestamp = Int32(Date().timeIntervalSince1970)
                self.resetCooldowns()
            }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var isEnabled: Bool {
        return self.mode != .off
    }

    public var customText: String {
        get {
            let stored = UserDefaults.standard.string(forKey: self.customTextKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? Mode.custom.defaultTemplate : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: self.customTextKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var cooldownSeconds: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: self.cooldownKey)
            return val > 0 ? val : 900
        }
        set {
            UserDefaults.standard.set(max(60, newValue), forKey: self.cooldownKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var replyInGroupsOnMention: Bool {
        get {
            return UserDefaults.standard.object(forKey: self.groupsMentionKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: self.groupsMentionKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public var enabledSinceTimestamp: Int32 {
        get {
            let val = UserDefaults.standard.integer(forKey: self.enabledSinceKey)
            return val > 0 ? Int32(val) : Int32(Date().timeIntervalSince1970)
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: self.enabledSinceKey)
        }
    }

    public var totalRepliesSent: Int {
        get { return UserDefaults.standard.integer(forKey: self.sentCountKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: self.sentCountKey) }
    }

    public var effectiveReplyText: String {
        switch self.mode {
        case .off:
            return ""
        case .custom:
            return self.customText
        default:
            return self.mode.defaultTemplate
        }
    }

    public func canReply(to peerId: Int64) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        let now = Date().timeIntervalSince1970
        if let last = self.lastRepliedByPeer[peerId] {
            return (now - last) >= Double(self.cooldownSeconds)
        }
        return true
    }

    public func markReplied(to peerId: Int64) {
        self.lock.lock()
        self.lastRepliedByPeer[peerId] = Date().timeIntervalSince1970
        self.lock.unlock()
        self.totalRepliesSent += 1
    }

    public func resetCooldowns() {
        self.lock.lock()
        self.lastRepliedByPeer.removeAll()
        self.lock.unlock()
    }
}

// MARK: - Кружки, Тексты и Микшер

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
