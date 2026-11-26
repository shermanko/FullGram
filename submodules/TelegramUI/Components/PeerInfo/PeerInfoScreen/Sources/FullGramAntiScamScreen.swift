import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
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

// MARK: - Экран мануала «Не попадись» (нативный ItemListController)

private enum FullGramGuideEntry: ItemListNodeEntry {
    case header(Int32, String)
    case text(Int32, String)

    var section: ItemListSectionId { return self.stableId / 100 }

    var stableId: Int32 {
        switch self {
        case let .header(id, _), let .text(id, _):
            return id
        }
    }

    static func < (lhs: FullGramGuideEntry, rhs: FullGramGuideEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .text(_, body):
            return ItemListTextItem(presentationData: presentationData, text: .plain(body), sectionId: self.section)
        }
    }
}

private func fullGramAntiScamGuideController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramGuideEntry] = []
        var sectionIndex: Int32 = 0
        var itemIndex: Int32 = 1

        for block in FullGramGuideContent.blocks {
            switch block {
            case let .heading(text):
                sectionIndex += 1
                itemIndex = 1
                entries.append(.header(sectionIndex * 100, text.uppercased()))
            case let .placeholder(text):
                entries.append(.text(sectionIndex * 100 + itemIndex, text))
                itemIndex += 1
            case let .important(title, text):
                entries.append(.text(sectionIndex * 100 + itemIndex, "⚠️ \(title)\n\n\(text)"))
                itemIndex += 1
            case let .example(title, text):
                entries.append(.text(sectionIndex * 100 + itemIndex, "\(title)\n\(text)"))
                itemIndex += 1
            case let .step(number, title, text):
                entries.append(.text(sectionIndex * 100 + itemIndex, "\(number). \(title)\n\(text)"))
                itemIndex += 1
            }
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text(FullGramGuideContent.screenTitle),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, ()))
    }
    return ItemListController(context: context, state: signal)
}

// MARK: - Главный раздел «Анти-скам» (нативный ItemListController)

private enum FullGramAntiScamToggle: Int32 {
    case antiOffer = 1
    case antiOtc = 2
    case mainEnabled = 3
    case checkLinks = 4
    case warnShorteners = 5
    case protectFiles = 6
    case markScamMessages = 7
    case ruleBanByTemplates = 8
    case ruleBanByLinks = 9
    case ruleBanNewAccounts = 10
    case ruleNewAccountRequireNoAvatar = 11
    case ruleBanMassJoins = 12
    case ruleAutoBanInAdminGroups = 13
}

private final class FullGramAntiScamArguments {
    let openGuide: () -> Void
    let toggle: (FullGramAntiScamToggle, Bool) -> Void
    let editTemplates: () -> Void
    let pickNewAccountThreshold: () -> Void
    let pickMassJoinLimit: () -> Void
    let openRuleEvents: () -> Void
    let manualCheck: () -> Void
    let clearWhitelist: () -> Void

    init(
        openGuide: @escaping () -> Void,
        toggle: @escaping (FullGramAntiScamToggle, Bool) -> Void,
        editTemplates: @escaping () -> Void,
        pickNewAccountThreshold: @escaping () -> Void,
        pickMassJoinLimit: @escaping () -> Void,
        openRuleEvents: @escaping () -> Void,
        manualCheck: @escaping () -> Void,
        clearWhitelist: @escaping () -> Void
    ) {
        self.openGuide = openGuide
        self.toggle = toggle
        self.editTemplates = editTemplates
        self.pickNewAccountThreshold = pickNewAccountThreshold
        self.pickMassJoinLimit = pickMassJoinLimit
        self.openRuleEvents = openRuleEvents
        self.manualCheck = manualCheck
        self.clearWhitelist = clearWhitelist
    }
}

