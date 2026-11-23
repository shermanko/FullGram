import Foundation
import UIKit
import CoreText
import CoreGraphics
import UIKitRuntimeUtils

/// Встроенные шрифты (UIAppFonts) + 50 шрифтов из GitHub-репозитория FullGram (без нагрузки на Cloudflare).
public enum FullGramFonts {
    public struct Option: Equatable, Sendable {
        public let id: String
        public let title: String
        /// PostScript-имя; nil — системный шрифт Telegram.
        public let postScriptName: String?
        public let sample: String
        public let author: String
        public let subtitle: String
        public let fileName: String?
        public let sizeBytes: Int

        public var isRemote: Bool {
            return self.fileName != nil
        }

        public init(
            id: String,
            title: String,
            postScriptName: String?,
            sample: String,
            author: String = "",
            subtitle: String = "",
            fileName: String? = nil,
            sizeBytes: Int = 0
        ) {
            self.id = id
            self.title = title
            self.postScriptName = postScriptName
            self.sample = sample
            self.author = author
            self.subtitle = subtitle
            self.fileName = fileName
            self.sizeBytes = sizeBytes
        }
    }

    public enum DownloadError: LocalizedError {
        case badResponse
        case invalidFontFile

        public var errorDescription: String? {
            switch self {
            case .badResponse:
                return "Не удалось скачать файл шрифта с GitHub"
            case .invalidFontFile:
                return "Скачанный файл не является корректным шрифтом TTF/OTF"
            }
        }
    }

