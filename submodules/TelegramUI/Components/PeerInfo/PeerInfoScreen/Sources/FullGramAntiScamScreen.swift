import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

// MARK: - Гайд «Не попадись» (структурированный экран, легко наполняемый через массив блоков)

private enum FullGramGuideBlock {
    case heading(String)
    case placeholder(String)
    case step(number: Int, title: String, text: String)
    case example(title: String, text: String)
    case important(title: String, text: String)
}

private enum FullGramGuideContent {
    static let screenTitle = "Не попадись"

    static let blocks: [FullGramGuideBlock] = [
        .heading("Простой антискам-мануал: как не просрать подарки, крипту и аккаунт в Telegram"),
        .important(
            title: "Главное правило (запомни раз и навсегда)",
            text: "Никогда не покупай и не продавай ничего «с рук» в личных сообщениях, не переходи по ссылкам от незнакомцев и не подключай чужих ботов. Почти всегда это развод."
        ),

        .heading("1. На чём сейчас ловят чаще всего"),
        .placeholder("Свежие разборы Борова @borov_club / TikTok @borov_tut и экспертов"),
        .example(
            title: "❄️ «50 звёзд и ссылка на награду» (моментальный бан)",
            text: "Тебе просто так кидают 50 звёзд (через Fragment), а потом просят нажать на ссылку «забрать бонус». Внутри ссылки зашит текст фейк-оффера — как только кликнешь, антифрод Telegram сразу заморозит твой аккаунт."
        ),
        .example(
            title: "📱 Взлом через старый iPhone",
            text: "У человека на старой iOS просто от открытия левого сайта сработала уязвимость DarkSword — украли 3 000 USD из кошелька и анонимный номер +888.\n\nМораль: всегда обновляй телефон."
        ),
        .example(
            title: "💸 Дешёвые офферы за 125 звёзд",
            text: "Мошенники пачками кидают минимальные ставки (125 звёзд) на дорогие подарки в расчёте, что ты сонный/в спешке нажмёшь «Принять» (так уже случайно отдали Plush Pepe #583)."
        ),
        .example(
            title: "🤖 Бот-воришка в настройках бизнеса",
            text: "Тебе предлагают «проверить редкость подарка» или «автоматически скупать дешёвые лоты» — нужно лишь добавить бота в Настройки → Telegram Business → Чат-боты (с мая 2026 года это работает даже без Premium). Как только добавишь, бот сам без твоего спроса переведёт и продаст все твои подарки и звёзды."
        ),
        .example(
            title: "🎭 Красивые кнопки в личке",
            text: "Незнакомец кидает выгодное предложение с красивой кнопкой от бизнес-бота. Нажимаешь — вылезает поддельное окно входа в Telegram. Вводишь номер и код — твой аккаунт угнали."
        ),
        .example(
            title: "🕵️‍♂️ Клоны блогеров",
            text: "Под известных ребят постоянно косят фейки. Настоящий владелец канала Борова (@tut_borov) никогда не пишет первым, не выступает гарантом и ничего не покупает с рук (настоящие ссылки только на borovtut.com)."
        ),
        .example(
            title: "🎬 «Заработок на TikTok» и фейк-подарки",
            text: "Зовут «смотреть видео за 2 евро», «пройти проверку для аирдропа» (где надо закинуть свою крипту) или шлют со взломанного аккаунта друга ссылку на «бесплатный Telegram Premium».\n\nИтог один — у тебя украдут либо деньги, либо аккаунт."
        ),

        .heading("2. Как разводят на OTC (сделки «с рук» в чатах и личке)"),
        .placeholder("Сделки в личке почти всегда заканчиваются скамом. Вот 4 любимых приёма жуликов:"),
        .example(
            title: "Подставной гарант",
            text: "Тебе кидают ссылку на якобы известного гаранта (на самом деле — бот-клон или аккаунт с похожим ником), а после перевода денег ещё и требуют доплатить за выдуманный «возвратный НДС». Из-за такого скам-гаранта держатель из Китая уже потерял 3 подарка Plush Pepe на 47 000 TON."
        ),
        .example(
            title: "Фальшивые OTC-чаты",
            text: "Жулики создают чат от имени блогера, нагоняют туда ботов, которые якобы покупают и продают подарки (WTS/WTB), чтобы ты поверил и перевёл актив."
        ),
        .example(
            title: "Схема «Треугольник»",
            text: "Мошенник сводит двух честных людей (один платит деньгами, второй отдаёт товар/подарок). В итоге деньги получает не тот, подарок забирает мошенник, а крайним остаёшься ты."
        ),
        .example(
            title: "Рисованные скриншоты и «левые» NFT",
            text: "Шлют фейковый скрин перевода («деньги зависли в банке, вот-вот придут») и просят отдать подарок первым. А в закрытых чатах ещё и продают визуальные копии популярных NFT или искусственно гоняют цену ботами вверх, чтобы впарить пустышку новичку."
        ),

        .heading("3. Красные флаги: если видишь это — сразу кидай в ЧС"),
        .important(
            title: "Немедленно прекращай диалог, если:",
            text: """
❌ Тебе пишут первыми в личку и предлагают за твой подарок цену выше рынка.

❌ Уводят с официального маркета на сторонний сайт, в «своего бота-чекера» или к «проверенному гаранту».

❌ Торопят: «Давай быстрее, предложение сгорит, у меня нет времени».

❌ Просят кинуть подарок/деньги первым, показать скрин, оплатить «комиссию» или «подтвердить личность депозитом».

❌ В кошельке просят подписать непонятную хрень (Sign или Approve) на левом сайте — так работает кошельковый дрейнер, который потом сам спишет всё подчистую.

❌ «Техподдержка» просит сид-фразу (12/24 секретных слова) — например, оставляет свой Telegram в комментарии к транзакции на 0.01 TON, как было с Tonkeeper. Настоящая поддержка никогда не просит секретные слова.
"""
        ),

        .heading("4. Что настроить в телефоне за 2 минуты (сделай прямо сейчас)"),
        .step(number: 1, title: "Включи облачный пароль (2FA)", text: "Настрой 2FA в настройках конфиденциальности Telegram и никому не говори одноразовые коды из сообщений."),
        .step(number: 2, title: "Включи автовыход со старых устройств", text: "Настройки → Устройства → Автоматически завершать сеансы → 1 неделю."),
        .step(number: 3, title: "Проверь, нет ли чужих ботов", text: "Зайди в Настройки → Telegram Business → Чат-боты и удали оттуда всё непонятное."),
        .step(number: 4, title: "Обнови телефон", text: "Особенно важно своевременно обновлять iOS на iPhone."),
        .step(number: 5, title: "Заведи второй «мусорный» кошелёк", text: "Держи там копейки для левых сайтов и тестов, а дорогие NFT и основные деньги храни отдельно."),

        .heading("5. Как покупать и продавать безопасно (4 простых шага)"),
        .step(number: 1, title: "Используй только официальные маркетплейсы", text: "✅ Fragment, MRKT, Portals, Tonnel. OTC-чаты используй только как доску объявлений, чтобы потом перевести покупателя на маркет."),
        .step(number: 2, title: "Перепроверяй цену оффера", text: "✅ Прежде чем нажать «Принять» на входящее предложение, посмотри на все цифры — не отдай дорогой подарок за 125 звёзд."),
        .step(number: 3, title: "Проверяй ID собеседника", text: "✅ Никнейм (@username) мошенник сменит за секунду, а цифровой ID не меняется. Скопируй его и проверь через антискам-бота (например, @anti_scam_base_bot), а также смотри, нет ли в профиле красной пометки Scam."),
        .step(number: 4, title: "Проверяй сам NFT перед покупкой", text: "✅ Оригинал коллекции сверяй по адресу контракта на Fragment, а историю сделок смотри в Tonviewer (чтобы не купить пустышку с накрученной ценой)."),

        .heading("6. SOS: что делать, если УЖЕ попался"),
        .important(
            title: "Действуй максимально быстро",
            text: "Вернуть угнанный Telegram проще всего в первые 24 часа:"
        ),
        .step(number: 1, title: "Сделай скриншоты всего", text: "Зафиксируй переписку, юзернейм, цифровой ID, адреса кошельков и чеки, пока мошенник не удалил чат."),
        .step(number: 2, title: "Выкинь чужаков из Telegram", text: "Настройки → Устройства → Завершить все другие сеансы, после чего срочно смени облачный пароль 2FA и пароль от почты."),
        .step(number: 3, title: "Отключи бизнес-ботов", text: "Настройки → Telegram Business → Чат-боты — удали всех, кого видишь, чтобы не дочистили подарки."),
        .step(number: 4, title: "Спасай деньги с кошелька", text: "• Если отдал секретную фразу (12/24 слова) или потерял средства в сети TON — срочно создавай новый чистый кошелёк и переводи туда всё, что осталось.\n• Если подписал опасное разрешение (Approve) на левом сайте в сетях EVM (Ethereum и др.) или Tron — кнопка «Disconnect» на сайте не спасёт. Срочно зайди на настоящий сайт Revoke.cash (для EVM) или в раздел Token Approvals на TronScan (для Tron) и отмени все чужие разрешения."),
        .step(number: 5, title: "Если утекли данные карты", text: "Звони в банк и блокируй карту, предупреди друзей о взломе и пиши заявление в полицию со всеми скриншотами.")
    ]
}

