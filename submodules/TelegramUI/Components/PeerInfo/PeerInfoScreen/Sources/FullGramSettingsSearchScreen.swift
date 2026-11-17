import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

private struct FullGramSearchItem {
    let title: String
    let subtitle: String
    let keywords: String
    let isEnabled: ((AccountContext) -> Bool)?
    let setEnabled: ((AccountContext, Bool) -> Void)?
    let destination: (AccountContext) -> ViewController

    init(
        title: String,
        subtitle: String,
        keywords: String,
        toggle: (get: () -> Bool, set: (Bool) -> Void)? = nil,
        destination: @escaping (AccountContext) -> ViewController
    ) {
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.isEnabled = toggle.map { pair in { _ in pair.get() } }
        self.setEnabled = toggle.map { pair in { _, value in pair.set(value) } }
        self.destination = destination
    }

    init(
        title: String,
        subtitle: String,
        keywords: String,
        contextToggle: (get: (AccountContext) -> Bool, set: (AccountContext, Bool) -> Void),
        destination: @escaping (AccountContext) -> ViewController
    ) {
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.isEnabled = contextToggle.get
        self.setEnabled = contextToggle.set
        self.destination = destination
    }
}

private final class FullGramSearchResultCell: UITableViewCell {
    static let reuseId = "FullGramSearchResultCell"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggleSwitch = UISwitch()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
    private var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.titleLabel.font = .systemFont(ofSize: 16.0, weight: .medium)
        self.titleLabel.numberOfLines = 1
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        self.subtitleLabel.font = .systemFont(ofSize: 12.5)
        self.subtitleLabel.numberOfLines = 2
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        self.toggleSwitch.addTarget(self, action: #selector(self.switchChanged), for: .valueChanged)
        self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = false

        self.chevronView.contentMode = .scaleAspectFit
        self.chevronView.translatesAutoresizingMaskIntoConstraints = false

        self.contentView.addSubview(self.titleLabel)
        self.contentView.addSubview(self.subtitleLabel)
        self.contentView.addSubview(self.toggleSwitch)
        self.contentView.addSubview(self.chevronView)

        NSLayoutConstraint.activate([
            self.titleLabel.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 10.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 16.0),
            self.titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.toggleSwitch.leadingAnchor, constant: -10.0),

            self.subtitleLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 2.0),
            self.subtitleLabel.leadingAnchor.constraint(equalTo: self.titleLabel.leadingAnchor),
            self.subtitleLabel.trailingAnchor.constraint(equalTo: self.titleLabel.trailingAnchor),
            self.subtitleLabel.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -10.0),

            self.toggleSwitch.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.toggleSwitch.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -14.0),

            self.chevronView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.chevronView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -16.0),
            self.chevronView.widthAnchor.constraint(equalToConstant: 12.0),
            self.chevronView.heightAnchor.constraint(equalToConstant: 16.0)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    func configure(with item: FullGramSearchItem, context: AccountContext, theme: PresentationTheme) {
        self.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.titleLabel.text = item.title
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.subtitleLabel.text = item.subtitle
        self.subtitleLabel.textColor = theme.list.itemSecondaryTextColor
        self.toggleSwitch.onTintColor = theme.list.itemAccentColor
        self.chevronView.tintColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.6)

        if let get = item.isEnabled, let set = item.setEnabled {
            self.toggleSwitch.isHidden = false
            self.chevronView.isHidden = true
            self.toggleSwitch.isOn = get(context)
            self.onToggle = { value in
                set(context, value)
            }
        } else {
            self.toggleSwitch.isHidden = true
            self.chevronView.isHidden = false
            self.onToggle = nil
        }
    }

    @objc private func switchChanged() {
        self.onToggle?(self.toggleSwitch.isOn)
    }
}

