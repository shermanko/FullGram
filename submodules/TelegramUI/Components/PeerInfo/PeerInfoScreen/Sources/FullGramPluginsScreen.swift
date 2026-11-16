import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Главный экран «Плагины»

private final class FullGramPluginsArguments {
    let toggleSystem: (Bool) -> Void
    let createPlugin: (FullGramPluginLanguage) -> Void
    let importFile: () -> Void
    let openRemoteCatalog: () -> Void
    let openPlugin: (FullGramPluginDescriptor) -> Void
    let openApiDocs: () -> Void

    init(
        toggleSystem: @escaping (Bool) -> Void,
        createPlugin: @escaping (FullGramPluginLanguage) -> Void,
        importFile: @escaping () -> Void,
        openRemoteCatalog: @escaping () -> Void,
        openPlugin: @escaping (FullGramPluginDescriptor) -> Void,
        openApiDocs: @escaping () -> Void
    ) {
        self.toggleSystem = toggleSystem
        self.createPlugin = createPlugin
        self.importFile = importFile
        self.openRemoteCatalog = openRemoteCatalog
        self.openPlugin = openPlugin
        self.openApiDocs = openApiDocs
    }
}

private enum FullGramPluginsSection: Int32 {
    case system
    case actions
    case list
}

private enum FullGramPluginsEntry: ItemListNodeEntry {
    case systemSwitch(Bool)
    case systemInfo(String)
    case remoteCatalog(String)
    case createLua
    case createPython
    case importFile
    case apiDocs
    case listHeader(String)
    case pluginItem(Int32, FullGramPluginDescriptor, String?)

    var section: ItemListSectionId {
        switch self {
        case .systemSwitch, .systemInfo: return FullGramPluginsSection.system.rawValue
        case .remoteCatalog, .createLua, .createPython, .importFile, .apiDocs: return FullGramPluginsSection.actions.rawValue
        case .listHeader, .pluginItem: return FullGramPluginsSection.list.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .systemSwitch: return 0
        case .systemInfo: return 1
        case .remoteCatalog: return 9
        case .createLua: return 10
        case .createPython: return 11
        case .importFile: return 12
        case .apiDocs: return 13
        case .listHeader: return 100
        case let .pluginItem(idx, _, _): return 101 + idx
        }
    }

    static func < (lhs: FullGramPluginsEntry, rhs: FullGramPluginsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramPluginsArguments
        switch self {
        case let .systemSwitch(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Включить систему плагинов", value: value, sectionId: self.section, style: .blocks, updated: args.toggleSystem)
        case let .systemInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .remoteCatalog(label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "🌐 Каталог плагинов с сервера", label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openRemoteCatalog)
        case .createLua:
            return ItemListActionItem(presentationData: presentationData, title: "+ Новый плагин на Lua (.lua)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.createPlugin(.lua)
            })
        case .createPython:
            return ItemListActionItem(presentationData: presentationData, title: "+ Новый плагин на Python (.py)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.createPlugin(.python)
            })
        case .importFile:
            return ItemListActionItem(presentationData: presentationData, title: "Импортировать файл (.lua / .py)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.importFile)
        case .apiDocs:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Справка по API (Lua и Python)", label: "", sectionId: self.section, style: .blocks, action: args.openApiDocs)
        case let .listHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .pluginItem(_, descriptor, error):
            let status = error != nil ? "Ошибка" : (descriptor.isEnabled ? "Вкл" : "Выкл")
            let label = "[\(descriptor.language.displayName)] \(status)"
            let title = descriptor.description.isEmpty ? descriptor.name : "\(descriptor.name)\n\(descriptor.description)"
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                args.openPlugin(descriptor)
            })
        }
    }
}

private final class FullGramPluginDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let first = urls.first {
            self.onPick(first)
        }
    }
}

private var activeDocumentPickerDelegate: FullGramPluginDocumentPickerDelegate?

