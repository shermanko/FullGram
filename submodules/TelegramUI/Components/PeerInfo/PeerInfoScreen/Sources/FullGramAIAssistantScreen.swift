import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import ItemListUI
import PresentationDataUtils
import TelegramPresentationData

private final class FullGramAIScreenArguments {
    let toggleEnabled: (Bool) -> Void
    let openAIChatWindow: () -> Void
    let toggleFloatingPet: (Bool) -> Void
    let pickProvider: () -> Void
    let editApiKey: () -> Void
    let editModel: () -> Void
    let editEndpoint: () -> Void
    let testConnection: () -> Void
    let toggleAllowReadChat: (Bool) -> Void
    let toggleAllowChatList: (Bool) -> Void
    let toggleAllowDrafts: (Bool) -> Void
    let editCustomPrompt: () -> Void
    let openSecurityPrompt: () -> Void

    init(
        toggleEnabled: @escaping (Bool) -> Void,
        openAIChatWindow: @escaping () -> Void,
        toggleFloatingPet: @escaping (Bool) -> Void,
        pickProvider: @escaping () -> Void,
        editApiKey: @escaping () -> Void,
        editModel: @escaping () -> Void,
        editEndpoint: @escaping () -> Void,
        testConnection: @escaping () -> Void,
        toggleAllowReadChat: @escaping (Bool) -> Void,
        toggleAllowChatList: @escaping (Bool) -> Void,
        toggleAllowDrafts: @escaping (Bool) -> Void,
        editCustomPrompt: @escaping () -> Void,
        openSecurityPrompt: @escaping () -> Void
    ) {
        self.toggleEnabled = toggleEnabled
        self.openAIChatWindow = openAIChatWindow
        self.toggleFloatingPet = toggleFloatingPet
        self.pickProvider = pickProvider
        self.editApiKey = editApiKey
        self.editModel = editModel
        self.editEndpoint = editEndpoint
        self.testConnection = testConnection
        self.toggleAllowReadChat = toggleAllowReadChat
        self.toggleAllowChatList = toggleAllowChatList
        self.toggleAllowDrafts = toggleAllowDrafts
        self.editCustomPrompt = editCustomPrompt
        self.openSecurityPrompt = openSecurityPrompt
    }
}

private final class FullGramAIHeroItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let sectionId: ItemListSectionId
    let isEnabled: Bool
    let providerTitle: String
    let modelName: String
    let hasKey: Bool
    let openChat: () -> Void
    let isAlwaysPlain: Bool = true

    init(
        theme: PresentationTheme,
        sectionId: ItemListSectionId,
        isEnabled: Bool,
        providerTitle: String,
        modelName: String,
        hasKey: Bool,
        openChat: @escaping () -> Void
    ) {
        self.theme = theme
        self.sectionId = sectionId
        self.isEnabled = isEnabled
        self.providerTitle = providerTitle
        self.modelName = modelName
        self.hasKey = hasKey
        self.openChat = openChat
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = FullGramAIHeroItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            completion(node, { return (nil, { _ in apply() }) })
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FullGramAIHeroItemNode {
                let (layout, apply) = nodeValue.asyncLayout()(self, params)
                completion(layout, { _ in apply() })
            }
        }
    }

    var selectable: Bool { return false }
}

private final class FullGramAIHeroItemNode: ListViewItemNode {
    private let cardView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let avatarRing = UIView()
    private let avatarView = UIImageView()
    private let titleLabel = UILabel()
    private let statusPill = UILabel()
    private let modelLabel = UILabel()
    private let openChatButton = UIButton(type: .system)
    private var openChatAction: (() -> Void)?
    private var didAttachCard = false