private enum FullGramAntiScamEntry: ItemListNodeEntry {
    case guideHeader(String)
    case guideLink(String, String)
    case guideInfo(String)
    case coreHeader(String)
    case antiOfferToggle(Bool)
    case antiOfferInfo(String)
    case antiOtcToggle(Bool)
    case antiOtcInfo(String)
    case extraHeader(String)
    case extraToggle(FullGramAntiScamToggle, String, Bool)
    case rulesHeader(String)
    case ruleToggle(FullGramAntiScamToggle, String, Bool)
    case ruleTemplatesLink(String, String)
    case ruleNewAccountIdLink(String, String)
    case ruleMassJoinLink(String, String)
    case ruleEventsLink(String, String)
    case rulesInfo(String)
    case toolsHeader(String)
    case manualCheck(String)
    case clearWhitelist(String)
    case stats(String)

    var section: ItemListSectionId {
        switch self {
        case .guideHeader, .guideLink, .guideInfo: return 0
        case .coreHeader, .antiOfferToggle, .antiOfferInfo, .antiOtcToggle, .antiOtcInfo: return 1
        case .extraHeader, .extraToggle: return 2
        case .rulesHeader, .ruleToggle, .ruleTemplatesLink, .ruleNewAccountIdLink, .ruleMassJoinLink, .ruleEventsLink, .rulesInfo: return 3
        case .toolsHeader, .manualCheck, .clearWhitelist, .stats: return 4
        }
    }

    var stableId: Int32 {
        switch self {
        case .guideHeader: return 0
        case .guideLink: return 1
        case .guideInfo: return 2
        case .coreHeader: return 10
        case .antiOfferToggle: return 11
        case .antiOfferInfo: return 12
        case .antiOtcToggle: return 13
        case .antiOtcInfo: return 14
        case .extraHeader: return 20
        case let .extraToggle(opt, _, _): return 20 + opt.rawValue
        case .rulesHeader: return 50
        case let .ruleToggle(opt, _, _): return 50 + opt.rawValue
        case .ruleTemplatesLink: return 80
        case .ruleNewAccountIdLink: return 81
        case .ruleMassJoinLink: return 82
        case .ruleEventsLink: return 83
        case .rulesInfo: return 84
        case .toolsHeader: return 100
        case .manualCheck: return 101
        case .clearWhitelist: return 102
        case .stats: return 103
        }
    }

    static func < (lhs: FullGramAntiScamEntry, rhs: FullGramAntiScamEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramAntiScamArguments
        switch self {
        case let .guideHeader(text), let .coreHeader(text), let .extraHeader(text), let .rulesHeader(text), let .toolsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .guideLink(title, label):
            let icon = UIImage(systemName: "book.closed.fill")?.withTintColor(UIColor(rgb: 0x007AFF), renderingMode: .alwaysOriginal)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openGuide)
        case let .guideInfo(text), let .antiOfferInfo(text), let .antiOtcInfo(text), let .rulesInfo(text), let .stats(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .antiOfferToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Анти-офер", value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(.antiOffer, $0) })
        case let .antiOtcToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Анти-OTC", value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(.antiOtc, $0) })
        case let .extraToggle(opt, title, value), let .ruleToggle(opt, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(opt, $0) })
        case let .ruleTemplatesLink(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editTemplates)
        case let .ruleNewAccountIdLink(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickNewAccountThreshold)
        case let .ruleMassJoinLink(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickMassJoinLimit)
        case let .ruleEventsLink(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openRuleEvents)
        case let .manualCheck(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.manualCheck)
        case let .clearWhitelist(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.clearWhitelist)
        }
    }
}