func fullGramPluginsController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?

    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let bump: () -> Void = {
        version += 1
        refresh.set(version)
    }

    let observer = NotificationCenter.default.addObserver(forName: FullGramPluginNotifications.pluginsDidChange, object: nil, queue: .main) { _ in
        bump()
    }

    let args = FullGramPluginsArguments(
        toggleSystem: { enabled in
            FullGramPluginManager.shared.isSystemEnabled = enabled
            bump()
        },
        createPlugin: { language in
            let template: String
            if language == .lua {
                template = """
-- @name Мой Lua-плагин
-- @version 1.0
-- @author User
-- @description Описание плагина

function on_command(ctx)
    if ctx.command == "hi" then
        return "Привет, " .. (ctx.args ~= "" and ctx.args or "мир") .. "!"
    end
    return nil
end

function on_outgoing_message(ctx)
    return nil
end
"""
            } else {
                template = """
# @name Мой Python-плагин
# @version 1.0
# @author User
# @description Описание плагина

import fullgram

def on_command(ctx):
    if ctx["command"] == "hi":
        target = ctx["args"] if ctx["args"] else "мир"
        return f"Привет, {target}!"
    return None

def on_outgoing_message(ctx):
    return None
"""
            }
            let draft = FullGramPluginDescriptor(
                id: "custom_\(Int(Date().timeIntervalSince1970))",
                name: language == .lua ? "Новый Lua-плагин" : "Новый Python-плагин",
                language: language,
                code: template,
                isEnabled: true,
                isBuiltIn: false
            )
            pushImpl?(FullGramPluginEditorContainerController(context: context, descriptor: draft, isNew: true, onChanged: bump))
        },
        importFile: {
            var types: [UTType] = [.plainText, .sourceCode]
            if let luaType = UTType(filenameExtension: "lua") { types.append(luaType) }
            if let pyType = UTType(filenameExtension: "py") { types.append(pyType) }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            let delegate = FullGramPluginDocumentPickerDelegate { url in
                activeDocumentPickerDelegate = nil
                do {
                    let imported = try FullGramPluginManager.shared.importPlugin(from: url)
                    bump()
                    let alert = textAlertController(context: context, title: "Плагин импортирован", text: "\(imported.name) [\(imported.language.displayName)] добавлен и включён.", actions: [
                        TextAlertAction(type: .defaultAction, title: "OK", action: {})
                    ])
                    presentControllerImpl?(alert)
                } catch {
                    let alert = textAlertController(context: context, title: "Ошибка импорта", text: error.localizedDescription, actions: [
                        TextAlertAction(type: .defaultAction, title: "OK", action: {})
                    ])
                    presentControllerImpl?(alert)
                }
            }
            activeDocumentPickerDelegate = delegate
            picker.delegate = delegate
            presentNativeImpl?(picker)
        },
        openRemoteCatalog: {
            pushImpl?(fullGramRemoteCatalogController(context: context))
        },
        openPlugin: { descriptor in
            pushImpl?(FullGramPluginEditorContainerController(context: context, descriptor: descriptor, isNew: false, onChanged: bump))
        },
        openApiDocs: {
            pushImpl?(fullGramPluginApiDocsController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let manager = FullGramPluginManager.shared
        let plugins = manager.allPlugins()
        let catalogStatus = manager.catalogURL.isEmpty ? "Настроить" : "Подключён"

        var entries: [FullGramPluginsEntry] = [
            .systemSwitch(manager.isSystemEnabled),
            .systemInfo("Встроенные движки Lua и Python работают локально в изолированной песочнице. Пишите плагины здесь, импортируйте .lua/.py или скачивайте новые из онлайн-каталога без переустановки FullGram."),
            .remoteCatalog(catalogStatus),
            .createLua,
            .createPython,
            .importFile,
            .apiDocs
        ]

        entries.append(.listHeader("УСТАНОВЛЕННЫЕ ПЛАГИНЫ (\(plugins.count))"))
        for (idx, item) in plugins.enumerated() {
            entries.append(.pluginItem(Int32(idx), item, manager.error(forPluginId: item.id)))
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Плагины"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}

// MARK: - Редактор плагина, тест и консоль

private final class FullGramPluginEditorViewController: UIViewController {
    private let theme: PresentationTheme
    private var descriptor: FullGramPluginDescriptor
    private let isNew: Bool
    private let onChanged: () -> Void
    var onClose: (() -> Void)?

    private let enableSwitch = UISwitch()
    private let metaLabel = UILabel()
    private let codeTextView = UITextView()
    private let testInputField = UITextField()
    private let outputTextView = UITextView()

    init(theme: PresentationTheme, descriptor: FullGramPluginDescriptor, isNew: Bool, onChanged: @escaping () -> Void) {
        self.theme = theme
        self.descriptor = descriptor
        self.isNew = isNew
        self.onChanged = onChanged
        super.init(nibName: nil, bundle: nil)
        self.title = descriptor.name
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.theme.list.blocksBackgroundColor

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
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
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12.0),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24.0),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 14.0),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -14.0)
        ])

        // Header card with enable switch & language badge
        let headerCard = UIView()
        headerCard.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        headerCard.layer.cornerRadius = 12.0
        let switchTitle = UILabel()
        switchTitle.text = "Включён [\(self.descriptor.language.displayName)]"
        switchTitle.font = .systemFont(ofSize: 16.0, weight: .medium)
        switchTitle.textColor = self.theme.list.itemPrimaryTextColor
        switchTitle.translatesAutoresizingMaskIntoConstraints = false
        self.enableSwitch.isOn = self.descriptor.isEnabled
        self.enableSwitch.onTintColor = self.theme.list.itemAccentColor
        self.enableSwitch.addTarget(self, action: #selector(self.toggleChanged), for: .valueChanged)
        self.enableSwitch.translatesAutoresizingMaskIntoConstraints = false

        self.metaLabel.font = .systemFont(ofSize: 12.5)
        self.metaLabel.textColor = self.theme.list.itemSecondaryTextColor
        self.metaLabel.numberOfLines = 0
        self.metaLabel.translatesAutoresizingMaskIntoConstraints = false
        self.refreshMetaLabel()

        headerCard.addSubview(switchTitle)
        headerCard.addSubview(self.enableSwitch)
        headerCard.addSubview(self.metaLabel)
        NSLayoutConstraint.activate([
            switchTitle.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 12.0),
            switchTitle.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 14.0),
            self.enableSwitch.centerYAnchor.constraint(equalTo: switchTitle.centerYAnchor),
            self.enableSwitch.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -14.0),
            self.metaLabel.topAnchor.constraint(equalTo: switchTitle.bottomAnchor, constant: 8.0),
            self.metaLabel.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 14.0),
            self.metaLabel.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -14.0),
            self.metaLabel.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -12.0)
        ])
        stack.addArrangedSubview(headerCard)

        // Code editor
        let codeHeader = UILabel()
        codeHeader.text = "КОД ПЛАГИНА (.\(self.descriptor.language.fileExtension))"
        codeHeader.font = .systemFont(ofSize: 12.0, weight: .semibold)
        codeHeader.textColor = self.theme.list.freeTextColor
        stack.addArrangedSubview(codeHeader)

        self.codeTextView.text = self.descriptor.code
        self.codeTextView.font = UIFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
        self.codeTextView.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        self.codeTextView.textColor = self.theme.list.itemPrimaryTextColor
        self.codeTextView.layer.cornerRadius = 12.0
        self.codeTextView.textContainerInset = UIEdgeInsets(top: 12.0, left: 10.0, bottom: 12.0, right: 10.0)
        self.codeTextView.autocorrectionType = .no
        self.codeTextView.autocapitalizationType = .none
        self.codeTextView.smartQuotesType = .no
        self.codeTextView.smartDashesType = .no
        self.codeTextView.smartInsertDeleteType = .no
        self.codeTextView.spellCheckingType = .no
        self.codeTextView.heightAnchor.constraint(equalToConstant: 290.0).isActive = true
        stack.addArrangedSubview(self.codeTextView)

        // Action buttons row: Save / Export / Delete
        let actionRow = UIStackView()
        actionRow.axis = .horizontal
        actionRow.spacing = 8.0
        actionRow.distribution = .fillEqually

        let saveBtn = self.makeButton(title: "Сохранить", bg: self.theme.list.itemAccentColor, fg: .white, action: #selector(self.saveTapped))
        let exportBtn = self.makeButton(title: "Экспорт", bg: self.theme.list.itemBlocksBackgroundColor, fg: self.theme.list.itemPrimaryTextColor, action: #selector(self.exportTapped))
        let deleteBtn = self.makeButton(title: "Удалить", bg: self.theme.list.itemBlocksBackgroundColor, fg: self.theme.list.itemDestructiveColor, action: #selector(self.deleteTapped))
        actionRow.addArrangedSubview(saveBtn)
        actionRow.addArrangedSubview(exportBtn)
        if !self.isNew {
            actionRow.addArrangedSubview(deleteBtn)
        }
        stack.addArrangedSubview(actionRow)

        // Sandbox test runner
        let testHeader = UILabel()
        testHeader.text = "ТЕСТ И КОНСОЛЬ ВЫВОДА"
        testHeader.font = .systemFont(ofSize: 12.0, weight: .semibold)
        testHeader.textColor = self.theme.list.freeTextColor
        stack.addArrangedSubview(testHeader)

        let testBar = UIStackView()
        testBar.axis = .horizontal
        testBar.spacing = 8.0
        self.testInputField.placeholder = "Ввод (напр. .shrug тест или .calc 6*7)"
        self.testInputField.text = ".shrug тест"
        self.testInputField.font = .systemFont(ofSize: 14.0)
        self.testInputField.textColor = self.theme.list.itemPrimaryTextColor
        self.testInputField.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        self.testInputField.layer.cornerRadius = 10.0
        self.testInputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        self.testInputField.leftViewMode = .always
        self.testInputField.autocorrectionType = .no
        self.testInputField.autocapitalizationType = .none
        self.testInputField.heightAnchor.constraint(equalToConstant: 40.0).isActive = true

        let runBtn = self.makeButton(title: "▶ Тест", bg: self.theme.list.itemAccentColor, fg: .white, action: #selector(self.runTestTapped))
        runBtn.widthAnchor.constraint(equalToConstant: 96.0).isActive = true

        testBar.addArrangedSubview(self.testInputField)
        testBar.addArrangedSubview(runBtn)
        stack.addArrangedSubview(testBar)

        self.outputTextView.isEditable = false
        self.outputTextView.font = UIFont.monospacedSystemFont(ofSize: 12.0, weight: .regular)
        self.outputTextView.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        self.outputTextView.textColor = self.theme.list.itemSecondaryTextColor
        self.outputTextView.layer.cornerRadius = 12.0
        self.outputTextView.textContainerInset = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
        self.outputTextView.heightAnchor.constraint(equalToConstant: 140.0).isActive = true
        self.refreshLogsView()
        stack.addArrangedSubview(self.outputTextView)
    }

    private func makeButton(title: String, bg: UIColor, fg: UIColor, action: Selector) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title = title
        cfg.baseBackgroundColor = bg
        cfg.baseForegroundColor = fg
        cfg.cornerStyle = .medium
        let btn = UIButton(configuration: cfg)
        btn.heightAnchor.constraint(equalToConstant: 42.0).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func refreshMetaLabel() {
        let err = FullGramPluginManager.shared.error(forPluginId: self.descriptor.id)
        if let err {
            self.metaLabel.text = "Ошибка: \(err)"
            self.metaLabel.textColor = self.theme.list.itemDestructiveColor
        } else {
            let desc = self.descriptor.description.isEmpty ? "Без описания" : self.descriptor.description
            self.metaLabel.text = "ID: \(self.descriptor.id) • v\(self.descriptor.version) • \(self.descriptor.author)\n\(desc)"
            self.metaLabel.textColor = self.theme.list.itemSecondaryTextColor
        }
    }

    private func refreshLogsView() {
        let logs = FullGramPluginManager.shared.logs(forPluginId: self.descriptor.id)
        self.outputTextView.text = logs.isEmpty ? "Логи пусты. Нажмите «▶ Тест» для проверки скрипта." : logs.joined(separator: "\n")
    }

    @objc private func toggleChanged() {
        self.descriptor.isEnabled = self.enableSwitch.isOn
        if !self.isNew {
            FullGramPluginManager.shared.setPluginEnabled(id: self.descriptor.id, enabled: self.enableSwitch.isOn)
            self.refreshMetaLabel()
            self.onChanged()
        }
    }

    @objc private func saveTapped() {
        let code = self.codeTextView.text ?? ""
        let saved = FullGramPluginManager.shared.savePlugin(
            id: self.isNew ? nil : self.descriptor.id,
            name: self.descriptor.name,
            language: self.descriptor.language,
            code: code,
            enabled: self.enableSwitch.isOn
        )
        self.descriptor = saved
        self.refreshMetaLabel()
        self.refreshLogsView()
        self.onChanged()
        let alert = UIAlertController(title: "Сохранено", message: "Плагин «\(saved.name)» [\(saved.language.displayName)] обновлён.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        self.present(alert, animated: true)
    }

    @objc private func runTestTapped() {
        let code = self.codeTextView.text ?? ""
        let sample = self.testInputField.text ?? ""
        let res = FullGramPluginManager.shared.testExecute(code: code, language: self.descriptor.language, sampleInput: sample)
        var lines: [String] = []
        if let err = res.error {
            lines.append("❌ ОШИБКА: \(err)")
        } else {
            lines.append("✅ Выполнено успешно")
            lines.append("→ Результат: \(res.output.isEmpty ? "(nil / без изменений)" : res.output)")
        }
        if !res.logs.isEmpty {
            lines.append("--- Консоль ---")
            lines.append(contentsOf: res.logs)
        }
        self.outputTextView.text = lines.joined(separator: "\n")
    }

    @objc private func exportTapped() {
        self.saveTappedQuietly()
        guard let url = FullGramPluginManager.shared.exportFileURL(forPluginId: self.descriptor.id) else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        self.present(activity, animated: true)
    }

    private func saveTappedQuietly() {
        let code = self.codeTextView.text ?? ""
        self.descriptor = FullGramPluginManager.shared.savePlugin(
            id: self.isNew ? nil : self.descriptor.id,
            name: self.descriptor.name,
            language: self.descriptor.language,
            code: code,
            enabled: self.enableSwitch.isOn
        )
        self.onChanged()
    }

    @objc private func deleteTapped() {
        FullGramPluginManager.shared.deletePlugin(id: self.descriptor.id)
        self.onChanged()
        self.onClose?()
    }
}

private final class FullGramPluginEditorContainerController: ViewController {
    private let hosted: FullGramPluginEditorViewController

    init(context: AccountContext, descriptor: FullGramPluginDescriptor, isNew: Bool, onChanged: @escaping () -> Void) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        self.hosted = FullGramPluginEditorViewController(theme: data.theme, descriptor: descriptor, isNew: isNew, onChanged: onChanged)
        let navBarTheme = NavigationBarTheme(overallDarkAppearance: data.theme.overallDarkAppearance, buttonColor: data.theme.rootController.navigationBar.buttonColor, disabledButtonColor: data.theme.rootController.navigationBar.disabledButtonColor, primaryTextColor: data.theme.rootController.navigationBar.primaryTextColor, backgroundColor: data.theme.rootController.navigationBar.opaqueBackgroundColor, opaqueBackgroundColor: data.theme.rootController.navigationBar.opaqueBackgroundColor, enableBackgroundBlur: false, separatorColor: data.theme.rootController.navigationBar.separatorColor, badgeBackgroundColor: data.theme.rootController.navigationBar.badgeBackgroundColor, badgeStrokeColor: data.theme.rootController.navigationBar.badgeStrokeColor, badgeTextColor: data.theme.rootController.navigationBar.badgeTextColor)
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: navBarTheme, strings: NavigationBarStrings(presentationStrings: data.strings)))
        self.title = descriptor.name
        self.hosted.onClose = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
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

// MARK: - Справка по API

private enum FullGramPluginDocsEntry: ItemListNodeEntry {
    case header(Int32, String)
    case text(Int32, String)

    var section: ItemListSectionId { return self.stableId / 100 }
    var stableId: Int32 {
        switch self {
        case let .header(id, _): return id
        case let .text(id, _): return id
        }
    }
    static func < (lhs: FullGramPluginDocsEntry, rhs: FullGramPluginDocsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, s): return ItemListSectionHeaderItem(presentationData: presentationData, text: s, sectionId: self.section)
        case let .text(_, s): return ItemListTextItem(presentationData: presentationData, text: .plain(s), sectionId: self.section)
        }
    }
}