    init() {
        super.init(layerBacked: false)
        self.cardView.layer.cornerRadius = 20.0
        self.cardView.clipsToBounds = true
        self.cardView.layer.borderWidth = 0.5
        self.cardView.layer.insertSublayer(self.gradientLayer, at: 0)

        self.avatarRing.layer.cornerRadius = 28.0
        self.avatarRing.layer.borderWidth = 1.5
        self.cardView.addSubview(self.avatarRing)

        self.avatarView.image = UIImage(named: "FullGramMascotPortrait") ?? UIImage(named: "FullGramMascotPet") ?? UIImage(systemName: "sparkles")
        self.avatarView.contentMode = .scaleAspectFill
        self.avatarView.layer.cornerRadius = 25.0
        self.avatarView.clipsToBounds = true
        self.avatarRing.addSubview(self.avatarView)

        self.titleLabel.text = "FullGram AI"
        self.titleLabel.font = Font.bold(19.0)
        self.cardView.addSubview(self.titleLabel)

        self.statusPill.font = Font.semibold(11.0)
        self.statusPill.textAlignment = .center
        self.statusPill.layer.cornerRadius = 9.0
        self.statusPill.clipsToBounds = true
        self.cardView.addSubview(self.statusPill)

        self.modelLabel.font = Font.regular(13.0)
        self.modelLabel.numberOfLines = 1
        self.cardView.addSubview(self.modelLabel)

        self.openChatButton.addTarget(self, action: #selector(self.openChatTapped), for: .touchUpInside)
        self.cardView.addSubview(self.openChatButton)
    }

    override func didLoad() {
        super.didLoad()
        if !self.didAttachCard {
            self.didAttachCard = true
            self.view.addSubview(self.cardView)
        }
    }

    @objc private func openChatTapped() {
        self.openChatAction?()
    }

    func asyncLayout() -> (FullGramAIHeroItem, ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params in
            let height: CGFloat = 148.0
            let layout = ListViewItemNodeLayout(
                contentSize: CGSize(width: params.width, height: height),
                insets: UIEdgeInsets(top: 6.0, left: 0.0, bottom: 6.0, right: 0.0)
            )
            let apply: () -> Void = {
                guard let self else { return }
                self.openChatAction = item.openChat
                let inset = params.leftInset + 16.0
                let cardW = max(240.0, params.width - inset * 2.0)
                let cardFrame = CGRect(x: inset, y: 6.0, width: cardW, height: height - 12.0)
                self.cardView.frame = cardFrame
                self.gradientLayer.frame = self.cardView.bounds

                let accent = item.theme.list.itemAccentColor
                let dark = item.theme.overallDarkAppearance
                let c1 = dark ? UIColor(rgb: 0x1E1B3A) : UIColor(rgb: 0xF1EEFF)
                let c2 = dark ? UIColor(rgb: 0x132038) : UIColor(rgb: 0xE7F4FF)
                self.gradientLayer.colors = [c1.cgColor, c2.cgColor]
                self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
                self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
                self.cardView.layer.borderColor = accent.withAlphaComponent(0.28).cgColor

                self.avatarRing.frame = CGRect(x: 16.0, y: 16.0, width: 56.0, height: 56.0)
                self.avatarRing.layer.borderColor = accent.withAlphaComponent(0.55).cgColor
                self.avatarRing.backgroundColor = accent.withAlphaComponent(0.12)
                self.avatarView.frame = CGRect(x: 3.0, y: 3.0, width: 50.0, height: 50.0)

                let badgeText: String
                let badgeBg: UIColor
                let badgeFg: UIColor
                if !item.isEnabled {
                    badgeText = "Выкл"
                    badgeBg = UIColor.systemGray.withAlphaComponent(0.20)
                    badgeFg = .systemGray
                } else if item.hasKey {
                    badgeText = "Готов"
                    badgeBg = UIColor.systemGreen.withAlphaComponent(0.20)
                    badgeFg = .systemGreen
                } else {
                    badgeText = "Нет ключа"
                    badgeBg = UIColor.systemOrange.withAlphaComponent(0.22)
                    badgeFg = .systemOrange
                }
                self.statusPill.text = badgeText
                self.statusPill.backgroundColor = badgeBg
                self.statusPill.textColor = badgeFg
                let pillW: CGFloat = max(56.0, self.statusPill.sizeThatFits(CGSize(width: 120.0, height: 18.0)).width + 16.0)
                self.statusPill.frame = CGRect(x: cardW - 16.0 - pillW, y: 20.0, width: pillW, height: 18.0)

                let textX: CGFloat = 84.0
                let textW = max(80.0, self.statusPill.frame.minX - textX - 8.0)
                self.titleLabel.textColor = item.theme.list.itemPrimaryTextColor
                self.titleLabel.frame = CGRect(x: textX, y: 18.0, width: textW, height: 22.0)

                self.modelLabel.text = "\(item.providerTitle) · \(item.modelName)"
                self.modelLabel.textColor = item.theme.list.itemSecondaryTextColor
                self.modelLabel.frame = CGRect(x: textX, y: 44.0, width: cardW - textX - 16.0, height: 18.0)

                var cfg = UIButton.Configuration.filled()
                var titleAttr = AttributedString("Открыть чат с ИИ")
                titleAttr.font = Font.semibold(14.5)
                cfg.attributedTitle = titleAttr
                cfg.image = UIImage(systemName: "sparkles", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold))
                cfg.imagePadding = 7.0
                cfg.cornerStyle = .capsule
                cfg.baseBackgroundColor = accent
                cfg.baseForegroundColor = .white
                self.openChatButton.configuration = cfg
                self.openChatButton.frame = CGRect(x: 16.0, y: 86.0, width: cardW - 32.0, height: 36.0)
            }
            return (layout, apply)
        }
    }
}

