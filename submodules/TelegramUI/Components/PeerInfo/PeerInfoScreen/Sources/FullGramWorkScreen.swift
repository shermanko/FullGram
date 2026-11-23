import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

// MARK: - Для работы (Подтверждение важных чатов, Архивы ZIP/RAR, Документы, Переименование)

private enum FullGramWorkToggleOption: Int32 {
    case confirmEnabled = 1
    case confirmAllChats = 2
    case kindText = 3
    case kindVoice = 4
    case kindVideoNote = 5
    case kindVideo = 6
    case kindFile = 7
    case archivePreview = 8
    case docViewer = 9
    case renameFile = 10
}

private final class FullGramWorkArguments {
    let toggle: (FullGramWorkToggleOption, Bool) -> Void
    let addChat: () -> Void
    let removeChat: (Int64) -> Void
    let clearChats: () -> Void
    let openLocalFile: () -> Void

    init(
        toggle: @escaping (FullGramWorkToggleOption, Bool) -> Void,
        addChat: @escaping () -> Void,
        removeChat: @escaping (Int64) -> Void,
        clearChats: @escaping () -> Void,
        openLocalFile: @escaping () -> Void
    ) {
        self.toggle = toggle
        self.addChat = addChat
        self.removeChat = removeChat
        self.clearChats = clearChats
        self.openLocalFile = openLocalFile
    }
}

private enum FullGramWorkEntry: ItemListNodeEntry {
    case confirmHeader(String)
    case toggle(FullGramWorkToggleOption, String, Bool)
    case addChat(String)
    case chatPeer(Int32, Int64, String, String)
    case clearChats(String)
    case confirmInfo(String)

    case kindsHeader(String)
    case kindToggle(FullGramWorkToggleOption, String, Bool)
    case kindsInfo(String)

    case filesHeader(String)
    case fileToggle(FullGramWorkToggleOption, String, Bool)
    case openLocalFile(String)
    case filesInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .confirmHeader, .toggle, .addChat, .chatPeer, .clearChats, .confirmInfo:
            return 0
        case .kindsHeader, .kindToggle, .kindsInfo:
            return 1
        case .filesHeader, .fileToggle, .openLocalFile, .filesInfo:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .confirmHeader: return 0
        case let .toggle(opt, _, _): return opt.rawValue
        case .addChat: return 20
        case let .chatPeer(idx, _, _, _): return 100 + idx
        case .clearChats: return 400
        case .confirmInfo: return 401
        case .kindsHeader: return 500
        case let .kindToggle(opt, _, _): return 500 + opt.rawValue
        case .kindsInfo: return 550
        case .filesHeader: return 600
        case let .fileToggle(opt, _, _): return 600 + opt.rawValue
        case .openLocalFile: return 650
        case .filesInfo: return 651
        }
    }

    static func < (lhs: FullGramWorkEntry, rhs: FullGramWorkEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramWorkArguments
        switch self {
        case let .confirmHeader(text), let .kindsHeader(text), let .filesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(opt, title, value), let .kindToggle(opt, title, value), let .fileToggle(opt, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(opt, $0) })
        case let .addChat(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.addChat)
        case let .chatPeer(_, peerId, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: { args.removeChat(peerId) })
        case let .clearChats(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.clearChats)
        case let .openLocalFile(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.openLocalFile)
        case let .confirmInfo(text), let .kindsInfo(text), let .filesInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class FullGramWorkFilePickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let first = urls.first {
            self.onPick(first)
        }
    }
}

private var activeWorkFilePickerDelegate: FullGramWorkFilePickerDelegate?