private func fullGramPluginApiDocsController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramPluginDocsEntry] = [
            .header(0, "ХУКИ ПЛАГИНОВ (LUA И PYTHON)"),
            .text(1, """
• on_command(ctx) — вызывается при отправке сообщения вида .команда аргументы или .plug подкоманда.
  Поля ctx: command, subcommand, args, text, peer_id, is_group, is_channel, chat_stats.
  Возврат: строка (заменит текст), nil/None (пропустить), или словарь/таблица { "cancel": true, "toast": "текст" }.

• on_outgoing_message(ctx) — перехват любого исходящего текста перед отправкой.
  Поля ctx: text, peer_id, is_group, is_channel.

• on_render_message(ctx) — модификация текста сообщения при отображении в чате.
  Поля ctx: text, peer_id, is_incoming, message_id.
"""),
            .header(100, "ВСТРОЕННЫЙ МОДУЛЬ fullgram"),
            .text(101, """
• fullgram.toast(text) — показать уведомление в чате
• fullgram.log(text) — записать строку в консоль плагина
• fullgram.storage_get(key, default) / fullgram.storage_set(key, val) — постоянное хранилище
• fullgram.clipboard_set(text) / fullgram.clipboard_get() — буфер обмена
• fullgram.get_chat_stats() — статистика текущего чата для команд .plug (first_date, last_date, top_words, rare_words, profanity_count, voice_count, round_count)
• fullgram.http_get(url) — HTTPS GET-запрос на публичные хосты (требует -- @permission net или # @permission net; недоступен в on_render_message)
• fullgram.register_command("cmd", fn) — регистрация команды

Python модули: import re, json, math, random, time, fullgram. Поддерживаются f-строки, def, lambda, list comprehensions, try/except.
Lua библиотеки: string, table, math, json, pairs, ipairs, pcall, print.
""")
        ]
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("API плагинов"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, ()))
    }
    return ItemListController(context: context, state: signal)
}