private final class FullGramAntiScamGuideUIViewController: UIViewController {
    private let theme: PresentationTheme

    init(theme: PresentationTheme) {
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        self.title = FullGramGuideContent.screenTitle
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.theme.list.blocksBackgroundColor

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16.0),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28.0),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16.0)
        ])

        for block in FullGramGuideContent.blocks {
            stack.addArrangedSubview(self.makeView(for: block))
        }
    }

    private func makeCard(background: UIColor, borderColor: UIColor? = nil) -> UIView {
        let view = UIView()
        view.backgroundColor = background
        view.layer.cornerRadius = 14.0
        if let borderColor {
            view.layer.borderWidth = 1.0
            view.layer.borderColor = borderColor.cgColor
        }
        return view
    }

    private func makeView(for block: FullGramGuideBlock) -> UIView {
        switch block {
        case let .heading(text):
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 22.0, weight: .bold)
            label.textColor = self.theme.list.itemPrimaryTextColor
            label.numberOfLines = 0
            return label

        case let .placeholder(text):
            let card = self.makeCard(background: self.theme.list.itemBlocksBackgroundColor)
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 15.0)
            label.textColor = self.theme.list.itemPrimaryTextColor
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: card.topAnchor, constant: 14.0),
                label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14.0),
                label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
                label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0)
            ])
            return card

        case let .step(number, title, text):
            let card = self.makeCard(background: self.theme.list.itemBlocksBackgroundColor)
            let badge = UILabel()
            badge.text = "\(number)"
            badge.font = .systemFont(ofSize: 13.0, weight: .bold)
            badge.textColor = .white
            badge.textAlignment = .center
            badge.backgroundColor = self.theme.list.itemAccentColor
            badge.layer.cornerRadius = 13.0
            badge.clipsToBounds = true
            badge.translatesAutoresizingMaskIntoConstraints = false

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .systemFont(ofSize: 16.0, weight: .semibold)
            titleLabel.textColor = self.theme.list.itemPrimaryTextColor
            titleLabel.numberOfLines = 0
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let bodyLabel = UILabel()
            bodyLabel.text = text
            bodyLabel.font = .systemFont(ofSize: 14.5)
            bodyLabel.textColor = self.theme.list.itemSecondaryTextColor
            bodyLabel.numberOfLines = 0
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false

            card.addSubview(badge)
            card.addSubview(titleLabel)
            card.addSubview(bodyLabel)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 14.0),
                badge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
                badge.widthAnchor.constraint(equalToConstant: 26.0),
                badge.heightAnchor.constraint(equalToConstant: 26.0),
                titleLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10.0),
                titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
                bodyLabel.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 8.0),
                bodyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
                bodyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
                bodyLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14.0)
            ])
            return card

        case let .example(title, text):
            let card = self.makeCard(
                background: self.theme.list.itemBlocksBackgroundColor,
                borderColor: self.theme.list.itemSecondaryTextColor.withAlphaComponent(0.22)
            )
            let titleLabel = UILabel()
            titleLabel.text = title.uppercased()
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .bold)
            titleLabel.textColor = self.theme.list.itemAccentColor
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let bodyLabel = UILabel()
            bodyLabel.text = text
            bodyLabel.font = .systemFont(ofSize: 14.5)
            bodyLabel.textColor = self.theme.list.itemPrimaryTextColor
            bodyLabel.numberOfLines = 0
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false

            card.addSubview(titleLabel)
            card.addSubview(bodyLabel)
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12.0),
                titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
                titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
                bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6.0),
                bodyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
                bodyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
                bodyLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12.0)
            ])
            return card

        case let .important(title, text):
            let accent = UIColor.systemOrange
            let card = self.makeCard(
                background: accent.withAlphaComponent(0.12),
                borderColor: accent.withAlphaComponent(0.45)
            )
            let titleLabel = UILabel()
            titleLabel.text = "⚠️ " + title
            titleLabel.font = .systemFont(ofSize: 15.0, weight: .bold)
            titleLabel.textColor = accent
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let bodyLabel = UILabel()
            bodyLabel.text = text
            bodyLabel.font = .systemFont(ofSize: 14.5, weight: .medium)
            bodyLabel.textColor = self.theme.list.itemPrimaryTextColor
            bodyLabel.numberOfLines = 0
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false

            card.addSubview(titleLabel)
            card.addSubview(bodyLabel)
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12.0),
                titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
                titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
                bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6.0),
                bodyLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
                bodyLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
                bodyLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12.0)
            ])
            return card
        }
    }
}