public func fullGramWorkController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?

    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramWorkArguments(
        toggle: { opt, value in
            let e = FullGramExtras.shared
            switch opt {
            case .confirmEnabled: e.confirmSendBeforePosting = value
            case .confirmAllChats: e.confirmSendForAllChats = value
            case .kindText: e.confirmSendText = value
            case .kindVoice: e.confirmSendVoice = value
            case .kindVideoNote: e.confirmSendVideoNotes = value
            case .kindVideo: e.confirmSendVideo = value
            case .kindFile: e.confirmSendFiles = value
            case .archivePreview: e.archivePreviewWithoutDownload = value
            case .docViewer: e.builtInDocumentViewer = value
            case .renameFile: e.renameFileBeforeSend = value
            }
        },
        addChat: {
            let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.onlyWriteable, .excludeDisabled],
                hasChatListSelector: true,
                hasContactSelector: true,
                hasGlobalSearch: true,
                title: "Важный чат для подтверждения"
            ))
            selector.peerSelected = { [weak selector] peer, _ in
                FullGramExtras.shared.addConfirmSendChat(peer.id.toInt64())
                selector?.dismiss()
            }
            presentControllerImpl?(selector)
        },
        removeChat: { peerId in
            FullGramExtras.shared.removeConfirmSendChat(peerId)
        },
        clearChats: {
            FullGramExtras.shared.clearConfirmSendChats()
        },
        openLocalFile: {
            var types: [UTType] = [.pdf, .zip, .data, .item]
            if let rar = UTType(filenameExtension: "rar") { types.append(rar) }
            if let docx = UTType(filenameExtension: "docx") { types.append(docx) }
            if let xlsx = UTType(filenameExtension: "xlsx") { types.append(xlsx) }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            let delegate = FullGramWorkFilePickerDelegate { url in
                activeWorkFilePickerDelegate = nil
                let fileName = url.lastPathComponent
                if FullGramArchivePreviewController.isSupportedArchive(fileName: fileName, mimeType: "") {
                    pushImpl?(FullGramArchivePreviewController(fileURL: url, fileName: fileName))
                } else {
                    pushImpl?(FullGramDocumentViewerController(fileURL: url, fileName: fileName, canShare: true))
                }
            }
            activeWorkFilePickerDelegate = delegate
            picker.delegate = delegate
            presentNativeImpl?(picker)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> mapToSignal { presentationData, _ -> Signal<(PresentationData, [(Int64, String)]), NoError> in
        let peerIds = Array(FullGramExtras.shared.confirmSendPeerIds).sorted()
        if peerIds.isEmpty {
            return .single((presentationData, []))
        }
        return context.engine.data.get(
            EngineDataList(
                peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: EnginePeer.Id($0)) }
            )
        )
        |> map { peers -> (PresentationData, [(Int64, String)]) in
            var rows: [(Int64, String)] = []
            for (idx, rawId) in peerIds.enumerated() {
                let title = peers[idx]?.compactDisplayTitle ?? "Чат \(rawId)"
                rows.append((rawId, title))
            }
            return (presentationData, rows)
        }
    }
    |> deliverOnMainQueue
    |> map { presentationData, chatRows -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let e = FullGramExtras.shared
        var entries: [FullGramWorkEntry] = [
            .confirmHeader("ПОДТВЕРЖДЕНИЕ ДЛЯ ВАЖНЫХ ЧАТОВ"),
            .toggle(.confirmEnabled, "Запрос «Вы точно хотите отправить?»", e.confirmSendBeforePosting),
            .toggle(.confirmAllChats, "Спрашивать во всех чатах", e.confirmSendForAllChats),
            .addChat("Добавить важный чат…")
        ]
        for (idx, row) in chatRows.enumerated() {
            entries.append(.chatPeer(Int32(idx), row.0, row.1, "Убрать"))
        }
        if !chatRows.isEmpty {
            entries.append(.clearChats("Очистить список важных чатов"))
        }
        entries.append(.confirmInfo("Для выбранных чатов (или для всех) перед отправкой появится плашка подтверждения. Нажмите на чат в списке, чтобы убрать его."))

        entries.append(contentsOf: [
            .kindsHeader("ДЛЯ КАКИХ ТИПОВ ПОКАЗЫВАТЬ ПЛАШКУ"),
            .kindToggle(.kindText, "Текстовые сообщения", e.confirmSendText),
            .kindToggle(.kindVoice, "Голосовые сообщения", e.confirmSendVoice),
            .kindToggle(.kindVideoNote, "Видеокружки", e.confirmSendVideoNotes),
            .kindToggle(.kindVideo, "Фото и видео", e.confirmSendVideo),
            .kindToggle(.kindFile, "Файлы и документы", e.confirmSendFiles),
            .kindsInfo("Вы можете оставить подтверждение, например, только для текста или только для файлов."),

            .filesHeader("АРХИВЫ, ДОКУМЕНТЫ И ФАЙЛЫ"),
            .fileToggle(.archivePreview, "Предпросмотр архивов ZIP / RAR без скачивания", e.archivePreviewWithoutDownload),
            .fileToggle(.docViewer, "Просмотр документов (DOCX, XLSX, PDF)", e.builtInDocumentViewer),
            .fileToggle(.renameFile, "Переименование файла перед отправкой", e.renameFileBeforeSend),
            .openLocalFile("Открыть архив или документ с устройства…"),
            .filesInfo("ZIP и RAR открываются сразу по заголовкам без ожидания полной загрузки всего файла. DOCX, XLSX и PDF поддерживают поиск по тексту.")
        ])

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Для работы"),
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
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}

