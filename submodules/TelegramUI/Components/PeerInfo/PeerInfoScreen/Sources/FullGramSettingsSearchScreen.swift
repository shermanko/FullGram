import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private struct FullGramSearchItem {
    let id: Int32
    let title: String
    let subtitle: String
    let keywords: String
    let isEnabled: ((AccountContext) -> Bool)?
    let setEnabled: ((AccountContext, Bool) -> Void)?
    let destination: ((AccountContext) -> ViewController)?

    init(
        id: Int32,
        title: String,
        subtitle: String,
        keywords: String,
        toggle: (get: () -> Bool, set: (Bool) -> Void)? = nil,
        destination: ((AccountContext) -> ViewController)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.isEnabled = toggle.map { pair in { _ in pair.get() } }
        self.setEnabled = toggle.map { pair in { _, value in pair.set(value) } }
        self.destination = destination
    }

    init(
        id: Int32,
        title: String,
        subtitle: String,
        keywords: String,
        contextToggle: (get: (AccountContext) -> Bool, set: (AccountContext, Bool) -> Void),
        destination: ((AccountContext) -> ViewController)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.isEnabled = contextToggle.get
        self.setEnabled = contextToggle.set
        self.destination = destination
    }
}

private enum FullGramSearchSection: Int32 {
    case query = 0
    case results = 1
}

private final class FullGramSearchArguments {
    let context: AccountContext
    let updateQuery: (String) -> Void
    let toggleItem: (Int32, Bool) -> Void
    let openItem: (Int32) -> Void

    init(
        context: AccountContext,
        updateQuery: @escaping (String) -> Void,
        toggleItem: @escaping (Int32, Bool) -> Void,
        openItem: @escaping (Int32) -> Void
    ) {
        self.context = context
        self.updateQuery = updateQuery
        self.toggleItem = toggleItem
        self.openItem = openItem
    }
}