private final class FullGramAntiScamGuideContainerController: ViewController {
    private let hosted: FullGramAntiScamGuideUIViewController

    init(context: AccountContext) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        self.hosted = FullGramAntiScamGuideUIViewController(theme: data.theme)
        let navBarTheme = NavigationBarTheme(overallDarkAppearance: data.theme.overallDarkAppearance, buttonColor: data.theme.rootController.navigationBar.buttonColor, disabledButtonColor: data.theme.rootController.navigationBar.disabledButtonColor, primaryTextColor: data.theme.rootController.navigationBar.primaryTextColor, backgroundColor: data.theme.rootController.navigationBar.opaqueBackgroundColor, opaqueBackgroundColor: data.theme.rootController.navigationBar.opaqueBackgroundColor, enableBackgroundBlur: false, separatorColor: data.theme.rootController.navigationBar.separatorColor, badgeBackgroundColor: data.theme.rootController.navigationBar.badgeBackgroundColor, badgeStrokeColor: data.theme.rootController.navigationBar.badgeStrokeColor, badgeTextColor: data.theme.rootController.navigationBar.badgeTextColor)
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: navBarTheme, strings: NavigationBarStrings(presentationStrings: data.strings)))
        self.title = FullGramGuideContent.screenTitle
    }

    required init?(coder: NSCoder) { return nil }

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