// MARK: - 10 Умных функций FullGram + Быстрые закладки

private enum FullGramSmartFeatureOption: Int32, CaseIterable {
    case focusMode = 1
    case cleanLinks = 2
    case disableSwipeBack = 3
    case autoLayoutFix = 4
    case turboVoiceSpeed = 5
    case charCounter = 6
    case smartTypography = 7
    case incognitoLinks = 8
    case confirmVideoCalls = 9
    case quickBookmarks = 10

    var title: String {
        switch self {
        case .focusMode: return "1. Режим фокуса (скрывать бейджи)"
        case .cleanLinks: return "2. Очистка ссылок от UTM-трекеров"
        case .disableSwipeBack: return "3. Защита от случайного свайпа назад"
        case .autoLayoutFix: return "4. Авто-раскладка (!! или .fix в сообщении)"
        case .turboVoiceSpeed: return "5. Турбо-ускорение голосовых (до 3×)"
        case .charCounter: return "6. Счётчик символов при наборе"
        case .smartTypography: return "7. Умная типографика (-- → —, ... → …)"
        case .incognitoLinks: return "8. Режим инкогнито для ссылок"
        case .confirmVideoCalls: return "9. Подтверждение видеозвонков и экрана"
        case .quickBookmarks: return "10. Быстрые локальные закладки"
        }
    }
}

private final class FullGramSmartFeaturesArguments {
    let toggle: (FullGramSmartFeatureOption, Bool) -> Void
    let openBookmarks: () -> Void
    init(toggle: @escaping (FullGramSmartFeatureOption, Bool) -> Void, openBookmarks: @escaping () -> Void) {
        self.toggle = toggle
        self.openBookmarks = openBookmarks
    }
}