private enum FullGramSearchEntry: ItemListNodeEntry {
    case searchInput(String)
    case resultsHeader(String)
    case disclosureItem(Int32, String, String)
    case switchItem(Int32, String, Bool)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .searchInput:
            return FullGramSearchSection.query.rawValue
        case .resultsHeader, .disclosureItem, .switchItem, .empty:
            return FullGramSearchSection.results.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .searchInput: return 0
        case .resultsHeader: return 1
        case let .disclosureItem(id, _, _): return 100 + id
        case let .switchItem(id, _, _): return 100 + id
        case .empty: return 9999
        }
    }

    static func == (lhs: FullGramSearchEntry, rhs: FullGramSearchEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.searchInput(a), .searchInput(b)):
            return a == b
        case let (.resultsHeader(a), .resultsHeader(b)):
            return a == b
        case let (.disclosureItem(ai, at, al), .disclosureItem(bi, bt, bl)):
            return ai == bi && at == bt && al == bl
        case let (.switchItem(ai, at, av), .switchItem(bi, bt, bv)):
            return ai == bi && at == bt && av == bv
        case let (.empty(a), .empty(b)):
            return a == b
        default:
            return false
        }
    }

    static func < (lhs: FullGramSearchEntry, rhs: FullGramSearchEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramSearchArguments
        switch self {
        case let .searchInput(query):
            return ItemListSingleLineInputItem(
                context: args.context,
                presentationData: presentationData,
                systemStyle: .glass,
                title: NSAttributedString(),
                text: query,
                placeholder: "Найти настройку, раздел или тумблер…",
                type: .regular(capitalization: false, autocorrection: false),
                returnKeyType: .search,
                clearType: .always,
                sectionId: self.section,
                textUpdated: { value in
                    args.updateQuery(value)
                },
                action: {},
                cleared: {
                    args.updateQuery("")
                }
            )
        case let .resultsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .disclosureItem(id, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    args.openItem(id)
                }
            )
        case let .switchItem(id, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    args.toggleItem(id, newValue)
                }
            )
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func buildFullGramSearchCatalog() -> [FullGramSearchItem] {
    return [
        // Приватность
        FullGramSearchItem(
            id: 1,
            title: "Режим призрака",
            subtitle: "Приватность",
            keywords: "ghost призрак читать онлайн сторис статус невидимка",
            destination: { fullGramGhostModeController(context: $0) }
        ),
        FullGramSearchItem(
            id: 2,
            title: "Деятельность и следы",
            subtitle: "Приватность",
            keywords: "следы метаданные ссылки онлайн звонки",
            destination: { fullGramActivityAndTracesController(context: $0) }
        ),
        FullGramSearchItem(
            id: 8,
            title: "Скрытие статусов",
            subtitle: "Приватность → Следы",
            keywords: "статусы печатает голосовое кружок стикер игра фото видео файл",
            destination: { fullGramActivityFilterController(context: $0) }
        ),
        FullGramSearchItem(
            id: 3,
            title: "Всегда онлайн",
            subtitle: "Приватность → Следы",
            keywords: "online статус всегда в сети",
            toggle: ({ FullGramExtras.shared.alwaysOnline }, { FullGramExtras.shared.alwaysOnline = $0 })
        ),
        FullGramSearchItem(
            id: 4,
            title: "Подтверждать звонки",
            subtitle: "Приватность → Следы",
            keywords: "звонок call подтверждение защита",
            toggle: ({ FullGramExtras.shared.confirmCalls }, { FullGramExtras.shared.confirmCalls = $0 })
        ),
        FullGramSearchItem(
            id: 5,
            title: "Удалять метаданные фото",
            subtitle: "EXIF, геопозиция",
            keywords: "exif метаданные фото камера приватность gps",
            toggle: ({ FullGramExtras.shared.removePhotoMetadata }, { FullGramExtras.shared.removePhotoMetadata = $0 })
        ),
        FullGramSearchItem(
            id: 6,
            title: "Случайные имена файлов",
            subtitle: "Приватность → Следы",
            keywords: "имя файла random отправка",
            toggle: ({ FullGramExtras.shared.randomFileNames }, { FullGramExtras.shared.randomFileNames = $0 })
        ),
        FullGramSearchItem(
            id: 7,
            title: "Чистые ссылки (без utm)",
            subtitle: "Приватность → Следы",
            keywords: "utm tracking ссылки чистка",
            toggle: ({ FullGramExtras.shared.cleanLinks }, { FullGramExtras.shared.cleanLinks = $0 })
        ),

        // Чаты
        FullGramSearchItem(
            id: 10,
            title: "Удалённые и изменённые сообщения",
            subtitle: "Чаты",
            keywords: "история удаленные измененные сообщения кэш медиаархив",
            destination: { fullGramMessageHistoryController(context: $0) }
        ),
        FullGramSearchItem(
            id: 11,
            title: "Обход ограничений (одноразовые медиа)",
            subtitle: "Чаты",
            keywords: "одноразовые запрет копирования просмотр пересылка защита контента",
            destination: { fullGramRestrictionBypassController(context: $0) }
        ),
        FullGramSearchItem(
            id: 12,
            title: "Панель быстрого форматирования",
            subtitle: "Чаты → Сообщение",
            keywords: "форматирование жирный курсив спойлер код панель в чате текст",
            toggle: ({ FullGramExtras.shared.quickFormattingBar }, { FullGramExtras.shared.quickFormattingBar = $0 })
        ),
        FullGramSearchItem(
            id: 13,
            title: "Сообщение (Анти-капс, автоперевод)",
            subtitle: "Чаты",
            keywords: "капс переводчик перед отправкой сообщение",
            destination: { fullGramSendingController(context: $0) }
        ),
        FullGramSearchItem(
            id: 14,
            title: "Перевод сообщений и провайдеры",
            subtitle: "Чаты",
            keywords: "переводчик язык google deepl yandex",
            destination: { fullGramTranslationSettingsController(context: $0) }
        ),
        FullGramSearchItem(
            id: 15,
            title: "Меню сообщения и реакции",
            subtitle: "Чаты",
            keywords: "меню сообщения id автор реакции",
            destination: { fullGramMessageMenuController(context: $0) }
        ),
        FullGramSearchItem(
            id: 16,
            title: "Безлимит недавних стикеров",
            subtitle: "Чаты",
            keywords: "стикеры лимит недавние",
            contextToggle: (
                get: { $0.account.network.fullGramGhostMode.current.interface.unlimitedRecentStickers },
                set: { ctx, value in
                    try? ctx.account.network.fullGramGhostMode.update { $0.interface.unlimitedRecentStickers = value }
                }
            )
        ),

        // Медиа и Аудио
        FullGramSearchItem(
            id: 20,
            title: "Голос, Шумодав и запикивание матов",
            subtitle: "Медиа и Аудио",
            keywords: "voice changer войс голос робот мультяшный наркоманский низкий маты запикивание шумоподавление шумодав студийный микрофон",
            destination: { fullGramVoiceController(context: $0) }
        ),
        FullGramSearchItem(
            id: 24,
            title: "Шумоподавление и Студийный микрофон",
            subtitle: "Медиа и Аудио → Голос",
            keywords: "шумоподавление шумодав микрофон ветер улица студийный голос",
            destination: { fullGramVoiceController(context: $0) }
        ),
        FullGramSearchItem(
            id: 25,
            title: "Конструктор своего голоса (Pitch / Эхо / Тембр)",
            subtitle: "Медиа и Аудио → Голос",
            keywords: "конструктор свой голос питч тон эхо реверберация тембр бас",
            destination: { fullGramVoiceController(context: $0) }
        ),
        FullGramSearchItem(
            id: 26,
            title: "Свой звук запикивания матов (запись / файл)",
            subtitle: "Медиа и Аудио → Голос",
            keywords: "свой звук кастомный запикивание кряк утки монетка",
            destination: { fullGramVoiceController(context: $0) }
        ),
        FullGramSearchItem(
            id: 27,
            title: "Авто-резюме голосовых (⚡️ Суть ГС)",
            subtitle: "Медиа и Аудио → Голос",
            keywords: "авто резюме суть гс коротко выжимка расшифровка голосовых",
            destination: { fullGramVoiceController(context: $0) }
        ),
        FullGramSearchItem(
            id: 17,
            title: "Авто-ответчик",
            subtitle: "Чаты",
            keywords: "автоответчик авто ответчик afk занят сплю за рулем",
            destination: { fullGramAutoResponderController(context: $0) }
        ),
        FullGramSearchItem(
            id: 21,
            title: "Кружки и камера (Маски, FPS)",
            subtitle: "Медиа и Аудио",
            keywords: "кружки видеосообщения маски пикселизация размытие эмодзи маскот 60 fps",
            destination: { fullGramRoundVideoController(context: $0) }
        ),
        FullGramSearchItem(
            id: 22,
            title: "Микшер (Эквалайзер плеера)",
            subtitle: "Медиа и Аудио",
            keywords: "микшер эквалайзер equalizer частоты басы рок вокал звук",
            destination: { fullGramMixerController(context: $0) }
        ),
        FullGramSearchItem(
            id: 23,
            title: "Источники текстов песен",
            subtitle: "Медиа и Аудио",
            keywords: "тексты песен лирика караоке lrclib lyrics.ovh плеер",
            destination: { fullGramLyricsSourcesController(context: $0) }
        ),

        // Оформление
        FullGramSearchItem(
            id: 30,
            title: "Шрифты (50+ шрифтов с GitHub)",
            subtitle: "Оформление",
            keywords: "шрифт font minecraft jetbrains dream локальные github каталог roboto inter montserrat",
            destination: { fullGramFontsController(context: $0) }
        ),
        FullGramSearchItem(
            id: 31,
            title: "Темы и конструктор палитры",
            subtitle: "Оформление",
            keywords: "тема темная oled цвета палитра конструктор",
            destination: { fullGramThemesController(context: $0) }
        ),
        FullGramSearchItem(
            id: 32,
            title: "OLED режим",
            subtitle: "Оформление → Темы",
            keywords: "oled черный тема amoled",
            toggle: ({ FullGramExtras.shared.oledMode }, { FullGramExtras.shared.oledMode = $0 })
        ),
        FullGramSearchItem(
            id: 33,
            title: "Дизайн (Удаление стекла, реакции)",
            subtitle: "Оформление",
            keywords: "удаление стекла убрать стекло заливка цвет старый дизайн telegram классический светящиеся реакции замедление анимаций",
            destination: { fullGramDesignController(context: $0) }
        ),
        FullGramSearchItem(
            id: 35,
            title: "Удаление стекла (сплошная заливка)",
            subtitle: "Оформление → Дизайн",
            keywords: "стекло убрать удалить без стекла заливка цвет плоские панели",
            toggle: ({ FullGramExtras.shared.removeGlass }, { FullGramExtras.shared.removeGlass = $0 })
        ),
        FullGramSearchItem(
            id: 34,
            title: "Иконки приложения",
            subtitle: "Оформление",
            keywords: "иконка приложения mascot красная зелёная синяя жёлтая розовая белая цветная",
            destination: { fullGramAppIconsController(context: $0) }
        ),
        FullGramSearchItem(
            id: 36,
            title: "Энергосбережение",
            subtitle: "Прочее",
            keywords: "энергосбережение батарея заряд экономия анимации автовоспроизведение",
            destination: { fullGramPowerSavingController(context: $0) }
        ),

        // Безопасность и Анти-скам
        FullGramSearchItem(
            id: 40,
            title: "Защита чатов по Face ID",
            subtitle: "Безопасность",
            keywords: "face id touch id пароль замок приватный чат",
            toggle: ({ FullGramChatPrivacy.isEnabled }, { FullGramChatPrivacy.isEnabled = $0 })
        ),
        FullGramSearchItem(
            id: 41,
            title: "Скрыть мой номер",
            subtitle: "Безопасность",
            keywords: "номер телефона скрыть скриншот демонстрация экрана видео",
            toggle: ({ FullGramExtras.shared.hidePhoneNumber }, { FullGramExtras.shared.hidePhoneNumber = $0 })
        ),
        FullGramSearchItem(
            id: 42,
            title: "Размытие в трее",
            subtitle: "Безопасность",
            keywords: "размытие трей свитчер многозадачность",
            toggle: ({ FullGramExtras.shared.blurInAppSwitcher }, { FullGramExtras.shared.blurInAppSwitcher = $0 })
        ),
        FullGramSearchItem(
            id: 43,
            title: "Анти-скам (Мануал, Анти-OTC, Анти-офер)",
            subtitle: "Раздел",
            keywords: "анти скам antiscam фишинг гайд мануал инструкция не попадись отс офер",
            destination: { fullGramAntiScamController(context: $0) }
        ),
        FullGramSearchItem(
            id: 44,
            title: "Анти-офер",
            subtitle: "Анти-скам",
            keywords: "анти офер offer оффер бот пересылка ссылка",
            toggle: ({ FullGramAntiScam.shared.antiOfferEnabled }, { FullGramAntiScam.shared.antiOfferEnabled = $0 })
        ),
        FullGramSearchItem(
            id: 45,
            title: "Анти-OTC",
            subtitle: "Анти-скам",
            keywords: "отс otc гарант сделка escrow",
            toggle: ({ FullGramAntiScam.shared.antiOtcEnabled }, { FullGramAntiScam.shared.antiOtcEnabled = $0 })
        ),

        // Прочее и Бэкап
        FullGramSearchItem(
            id: 50,
            title: "Бэкап и настройки «Прочее» (.fullgram)",
            subtitle: "Прочее",
            keywords: "бэкап backup экспорт импорт перенос настройки fullgram",
            destination: { fullGramOtherCategoryController(context: $0) }
        ),
        FullGramSearchItem(
            id: 51,
            title: "Бейджи FullGram (badges.json)",
            subtitle: "Прочее",
            keywords: "бейджи badges статус создатель премиум fullgram+ сервер",
            destination: { fullGramBadgesController(context: $0) }
        ),
        FullGramSearchItem(
            id: 52,
            title: "Локальный Premium",
            subtitle: "Прочее",
            keywords: "premium премиум статус",
            toggle: ({ FullGramExtras.shared.localPremium }, { FullGramExtras.shared.localPremium = $0 })
        ),
        FullGramSearchItem(
            id: 53,
            title: "Улучшение загрузки и множитель (x2–x8)",
            subtitle: "Прочее → Основное",
            keywords: "скорость загрузки улучшение ускорение множитель x2 x3 x4 x6 x8 cdn",
            destination: { fullGramOtherGeneralController(context: $0) }
        ),
        FullGramSearchItem(
            id: 54,
            title: "Бесплатная расшифровка голосовых и кружков",
            subtitle: "Прочее → Основное",
            keywords: "расшифровка транскрипция голос в текст кружки голосовые речь speech",
            toggle: ({ FullGramExtras.shared.localFreeTranscription }, { FullGramExtras.shared.localFreeTranscription = $0 })
        ),
        FullGramSearchItem(
            id: 55,
            title: "Не гасить экран в голосовых и кружках",
            subtitle: "Прочее → Основное",
            keywords: "датчик приближения экран гаснет ухо кружок",
            toggle: ({ FullGramExtras.shared.keepScreenOnInVoice }, { FullGramExtras.shared.keepScreenOnInVoice = $0 })
        ),

        // ИИ Ассистент
        FullGramSearchItem(
            id: 60,
            title: "ИИ Ассистент (свой агент и сводки)",
            subtitle: "ИИ Ассистент",
            keywords: "ии ai агент openai anthropic claude gemini google groq openrouter ключ ассистент сводка",
            destination: { fullGramAIAssistantController(context: $0) }
        ),
        FullGramSearchItem(
            id: 61,
            title: "Питомец (маскот) поверх экрана",
            subtitle: "ИИ Ассистент",
            keywords: "питомец маскот помощник плавающий экран ai ии",
            toggle: ({ FullGramAIStore.shared.showFloatingPet }, { FullGramAIStore.shared.showFloatingPet = $0 })
        ),
        FullGramSearchItem(
            id: 62,
            title: "Промпт безопасности ИИ-агента",
            subtitle: "ИИ Ассистент",
            keywords: "промпт безопасность prompt injection защита ии",
            destination: { fullGramAISecurityPromptController(context: $0) }
        ),

        // Плагины
        FullGramSearchItem(
            id: 70,
            title: "Система плагинов (Lua и Python)",
            subtitle: "Плагины",
            keywords: "плагины скрипты lua python код редактор маркет информация о чате",
            destination: { fullGramPluginsController(context: $0) }
        )
    ]
}

