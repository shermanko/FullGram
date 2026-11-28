import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import AsyncDisplayKit
@preconcurrency import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
@preconcurrency import AccountContext

// MARK: - Главный экран «Плагины»

private final class FullGramPluginsArguments {
    let toggleSystem: (Bool) -> Void
    let toggleBackground: (Bool) -> Void
    let createPlugin: (FullGramPluginLanguage) -> Void
    let importFromFile: () -> Void
    let openPlugin: (FullGramPluginDescriptor) -> Void
    let openApiDocs: () -> Void

    init(
        toggleSystem: @escaping (Bool) -> Void,
        toggleBackground: @escaping (Bool) -> Void,
        createPlugin: @escaping (FullGramPluginLanguage) -> Void,
        importFromFile: @escaping () -> Void,
        openPlugin: @escaping (FullGramPluginDescriptor) -> Void,
        openApiDocs: @escaping () -> Void
    ) {
        self.toggleSystem = toggleSystem
        self.toggleBackground = toggleBackground
        self.createPlugin = createPlugin
        self.importFromFile = importFromFile
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
    case backgroundSwitch(Bool)
    case systemInfo(String)
    case createLua
    case createPython
    case createRust
    case importFile
    case apiDocs
    case listHeader(String)
    case emptyListInfo(String)
    case pluginItem(Int32, FullGramPluginDescriptor, String?)

    var section: ItemListSectionId {
        switch self {
        case .systemSwitch, .backgroundSwitch, .systemInfo: return FullGramPluginsSection.system.rawValue
        case .createLua, .createPython, .createRust, .importFile, .apiDocs: return FullGramPluginsSection.actions.rawValue
        case .listHeader, .emptyListInfo, .pluginItem: return FullGramPluginsSection.list.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .systemSwitch: return 0
        case .backgroundSwitch: return 1
        case .systemInfo: return 2
        case .createLua: return 10
        case .createPython: return 11
        case .createRust: return 12
        case .importFile: return 13
        case .apiDocs: return 14
        case .listHeader: return 100
        case .emptyListInfo: return 101
        case let .pluginItem(idx, _, _): return 102 + idx
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
        case let .backgroundSwitch(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Фоновый режим плагинов", value: value, sectionId: self.section, style: .blocks, updated: args.toggleBackground)
        case let .systemInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case .createLua:
            return ItemListActionItem(presentationData: presentationData, title: "+ Новый плагин на Lua (.lua)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.createPlugin(.lua)
            })
        case .createPython:
            return ItemListActionItem(presentationData: presentationData, title: "+ Новый плагин на Python (.py)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.createPlugin(.python)
            })
        case .createRust:
            return ItemListActionItem(presentationData: presentationData, title: "+ Новый плагин на Rust (.rs)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.createPlugin(.rust)
            })
        case .importFile:
            return ItemListActionItem(presentationData: presentationData, title: "📥 Импорт из Файлов (.lua / .py / .rs)", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.importFromFile)
        case .apiDocs:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Справка по Plugin API v2.0 (Lua, Python, Rust)", label: "", sectionId: self.section, style: .blocks, action: args.openApiDocs)
        case let .listHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .emptyListInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .pluginItem(_, descriptor, error):
            let status = error != nil ? "Ошибка" : (descriptor.isEnabled ? "Вкл" : "Выкл")
            let bgTag = (descriptor.isEnabled && descriptor.backgroundEnabled) ? " • Фон" : ""
            let label = "[\(descriptor.language.displayName)] \(status)\(bgTag)"
            let title = descriptor.description.isEmpty ? descriptor.name : "\(descriptor.name)\n\(descriptor.description)"
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                args.openPlugin(descriptor)
            })
        }
    }
}

private final class FullGramPluginFilePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        activePluginFilePickerDelegate = nil
        if let first = urls.first { self.onPick(first) }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        activePluginFilePickerDelegate = nil
    }
}

private nonisolated(unsafe) var activePluginFilePickerDelegate: FullGramPluginFilePickerDelegate?