private final class FullGramSettingsSearchUIViewController: UIViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let theme: PresentationTheme
    var pushController: ((ViewController) -> Void)?

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()

    private let allItems: [FullGramSearchItem]
    private var filteredItems: [FullGramSearchItem] = []

    init(context: AccountContext, theme: PresentationTheme) {
        self.context = context
        self.theme = theme
        self.allItems = Self.buildCatalog()
        self.filteredItems = self.allItems
        super.init(nibName: nil, bundle: nil)
        self.title = "Поиск"
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.theme.list.blocksBackgroundColor

        self.searchBar.placeholder = "Найти настройку, раздел или тумблер…"
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.delegate = self
        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.searchBar)

        self.tableView.backgroundColor = self.theme.list.blocksBackgroundColor
        self.tableView.separatorColor = self.theme.list.itemPlainSeparatorColor
        self.tableView.keyboardDismissMode = .onDrag
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(FullGramSearchResultCell.self, forCellReuseIdentifier: FullGramSearchResultCell.reuseId)
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.tableView)

        self.emptyLabel.text = "Ничего не найдено.\nПопробуйте: призрак, скам, голос, шрифт, загрузка, плагины…"
        self.emptyLabel.font = .systemFont(ofSize: 15.0)
        self.emptyLabel.textColor = self.theme.list.itemSecondaryTextColor
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.numberOfLines = 0
        self.emptyLabel.isHidden = true
        self.emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.emptyLabel)

        NSLayoutConstraint.activate([
            self.searchBar.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 4.0),
            self.searchBar.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 8.0),
            self.searchBar.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -8.0),

            self.tableView.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.emptyLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.emptyLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            self.emptyLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 32.0),
            self.emptyLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -32.0)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.searchBar.becomeFirstResponder()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.applyFilter(query: searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private func applyFilter(query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ё", with: "е")
        if q.isEmpty {
            self.filteredItems = self.allItems
        } else {
            let terms = q.split(separator: " ").map(String.init)
            self.filteredItems = self.allItems.filter { item in
                let haystack = "\(item.title) \(item.subtitle) \(item.keywords)".lowercased().replacingOccurrences(of: "ё", with: "е")
                return terms.allSatisfy { haystack.contains($0) }
            }
        }
        self.emptyLabel.isHidden = !self.filteredItems.isEmpty
        self.tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filteredItems.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let query = self.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return query.isEmpty ? "ВСЕ НАСТРОЙКИ FULLGRAM (\(self.filteredItems.count))" : "НАЙДЕНО (\(self.filteredItems.count))"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: FullGramSearchResultCell.reuseId, for: indexPath) as! FullGramSearchResultCell
        cell.configure(with: self.filteredItems[indexPath.row], context: self.context, theme: self.theme)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.searchBar.resignFirstResponder()
        let item = self.filteredItems[indexPath.row]
        self.pushController?(item.destination(self.context))
    }

    // MARK: - Каталог настроек для поиска

    private static func buildCatalog() -> [FullGramSearchItem] {
        return [
            // Приватность
            FullGramSearchItem(
                title: "Режим призрака",
                subtitle: "Приватность • Не читать, скрывать онлайн и набор текста",
                keywords: "ghost призрак читать онлайн сторис статус невидимка",
                contextToggle: (
                    get: { $0.account.network.fullGramGhostMode.current.isActive },
                    set: { ctx, value in
                        try? ctx.account.network.fullGramGhostMode.update { $0.setAllEnabled(value) }
                    }
                ),
                destination: { fullGramGhostModeController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Деятельность и следы",
                subtitle: "Приватность • Скрытие статусов, звонков и метаданных",
                keywords: "следы статусы игра печать фото видео голос",
                destination: { fullGramActivityAndTracesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Всегда онлайн",
                subtitle: "Приватность → Деятельность и следы",
                keywords: "online статус всегда в сети",
                toggle: ({ FullGramExtras.shared.alwaysOnline }, { FullGramExtras.shared.alwaysOnline = $0 }),
                destination: { fullGramActivityAndTracesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Подтверждать звонки",
                subtitle: "Приватность → Деятельность и следы",
                keywords: "звонок call подтверждение защита",
                toggle: ({ FullGramExtras.shared.confirmCalls }, { FullGramExtras.shared.confirmCalls = $0 }),
                destination: { fullGramActivityAndTracesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Удалять метаданные фото",
                subtitle: "Приватность → Деятельность и следы • EXIF, геопозиция",
                keywords: "exif метаданные фото камера приватность gps",
                toggle: ({ FullGramExtras.shared.removePhotoMetadata }, { FullGramExtras.shared.removePhotoMetadata = $0 }),
                destination: { fullGramActivityAndTracesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Случайные имена файлов",
                subtitle: "Приватность → Деятельность и следы",
                keywords: "имя файла random отправка",
                toggle: ({ FullGramExtras.shared.randomFileNames }, { FullGramExtras.shared.randomFileNames = $0 }),
                destination: { fullGramActivityAndTracesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Чистые ссылки",
                subtitle: "Приватность → Деятельность и следы • Без utm-меток",
                keywords: "utm tracking ссылки чистка",
                toggle: ({ FullGramExtras.shared.cleanLinks }, { FullGramExtras.shared.cleanLinks = $0 }),
                destination: { fullGramActivityAndTracesController(context: $0) }
            ),

            // Чаты
            FullGramSearchItem(
                title: "Удалённые и изменённые сообщения",
                subtitle: "Чаты • Сохранение удалённых и истории правок",
                keywords: "история удаленные измененные сообщения кэш медиаархив",
                destination: { fullGramMessageHistoryController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Сохранять удалённые",
                subtitle: "Чаты → Удалённые и изменённые",
                keywords: "удаленные сообщения история",
                destination: { fullGramMessageHistoryController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Обход ограничений (одноразовые фото/видео)",
                subtitle: "Чаты • Сохранение медиа и пересылка без ограничений",
                keywords: "одноразовые запрет копирования просмотр пересылка защита контента",
                destination: { fullGramRestrictionBypassController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Панель быстрого форматирования",
                subtitle: "Чаты → Сообщение • Кнопки Ж, К, Ч, З, </>, Спойлер над полем ввода",
                keywords: "форматирование жирный курсив спойлер код панель в чате текст",
                toggle: ({ FullGramExtras.shared.quickFormattingBar }, { FullGramExtras.shared.quickFormattingBar = $0 }),
                destination: { fullGramSendingController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Анти-капс и перевод перед отправкой",
                subtitle: "Чаты → Сообщение",
                keywords: "капс переводчик перед отправкой сообщение",
                destination: { fullGramSendingController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Перевод сообщений и провайдеры",
                subtitle: "Чаты → Перевод",
                keywords: "переводчик язык google deepl yandex",
                destination: { fullGramTranslationSettingsController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Меню сообщения и реакции",
                subtitle: "Чаты • Настройка контекстного меню и реакций",
                keywords: "меню сообщения id автор реакции",
                destination: { fullGramMessageMenuController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Безлимит недавних стикеров",
                subtitle: "Чаты • Снимает лимит недавних стикеров",
                keywords: "стикеры лимит недавние",
                contextToggle: (
                    get: { $0.account.network.fullGramGhostMode.current.interface.unlimitedRecentStickers },
                    set: { ctx, value in
                        try? ctx.account.network.fullGramGhostMode.update { $0.interface.unlimitedRecentStickers = value }
                    }
                ),
                destination: { fullGramChatsCategoryController(context: $0) }
            ),

            // Медиа и Аудио
            FullGramSearchItem(
                title: "Голос (изменение голоса)",
                subtitle: "Медиа и Аудио → Голос • Низкий, Робот, Мультяшный, Наркоманский",
                keywords: "voice changer войс голос робот мультяшный наркоманский низкий тембр",
                destination: { fullGramVoiceController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Запикивание матов",
                subtitle: "Медиа и Аудио → Голос • Звон, Пустота, Дельфинячий писк",
                keywords: "маты запикивание цензура губка боб дельфин писк звон",
                destination: { fullGramVoiceController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Кружки и камера (Маски, Разрешение, FPS)",
                subtitle: "Медиа и Аудио → Кружки и камера • Меняет лицо в кружке",
                keywords: "кружки видеосообщения маски пикселизация размытие эмодзи маскот 60 fps 480 640",
                destination: { fullGramRoundVideoController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Микшер (Эквалайзер плеера)",
                subtitle: "Медиа и Аудио → Микшер • Дефолт, Басы, Вокал, Рок",
                keywords: "микшер эквалайзер equalizer частоты басы рок вокал звук",
                toggle: ({ FullGramMixer.isEnabled }, { FullGramMixer.isEnabled = $0 }),
                destination: { fullGramMixerController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Источники текстов песен",
                subtitle: "Медиа и Аудио → Источники текстов • LRCLIB, Lyrics.ovh, NetEase",
                keywords: "тексты песен лирика караоке lrclib lyrics.ovh плеер",
                destination: { fullGramLyricsSourcesController(context: $0) }
            ),

            // Оформление
            FullGramSearchItem(
                title: "Шрифты",
                subtitle: "Оформление → Шрифты • Minecraft, JetBrains Mono, Dream Font",
                keywords: "шрифт font minecraft jetbrains dream локальные",
                destination: { fullGramFontsController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Темы и OLED режим",
                subtitle: "Оформление → Темы • Палитры и конструктор своей темы",
                keywords: "тема темная oled цвета палитра конструктор",
                destination: { fullGramThemesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "OLED режим",
                subtitle: "Оформление → Темы • Настоящий чёрный фон",
                keywords: "oled черный тема amoled",
                toggle: ({ FullGramExtras.shared.oledMode }, { FullGramExtras.shared.oledMode = $0 }),
                destination: { fullGramThemesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Дизайн (Старый дизайн, Светящиеся реакции)",
                subtitle: "Оформление → Дизайн",
                keywords: "старый дизайн telegram классический светящиеся реакции замедление анимаций",
                destination: { fullGramDesignController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Иконки приложения",
                subtitle: "Оформление → Иконки • Монохромные и кастомные (Red, Mascot, Orange)",
                keywords: "иконка приложения mascot красная оранжевая монохромная",
                destination: { fullGramAppIconsController(context: $0) }
            ),

            // Безопасность и Анти-скам
            FullGramSearchItem(
                title: "Защита чатов по Face ID",
                subtitle: "Безопасность • Блокировка выбранных чатов",
                keywords: "face id touch id пароль замок приватный чат",
                toggle: ({ FullGramChatPrivacy.isEnabled }, { FullGramChatPrivacy.isEnabled = $0 }),
                destination: { fullGramSecurityCategoryController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Скрыть мой номер",
                subtitle: "Безопасность • Скрывает номер для скриншотов и стримов",
                keywords: "номер телефона скрыть скриншот демонстрация экрана видео",
                toggle: ({ FullGramExtras.shared.hidePhoneNumber }, { FullGramExtras.shared.hidePhoneNumber = $0 }),
                destination: { fullGramSecurityCategoryController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Размытие в трее",
                subtitle: "Безопасность • Прячет экран в переключателе приложений",
                keywords: "размытие трей свитчер многозадачность",
                toggle: ({ FullGramExtras.shared.blurInAppSwitcher }, { FullGramExtras.shared.blurInAppSwitcher = $0 }),
                destination: { fullGramSecurityCategoryController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Анти-скам и гайд «Не попадись»",
                subtitle: "Безопасность → Анти-скам • Ссылки, файлы, гайд",
                keywords: "анти скам antiscam фишинг гайд инструкция не попадись",
                toggle: ({ FullGramAntiScam.shared.isEnabled }, { FullGramAntiScam.shared.isEnabled = $0 }),
                destination: { fullGramAntiScamController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Анти-офер",
                subtitle: "Безопасность → Анти-скам • Предупреждает, если оффер ненастоящий",
                keywords: "анти офер offer оффер бот пересылка ссылка",
                toggle: ({ FullGramAntiScam.shared.antiOfferEnabled }, { FullGramAntiScam.shared.antiOfferEnabled = $0 }),
                destination: { fullGramAntiScamController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Анти-OTC",
                subtitle: "Безопасность → Анти-скам • Предупреждает о гаранте",
                keywords: "отс otc гарант сделка escrow",
                toggle: ({ FullGramAntiScam.shared.antiOtcEnabled }, { FullGramAntiScam.shared.antiOtcEnabled = $0 }),
                destination: { fullGramAntiScamController(context: $0) }
            ),

            // Прочее и Бэкап
            FullGramSearchItem(
                title: "Бэкап всех настроек (.fullgram)",
                subtitle: "Прочее → Бэкап FullGram • Экспорт и импорт настроек и тем",
                keywords: "бэкап backup экспорт импорт перенос настройки fullgram",
                destination: { fullGramOtherCategoryController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Бейджи FullGram (badges.json)",
                subtitle: "Прочее → Бейджи • Отметки создателя, проекта и Premium-пользователей",
                keywords: "бейджи badges статус создатель премиум fullgram+ сервер",
                toggle: ({ FullGramBadges.shared.isEnabled }, { FullGramBadges.shared.isEnabled = $0 }),
                destination: { fullGramBadgesController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Локальный Premium",
                subtitle: "Прочее • Локальные иконки и функции интерфейса",
                keywords: "premium премиум статус",
                toggle: ({ FullGramExtras.shared.localPremium }, { FullGramExtras.shared.localPremium = $0 }),
                destination: { fullGramOtherCategoryController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Улучшение загрузки",
                subtitle: "Прочее → Основное • Ускорение скачивания и отправки файлов",
                keywords: "скорость загрузки улучшение ускорение интернет скачивание cdn",
                toggle: ({ FullGramExtras.shared.downloadBoost }, { FullGramExtras.shared.downloadBoost = $0 }),
                destination: { fullGramOtherGeneralController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Бесплатная расшифровка голосовых и кружков",
                subtitle: "Прочее → Основное • Локальное распознавание речи без Premium",
                keywords: "расшифровка транскрипция голос в текст кружки голосовые речь speech",
                toggle: ({ FullGramExtras.shared.localFreeTranscription }, { FullGramExtras.shared.localFreeTranscription = $0 }),
                destination: { fullGramOtherGeneralController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Не гасить экран в голосовых и кружках",
                subtitle: "Прочее → Основное • Отключает датчик приближения",
                keywords: "датчик приближения экран гаснет ухо кружок",
                toggle: ({ FullGramExtras.shared.keepScreenOnInVoice }, { FullGramExtras.shared.keepScreenOnInVoice = $0 }),
                destination: { fullGramOtherGeneralController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Показывать ID, время с секундами и точные числа",
                subtitle: "Прочее → Основное",
                keywords: "id секунды округление чисел реклама",
                destination: { fullGramOtherGeneralController(context: $0) }
            ),

            // ИИ Ассистент
            FullGramSearchItem(
                title: "ИИ Ассистент (свой агент по API-ключу)",
                subtitle: "ИИ Ассистент / Прочее • .ai в чатах, сводки, окно и провайдеры",
                keywords: "ии ai агент openai anthropic claude gemini google groq openrouter ключ ассистент",
                toggle: ({ FullGramAIStore.shared.isEnabled }, { FullGramAIStore.shared.isEnabled = $0 }),
                destination: { fullGramAIAssistantController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Питомец (маскот) поверх экрана",
                subtitle: "ИИ Ассистент • Кнопка-маскот на экране для быстрого открытия ИИ-чата",
                keywords: "питомец маскот помощник плавающий экран ai ии",
                toggle: ({ FullGramAIStore.shared.showFloatingPet }, { FullGramAIStore.shared.showFloatingPet = $0 }),
                destination: { fullGramAIAssistantController(context: $0) }
            ),
            FullGramSearchItem(
                title: "Промпт безопасности ИИ-агента",
                subtitle: "ИИ Ассистент → Внутренний системный промпт защиты",
                keywords: "промпт безопасность prompt injection защита ии",
                destination: { fullGramAISecurityPromptController(context: $0) }
            ),

            // Плагины
            FullGramSearchItem(
                title: "Система плагинов (Lua и Python)",
                subtitle: "Плагины • Редактор кода, импорт .lua/.py, команды",
                keywords: "плагины скрипты lua python код редактор",
                toggle: ({ FullGramPluginManager.shared.isSystemEnabled }, { FullGramPluginManager.shared.isSystemEnabled = $0 }),
                destination: { fullGramPluginsController(context: $0) }
            )
        ]
    }
}

private final class FullGramSettingsSearchContainerController: ViewController {
    private let hosted: FullGramSettingsSearchUIViewController

    init(context: AccountContext) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        self.hosted = FullGramSettingsSearchUIViewController(context: context, theme: data.theme)
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: data))
        self.title = "Поиск"
        self.hosted.pushController = { [weak self] controller in
            self?.push(controller)
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func displayNodeDidLoad() {
        super.displayNodeDidLoad()
        self.addChild(self.hosted)
        self.hosted.view.frame = self.displayNode.bounds
        self.hosted.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.displayNode.view.addSubview(self.hosted.view)
        self.hosted.didMove(toParent: self)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.hosted.additionalSafeAreaInsets = UIEdgeInsets(top: topInset, left: layout.safeInsets.left, bottom: layout.intrinsicInsets.bottom, right: layout.safeInsets.right)
    }
}

func fullGramSettingsSearchController(context: AccountContext) -> ViewController {
    return FullGramSettingsSearchContainerController(context: context)
}