// MARK: - Главный экран вкладки «Анти-скам» (Карточка 1, 2, 3 + доп. защита)

private final class FullGramAntiScamUIViewController: UIViewController {
    private let context: AccountContext
    private let theme: PresentationTheme

    private let antiOfferSwitch = UISwitch()
    private let antiOtcSwitch = UISwitch()
    private let mainSwitch = UISwitch()
    private let linksSwitch = UISwitch()
    private let shortenersSwitch = UISwitch()
    private let filesSwitch = UISwitch()
    private let statsLabel = UILabel()
    private var observer: NSObjectProtocol?

    init(context: AccountContext, theme: PresentationTheme) {
        self.context = context
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        self.title = "Анти-скам"
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.theme.list.blocksBackgroundColor

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16.0),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28.0),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16.0)
        ])

        // Карточка 1: Гайд «Не попадись» (название в одну строку с усечением …, кнопка «Открыть»)
        stack.addArrangedSubview(self.makeGuideCard())

        // Карточка 2: Анти-офер
        stack.addArrangedSubview(self.makeToggleCard(
            iconName: "exclamationmark.shield.fill",
            iconTint: UIColor.systemOrange,
            title: "Анти-офер",
            description: "Предупреждает, если оффер ненастоящий",
            detail: "Проверяет офферы со ссылками, пересланные сообщения от неизвестных и через ботов.",
            toggle: self.antiOfferSwitch,
            action: #selector(self.antiOfferToggled)
        ))

        // Карточка 3: Анти-OTC
        stack.addArrangedSubview(self.makeToggleCard(
            iconName: "hand.raised.fill",
            iconTint: UIColor.systemRed,
            title: "Анти-OTC",
            description: "Предупреждает о гаранте",
            detail: "При OTC-сделке выводит предупреждение о риске скама со стороны гаранта.",
            toggle: self.antiOtcSwitch,
            action: #selector(self.antiOtcToggled)
        ))

        // Дополнительная защита
        let extraHeader = UILabel()
        extraHeader.text = "ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА"
        extraHeader.font = .systemFont(ofSize: 12.0, weight: .semibold)
        extraHeader.textColor = self.theme.list.freeTextColor
        stack.addArrangedSubview(extraHeader)

        stack.addArrangedSubview(self.makeExtraControlsCard())

        self.statsLabel.font = .systemFont(ofSize: 12.5)
        self.statsLabel.textColor = self.theme.list.freeTextColor
        self.statsLabel.numberOfLines = 0
        stack.addArrangedSubview(self.statsLabel)

        var checkCfg = UIButton.Configuration.filled()
        checkCfg.title = "Проверить ссылку или текст вручную"
        checkCfg.baseBackgroundColor = self.theme.list.itemBlocksBackgroundColor
        checkCfg.baseForegroundColor = self.theme.list.itemAccentColor
        checkCfg.cornerStyle = .medium
        let checkBtn = UIButton(configuration: checkCfg)
        checkBtn.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        checkBtn.addTarget(self, action: #selector(self.manualCheckTapped), for: .touchUpInside)
        stack.addArrangedSubview(checkBtn)

        self.observer = NotificationCenter.default.addObserver(forName: FullGramAntiScam.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        self.refresh()
    }

    private func makeCard() -> UIView {
        let view = UIView()
        view.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        view.layer.cornerRadius = 16.0
        return view
    }

    private func makeGuideCard() -> UIView {
        let card = self.makeCard()

        let iconWrap = UIView()
        iconWrap.backgroundColor = self.theme.list.itemAccentColor.withAlphaComponent(0.14)
        iconWrap.layer.cornerRadius = 12.0
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "book.closed.fill"))
        icon.tintColor = self.theme.list.itemAccentColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = "Гайд «Не попадись»"
        titleLabel.font = .systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = self.theme.list.itemPrimaryTextColor
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Пошаговая инструкция для новичков"
        subtitleLabel.font = .systemFont(ofSize: 13.5)
        subtitleLabel.textColor = self.theme.list.itemSecondaryTextColor
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Открыть"
        cfg.baseBackgroundColor = self.theme.list.itemAccentColor
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 7.0, leading: 14.0, bottom: 7.0, trailing: 14.0)
        let openButton = UIButton(configuration: cfg)
        openButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        openButton.setContentHuggingPriority(.required, for: .horizontal)
        openButton.addTarget(self, action: #selector(self.openGuideTapped), for: .touchUpInside)
        openButton.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconWrap)
        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(openButton)

        NSLayoutConstraint.activate([
            iconWrap.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
            iconWrap.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 42.0),
            iconWrap.heightAnchor.constraint(equalToConstant: 42.0),

            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22.0),
            icon.heightAnchor.constraint(equalToConstant: 22.0),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14.0),
            titleLabel.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: 12.0),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: openButton.leadingAnchor, constant: -10.0),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3.0),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -10.0),
            subtitleLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14.0),

            openButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
            openButton.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
        return card
    }

    private func makeToggleCard(
        iconName: String,
        iconTint: UIColor,
        title: String,
        description: String,
        detail: String,
        toggle: UISwitch,
        action: Selector
    ) -> UIView {
        let card = self.makeCard()

        let iconWrap = UIView()
        iconWrap.backgroundColor = iconTint.withAlphaComponent(0.14)
        iconWrap.layer.cornerRadius = 12.0
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: iconName))
        icon.tintColor = iconTint
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = self.theme.list.itemPrimaryTextColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = description
        descLabel.font = .systemFont(ofSize: 14.0, weight: .medium)
        descLabel.textColor = self.theme.list.itemPrimaryTextColor
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.font = .systemFont(ofSize: 12.5)
        detailLabel.textColor = self.theme.list.itemSecondaryTextColor
        detailLabel.numberOfLines = 0
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        toggle.onTintColor = self.theme.list.itemAccentColor
        toggle.addTarget(self, action: action, for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(iconWrap)
        card.addSubview(titleLabel)
        card.addSubview(descLabel)
        card.addSubview(detailLabel)
        card.addSubview(toggle)

        NSLayoutConstraint.activate([
            iconWrap.topAnchor.constraint(equalTo: card.topAnchor, constant: 14.0),
            iconWrap.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
            iconWrap.widthAnchor.constraint(equalToConstant: 40.0),
            iconWrap.heightAnchor.constraint(equalToConstant: 40.0),

            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 21.0),
            icon.heightAnchor.constraint(equalToConstant: 21.0),

            titleLabel.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: 12.0),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10.0),

            toggle.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),

            descLabel.topAnchor.constraint(equalTo: iconWrap.bottomAnchor, constant: 10.0),
            descLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
            descLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),

            detailLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 4.0),
            detailLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14.0),
            detailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14.0),
            detailLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14.0)
        ])
        return card
    }

    private func makeExtraControlsCard() -> UIView {
        let card = self.makeCard()
        let rows: [(String, UISwitch, Selector)] = [
            ("Общая защита Анти-скам", self.mainSwitch, #selector(self.mainToggled)),
            ("Проверка фишинговых ссылок", self.linksSwitch, #selector(self.linksToggled)),
            ("Предупреждать о сокращателях URL", self.shortenersSwitch, #selector(self.shortenersToggled)),
            ("Защита от опасных файлов", self.filesSwitch, #selector(self.filesToggled))
        ]
        let list = UIStackView()
        list.axis = .vertical
        list.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: card.topAnchor),
            list.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        for (idx, item) in rows.enumerated() {
            let row = UIView()
            let label = UILabel()
            label.text = item.0
            label.font = .systemFont(ofSize: 15.5)
            label.textColor = self.theme.list.itemPrimaryTextColor
            label.translatesAutoresizingMaskIntoConstraints = false
            item.1.onTintColor = self.theme.list.itemAccentColor
            item.1.addTarget(self, action: item.2, for: .valueChanged)
            item.1.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)
            row.addSubview(item.1)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14.0),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: item.1.leadingAnchor, constant: -10.0),
                item.1.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14.0),
                item.1.topAnchor.constraint(equalTo: row.topAnchor, constant: 10.0),
                item.1.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10.0)
            ])
            list.addArrangedSubview(row)
            if idx + 1 < rows.count {
                let sep = UIView()
                sep.backgroundColor = self.theme.list.itemPlainSeparatorColor
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
                list.addArrangedSubview(sep)
            }
        }
        return card
    }

    private func refresh() {
        let antiScam = FullGramAntiScam.shared
        self.antiOfferSwitch.isOn = antiScam.antiOfferEnabled
        self.antiOtcSwitch.isOn = antiScam.antiOtcEnabled
        self.mainSwitch.isOn = antiScam.isEnabled
        self.linksSwitch.isOn = antiScam.checkLinks
        self.shortenersSwitch.isOn = antiScam.warnShorteners
        self.filesSwitch.isOn = antiScam.protectDangerFiles
        self.statsLabel.text = "Предотвращено угроз локально: \(antiScam.blockedCount)."
    }

    @objc private func openGuideTapped() {
        if let parent = self.parent as? FullGramAntiScamContainerController {
            parent.pushGuide()
        }
    }

    @objc private func antiOfferToggled() { FullGramAntiScam.shared.antiOfferEnabled = self.antiOfferSwitch.isOn }
    @objc private func antiOtcToggled() { FullGramAntiScam.shared.antiOtcEnabled = self.antiOtcSwitch.isOn }
    @objc private func mainToggled() { FullGramAntiScam.shared.isEnabled = self.mainSwitch.isOn }
    @objc private func linksToggled() { FullGramAntiScam.shared.checkLinks = self.linksSwitch.isOn }
    @objc private func shortenersToggled() { FullGramAntiScam.shared.warnShorteners = self.shortenersSwitch.isOn }
    @objc private func filesToggled() { FullGramAntiScam.shared.protectDangerFiles = self.filesSwitch.isOn }

    @objc private func manualCheckTapped() {
        let alert = UIAlertController(title: "Проверка на скам", message: "Вставьте ссылку, имя файла или текст оффера/сделки", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https://... или текст"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Проверить", style: .default) { [weak self] _ in
            guard let self else { return }
            let input = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !input.isEmpty else { return }
            let offerVerdict = FullGramAntiScam.shared.inspectOffer(text: input, isForwarded: false, fromUnknownAuthor: false, viaBot: false, forceCheck: true)
            let otcVerdict = FullGramAntiScam.shared.inspectOTC(text: input, forceCheck: true) ?? FullGramAntiScam.shared.inspectOTCUrl(input, forceCheck: true)
            let urlVerdict = FullGramAntiScam.shared.inspectURL(input, forceCheck: true)
            let msgVerdict = FullGramAntiScam.shared.inspectIncomingMessage(input, forceCheck: true)
            let fileReason = FullGramAntiScam.shared.inspectFileName(input, forceCheck: true)

            let title: String
            let body: String
            if let otcVerdict {
                title = "⚠️ Анти-OTC"
                body = otcVerdict
            } else if let v = offerVerdict ?? urlVerdict ?? msgVerdict {
                title = v.severity == .high ? "⛔️ Высокий риск" : "⚠️ Подозрительно"
                body = v.summary + "\n\n" + v.reasons.map { "• " + $0 }.joined(separator: "\n")
            } else if let f = fileReason {
                title = "⚠️ Опасный файл"
                body = f
            } else {
                title = "✅ Угроз не обнаружено"
                body = "Локальный анализатор не выявил признаков фишинга или скама."
            }
            let resultAlert = UIAlertController(title: title, message: body, preferredStyle: .alert)
            resultAlert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(resultAlert, animated: true)
        })
        self.present(alert, animated: true)
    }
}

