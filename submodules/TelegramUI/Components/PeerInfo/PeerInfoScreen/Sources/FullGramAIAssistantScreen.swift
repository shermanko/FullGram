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

private enum FullGramAISection: Int32 {
    case main
    case connection
    case security
}

private enum FullGramAIEntry: ItemListNodeEntry {
    case mainHeader(String)
    case enabled(Bool)
    case openWindow(String)
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
        case .mainHeader, .enabled, .openWindow, .floatingPet, .mainFooter:
            return FullGramAISection.main.rawValue
        case .connectionHeader, .provider, .apiKey, .model, .endpoint, .testConnection, .connectionFooter:
            return FullGramAISection.connection.rawValue
        case .securityHeader, .allowReadChat, .allowChatList, .allowDrafts, .customPrompt, .viewSecurityPrompt, .securityFooter:
            return FullGramAISection.security.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .mainHeader: return 0
        case .enabled: return 1
        case .openWindow: return 2
        case .floatingPet: return 3
        case .mainFooter: return 4

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

    static func < (lhs: FullGramAIEntry, rhs: FullGramAIEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramAIScreenArguments
        switch self {
        case let .mainHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .enabled(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Включить ИИ-ассистента (.ai и окно)", value: val, sectionId: self.section, style: .blocks, updated: args.toggleEnabled)
        case let .openWindow(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.openAIChatWindow)
        case let .floatingPet(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Питомец (маскот) поверх экрана", value: val, sectionId: self.section, style: .blocks, updated: args.toggleFloatingPet)
        case let .mainFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case let .connectionHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .provider(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickProvider)
        case let .apiKey(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editApiKey)
        case let .model(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editModel)
        case let .endpoint(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editEndpoint)
        case let .testConnection(title, kind):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: kind, alignment: .center, sectionId: self.section, style: .blocks, action: args.testConnection)
        case let .connectionFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)

        case let .securityHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .allowReadChat(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Изучать открытый чат и даты", value: val, sectionId: self.section, style: .blocks, updated: args.toggleAllowReadChat)
        case let .allowChatList(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Видеть список последних диалогов", value: val, sectionId: self.section, style: .blocks, updated: args.toggleAllowChatList)
        case let .allowDrafts(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Вставлять черновики в поле ввода", value: val, sectionId: self.section, style: .blocks, updated: args.toggleAllowDrafts)
        case let .customPrompt(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editCustomPrompt)
        case let .viewSecurityPrompt(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openSecurityPrompt)
        case let .securityFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramAIAssistantController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?

    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    var isTestingConnection = false

    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
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
            let alert = UIAlertController(title: "Провайдер ИИ", message: nil, preferredStyle: .actionSheet)
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
                tf.placeholder = "sk-..."
                tf.isSecureTextEntry = true
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
                let val = alert.textFields?.first?.text ?? ""
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
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
                FullGramAIStore.shared.modelName = alert.textFields?.first?.text ?? ""
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
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
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
                FullGramAIStore.shared.customEndpoint = alert.textFields?.first?.text ?? ""
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        testConnection: {
            guard !isTestingConnection else { return }
            isTestingConnection = true
            bump()
            FullGramAIStore.shared.testConnection { result in
                isTestingConnection = false
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
            let alert = UIAlertController(
                title: "Свои инструкции для ИИ",
                message: "Дополнительные пожелания по стилю ответов (системные правила безопасности всегда остаются активными).",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.text = FullGramAIStore.shared.customInstructions
                tf.placeholder = "Например: Отвечай максимально коротко по пунктам"
            }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
                FullGramAIStore.shared.customInstructions = alert.textFields?.first?.text ?? ""
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
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
        let endpointDisplay = store.customEndpoint.isEmpty ? "По умолчанию" : String(store.customEndpoint.suffix(26))
        let promptSummary = store.customInstructions.isEmpty ? "Не заданы" : String(store.customInstructions.prefix(20))

        let entries: [FullGramAIEntry] = [
            .mainHeader("ИИ АССИСТЕНТ И ПИТОМЕЦ"),
            .enabled(store.isEnabled),
            .openWindow("💬 Открыть плавающее окно ИИ-чата"),
            .floatingPet(store.showFloatingPet),
            .mainFooter("Пишите прямо в любом чате «.ai привет изучи чат и напиши сколько сообщений было 15.05.2026», открывайте сворачиваемое окно в теме приложения или включите питомца-маскота поверх экрана."),

            .connectionHeader("ПОДКЛЮЧЕНИЕ ПО API-КЛЮЧУ"),
            .provider("Провайдер", provider.title),
            .apiKey("API-ключ", FullGramAIKeychain.maskedKey(for: provider)),
            .model("Модель", store.effectiveModel),
            .endpoint("URL API", endpointDisplay),
            .testConnection(isTestingConnection ? "⏳ Проверка подключения…" : "🔌 Проверить подключение", isTestingConnection ? .neutral : .generic),
            .connectionFooter("Поддерживаются OpenAI, OpenRouter, Groq, Anthropic Claude и любой OpenAI-совместимый сервер (включая локальный Ollama)."),

            .securityHeader("БЕЗОПАСНОСТЬ И ДОСТУП К TELEGRAM"),
            .allowReadChat(store.allowReadCurrentChat),
            .allowChatList(store.allowReadChatList),
            .allowDrafts(store.allowDraftInsert),
            .customPrompt("Свои инструкции стиля", promptSummary),
            .viewSecurityPrompt("🛡 Внутренний промпт безопасности"),
            .securityFooter("Встроенная защита от Prompt Injection: чужие сообщения изолируются в теге [UNTRUSTED_CHAT_DATA], API-ключи лежат в Keychain, а отправка сообщений и изменение настроек возможны только по вашему нажатию.")
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
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}

// MARK: - Внутренний промпт безопасности ИИ (просмотр + копирование)

private final class FullGramAISecurityPromptController: ViewController {
    private var theme: PresentationTheme

    init(context: AccountContext) {
        self.theme = context.sharedContext.currentPresentationData.with { $0 }.theme
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }))
        self.title = "Промпт безопасности ИИ"
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func displayNodeDidLoad() {
        super.displayNodeDidLoad()
        let root = self.displayNode.view
        root.backgroundColor = self.theme.list.blocksBackgroundColor

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

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

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
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