private enum FullGramAISection: Int32 {
    case hero
    case main
    case connection
    case security
}

private enum FullGramAIEntry: ItemListNodeEntry {
    case hero(PresentationTheme, Bool, String, String, Bool)
    case mainHeader(String)
    case enabled(Bool)
    case floatingPet(Bool)
    case mainFooter(String)

    case connectionHeader(String)
    case provider(String, String)
    case apiKey(String, String)
    case model(String, String)
    case endpoint(String, String)
    case testConnection(String, ItemListActionKind)
    case connectionFooter(String)

    case securityHeader(String)
    case allowReadChat(Bool)
    case allowChatList(Bool)
    case allowDrafts(Bool)
    case customPrompt(String, String)
    case viewSecurityPrompt(String)
    case securityFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .hero:
            return FullGramAISection.hero.rawValue
        case .mainHeader, .enabled, .floatingPet, .mainFooter:
            return FullGramAISection.main.rawValue
        case .connectionHeader, .provider, .apiKey, .model, .endpoint, .testConnection, .connectionFooter:
            return FullGramAISection.connection.rawValue
        case .securityHeader, .allowReadChat, .allowChatList, .allowDrafts, .customPrompt, .viewSecurityPrompt, .securityFooter:
            return FullGramAISection.security.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .hero: return 0
        case .mainHeader: return 10
        case .enabled: return 11
        case .floatingPet: return 12
        case .mainFooter: return 13

        case .connectionHeader: return 100
        case .provider: return 101
        case .apiKey: return 102
        case .model: return 103
        case .endpoint: return 104
        case .testConnection: return 105
        case .connectionFooter: return 106