// MARK: - Онлайн-каталог плагинов (бесплатный сервер plugins.json без переустановки)

private final class FullGramRemoteCatalogArguments {
    let editURL: () -> Void
    let reloadCatalog: () -> Void
    let installItem: (FullGramRemotePluginItem) -> Void
    init(editURL: @escaping () -> Void, reloadCatalog: @escaping () -> Void, installItem: @escaping (FullGramRemotePluginItem) -> Void) {
        self.editURL = editURL
        self.reloadCatalog = reloadCatalog
        self.installItem = installItem
    }
}

private enum FullGramRemoteCatalogSection: Int32 {
    case server
    case items
}

private enum FullGramRemoteCatalogEntry: ItemListNodeEntry {
    case serverHeader(String)
    case serverURL(String, String)
    case reload(String, ItemListActionKind)
    case serverInfo(String)
    case itemsHeader(String)
    case pluginItem(Int32, FullGramRemotePluginItem, Bool)
    case emptyStatus(String)

    var section: ItemListSectionId {
        switch self {
        case .serverHeader, .serverURL, .reload, .serverInfo: return FullGramRemoteCatalogSection.server.rawValue
        case .itemsHeader, .pluginItem, .emptyStatus: return FullGramRemoteCatalogSection.items.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .serverHeader: return 0
        case .serverURL: return 1
        case .reload: return 2
        case .serverInfo: return 3
        case .itemsHeader: return 100
        case let .pluginItem(idx, _, _): return 101 + idx
        case .emptyStatus: return 500
        }
    }