    private static let rawBaseURL = "https://raw.githubusercontent.com/shermanko/FullGram/master/assets/fonts/"
    private static let cdnBaseURL = "https://cdn.jsdelivr.net/gh/shermanko/FullGram@master/assets/fonts/"
    private static let lock = NSLock()
    private static var registeredIds: Set<String> = []

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        return URLSession(configuration: config)
    }()

    public static let builtInOptions: [Option] = [
        Option(id: "system", title: "Системный (SF Pro)", postScriptName: nil, sample: "Привет, Hello 123", subtitle: "Стандартный шрифт iOS и Telegram"),
        Option(id: "jetbrains", title: "JetBrains Mono (встроенный)", postScriptName: "JetBrainsMono-Regular", sample: "Привет, Hello 123", subtitle: "Моноширинный шрифт в комплекте"),
        Option(id: "minecraft", title: "Minecraft", postScriptName: "Monocraft", sample: "Привет, Hello 123", subtitle: "Пиксельный в стиле Minecraft"),
        Option(id: "dreamfont", title: "DreamFont", postScriptName: "DreamFont-Regular", sample: "Привет, Hello 123", subtitle: "Фирменный декоративный"),
        Option(id: "inkitalic", title: "Ink Italic", postScriptName: "InkItalic-Regular", sample: "Привет, Hello 123", subtitle: "Чернильный наклонный"),
        Option(id: "narrowx", title: "NARROW X", postScriptName: "NARROWX-Regular", sample: "Привет, Hello 123", subtitle: "Узкий акцидентный"),
        Option(id: "slicecut", title: "Slice Cut", postScriptName: "SliceCut-Regular", sample: "Привет, Hello 123", subtitle: "Геометричный с резаными штрихами"),
        Option(id: "georgia", title: "Georgia (с засечками)", postScriptName: "Georgia", sample: "Привет, Hello 123", subtitle: "Системная антиква iOS"),
        Option(id: "menlo", title: "Menlo (моноширинный)", postScriptName: "Menlo-Regular", sample: "Привет, Hello 123", subtitle: "Системный моноширинный iOS"),
        Option(id: "avenir", title: "Avenir Next", postScriptName: "AvenirNext-Regular", sample: "Привет, Hello 123", subtitle: "Системный геометричный iOS")
    ]

    public static let remoteOptions: [Option] = [
        Option(id: "roboto", title: "Roboto", postScriptName: "Roboto-Regular", sample: "Привет, Hello 123", author: "Christian Robertson", subtitle: "Нейтральный гротеск, кириллица и латиница", fileName: "roboto.ttf", sizeBytes: 488584),
        Option(id: "inter", title: "Inter", postScriptName: "Inter-Regular", sample: "Привет, Hello 123", author: "Rasmus Andersson", subtitle: "Чёткий интерфейсный гротеск", fileName: "inter.ttf", sizeBytes: 876576),
        Option(id: "montserrat", title: "Montserrat", postScriptName: "Montserrat-Thin", sample: "Привет, Hello 123", author: "Julieta Ulanovsky", subtitle: "Геометричный широкий шрифт", fileName: "montserrat.ttf", sizeBytes: 744936),
        Option(id: "rubik", title: "Rubik", postScriptName: "Rubik-Light", sample: "Привет, Hello 123", author: "Hubert & Fischer", subtitle: "Мягкий гротеск со скруглёнными углами", fileName: "rubik.ttf", sizeBytes: 359804),
        Option(id: "nunito", title: "Nunito", postScriptName: "Nunito-ExtraLight", sample: "Привет, Hello 123", author: "Vernon Adams", subtitle: "Дружелюбный округлый гротеск", fileName: "nunito.ttf", sizeBytes: 276932),
        Option(id: "comfortaa", title: "Comfortaa", postScriptName: "Comfortaa-Regular", sample: "Привет, Hello 123", author: "Johan Aakerlund", subtitle: "Круглый геометричный стиль", fileName: "comfortaa.ttf", sizeBytes: 201756),
        Option(id: "lobster", title: "Lobster", postScriptName: "Lobster-Regular", sample: "Привет, Hello 123", author: "Pablo Impallari", subtitle: "Жирный декоративный рукописный", fileName: "lobster.ttf", sizeBytes: 406076),
        Option(id: "jetbrainsmono-gf", title: "JetBrains Mono (Google)", postScriptName: "JetBrainsMono-Regular", sample: "Привет, Hello 123", author: "JetBrains", subtitle: "Переменный моноширинный для кода", fileName: "jetbrainsmono-gf.ttf", sizeBytes: 187208),
        Option(id: "manrope", title: "Manrope", postScriptName: "Manrope-ExtraLight", sample: "Привет, Hello 123", author: "Mikhail Sharanda", subtitle: "Современный минималистичный гротеск", fileName: "manrope.ttf", sizeBytes: 164700),
        Option(id: "oswald", title: "Oswald", postScriptName: "Oswald-Regular", sample: "Привет, Hello 123", author: "Vernon Adams", subtitle: "Узкий плакатный шрифт", fileName: "oswald.ttf", sizeBytes: 172088),
        Option(id: "playfairdisplay", title: "Playfair Display", postScriptName: "PlayfairDisplay-Regular", sample: "Привет, Hello 123", author: "Claus Eggers Sørensen", subtitle: "Элегантная антиква с засечками", fileName: "playfairdisplay.ttf", sizeBytes: 300724),
        Option(id: "ptsans", title: "PT Sans", postScriptName: "PTSans-Regular", sample: "Привет, Hello 123", author: "ParaType", subtitle: "Классический русский гротеск", fileName: "ptsans.ttf", sizeBytes: 442960),
        Option(id: "ubuntu", title: "Ubuntu", postScriptName: "Ubuntu-Regular", sample: "Привет, Hello 123", author: "Dalton Maag", subtitle: "Фирменный гротеск Ubuntu", fileName: "ubuntu.ttf", sizeBytes: 351884),
        Option(id: "exo2", title: "Exo 2", postScriptName: "Exo2-Regular", sample: "Привет, Hello 123", author: "Natanael Gama", subtitle: "Технологичный футуристичный гротеск", fileName: "exo2.ttf", sizeBytes: 303940),
        Option(id: "firasans", title: "Fira Sans", postScriptName: "FiraSans-Regular", sample: "Привет, Hello 123", author: "Carrois Apostrophe", subtitle: "Гуманистический гротеск Mozilla", fileName: "firasans.ttf", sizeBytes: 456996),
        Option(id: "opensans", title: "Open Sans", postScriptName: "OpenSans-Regular", sample: "Привет, Hello 123", author: "Steve Matteson", subtitle: "Универсальный читаемый гротеск", fileName: "opensans.ttf", sizeBytes: 532636),
        Option(id: "caveat", title: "Caveat", postScriptName: "Caveat-Regular", sample: "Привет, Hello 123", author: "Impallari Type", subtitle: "Естественный рукописный почерк", fileName: "caveat.ttf", sizeBytes: 403648),
        Option(id: "pressstart2p", title: "Press Start 2P", postScriptName: "PressStart2P-Regular", sample: "Привет, Hello 123", author: "CodeMan38", subtitle: "Пиксельный 8-битный ретро-шрифт", fileName: "pressstart2p.ttf", sizeBytes: 118204),
        Option(id: "unbounded", title: "Unbounded", postScriptName: "Unbounded-Regular", sample: "Привет, Hello 123", author: "NaN", subtitle: "Широкий выразительный акцидентный", fileName: "unbounded.ttf", sizeBytes: 778272),
        Option(id: "golostext", title: "Golos Text", postScriptName: "GolosText-Regular", sample: "Привет, Hello 123", author: "Paratype", subtitle: "Экранный шрифт с отличной кириллицей", fileName: "golostext.ttf", sizeBytes: 184292),
        Option(id: "ibmplexsans", title: "IBM Plex Sans", postScriptName: "IBMPlexSans-Regular", sample: "Привет, Hello 123", author: "IBM", subtitle: "Строгий корпоративный гротеск", fileName: "ibmplexsans.ttf", sizeBytes: 537244),
        Option(id: "yesevaone", title: "Yeseva One", postScriptName: "YesevaOne-Regular", sample: "Привет, Hello 123", author: "Jovanny Lemonad", subtitle: "Изящный шрифт для заголовков", fileName: "yesevaone.ttf", sizeBytes: 108016),
        Option(id: "russoone", title: "Russo One", postScriptName: "RussoOne-Regular", sample: "Привет, Hello 123", author: "Jovanny Lemonad", subtitle: "Жирный спортивный заголовочный", fileName: "russoone.ttf", sizeBytes: 39124),
        Option(id: "amaticsc", title: "Amatic SC", postScriptName: "AmaticSC-Regular", sample: "Привет, Hello 123", author: "Vernon Adams", subtitle: "Узкий рукописный капительный", fileName: "amaticsc.ttf", sizeBytes: 151624),
        Option(id: "raleway", title: "Raleway", postScriptName: "Raleway-Thin", sample: "Привет, Hello 123", author: "Matt McInerney", subtitle: "Лёгкий геометричный гротеск", fileName: "raleway.ttf", sizeBytes: 312352),
        Option(id: "lora", title: "Lora", postScriptName: "Lora-Regular", sample: "Привет, Hello 123", author: "Cyreal", subtitle: "Тёплая современная антиква", fileName: "lora.ttf", sizeBytes: 212196),
        Option(id: "merriweather", title: "Merriweather", postScriptName: "Merriweather-Light", sample: "Привет, Hello 123", author: "Sorkin Type", subtitle: "Классическая книжная антиква", fileName: "merriweather.ttf", sizeBytes: 4628080),
        Option(id: "sourcesans3", title: "Source Sans 3", postScriptName: "SourceSans3-Roman", sample: "Привет, Hello 123", author: "Adobe", subtitle: "Чёткий интерфейсный от Adobe", fileName: "sourcesans3.ttf", sizeBytes: 646340),
        Option(id: "notosans", title: "Noto Sans", postScriptName: "NotoSans-Regular", sample: "Привет, Hello 123", author: "Google", subtitle: "Универсальный стандарт Google", fileName: "notosans.ttf", sizeBytes: 2049096),
        Option(id: "notoserif", title: "Noto Serif", postScriptName: "NotoSerif-Regular", sample: "Привет, Hello 123", author: "Google", subtitle: "Классический антиквенный Noto", fileName: "notoserif.ttf", sizeBytes: 1887192),
        Option(id: "firacode", title: "Fira Code", postScriptName: "FiraCode-Light", sample: "Привет, Hello 123", author: "Nikita Prokopov", subtitle: "Моноширинный с лигатурами", fileName: "firacode.ttf", sizeBytes: 260364),
        Option(id: "spacemono", title: "Space Mono", postScriptName: "SpaceMono-Regular", sample: "Привет, Hello 123", author: "Colophon Foundry", subtitle: "Ретро-футуристичный моноширинный", fileName: "spacemono.ttf", sizeBytes: 99356),
        Option(id: "spacegrotesk", title: "Space Grotesk", postScriptName: "SpaceGrotesk-Light", sample: "Привет, Hello 123", author: "Florian Karsten", subtitle: "Характерный техно-гротеск", fileName: "spacegrotesk.ttf", sizeBytes: 136676),
        Option(id: "cormorantgaramond", title: "Cormorant Garamond", postScriptName: "CormorantGaramond-Light", sample: "Привет, Hello 123", author: "Christian Thalmann", subtitle: "Высококонтрастная книжная классика", fileName: "cormorantgaramond.ttf", sizeBytes: 1195560),
        Option(id: "jura", title: "Jura", postScriptName: "Jura-Light", sample: "Привет, Hello 123", author: "Ten By Twenty", subtitle: "Округлый техно-стиль", fileName: "jura.ttf", sizeBytes: 258404),
        Option(id: "kellyslab", title: "Kelly Slab", postScriptName: "KellySlab-Regular", sample: "Привет, Hello 123", author: "Denis Masharov", subtitle: "Индустриальный брусковый шрифт", fileName: "kellyslab.ttf", sizeBytes: 77816),
        Option(id: "marckscript", title: "Marck Script", postScriptName: "MarckScript-Regular", sample: "Привет, Hello 123", author: "Denis Masharov", subtitle: "Каллиграфический фломастерный", fileName: "marckscript.ttf", sizeBytes: 83664),
        Option(id: "badscript", title: "Bad Script", postScriptName: "BadScript-Regular", sample: "Привет, Hello 123", author: "Gaslight", subtitle: "Небрежный рукописный курсив", fileName: "badscript.ttf", sizeBytes: 184216),
        Option(id: "neucha", title: "Neucha", postScriptName: "Neucha", sample: "Привет, Hello 123", author: "Jovanny Lemonad", subtitle: "Живой ручной шрифт для заметок", fileName: "neucha.ttf", sizeBytes: 141432),
        Option(id: "poiretone", title: "Poiret One", postScriptName: "PoiretOne-Regular", sample: "Привет, Hello 123", author: "Denis Masharov", subtitle: "Тонкий ар-деко геометрик", fileName: "poiretone.ttf", sizeBytes: 130176),
        Option(id: "pangolin", title: "Pangolin", postScriptName: "Pangolin-Regular", sample: "Привет, Hello 123", author: "Kevin Burke", subtitle: "Мягкий комиксный/рукописный", fileName: "pangolin.ttf", sizeBytes: 593408),
        Option(id: "philosopher", title: "Philosopher", postScriptName: "Philosopher-Regular", sample: "Привет, Hello 123", author: "Jovanny Lemonad", subtitle: "Гуманистический с мягкими штрихами", fileName: "philosopher.ttf", sizeBytes: 111676),
        Option(id: "alegreya", title: "Alegreya", postScriptName: "Alegreya-Regular", sample: "Привет, Hello 123", author: "Huerta Tipográfica", subtitle: "Литературная динамичная антиква", fileName: "alegreya.ttf", sizeBytes: 425288),
        Option(id: "arimo", title: "Arimo", postScriptName: "Arimo-Regular", sample: "Привет, Hello 123", author: "Steve Matteson", subtitle: "Метрический аналог Arial/Helvetica", fileName: "arimo.ttf", sizeBytes: 496268),
        Option(id: "tinos", title: "Tinos", postScriptName: "Tinos-Regular", sample: "Привет, Hello 123", author: "Steve Matteson", subtitle: "Метрический аналог Times с кириллицей", fileName: "tinos.ttf", sizeBytes: 521588),
        Option(id: "balsamiqsans", title: "Balsamiq Sans", postScriptName: "BalsamiqSans-Regular", sample: "Привет, Hello 123", author: "Michael Angeles", subtitle: "Дружелюбный вайрфрейм-шрифт", fileName: "balsamiqsans.ttf", sizeBytes: 407528),
        Option(id: "onest", title: "Onest", postScriptName: "Onest-Regular", sample: "Привет, Hello 123", author: "Dmitry Chernyy", subtitle: "Современный медиа-гротеск", fileName: "onest.ttf", sizeBytes: 193056),
        Option(id: "delagothicone", title: "Dela Gothic One", postScriptName: "DelaGothicOne-Regular", sample: "Привет, Hello 123", author: "artakana", subtitle: "Ультражирный японско-кириллический", fileName: "delagothicone.ttf", sizeBytes: 2508848),
        Option(id: "pacifico", title: "Pacifico", postScriptName: "Pacifico-Regular", sample: "Привет, Hello 123", author: "Vernon Adams", subtitle: "Сёрф-каллиграфия", fileName: "pacifico.ttf", sizeBytes: 329380),
        Option(id: "ptmono", title: "PT Mono", postScriptName: "PTMono-Regular", sample: "Привет, Hello 123", author: "ParaType", subtitle: "Строгий русский моноширинный", fileName: "ptmono.ttf", sizeBytes: 185912)
    ]

    public struct CustomFontRecord: Codable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let postScriptName: String
        public let fileName: String
        public let sizeBytes: Int
    }

    public static let options: [Option] = builtInOptions + remoteOptions
    public static var allOptions: [Option] {
        return self.builtInOptions + self.customOptions + self.remoteOptions
    }

    public static let didChangeNotification = Notification.Name("FullGram.FontChanged")
    public static let didRequestAppRestartNotification = Notification.Name("FullGramDidRequestAppRestartNotification")

    private static let reopenFontsAfterRestartKey = "fullgram_reopen_fonts_after_restart"
    private static let customFontsKey = "fullgram.appearance.customFonts"
    private static let key = "fullgram.appearance.fontId"
    private static let psKeyPrefix = "fullgram.appearance.fontPS."
    private static var _cachedLaunchFontName: String? = nil
    private static var _didInitLaunchFontName: Bool = false

    public static var reopenFontsAfterRestart: Bool {
        get { UserDefaults.standard.bool(forKey: self.reopenFontsAfterRestartKey) }
        set { UserDefaults.standard.set(newValue, forKey: self.reopenFontsAfterRestartKey) }
    }

    public static var customOptions: [Option] {
        guard let data = UserDefaults.standard.data(forKey: self.customFontsKey),
              let records = try? JSONDecoder().decode([CustomFontRecord].self, from: data) else {
            return []
        }
        return records.map { rec in
            Option(
                id: rec.id,
                title: rec.title,
                postScriptName: rec.postScriptName,
                sample: "Привет, Hello 123",
                author: "Пользовательский",
                subtitle: rec.fileName,
                fileName: "custom/" + rec.fileName,
                sizeBytes: rec.sizeBytes
            )
        }
    }

    public static func customDirectory() -> URL {
        let dir = self.cacheDirectory().appendingPathComponent("custom", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func resolveLaunchFontNameLocked() -> String? {
        let id = UserDefaults.standard.string(forKey: self.key) ?? "system"
        guard let option = self.allOptions.first(where: { $0.id == id }) else {
            return nil
        }
        let resolvedName: String?
        if option.isRemote {
            resolvedName = self.registerFontFileIfNeeded(option: option)
        } else {
            resolvedName = option.postScriptName
        }
        guard let name = resolvedName, UIFont(name: name, size: 12.0) != nil else {
            return nil
        }
        return name
    }

    public static func reloadActiveFont() {
        for custom in self.customOptions {
            _ = self.registerFontFileIfNeeded(option: custom)
        }
        if let option = self.allOptions.first(where: { $0.id == self.selectedId }) {
            _ = self.registerFontFileIfNeeded(option: option)
        }
        let fresh = self.resolveLaunchFontNameLocked()
        self.lock.lock()
        self._cachedLaunchFontName = fresh
        self._didInitLaunchFontName = true
        self.lock.unlock()
        Font.clearCache()
        NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
    }

    public static var selectedId: String {
        get { return UserDefaults.standard.string(forKey: key) ?? "system" }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FullGram/Fonts", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func cachedFileURL(for option: Option) -> URL? {
        guard let fileName = option.fileName else { return nil }
        if fileName.hasPrefix("custom/") {
            let rel = String(fileName.dropFirst("custom/".count))
            return self.customDirectory().appendingPathComponent(rel)
        }
        return cacheDirectory().appendingPathComponent(fileName)
    }

    public static func isDownloaded(_ option: Option) -> Bool {
        guard let url = cachedFileURL(for: option) else { return true }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    public static func registerFontFileIfNeeded(option: Option) -> String? {
        guard let url = cachedFileURL(for: option), FileManager.default.fileExists(atPath: url.path) else {
            return option.postScriptName
        }
        self.lock.lock()
        let already = self.registeredIds.contains(option.id)
        self.lock.unlock()

        if already, let cachedPS = UserDefaults.standard.string(forKey: psKeyPrefix + option.id) {
            return cachedPS
        }

        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider) else {
            return nil
        }

        _ = CTFontManagerRegisterGraphicsFont(cgFont, nil)
        let psName = (cgFont.postScriptName as String?) ?? option.postScriptName
        if let psName {
            UserDefaults.standard.set(psName, forKey: psKeyPrefix + option.id)
        }
        self.lock.lock()
        self.registeredIds.insert(option.id)
        self.lock.unlock()
        return psName
    }

    public static func importCustomFont(from sourceURL: URL) -> Result<Option, Error> {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            return .failure(error)
        }
        guard data.count > 1024, data.count <= 25_000_000,
              let provider = CGDataProvider(data: data as CFData),
              let cgFont = CGFont(provider),
              let psName = cgFont.postScriptName as String?,
              !psName.isEmpty else {
            return .failure(DownloadError.invalidFontFile)
        }
        let ext = sourceURL.pathExtension.lowercased() == "otf" ? "otf" : "ttf"
        let id = "custom_" + UUID().uuidString.prefix(8).lowercased()
        let fileName = "\(id).\(ext)"
        let destURL = self.customDirectory().appendingPathComponent(fileName)
        do {
            try data.write(to: destURL, options: .atomic)
        } catch {
            return .failure(error)
        }
        _ = CTFontManagerRegisterGraphicsFont(cgFont, nil)
        UserDefaults.standard.set(psName, forKey: self.psKeyPrefix + id)
        self.lock.lock()
        self.registeredIds.insert(id)
        self.lock.unlock()

        let baseTitle = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = baseTitle.isEmpty ? psName : baseTitle
        var records: [CustomFontRecord] = []
        if let raw = UserDefaults.standard.data(forKey: self.customFontsKey),
           let existing = try? JSONDecoder().decode([CustomFontRecord].self, from: raw) {
            records = existing
        }
        records.append(CustomFontRecord(id: id, title: title, postScriptName: psName, fileName: fileName, sizeBytes: data.count))
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: self.customFontsKey)
        }
        let opt = Option(id: id, title: title, postScriptName: psName, sample: "Привет, Hello 123", author: "Пользовательский", subtitle: fileName, fileName: "custom/" + fileName, sizeBytes: data.count)
        NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
        return .success(opt)
    }

    public static func deleteCustomFont(id: String) {
        var records: [CustomFontRecord] = []
        if let raw = UserDefaults.standard.data(forKey: self.customFontsKey),
           let existing = try? JSONDecoder().decode([CustomFontRecord].self, from: raw) {
            records = existing
        }
        if let target = records.first(where: { $0.id == id }) {
            let fileURL = self.customDirectory().appendingPathComponent(target.fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        records.removeAll { $0.id == id }
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: self.customFontsKey)
        }
        if self.selectedId == id {
            self.selectAndRestart(optionId: "system")
        } else {
            NotificationCenter.default.post(name: self.didChangeNotification, object: nil)
        }
    }

    public static func selectAndRestart(optionId: String) {
        if let option = self.allOptions.first(where: { $0.id == optionId }) {
            _ = self.registerFontFileIfNeeded(option: option)
        }
        self.selectedId = optionId
        self.reopenFontsAfterRestart = true
        self.reloadActiveFont()
        NotificationCenter.default.post(name: self.didRequestAppRestartNotification, object: nil)
    }

    public static func downloadAndSelect(option: Option, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        guard let fileName = option.fileName, let destURL = cachedFileURL(for: option) else {
            self.selectAndRestart(optionId: option.id)
            DispatchQueue.main.async { completion(.success(())) }
            return
        }
        if FileManager.default.fileExists(atPath: destURL.path), self.registerFontFileIfNeeded(option: option) != nil {
            self.selectAndRestart(optionId: option.id)
            DispatchQueue.main.async { completion(.success(())) }
            return
        }
        guard let primaryURL = URL(string: rawBaseURL + fileName) else {
            DispatchQueue.main.async { completion(.failure(DownloadError.badResponse)) }
            return
        }
        let fallbackURL = URL(string: cdnBaseURL + fileName)
        fetchFontData(primary: primaryURL, fallback: fallbackURL) { result in
            switch result {
            case let .success(data):
                do {
                    try data.write(to: destURL, options: .atomic)
                    guard self.registerFontFileIfNeeded(option: option) != nil else {
                        try? FileManager.default.removeItem(at: destURL)
                        DispatchQueue.main.async { completion(.failure(DownloadError.invalidFontFile)) }
                        return
                    }
                    DispatchQueue.main.async {
                        self.selectAndRestart(optionId: option.id)
                        completion(.success(()))
                    }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            case let .failure(err):
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }

    private static func fetchFontData(primary: URL, fallback: URL?, completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        var req = URLRequest(url: primary)
        req.setValue("FullGram/1.0", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: req) { data, response, err in
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let data, data.count > 4096 {
                completion(.success(data))
                return
            }
            if let fallback {
                var fbReq = URLRequest(url: fallback)
                fbReq.setValue("FullGram/1.0", forHTTPHeaderField: "User-Agent")
                session.dataTask(with: fbReq) { fbData, fbResp, fbErr in
                    if let http = fbResp as? HTTPURLResponse, http.statusCode == 200,
                       let fbData, fbData.count > 4096 {
                        completion(.success(fbData))
                    } else {
                        completion(.failure(fbErr ?? err ?? DownloadError.badResponse))
                    }
                }.resume()
            } else {
                completion(.failure(err ?? DownloadError.badResponse))
            }
        }.resume()
    }

    public static func clearDownloadedCache() {
        let dir = cacheDirectory()
        if let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in items {
                try? FileManager.default.removeItem(at: item)
            }
        }
        self.lock.lock()
        self.registeredIds.removeAll()
        self.lock.unlock()
        if let current = options.first(where: { $0.id == selectedId }), current.isRemote {
            selectedId = "system"
        } else {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Шрифты кэшируются в Font, поэтому обновляются при reloadActiveFont() и перезапуске UI.
    public static var launchFontName: String? {
        self.lock.lock()
        let initialized = self._didInitLaunchFontName
        let cached = self._cachedLaunchFontName
        self.lock.unlock()
        if initialized {
            return cached
        }
        let resolved = self.resolveLaunchFontNameLocked()
        self.lock.lock()
        self._cachedLaunchFontName = resolved
        self._didInitLaunchFontName = true
        self.lock.unlock()
        return resolved
    }

    public static var needsRelaunch: Bool {
        let id = selectedId
        guard let option = self.allOptions.first(where: { $0.id == id }) else {
            return false
        }
        let current = UserDefaults.standard.string(forKey: psKeyPrefix + option.id) ?? option.postScriptName
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

    public struct Preset: Equatable {
        public let id: String
        public let title: String
        public let colors: [Slot: String]
    }

    private static func key(_ slot: Slot) -> String { return "fullgram.theme." + slot.rawValue }

    private struct CachedSlot {
        let hex: String?
        let rgb: UInt32?
        let color: UIColor?
    }

    private static let cacheLock = NSLock()
    private static var slotCache: [Slot: CachedSlot] = [:]
    private static var cachedHasColors: Bool?
    private static var _revision: Int = 0

    public static var revision: Int {
        self.cacheLock.lock()
        defer { self.cacheLock.unlock() }
        return self._revision
    }

    private static func cachedEntry(for slot: Slot) -> CachedSlot {
        self.cacheLock.lock()
        if let entry = self.slotCache[slot] {
            self.cacheLock.unlock()
            return entry
        }
        let raw = UserDefaults.standard.string(forKey: key(slot)) ?? ""
        let hex: String? = raw.isEmpty ? nil : raw
        let rgb = hex.flatMap(parse)
        let color = rgb.map { UIColor(rgb: $0) }
        let entry = CachedSlot(hex: hex, rgb: rgb, color: color)
        self.slotCache[slot] = entry
        self.cacheLock.unlock()
        return entry
    }

    public static func hex(_ slot: Slot) -> String? {
        return self.cachedEntry(for: slot).hex
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
        return self.cachedEntry(for: slot).rgb
    }

    public static func color(_ slot: Slot) -> UIColor? {
        return self.cachedEntry(for: slot).color
    }

    public static func set(_ slot: Slot, hex: String?) {
        if let hex, let value = parse(hex) {
            UserDefaults.standard.set(String(format: "#%06X", value), forKey: key(slot))
        } else {
            UserDefaults.standard.removeObject(forKey: key(slot))
        }
        self.cacheLock.lock()
        self.slotCache.removeValue(forKey: slot)
        self.cachedHasColors = nil
        self.cacheLock.unlock()
        changed()
    }

    public static var hasColors: Bool {
        self.cacheLock.lock()
        if let v = self.cachedHasColors {
            self.cacheLock.unlock()
            return v
        }
        self.cacheLock.unlock()
        let v = Slot.allCases.contains(where: { hex($0) != nil })
        self.cacheLock.lock()
        self.cachedHasColors = v
        self.cacheLock.unlock()
        return v
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
        self.cacheLock.lock()
        self.slotCache.removeAll()
        self.cachedHasColors = nil
        self.cacheLock.unlock()
        changed()
    }

    public static func reset() {
        for slot in Slot.allCases {
            UserDefaults.standard.removeObject(forKey: key(slot))
        }
        UserDefaults.standard.removeObject(forKey: "fullgram.theme.presetId")
        self.cacheLock.lock()
        self.slotCache.removeAll()
        self.cachedHasColors = false
        self.cacheLock.unlock()
        changed()
    }

    public static func invalidateCache() {
        self.cacheLock.lock()
        self.slotCache.removeAll()
        self.cachedHasColors = nil
        self._revision += 1
        self.cacheLock.unlock()
    }

    public static func markCustom() {
        UserDefaults.standard.set("custom", forKey: "fullgram.theme.presetId")
    }

    private static func changed() {
        self.cacheLock.lock()
        self._revision += 1
        self.cacheLock.unlock()
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