func fullGramPluginsController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?

    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let bump: @Sendable () -> Void = {
        refresh.set(version.modify { $0 + 1 })
    }

    let observer = NotificationCenter.default.addObserver(forName: FullGramPluginNotifications.pluginsDidChange, object: nil, queue: .main) { _ in
        bump()
    }

    let args = FullGramPluginsArguments(
        toggleSystem: { enabled in
            FullGramPluginManager.shared.isSystemEnabled = enabled
            bump()
        },
        toggleBackground: { enabled in
            FullGramPluginManager.shared.isBackgroundExecutionEnabled = enabled
            bump()
        },
        createPlugin: { language in
            let template: String
            let defaultName: String
            switch language {
            case .lua:
                defaultName = "Новый Lua-плагин"
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
            case .python:
                defaultName = "Новый Python-плагин"
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
            case .rust:
                defaultName = "Новый Rust-плагин"
                template = """
// @name Мой Rust-плагин
// @version 1.0
// @author User
// @description Описание плагина

use fullgram::*;

fn on_command(ctx: Context) -> Option<String> {
    if ctx.command == "hi" {
        let target = if !ctx.args.is_empty() { ctx.args } else { "мир" };
        return Some(format!("Привет, {}!", target));
    }
    None
}

fn on_outgoing_message(ctx: Context) -> Option<String> {
    None
}
"""
            }
            let draft = FullGramPluginDescriptor(
                id: "custom_\(Int(Date().timeIntervalSince1970))",
                name: defaultName,
                language: language,
                code: template,
                isEnabled: true,
                isBuiltIn: false
            )
            pushImpl?(FullGramPluginEditorContainerController(context: context, descriptor: draft, isNew: true, onChanged: bump))
        },
        importFromFile: {
            var types: [UTType] = [.plainText, .sourceCode, .data, .item]
            if let luaType = UTType(filenameExtension: "lua") { types.insert(luaType, at: 0) }
            if let pyType = UTType(filenameExtension: "py") { types.insert(pyType, at: 0) }
            if let rsType = UTType(filenameExtension: "rs") { types.insert(rsType, at: 0) }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            let delegate = FullGramPluginFilePickerDelegate { url in
                activePluginFilePickerDelegate = nil
                do {
                    let saved = try FullGramPluginManager.shared.importPlugin(from: url)
                    bump()
                    let alert = UIAlertController(title: "Плагин установлен", message: "«\(saved.name)» [\(saved.language.displayName)] импортирован и включён.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(alert)
                } catch {
                    let alert = UIAlertController(title: "Ошибка импорта", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(alert)
                }
            }
            activePluginFilePickerDelegate = delegate
            picker.delegate = delegate
            presentNativeImpl?(picker)
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
        let bgSummary = manager.backgroundStatusSummary()

        var entries: [FullGramPluginsEntry] = [
            .systemSwitch(manager.isSystemEnabled),
            .backgroundSwitch(manager.isBackgroundExecutionEnabled),
            .systemInfo("FullGram Plugin System v2.0 (Lua, Python, Rust):\n• Создавайте собственные плагины или импортируйте готовые скрипты (.lua, .py, .rs).\n• В чате введите «.» или нажмите «⚡ Плагины» над полем ввода.\n• Фоновый движок (\(bgSummary.running ? "активен" : "на паузе"), активных: \(bgSummary.activeCount), тиков: \(bgSummary.totalTicks)) выполняет on_background_tick в фоне и при сворачивании приложения."),
            .createLua,
            .createPython,
            .createRust,
            .importFile,
            .apiDocs
        ]

        entries.append(.listHeader("УСТАНОВЛЕННЫЕ ПЛАГИНЫ (\(plugins.count))"))
        if plugins.isEmpty {
            entries.append(.emptyListInfo("Установленных плагинов пока нет. Создайте новый плагин или импортируйте .lua / .py / .rs файл."))
        } else {
            for (idx, item) in plugins.enumerated() {
                entries.append(.pluginItem(Int32(idx), item, manager.error(forPluginId: item.id)))
            }
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
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}

// MARK: - Редактор плагина, тест и консоль

private final class FullGramPluginEditorViewController: UIViewController {
    private let theme: PresentationTheme
    private var descriptor: FullGramPluginDescriptor
    private var isNew: Bool
    private let onChanged: () -> Void
    var onClose: (() -> Void)?

    private let enableSwitch = UISwitch()
    private let backgroundSwitch = UISwitch()
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
            scroll.topAnchor.constraint(equalTo: self.view.topAnchor),
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

        let bgTitle = UILabel()
        bgTitle.text = "Работа в фоне (интервал \(self.descriptor.backgroundInterval)с)"
        bgTitle.font = .systemFont(ofSize: 15.0, weight: .regular)
        bgTitle.textColor = self.theme.list.itemPrimaryTextColor
        bgTitle.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundSwitch.isOn = self.descriptor.backgroundEnabled
        self.backgroundSwitch.onTintColor = self.theme.list.itemAccentColor
        self.backgroundSwitch.addTarget(self, action: #selector(self.backgroundToggleChanged), for: .valueChanged)
        self.backgroundSwitch.translatesAutoresizingMaskIntoConstraints = false

        self.metaLabel.font = .systemFont(ofSize: 12.5)
        self.metaLabel.textColor = self.theme.list.itemSecondaryTextColor
        self.metaLabel.numberOfLines = 0
        self.metaLabel.translatesAutoresizingMaskIntoConstraints = false
        self.refreshMetaLabel()

        headerCard.addSubview(switchTitle)
        headerCard.addSubview(self.enableSwitch)
        headerCard.addSubview(bgTitle)
        headerCard.addSubview(self.backgroundSwitch)
        headerCard.addSubview(self.metaLabel)
        NSLayoutConstraint.activate([
            switchTitle.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 12.0),
            switchTitle.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 14.0),
            self.enableSwitch.centerYAnchor.constraint(equalTo: switchTitle.centerYAnchor),
            self.enableSwitch.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -14.0),
            bgTitle.topAnchor.constraint(equalTo: switchTitle.bottomAnchor, constant: 12.0),
            bgTitle.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 14.0),
            self.backgroundSwitch.centerYAnchor.constraint(equalTo: bgTitle.centerYAnchor),
            self.backgroundSwitch.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -14.0),
            self.metaLabel.topAnchor.constraint(equalTo: bgTitle.bottomAnchor, constant: 10.0),
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
        self.testInputField.placeholder = "Ввод (напр. .hi тест)"
        self.testInputField.text = ".hi тест"
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
        runBtn.widthAnchor.constraint(equalToConstant: 86.0).isActive = true

        let bgRunBtn = self.makeButton(title: "⏱ Фон", bg: self.theme.list.itemBlocksBackgroundColor, fg: self.theme.list.itemAccentColor, action: #selector(self.runBackgroundTestTapped))
        bgRunBtn.widthAnchor.constraint(equalToConstant: 78.0).isActive = true

        testBar.addArrangedSubview(self.testInputField)
        testBar.addArrangedSubview(runBtn)
        testBar.addArrangedSubview(bgRunBtn)
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
            let usage = "\nОткрыть в чате: введите «.» или нажмите «⚡ Плагины» / «...» → «Плагины FullGram»."
            self.metaLabel.text = "ID: \(self.descriptor.id) • v\(self.descriptor.version) • \(self.descriptor.author)\n\(desc)\(usage)"
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

    @objc private func backgroundToggleChanged() {
        self.descriptor.backgroundEnabled = self.backgroundSwitch.isOn
        if !self.isNew {
            FullGramPluginManager.shared.setPluginBackground(id: self.descriptor.id, enabled: self.backgroundSwitch.isOn)
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
            enabled: self.enableSwitch.isOn,
            backgroundEnabled: self.backgroundSwitch.isOn
        )
        self.descriptor = saved
        self.backgroundSwitch.isOn = saved.backgroundEnabled
        self.isNew = false
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

    @objc private func runBackgroundTestTapped() {
        let code = self.codeTextView.text ?? ""
        let res = FullGramPluginManager.shared.testBackgroundTick(code: code, language: self.descriptor.language)
        var lines: [String] = []
        if let err = res.error {
            lines.append("❌ ОШИБКА ФОНА: \(err)")
        } else {
            lines.append("⏱ Фоновый тик выполнен успешно")
            lines.append("→ Возврат: \(res.output.isEmpty ? "(nil)" : res.output)")
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
        if let pop = activity.popoverPresentationController {
            pop.sourceView = self.view
            pop.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 1.0, height: 1.0)
        }
        self.present(activity, animated: true)
    }

    private func saveTappedQuietly() {
        let code = self.codeTextView.text ?? ""
        self.descriptor = FullGramPluginManager.shared.savePlugin(
            id: self.isNew ? nil : self.descriptor.id,
            name: self.descriptor.name,
            language: self.descriptor.language,
            code: code,
            enabled: self.enableSwitch.isOn,
            backgroundEnabled: self.backgroundSwitch.isOn
        )
        self.isNew = false
        self.onChanged()
    }

    @objc private func deleteTapped() {
        FullGramPluginManager.shared.deletePlugin(id: self.descriptor.id)
        self.onChanged()
        self.onClose?()
    }
}

private final class FullGramPluginEditorContainerController: FullGramHostedViewController<FullGramPluginEditorViewController> {
    init(context: AccountContext, descriptor: FullGramPluginDescriptor, isNew: Bool, onChanged: @escaping () -> Void) {
        super.init(context: context, title: descriptor.name) { theme in
            FullGramPluginEditorViewController(theme: theme, descriptor: descriptor, isNew: isNew, onChanged: onChanged)
        }
        self.hosted.onClose = { [weak self] in
            self?.dismiss()
        }
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramPluginDocsEntry] = [
            .header(0, "ХУКИ ЖИЗНЕННОГО ЦИКЛА (API v2.0)"),
            .text(1, """
• on_command(ctx) — команды .команда и .plug подкоманда.
  Поля ctx: command, subcommand, args, text, peer_id, is_group, is_channel, chat_stats.
  Возврат: строка (замена текста), nil/None, { text = "..." } или { cancel = true, toast = "..." }.

• on_outgoing_message(ctx) — перехват исходящих сообщений (text, peer_id, is_group, is_channel).
• on_incoming_message(ctx) — фоновая обработка новых входящих сообщений (text, peer_id, sender_name, timestamp, is_group, is_channel, time).
• on_render_message(ctx) — модификация текста при рендере (text, peer_id, is_incoming, message_id).
• on_message_action(ctx) — действие в контекстном меню сообщения (text, peer_id).
• on_ui_event(ctx) — нажатие кнопки в open_ui (action, input).
• on_background_tick(ctx) / on_tick(ctx) — фоновый таймер плагина (требует @background true и @interval 30).
  Поля ctx: tick, interval, in_background, app_state, time, profile, device.
• on_app_state(ctx) — смена состояния приложения (state: "foreground" | "background", in_background, time).
• on_load() / on_unload() — запуск и выгрузка плагина.
"""),
            .header(100, "ПРОФИЛЬ И НИК TELEGRAM (fullgram.profile)"),
            .text(101, """
• fullgram.profile.get() / fullgram.get_profile() — таблица профиля: id, first_name, last_name, full_name, username, bio, phone, original_first_name, original_last_name.
• fullgram.profile.set_name(first, last?) / fullgram.set_nickname(first, last?) — смена отображаемого имени в Telegram (с авто-сохранением исходного ника и анти-флудом).
• fullgram.profile.restore_name() / fullgram.restore_nickname() — вернуть исходный ник.
• fullgram.profile.set_username(username) — сменить @username аккаунта.
• fullgram.profile.set_bio(bio) — сменить «О себе».
• fullgram.profile.format_nick(template, style?, base_first?) — подставить {time}, {time_sec}, {time_bold}, {time_mono}, {time_fancy}, {clock}, {date}, {weekday}, {battery}, {name}.
• fullgram.profile.apply_template(template?, style?) — отформатировать и сразу применить ник.
"""),
            .header(200, "ВРЕМЯ ТЕЛЕФОНА И УСТРОЙСТВО (fullgram.time, fullgram.device)"),
            .text(201, """
• fullgram.time.now() / fullgram.get_time() — timestamp, unix, unix_ms, hm, hms, formatted, date, iso, year, month, day, hour, minute, second, weekday, weekday_name, weekday_short, timezone, utc_offset, utc_offset_str, is_24h, bold_hm, mono_hm, double_hm, fancy_hm, clock_emoji.
• fullgram.time.format(fmt?, ts?, style?) — формат по DateFormatter + стиль цифр ("normal", "bold", "mono", "double", "sans", "circled").
• fullgram.time.stylize(text, style?) — стилизация цифр строки.
• fullgram.device.info() / fullgram.get_device_info() — model, system_name, system_version, battery_level, battery_state, is_charging, is_low_power, locale, timezone, app_state, is_background, uptime.
• fullgram.device.battery() / fullgram.device.haptic(style?).
"""),
            .header(300, "ФОНОВЫЙ РЕЖИМ, ЧАТЫ, ХРАНИЛИЩЕ И СЕТЬ"),
            .text(301, """
• fullgram.background.set_interval(sec) / stop_interval() / status() — управление фоновым циклом (5..3600 сек).
• fullgram.background.on(event, fn) / emit(event, data) — шина событий между плагинами.
• fullgram.chat.send(text, peer_id?) / set_draft(text) / active() / stats().
• fullgram.storage.get(k, def) / set(k, v) / delete(k) / keys() / clear() / shared_get(k, def) / shared_set(k, v).
• fullgram.net.get(url, headers?) / post(url, body?, headers?) / request(spec).
• fullgram.crypto.sha256(s) / base64_encode(s) / base64_decode(s) / url_encode(s) / uuid().
• fullgram.ui.toast(t) / alert(title, msg) / open(spec) / log(...) / clipboard_get() / clipboard_set(t).

Теги шапки: @name, @id, @version, @author, @description, @background true, @interval 30, @permission net.
Stdlib: Lua (os.time, os.date, os.clock, string, table, math, json), Python (time, datetime, re, json, math, random, fullgram), Rust (fullgram::*).
""")
        ]
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Plugin API v2.0"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, ()))
    }
    return ItemListController(context: context, state: signal)
}