        case .securityHeader: return 200
        case .allowReadChat: return 201
        case .allowChatList: return 202
        case .allowDrafts: return 203
        case .customPrompt: return 204
        case .viewSecurityPrompt: return 205
        case .securityFooter: return 206
        }
    }

    static func == (lhs: FullGramAIEntry, rhs: FullGramAIEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.hero(lt, le, lp, lm, lk), .hero(rt, re, rp, rm, rk)):
            return lt === rt && le == re && lp == rp && lm == rm && lk == rk
        case let (.mainHeader(a), .mainHeader(b)): return a == b
        case let (.enabled(a), .enabled(b)): return a == b
        case let (.floatingPet(a), .floatingPet(b)): return a == b
        case let (.mainFooter(a), .mainFooter(b)): return a == b
        case let (.connectionHeader(a), .connectionHeader(b)): return a == b
        case let (.provider(at, av), .provider(bt, bv)): return at == bt && av == bv
        case let (.apiKey(at, av), .apiKey(bt, bv)): return at == bt && av == bv
        case let (.model(at, av), .model(bt, bv)): return at == bt && av == bv
        case let (.endpoint(at, av), .endpoint(bt, bv)): return at == bt && av == bv
        case let (.testConnection(at, ak), .testConnection(bt, bk)): return at == bt && ak == bk
        case let (.connectionFooter(a), .connectionFooter(b)): return a == b
        case let (.securityHeader(a), .securityHeader(b)): return a == b
        case let (.allowReadChat(a), .allowReadChat(b)): return a == b
        case let (.allowChatList(a), .allowChatList(b)): return a == b
        case let (.allowDrafts(a), .allowDrafts(b)): return a == b
        case let (.customPrompt(at, av), .customPrompt(bt, bv)): return at == bt && av == bv
        case let (.viewSecurityPrompt(a), .viewSecurityPrompt(b)): return a == b
        case let (.securityFooter(a), .securityFooter(b)): return a == b
        default: return false
        }
    }

    static func < (lhs: FullGramAIEntry, rhs: FullGramAIEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramAIScreenArguments
        switch self {
        case let .hero(theme, isEnabled, providerTitle, modelName, hasKey):
            return FullGramAIHeroItem(
                theme: theme,
                sectionId: self.section,
                isEnabled: isEnabled,
                providerTitle: providerTitle,
                modelName: modelName,
                hasKey: hasKey,
                openChat: args.openAIChatWindow
            )
        case let .mainHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .enabled(val):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("power", color: UIColor(rgb: 0x34C759)),
                title: "Включить ИИ (.ai и окно)",
                value: val,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleEnabled
            )
        case let .floatingPet(val):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("pawprint.fill", color: UIColor(rgb: 0xAF52DE)),
                title: "Питомец поверх экрана",
                value: val,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleFloatingPet
            )
        case let .mainFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case let .connectionHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .provider(title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("cpu", color: UIColor(rgb: 0x5856D6)),
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.pickProvider
            )
        case let .apiKey(title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("key.fill", color: UIColor(rgb: 0xFF9500)),
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.editApiKey
            )
        case let .model(title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("cube.fill", color: UIColor(rgb: 0x007AFF)),
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.editModel
            )
        case let .endpoint(title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("network", color: UIColor(rgb: 0x32ADE6)),
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.editEndpoint
            )
        case let .testConnection(title, kind):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: kind, alignment: .center, sectionId: self.section, style: .blocks, action: args.testConnection)
        case let .connectionFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case let .securityHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .allowReadChat(val):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("message.fill", color: UIColor(rgb: 0x007AFF)),
                title: "Изучать открытый чат",
                value: val,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleAllowReadChat
            )
        case let .allowChatList(val):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("list.bullet.rectangle.portrait.fill", color: UIColor(rgb: 0x34C759)),
                title: "Видеть список диалогов",
                value: val,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleAllowChatList
            )
        case let .allowDrafts(val):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("square.and.pencil", color: UIColor(rgb: 0xFF9500)),
                title: "Вставлять черновики",
                value: val,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleAllowDrafts
            )
        case let .customPrompt(title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("text.badge.star", color: UIColor(rgb: 0xAF52DE)),
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.editCustomPrompt
            )
        case let .viewSecurityPrompt(title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("lock.shield.fill", color: UIColor(rgb: 0xFF3B30)),
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.openSecurityPrompt
            )
        case let .securityFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func fullGramModelPresets(for provider: FullGramAIProvider) -> [String] {
    switch provider {
    case .gemini:
        return ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]
    case .openAI:
        return ["gpt-4o-mini", "gpt-4.1", "gpt-4o"]
    case .anthropic:
        return ["claude-3-7-sonnet-latest", "claude-3-5-haiku-latest"]
    case .groq:
        return ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
    case .openRouter:
        return ["deepseek/deepseek-chat", "anthropic/claude-3.7-sonnet", "openai/gpt-4o-mini"]
    case .custom:
        return [provider.defaultModel, "llama3.2", "qwen2.5:14b"]
    }
}