private enum FullGramSmartFeaturesEntry: ItemListNodeEntry {
    case header(String)
    case toggle(FullGramSmartFeatureOption, Bool)
    case bookmarksLink(String, String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .bookmarksLink, .footer: return 1
        default: return 0
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .toggle(opt, _): return opt.rawValue
        case .bookmarksLink: return 50
        case .footer: return 51
        }
    }

    static func < (lhs: FullGramSmartFeaturesEntry, rhs: FullGramSmartFeaturesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramSmartFeaturesArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(opt, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: opt.title, value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(opt, $0) })
        case let .bookmarksLink(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openBookmarks)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramSmartFeaturesController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramSmartFeaturesArguments(
        toggle: { opt, value in
            let e = FullGramExtras.shared
            switch opt {
            case .focusMode: e.focusModeHideBadges = value
            case .cleanLinks: e.autoCleanCopiedLinks = value
            case .disableSwipeBack: e.disableEdgeSwipeBackInChat = value
            case .autoLayoutFix: e.autoLayoutFixCommand = value
            case .turboVoiceSpeed: e.turboVoiceSpeedEnabled = value
            case .charCounter: e.showComposeCharCounter = value
            case .smartTypography: e.smartTypographyEnabled = value
            case .incognitoLinks: e.incognitoLinkOpening = value
            case .confirmVideoCalls: e.confirmScreenShareAndVideoCalls = value
            case .quickBookmarks: e.quickBookmarksEnabled = value
            }
        },
        openBookmarks: {
            pushImpl?(fullGramBookmarksController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let e = FullGramExtras.shared
        let pairs: [(FullGramSmartFeatureOption, Bool)] = [
            (.focusMode, e.focusModeHideBadges),
            (.cleanLinks, e.autoCleanCopiedLinks),
            (.disableSwipeBack, e.disableEdgeSwipeBackInChat),
            (.autoLayoutFix, e.autoLayoutFixCommand),
            (.turboVoiceSpeed, e.turboVoiceSpeedEnabled),
            (.charCounter, e.showComposeCharCounter),
            (.smartTypography, e.smartTypographyEnabled),
            (.incognitoLinks, e.incognitoLinkOpening),
            (.confirmVideoCalls, e.confirmScreenShareAndVideoCalls),
            (.quickBookmarks, e.quickBookmarksEnabled)
        ]
        var entries: [FullGramSmartFeaturesEntry] = [.header("10 УМНЫХ ФУНКЦИЙ FULLGRAM")]
        for (opt, val) in pairs {
            entries.append(.toggle(opt, val))
        }
        entries.append(.bookmarksLink("Сохранённые закладки FullGram", "\(e.bookmarks.count)"))
        entries.append(.footer("• Авто-раскладка: начните сообщение с «!!» (например: !!ghbdtn) — текст автоматически переведётся перед отправкой.\n• Очистка ссылок удаляет utm_*, fbclid, gclid, yclid, si.\n• Умная типографика заменяет -- на тире —, <<>> на «», ... на …"))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Умные функции"),
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
    return controller
}

private final class FullGramBookmarksArguments {
    let addBookmark: () -> Void
    let tapBookmark: (FullGramExtras.FullGramBookmark) -> Void
    let clearAll: () -> Void
    init(
        addBookmark: @escaping () -> Void,
        tapBookmark: @escaping (FullGramExtras.FullGramBookmark) -> Void,
        clearAll: @escaping () -> Void
    ) {
        self.addBookmark = addBookmark
        self.tapBookmark = tapBookmark
        self.clearAll = clearAll
    }
}

private enum FullGramBookmarksEntry: ItemListNodeEntry {
    case add(String)
    case item(Int32, FullGramExtras.FullGramBookmark)
    case clear(String)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .add: return 0
        case .item, .empty: return 1
        case .clear: return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .add: return 0
        case let .item(idx, _): return 10 + idx
        case .empty: return 999
        case .clear: return 1000
        }
    }

    static func < (lhs: FullGramBookmarksEntry, rhs: FullGramBookmarksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramBookmarksArguments
        switch self {
        case let .add(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.addBookmark)
        case let .item(_, bm):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: bm.text, label: bm.peerTitle, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: { args.tapBookmark(bm) })
        case let .clear(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.clearAll)
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramBookmarksController(context: AccountContext) -> ViewController {
    var presentNativeImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramBookmarksArguments(
        addBookmark: {
            let alert = UIAlertController(title: "Новая закладка", message: "Введите заметку или важную фразу для быстрого доступа:", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = "Текст закладки…"
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
                let text = alert.textFields?.first?.text ?? ""
                FullGramExtras.shared.addBookmark(peerId: context.account.peerId.toInt64(), peerTitle: "Заметка", text: text)
            })
            presentNativeImpl?(alert)
        },
        tapBookmark: { bm in
            let sheet = UIAlertController(title: bm.peerTitle, message: bm.text, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Скопировать", style: .default) { _ in
                UIPasteboard.general.string = bm.text
            })
            sheet.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in
                FullGramExtras.shared.removeBookmark(id: bm.id)
            })
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        clearAll: {
            FullGramExtras.shared.clearBookmarks()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let list = FullGramExtras.shared.bookmarks
        var entries: [FullGramBookmarksEntry] = [.add("Добавить быструю заметку…")]
        if list.isEmpty {
            entries.append(.empty("Закладок пока нет. Вы можете сохранять заметки здесь или из меню сообщения."))
        } else {
            for (idx, bm) in list.enumerated() {
                entries.append(.item(Int32(idx), bm))
            }
            entries.append(.clear("Очистить все закладки"))
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Закладки FullGram"),
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
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}