private final class FullGramAntiScamContainerController: ViewController {
    private let context: AccountContext
    private let hosted: FullGramAntiScamUIViewController

    init(context: AccountContext) {
        self.context = context
        let data = context.sharedContext.currentPresentationData.with { $0 }
        self.hosted = FullGramAntiScamUIViewController(context: context, theme: data.theme)
        let navBarTheme = NavigationBarTheme(overallDarkAppearance: data.theme.overallDarkAppearance, buttonColor: data.theme.rootController.navigationBar.buttonColor, disabledButtonColor: data.theme.rootController.navigationBar.disabledButtonColor, primaryTextColor: data.theme.rootController.navigationBar.primaryTextColor, backgroundColor: data.theme.rootController.navigationBar.opaqueBackgroundColor, opaqueBackgroundColor: data.theme.rootController.navigationBar.opaqueBackgroundColor, enableBackgroundBlur: false, separatorColor: data.theme.rootController.navigationBar.separatorColor, badgeBackgroundColor: data.theme.rootController.navigationBar.badgeBackgroundColor, badgeStrokeColor: data.theme.rootController.navigationBar.badgeStrokeColor, badgeTextColor: data.theme.rootController.navigationBar.badgeTextColor)
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: navBarTheme, strings: NavigationBarStrings(presentationStrings: data.strings)))
        self.title = "Анти-скам"
    }

    required init?(coder: NSCoder) { return nil }

    func pushGuide() {
        self.push(FullGramAntiScamGuideContainerController(context: self.context))
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

func fullGramAntiScamController(context: AccountContext) -> ViewController {
    return FullGramAntiScamContainerController(context: context)
}