    static func < (lhs: FullGramRemoteCatalogEntry, rhs: FullGramRemoteCatalogEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramRemoteCatalogArguments
        switch self {
        case let .serverHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .serverURL(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editURL)
        case let .reload(title, kind):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: kind, alignment: .center, sectionId: self.section, style: .blocks, action: args.reloadCatalog)
        case let .serverInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .itemsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .pluginItem(_, item, installed):
            let status = installed ? "Установлен" : "Скачать"
            let title = item.description.isEmpty ? item.name : "\(item.name)\n\(item.description)"
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "[\(item.language.displayName)] \(status)", sectionId: self.section, style: .blocks, action: {
                args.installItem(item)
            })
        case let .emptyStatus(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func fullGramRemoteCatalogController(context: AccountContext) -> ViewController {
    var presentNativeImpl: ((UIViewController) -> Void)?
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    var isLoading = false
    var statusMessage = FullGramPluginManager.shared.catalogURL.isEmpty
        ? "Укажите ссылку на plugins.json (например, GitHub Raw / Cloudflare Workers) и нажмите «Обновить каталог»."
        : "Нажмите «Обновить каталог» для загрузки списка плагинов."
    var remoteItems: [FullGramRemotePluginItem] = []

    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
    }

    let performFetch: () -> Void = {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = "Загрузка каталога…"
        bump()
        FullGramPluginManager.shared.fetchRemoteCatalog { result in
            isLoading = false
            switch result {
            case let .success(catalog):
                remoteItems = catalog.plugins
                statusMessage = catalog.plugins.isEmpty ? "Каталог пуст." : "Загружено плагинов: \(catalog.plugins.count)"
            case let .failure(error):
                statusMessage = "Ошибка: \(error.localizedDescription)"
            }
            bump()
        }
    }

    let args = FullGramRemoteCatalogArguments(
        editURL: {
            let alert = UIAlertController(
                title: "URL каталога (plugins.json)",
                message: "Вставьте прямую https:// ссылку на JSON-файл каталога (GitHub Raw, jsDelivr CDN или Cloudflare Workers).",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.text = FullGramPluginManager.shared.catalogURL
                tf.placeholder = "https://raw.githubusercontent.com/user/fullgram-plugins/main/plugins.json"
                tf.keyboardType = .URL
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "Сохранить и обновить", style: .default, handler: { _ in
                FullGramPluginManager.shared.catalogURL = alert.textFields?.first?.text ?? ""
                performFetch()
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        reloadCatalog: {
            performFetch()
        },
        installItem: { item in
            let alert = UIAlertController(
                title: item.name,
                message: "Автор: \(item.author) • v\(item.version) [\(item.language.displayName)]\n\(item.description)\n\nУстановить этот плагин?",
                preferredStyle: .alert
            )
            let doInstall: (Bool) -> Void = { enable in
                FullGramPluginManager.shared.installRemotePlugin(item, enableImmediately: enable) { res in
                    let doneAlert: UIAlertController
                    switch res {
                    case let .success(saved):
                        doneAlert = UIAlertController(title: "Готово", message: "Плагин «\(saved.name)» установлен\(enable ? " и включён" : " (отключён)").", preferredStyle: .alert)
                    case let .failure(err):
                        doneAlert = UIAlertController(title: "Ошибка установки", message: err.localizedDescription, preferredStyle: .alert)
                    }
                    doneAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(doneAlert)
                    bump()
                }
            }
            alert.addAction(UIAlertAction(title: "Установить и включить", style: .default, handler: { _ in doInstall(true) }))
            alert.addAction(UIAlertAction(title: "Только скачать (выкл.)", style: .default, handler: { _ in doInstall(false) }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        }
    )

    if !FullGramPluginManager.shared.catalogURL.isEmpty {
        DispatchQueue.main.async {
            performFetch()
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let currentUrl = FullGramPluginManager.shared.catalogURL
        let urlLabel = currentUrl.isEmpty ? "Не задан" : String(currentUrl.suffix(28))
        let installedIds = Set(FullGramPluginManager.shared.allPlugins().map { $0.id })

        var entries: [FullGramRemoteCatalogEntry] = [
            .serverHeader("СЕРВЕР КАТАЛОГА (0₽ / БЕЗ ПЕРЕУСТАНОВКИ)"),
            .serverURL("Ссылка на plugins.json", urlLabel),
            .reload(isLoading ? "⏳ Обновление…" : "🔄 Обновить каталог", isLoading ? .neutral : .generic),
            .serverInfo("Поддерживаются бесплатный GitHub (Raw / Pages / jsDelivr) и Cloudflare Workers: добавляйте скрипты в репозиторий, и пользователи увидят их здесь сразу без обновления приложения.")
        ]

        entries.append(.itemsHeader("ПЛАГИНЫ НА СЕРВЕРЕ (\(remoteItems.count))"))
        if remoteItems.isEmpty {
            entries.append(.emptyStatus(statusMessage))
        } else {
            for (idx, item) in remoteItems.enumerated() {
                entries.append(.pluginItem(Int32(idx), item, installedIds.contains(item.id)))
            }
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Каталог плагинов"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }

    let controller = ItemListController(context: context, state: signal)
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}