public func fullGramAIAssistantController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?

    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let tick = Atomic<Int>(value: 0)
    let testingState = Atomic<Bool>(value: false)

    let bump: () -> Void = {
        refresh.set(tick.modify { $0 + 1 })
    }

    let observer = NotificationCenter.default.addObserver(forName: FullGramAINotifications.settingsChanged, object: nil, queue: .main) { _ in
        bump()
    }

    let args = FullGramAIScreenArguments(
        toggleEnabled: { val in
            FullGramAIStore.shared.isEnabled = val
        },
        openAIChatWindow: {
            NotificationCenter.default.post(name: FullGramAINotifications.openWindow, object: nil)
        },
        toggleFloatingPet: { val in
            FullGramAIStore.shared.showFloatingPet = val
        },
        pickProvider: {
            let current = FullGramAIStore.shared.provider
            let alert = UIAlertController(title: "Провайдер ИИ", message: "Выберите движок модели", preferredStyle: .actionSheet)
            for provider in FullGramAIProvider.allCases {
                let mark = provider == current ? " ✓" : ""
                alert.addAction(UIAlertAction(title: "\(provider.title)\(mark)", style: .default, handler: { _ in
                    FullGramAIStore.shared.provider = provider
                }))
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        editApiKey: {
            let provider = FullGramAIStore.shared.provider
            let alert = UIAlertController(
                title: "API-ключ (\(provider.title))",
                message: "Ключ сохраняется локально в зашифрованном iOS Keychain и не попадает в бэкапы.",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                switch provider {
                case .gemini:
                    tf.placeholder = "AIza..."
                case .anthropic:
                    tf.placeholder = "sk-ant-..."
                case .openAI, .openRouter, .groq, .custom:
                    tf.placeholder = "sk-..."
                }
                tf.isSecureTextEntry = true
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
                let val = alert?.textFields?.first?.text ?? ""
                FullGramAIKeychain.setApiKey(val, for: provider)
            }))
            alert.addAction(UIAlertAction(title: "Очистить ключ", style: .destructive, handler: { _ in
                FullGramAIKeychain.setApiKey("", for: provider)
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        editModel: {
            let provider = FullGramAIStore.shared.provider
            let current = FullGramAIStore.shared.effectiveModel
            let sheet = UIAlertController(title: "Модель (\(provider.title))", message: "Выберите пресет или задайте вручную", preferredStyle: .actionSheet)
            for preset in fullGramModelPresets(for: provider) {
                let mark = preset == current ? " ✓" : ""
                sheet.addAction(UIAlertAction(title: "\(preset)\(mark)", style: .default, handler: { _ in
                    FullGramAIStore.shared.modelName = preset == provider.defaultModel ? "" : preset
                }))
            }
            sheet.addAction(UIAlertAction(title: "Ввести вручную…", style: .default, handler: { _ in
                let alert = UIAlertController(
                    title: "Модель ИИ",
                    message: "Оставьте пустым для значения по умолчанию (\(provider.defaultModel)).",
                    preferredStyle: .alert
                )
                alert.addTextField { tf in
                    tf.text = FullGramAIStore.shared.modelName
                    tf.placeholder = provider.defaultModel
                    tf.autocorrectionType = .no
                    tf.autocapitalizationType = .none
                }
                alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
                    FullGramAIStore.shared.modelName = alert?.textFields?.first?.text ?? ""
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                presentNativeImpl?(alert)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        editEndpoint: {
            let provider = FullGramAIStore.shared.provider
            let alert = UIAlertController(
                title: "URL API эндпоинта",
                message: "Разрешены https:// или локальный http://localhost. По умолчанию: \(provider.defaultEndpoint)",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.text = FullGramAIStore.shared.customEndpoint
                tf.placeholder = provider.defaultEndpoint
                tf.keyboardType = .URL
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
                FullGramAIStore.shared.customEndpoint = alert?.textFields?.first?.text ?? ""
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        testConnection: {
            let wasTesting = testingState.swap(true)
            guard !wasTesting else { return }
            bump()
            FullGramAIStore.shared.testConnection { result in
                _ = testingState.swap(false)
                bump()
                let title: String
                let message: String
                switch result {
                case let .success(reply):
                    title = "Подключение работает"
                    message = "Ответ модели: «\(reply)»"
                case let .failure(error):
                    title = "Ошибка подключения"
                    message = error.localizedDescription
                }
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                presentNativeImpl?(alert)
            }
        },
        toggleAllowReadChat: { val in
            FullGramAIStore.shared.allowReadCurrentChat = val
        },
        toggleAllowChatList: { val in
            FullGramAIStore.shared.allowReadChatList = val
        },
        toggleAllowDrafts: { val in
            FullGramAIStore.shared.allowDraftInsert = val
        },
        editCustomPrompt: {
            let sheet = UIAlertController(title: "Стиль ответов ИИ", message: "Быстрый пресет или свои инструкции", preferredStyle: .actionSheet)
            let presets: [(String, String)] = [
                ("Коротко и по делу", "Отвечай максимально коротко, чётко и по пунктам."),
                ("Подробный разбор", "Давай развёрнутый анализ с примерами и выводами."),
                ("Дружелюбный тон", "Общайся тепло, кратко и понятно."),
                ("Сбросить инструкции", "")
            ]
            for (label, value) in presets {
                sheet.addAction(UIAlertAction(title: label, style: value.isEmpty ? .destructive : .default, handler: { _ in
                    FullGramAIStore.shared.customInstructions = value
                }))
            }
            sheet.addAction(UIAlertAction(title: "Написать свой промпт…", style: .default, handler: { _ in
                let alert = UIAlertController(
                    title: "Свои инструкции для ИИ",
                    message: "Дополнительные пожелания по стилю ответов (системные правила безопасности всегда остаются активными).",
                    preferredStyle: .alert
                )
                alert.addTextField { tf in
                    tf.text = FullGramAIStore.shared.customInstructions
                    tf.placeholder = "Например: Отвечай максимально коротко по пунктам"
                }
                alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
                    FullGramAIStore.shared.customInstructions = alert?.textFields?.first?.text ?? ""
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                presentNativeImpl?(alert)
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        openSecurityPrompt: {
            pushImpl?(fullGramAISecurityPromptController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let store = FullGramAIStore.shared
        let provider = store.provider
        let endpointDisplay = store.customEndpoint.isEmpty ? "По умолчанию" : String(store.customEndpoint.suffix(24))
        let promptSummary = store.customInstructions.isEmpty ? "Стандартный" : String(store.customInstructions.prefix(18))
        let hasKey = !FullGramAIKeychain.apiKey(for: provider).isEmpty
        let isTesting = testingState.with { $0 }

        let entries: [FullGramAIEntry] = [
            .hero(presentationData.theme, store.isEnabled, provider.title, store.effectiveModel, hasKey),

            .mainHeader("ОСНОВНОЕ"),
            .enabled(store.isEnabled),
            .floatingPet(store.showFloatingPet),
            .mainFooter("В любом чате напишите «.ai вопрос» или откройте плавающее окно кнопкой сверху."),

            .connectionHeader("МОДЕЛЬ И API"),
            .provider("Провайдер", provider.title),
            .apiKey("API-ключ", FullGramAIKeychain.maskedKey(for: provider)),
            .model("Модель", store.effectiveModel),
            .endpoint("URL API", endpointDisplay),
            .testConnection(isTesting ? "Проверка подключения…" : "Проверить подключение", isTesting ? .neutral : .generic),
            .connectionFooter("Поддерживаются OpenAI, OpenRouter, Groq, Anthropic Claude, Google Gemini и локальный Ollama."),

            .securityHeader("ПРИВАТНОСТЬ И СТИЛЬ"),
            .allowReadChat(store.allowReadCurrentChat),
            .allowChatList(store.allowReadChatList),
            .allowDrafts(store.allowDraftInsert),
            .customPrompt("Стиль ответов", promptSummary),
            .viewSecurityPrompt("Промпт безопасности"),
            .securityFooter("Защита от Prompt Injection: чужие сообщения изолируются в [UNTRUSTED_CHAT_DATA], ключи хранятся в iOS Keychain.")
        ]

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("ИИ Ассистент"),
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

// MARK: - Внутренний промпт безопасности ИИ (просмотр + копирование)

private final class FullGramAISecurityPromptController: ViewController {
    private var theme: PresentationTheme
    private var scrollTopConstraint: NSLayoutConstraint?

    init(context: AccountContext) {
        self.theme = context.sharedContext.currentPresentationData.with { $0 }.theme
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }))
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = "Промпт безопасности ИИ"
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.scrollTopConstraint?.constant = topInset
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
    }

    override func displayNodeDidLoad() {
        super.displayNodeDidLoad()
        let root = self.displayNode.view
        root.backgroundColor = self.theme.list.blocksBackgroundColor

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        if let navView = self.navigationBar?.view, navView.superview === root {
            root.insertSubview(scroll, belowSubview: navView)
        } else {
            root.insertSubview(scroll, at: 0)
        }

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let heroCard = UIView()
        heroCard.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        heroCard.layer.cornerRadius = 14.0
        stack.addArrangedSubview(heroCard)

        let imgView = UIImageView(image: UIImage(named: "FullGramMascotPortrait"))
        imgView.contentMode = .scaleAspectFill
        imgView.layer.cornerRadius = 28.0
        imgView.clipsToBounds = true
        imgView.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(imgView)

        let heroTitle = UILabel()
        heroTitle.text = "Системный промпт защиты агента"
        heroTitle.font = .systemFont(ofSize: 16.0, weight: .semibold)
        heroTitle.textColor = self.theme.list.itemPrimaryTextColor
        heroTitle.numberOfLines = 0
        heroTitle.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(heroTitle)

        let heroSub = UILabel()
        heroSub.text = "Этот промпт автоматически добавляется первым в каждый запрос к вашему ИИ-агенту."
        heroSub.font = .systemFont(ofSize: 13.0)
        heroSub.textColor = self.theme.list.itemSecondaryTextColor
        heroSub.numberOfLines = 0
        heroSub.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(heroSub)

        NSLayoutConstraint.activate([
            imgView.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 14.0),
            imgView.centerYAnchor.constraint(equalTo: heroCard.centerYAnchor),
            imgView.widthAnchor.constraint(equalToConstant: 56.0),
            imgView.heightAnchor.constraint(equalToConstant: 56.0),

            heroTitle.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 14.0),
            heroTitle.leadingAnchor.constraint(equalTo: imgView.trailingAnchor, constant: 12.0),
            heroTitle.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -14.0),

            heroSub.topAnchor.constraint(equalTo: heroTitle.bottomAnchor, constant: 4.0),
            heroSub.leadingAnchor.constraint(equalTo: heroTitle.leadingAnchor),
            heroSub.trailingAnchor.constraint(equalTo: heroTitle.trailingAnchor),
            heroSub.bottomAnchor.constraint(lessThanOrEqualTo: heroCard.bottomAnchor, constant: -14.0),
            heroCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 84.0)
        ])

        let textCard = UIView()
        textCard.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        textCard.layer.cornerRadius = 14.0
        stack.addArrangedSubview(textCard)

        let promptLabel = UILabel()
        promptLabel.numberOfLines = 0
        promptLabel.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        promptLabel.textColor = self.theme.list.itemPrimaryTextColor
        promptLabel.text = FullGramAIStore.securitySystemPrompt
        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        textCard.addSubview(promptLabel)

        NSLayoutConstraint.activate([
            promptLabel.topAnchor.constraint(equalTo: textCard.topAnchor, constant: 14.0),
            promptLabel.bottomAnchor.constraint(equalTo: textCard.bottomAnchor, constant: -14.0),
            promptLabel.leadingAnchor.constraint(equalTo: textCard.leadingAnchor, constant: 14.0),
            promptLabel.trailingAnchor.constraint(equalTo: textCard.trailingAnchor, constant: -14.0)
        ])

        var copyCfg = UIButton.Configuration.filled()
        copyCfg.title = "Скопировать системный промпт"
        copyCfg.baseBackgroundColor = self.theme.chat.inputPanel.actionControlFillColor
        copyCfg.baseForegroundColor = .white
        copyCfg.cornerStyle = .large
        copyCfg.contentInsets = NSDirectionalEdgeInsets(top: 12.0, leading: 16.0, bottom: 12.0, trailing: 16.0)
        let copyButton = UIButton(configuration: copyCfg)
        copyButton.addTarget(self, action: #selector(self.copyTapped), for: .touchUpInside)
        stack.addArrangedSubview(copyButton)

        let topC = scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 88.0)
        self.scrollTopConstraint = topC
        NSLayoutConstraint.activate([
            topC,
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16.0),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24.0),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16.0)
        ])
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = FullGramAIStore.securitySystemPrompt
        let alert = UIAlertController(title: nil, message: "Промпт безопасности скопирован в буфер обмена.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(alert, animated: true)
    }
}

public func fullGramAISecurityPromptController(context: AccountContext) -> ViewController {
    return FullGramAISecurityPromptController(context: context)
}