func fullGramSettingsSearchController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let canOpenAdmin = fullGramCanOpenAdmin(context: context)
    let catalog = buildFullGramSearchCatalog().filter { $0.id != 51 || canOpenAdmin }
    let queryPromise = ValuePromise<String>("", ignoreRepeated: true)
    let tickPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        tickPromise.set(tick)
    }

    let extrasObs = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in bump() }
    let antiScamObs = NotificationCenter.default.addObserver(forName: FullGramAntiScam.didChangeNotification, object: nil, queue: .main) { _ in bump() }
    let aiObs = NotificationCenter.default.addObserver(forName: FullGramAINotifications.settingsChanged, object: nil, queue: .main) { _ in bump() }
    let pluginObs = NotificationCenter.default.addObserver(forName: FullGramPluginNotifications.pluginsDidChange, object: nil, queue: .main) { _ in bump() }

    let args = FullGramSearchArguments(
        context: context,
        updateQuery: { value in
            queryPromise.set(value)
        },
        toggleItem: { id, newValue in
            if let item = catalog.first(where: { $0.id == id }) {
                item.setEnabled?(context, newValue)
                bump()
            }
        },
        openItem: { id in
            if let item = catalog.first(where: { $0.id == id }), let makeDestination = item.destination {
                pushImpl?(makeDestination(context))
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, queryPromise.get(), tickPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, query, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        let filtered: [FullGramSearchItem]
        if normalized.isEmpty {
            filtered = catalog
        } else {
            let terms = normalized.split(separator: " ").map(String.init)
            filtered = catalog.filter { item in
                let haystack = "\(item.title) \(item.subtitle) \(item.keywords)"
                    .lowercased()
                    .replacingOccurrences(of: "ё", with: "е")
                return terms.allSatisfy { haystack.contains($0) }
            }
        }

        var entries: [FullGramSearchEntry] = [
            .searchInput(query),
            .resultsHeader(normalized.isEmpty ? "ВСЕ НАСТРОЙКИ FULLGRAM (\(filtered.count))" : "НАЙДЕНО (\(filtered.count))")
        ]

        if filtered.isEmpty {
            entries.append(.empty("Ничего не найдено.\nПопробуйте: призрак, скам, отс, офер, голос, шрифт, загрузка, плагины…"))
        } else {
            for item in filtered {
                if let getter = item.isEnabled {
                    entries.append(.switchItem(item.id, item.title, getter(context)))
                } else {
                    entries.append(.disclosureItem(item.id, item.title, item.subtitle))
                }
            }
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Поиск"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(extrasObs)
        NotificationCenter.default.removeObserver(antiScamObs)
        NotificationCenter.default.removeObserver(aiObs)
        NotificationCenter.default.removeObserver(pluginObs)
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in controller?.push(c) }
    return controller
}