func fullGramAntiScamController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?

    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramAntiScam.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramAntiScamArguments(
        openGuide: {
            pushImpl?(fullGramAntiScamGuideController(context: context))
        },
        toggle: { opt, value in
            switch opt {
            case .antiOffer: FullGramAntiScam.shared.antiOfferEnabled = value
            case .antiOtc: FullGramAntiScam.shared.antiOtcEnabled = value
            case .mainEnabled: FullGramAntiScam.shared.isEnabled = value
            case .checkLinks: FullGramAntiScam.shared.checkLinks = value
            case .warnShorteners: FullGramAntiScam.shared.warnShorteners = value
            case .protectFiles: FullGramAntiScam.shared.protectDangerFiles = value
            case .markScamMessages: FullGramAntiScam.shared.markScamMessages = value
            case .ruleBanByTemplates: FullGramAntiScam.shared.ruleBanByTemplates = value
            case .ruleBanByLinks: FullGramAntiScam.shared.ruleBanByLinks = value
            case .ruleBanNewAccounts: FullGramAntiScam.shared.ruleBanNewAccounts = value
            case .ruleNewAccountRequireNoAvatar: FullGramAntiScam.shared.ruleNewAccountRequireNoAvatar = value
            case .ruleBanMassJoins: FullGramAntiScam.shared.ruleBanMassJoins = value
            case .ruleAutoBanInAdminGroups: FullGramAntiScam.shared.ruleAutoBanInAdminGroups = value
            }
        },
        editTemplates: {
            let current = FullGramAntiScam.shared.ruleCustomTemplates
            let sheet = UIAlertController(title: "Шаблоны и стоп-слова", message: "Текущие (\(current.count)):\n" + current.joined(separator: ", "), preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Добавить шаблон или /regex/…", style: .default) { _ in
                let alert = UIAlertController(title: "Новый шаблон", message: "Введите фразу или регулярное выражение в формате /pattern/:", preferredStyle: .alert)
                alert.addTextField { tf in tf.placeholder = "Например: криптосигнал или /earn.*\\$/" }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak alert] _ in
                    if let txt = alert?.textFields?.first?.text {
                        FullGramAntiScam.shared.addCustomTemplate(txt)
                    }
                })
                presentNativeImpl?(alert)
            })
            if !current.isEmpty {
                sheet.addAction(UIAlertAction(title: "Удалить шаблон…", style: .destructive) { _ in
                    let delSheet = UIAlertController(title: "Удалить шаблон", message: nil, preferredStyle: .actionSheet)
                    for tpl in current {
                        delSheet.addAction(UIAlertAction(title: tpl, style: .destructive) { _ in
                            FullGramAntiScam.shared.removeCustomTemplate(tpl)
                        })
                    }
                    delSheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                    presentNativeImpl?(delSheet)
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        pickNewAccountThreshold: {
            let sheet = UIAlertController(title: "Порог нового аккаунта по Telegram ID", message: "Чем выше ID, тем свежее регистрация аккаунта:", preferredStyle: .actionSheet)
            let options: [(String, Int64)] = [
                ("ID ≥ 6 000 000 000", 6_000_000_000),
                ("ID ≥ 7 000 000 000 (реком.)", 7_000_000_000),
                ("ID ≥ 7 500 000 000", 7_500_000_000),
                ("ID ≥ 8 000 000 000 (совсем новые)", 8_000_000_000)
            ]
            for (title, val) in options {
                sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                    FullGramAntiScam.shared.ruleNewAccountMinId = val
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        pickMassJoinLimit: {
            let sheet = UIAlertController(title: "Порог анти-рейда (массовые вступления)", message: "Сколько входов подряд считать атакой:", preferredStyle: .actionSheet)
            let presets: [(String, Int, Int)] = [
                ("3 входа за 15 сек.", 3, 15),
                ("5 входов за 30 сек.", 5, 30),
                ("8 входов за 45 сек.", 8, 45),
                ("12 входов за 60 сек.", 12, 60)
            ]
            for (title, limit, win) in presets {
                sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                    FullGramAntiScam.shared.ruleMassJoinLimit = limit
                    FullGramAntiScam.shared.ruleMassJoinWindowSeconds = win
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        openRuleEvents: {
            let events = FullGramAntiScam.shared.ruleEvents
            let msg = events.isEmpty
                ? "Нарушений правил пока не зафиксировано."
                : events.prefix(15).map { "• [\($0.ruleName)] ID \($0.authorId): \($0.detail)" }.joined(separator: "\n")
            let alert = UIAlertController(title: "Журнал срабатываний (\(events.count))", message: msg, preferredStyle: .alert)
            if !events.isEmpty {
                alert.addAction(UIAlertAction(title: "Очистить", style: .destructive) { _ in
                    FullGramAntiScam.shared.clearRuleEvents()
                })
            }
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            presentNativeImpl?(alert)
        },
        manualCheck: {
            let alert = UIAlertController(title: "Проверка на скам", message: "Вставьте ссылку, имя файла или текст оффера/сделки", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = "https://... или текст"
                tf.autocapitalizationType = .none
                tf.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Проверить", style: .default) { [weak alert] _ in
                let input = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
                presentNativeImpl?(resultAlert)
            })
            presentNativeImpl?(alert)
        },
        clearWhitelist: {
            FullGramAntiScam.shared.clearWhitelist()
            let done = UIAlertController(title: "Белый список очищен", message: "Все доверенные домены сброшены.", preferredStyle: .alert)
            done.addAction(UIAlertAction(title: "OK", style: .default))
            presentNativeImpl?(done)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let antiScam = FullGramAntiScam.shared
        let minIdB = String(format: "%.1f млрд", Double(antiScam.ruleNewAccountMinId) / 1_000_000_000.0)
        var entries: [FullGramAntiScamEntry] = [
            .guideHeader("МАНУАЛ И ГАЙД"),
            .guideLink("Не попадись: антискам-мануал", "Открыть"),
            .guideInfo("Разбор актуальных схем (фейк-офферы, бизнес-боты, подставные гаранты OTC, фишинг) и чек-лист защиты."),

            .coreHeader("МОДУЛИ АНТИ-СКАМА"),
            .antiOfferToggle(antiScam.antiOfferEnabled),
            .antiOfferInfo("Анти-офер: проверяет офферы со ссылками, пересланные сообщения от неизвестных и через ботов."),
            .antiOtcToggle(antiScam.antiOtcEnabled),
            .antiOtcInfo("Анти-OTC: при OTC-сделке и подозрительных гарантах выводит предупреждение о риске скама."),

            .extraHeader("ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА"),
            .extraToggle(.mainEnabled, "Общая защита Анти-скам", antiScam.isEnabled),
            .extraToggle(.checkLinks, "Проверка фишинговых ссылок", antiScam.checkLinks),
            .extraToggle(.warnShorteners, "Предупреждать о сокращателях URL", antiScam.warnShorteners),
            .extraToggle(.protectFiles, "Защита от опасных файлов", antiScam.protectDangerFiles),
            .extraToggle(.markScamMessages, "Помечать скам-сообщения в чатах", antiScam.markScamMessages),

            .rulesHeader("ПРАВИЛА АНТИ-СКАМ МОДЕРАЦИИ"),
            .ruleToggle(.ruleBanByTemplates, "Бан по шаблонам (фразы / regex)", antiScam.ruleBanByTemplates),
            .ruleTemplatesLink("Список шаблонов и стоп-слов", "\(antiScam.ruleCustomTemplates.count)"),
            .ruleToggle(.ruleBanByLinks, "Бан по ссылкам (кроме белых)", antiScam.ruleBanByLinks),
            .ruleToggle(.ruleBanNewAccounts, "Защита от новых аккаунтов", antiScam.ruleBanNewAccounts),
            .ruleNewAccountIdLink("Порог нового аккаунта", minIdB),
            .ruleToggle(.ruleNewAccountRequireNoAvatar, "Новые: только без фото/@ника", antiScam.ruleNewAccountRequireNoAvatar),
            .ruleToggle(.ruleBanMassJoins, "Защита от массовых вступлений", antiScam.ruleBanMassJoins),
            .ruleMassJoinLink("Порог массовых вступлений", "\(antiScam.ruleMassJoinLimit) / \(antiScam.ruleMassJoinWindowSeconds)с"),
            .ruleToggle(.ruleAutoBanInAdminGroups, "Авто-бан нарушителей в моих группах", antiScam.ruleAutoBanInAdminGroups),
            .ruleEventsLink("Журнал срабатываний правил", "\(antiScam.ruleEvents.count)"),
            .rulesInfo("Правила мгновенно помечают подозрительные сообщения и при включённом авто-бане блокируют нарушителей в группах, где вы администратор."),

            .toolsHeader("ПРОВЕРКА И СТАТИСТИКА"),
            .manualCheck("Проверить ссылку, файл или текст")
        ]

        let whitelistCount = antiScam.whitelistDomains.count
        if whitelistCount > 0 {
            entries.append(.clearWhitelist("Очистить белый список доменов (\(whitelistCount))"))
        }
        entries.append(.stats("Предотвращено угроз локально: \(antiScam.blockedCount)."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Анти-скам"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}
