import Foundation
import UIKit
import UniformTypeIdentifiers
import AsyncDisplayKit
import Display
@preconcurrency import SwiftSignalKit
import TelegramCore
@preconcurrency import AccountContext
import ItemListUI
import PresentationDataUtils
import TelegramPresentationData

// MARK: - 2.1. Шрифты (локальные + пользовательские TTF/OTF + 50 шрифтов из GitHub-каталога FullGram)

private final class FullGramFontDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private var retainedSelf: FullGramFontDocumentPickerDelegate?
    private let onPick: (URL) -> Void

    init(onPick: @escaping (URL) -> Void) {
        self.onPick = onPick
        super.init()
        self.retainedSelf = self
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.retainedSelf = nil
        if let url = urls.first {
            self.onPick(url)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.retainedSelf = nil
    }
}

private final class FullGramFontDownloadState: @unchecked Sendable {
    var downloadingId: String?
    var lastError: String?
    var presentNative: ((UIViewController) -> Void)?
    var onChanged: (() -> Void)?
}

private struct FullGramFontsArguments {
    let select: (FullGramFonts.Option) -> Void
    let uploadCustom: () -> Void
    let manageCustom: (FullGramFonts.Option) -> Void
    let clearCache: () -> Void
}

private enum FullGramFontsEntry: ItemListNodeEntry {
    case customHeader(String)
    case uploadCustomAction(String)
    case customFont(Int32, FullGramFonts.Option, Bool)
    case builtInHeader(String)
    case builtInFont(Int32, FullGramFonts.Option, Bool)
    case remoteHeader(String)
    case remoteFont(Int32, FullGramFonts.Option, String, Bool)
    case cacheHeader(String)
    case clearCache(String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .customHeader, .uploadCustomAction, .customFont:
            return 0
        case .builtInHeader, .builtInFont:
            return 1
        case .remoteHeader, .remoteFont:
            return 2
        case .cacheHeader, .clearCache, .info:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .customHeader: return 0
        case .uploadCustomAction: return 1
        case let .customFont(idx, _, _): return 2 + idx
        case .builtInHeader: return 100
        case let .builtInFont(idx, _, _): return 101 + idx
        case .remoteHeader: return 200
        case let .remoteFont(idx, _, _, _): return 201 + idx
        case .cacheHeader: return 500
        case .clearCache: return 501
        case .info: return 502
        }
    }

    static func ==(lhs: FullGramFontsEntry, rhs: FullGramFontsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.customHeader(a), .customHeader(b)): return a == b
        case let (.uploadCustomAction(a), .uploadCustomAction(b)): return a == b
        case let (.customFont(ai, ao, ac), .customFont(bi, bo, bc)): return ai == bi && ao.id == bo.id && ac == bc
        case let (.builtInHeader(a), .builtInHeader(b)): return a == b
        case let (.builtInFont(ai, ao, ac), .builtInFont(bi, bo, bc)): return ai == bi && ao.id == bo.id && ac == bc
        case let (.remoteHeader(a), .remoteHeader(b)): return a == b
        case let (.remoteFont(ai, ao, asub, ac), .remoteFont(bi, bo, bsub, bc)): return ai == bi && ao.id == bo.id && asub == bsub && ac == bc
        case let (.cacheHeader(a), .cacheHeader(b)): return a == b
        case let (.clearCache(a), .clearCache(b)): return a == b
        case let (.info(a), .info(b)): return a == b
        default: return false
        }
    }

    static func <(lhs: FullGramFontsEntry, rhs: FullGramFontsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramFontsArguments
        switch self {
        case let .customHeader(text), let .builtInHeader(text), let .remoteHeader(text), let .cacheHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .uploadCustomAction(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: args.uploadCustom
            )
        case let .customFont(_, option, selected):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: option.title,
                label: selected ? "✓ Активен" : "Применить",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    args.manageCustom(option)
                }
            )
        case let .builtInFont(_, option, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: option.title,
                style: .right,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.select(option)
                }
            )
        case let .remoteFont(_, option, statusLabel, selected):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: option.title,
                label: selected ? "✓ Выбран" : statusLabel,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: selected ? .none : .arrow,
                action: {
                    args.select(option)
                }
            )
        case let .clearCache(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: args.clearCache
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramFontsController(context: AccountContext) -> ViewController {
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let dlState = FullGramFontDownloadState()

    let bump: () -> Void = {
        changed.set(version.modify { $0 + 1 })
    }
    dlState.onChanged = bump

    let observer = NotificationCenter.default.addObserver(forName: FullGramFonts.didChangeNotification, object: nil, queue: .main) { _ in
        bump()
    }

    let args = FullGramFontsArguments(
        select: { option in
            if !option.isRemote || FullGramFonts.isDownloaded(option) {
                FullGramFonts.selectAndRestart(optionId: option.id)
                return
            }
            guard dlState.downloadingId == nil else { return }
            dlState.downloadingId = option.id
            dlState.lastError = nil
            bump()
            FullGramFonts.downloadAndSelect(option: option) { result in
                Task { @MainActor in
                    dlState.downloadingId = nil
                    switch result {
                    case .success:
                        dlState.lastError = nil
                        dlState.onChanged?()
                    case let .failure(error):
                        dlState.lastError = error.localizedDescription
                        dlState.onChanged?()
                        let alert = UIAlertController(title: "Ошибка загрузки шрифта", message: error.localizedDescription, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        dlState.presentNative?(alert)
                    }
                }
            }
        },
        uploadCustom: {
            let types: [UTType]
            if #available(iOS 14.0, *) {
                var list: [UTType] = [.font]
                if let ttf = UTType(filenameExtension: "ttf") { list.append(ttf) }
                if let otf = UTType(filenameExtension: "otf") { list.append(otf) }
                types = list
            } else {
                types = []
            }
            let delegate = FullGramFontDocumentPickerDelegate { url in
                let result = FullGramFonts.importCustomFont(from: url)
                switch result {
                case let .success(option):
                    FullGramFonts.selectAndRestart(optionId: option.id)
                case let .failure(err):
                    let alert = UIAlertController(title: "Не удалось загрузить шрифт", message: err.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    dlState.presentNative?(alert)
                }
            }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.allowsMultipleSelection = false
            picker.delegate = delegate
            dlState.presentNative?(picker)
        },
        manageCustom: { option in
            let sheet = UIAlertController(title: option.title, message: option.postScriptName ?? option.subtitle, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Применить и перезагрузить", style: .default, handler: { _ in
                FullGramFonts.selectAndRestart(optionId: option.id)
            }))
            sheet.addAction(UIAlertAction(title: "Удалить шрифт", style: .destructive, handler: { _ in
                FullGramFonts.deleteCustomFont(id: option.id)
                bump()
            }))
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            dlState.presentNative?(sheet)
        },
        clearCache: {
            FullGramFonts.clearDownloadedCache()
            bump()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let selected = FullGramFonts.selectedId
        let customList = FullGramFonts.customOptions
        var entries: [FullGramFontsEntry] = [
            .customHeader("МОИ ШРИФТЫ (.TTF / .OTF)"),
            .uploadCustomAction("Загрузить шрифт с устройства (.ttf / .otf)…")
        ]
        for (index, option) in customList.enumerated() {
            entries.append(.customFont(Int32(index), option, option.id == selected))
        }
        entries.append(.builtInHeader("ВСТРОЕННЫЕ И СИСТЕМНЫЕ (\(FullGramFonts.builtInOptions.count))"))
        for (index, option) in FullGramFonts.builtInOptions.enumerated() {
            entries.append(.builtInFont(Int32(index), option, option.id == selected))
        }
        entries.append(.remoteHeader("КАТАЛОГ GITHUB (\(FullGramFonts.remoteOptions.count) ШРИФТОВ)"))
        for (index, option) in FullGramFonts.remoteOptions.enumerated() {
            let status: String
            if dlState.downloadingId == option.id {
                status = "Загрузка…"
            } else if FullGramFonts.isDownloaded(option) {
                status = "Загружен"
            } else {
                let kb = max(1, option.sizeBytes / 1024)
                status = "↓ \(kb) КБ"
            }
            entries.append(.remoteFont(Int32(index), option, status, option.id == selected))
        }
        let downloadedCount = FullGramFonts.remoteOptions.filter { FullGramFonts.isDownloaded($0) }.count
        entries.append(.cacheHeader("КЭШ ШРИФТОВ"))
        if downloadedCount > 0 {
            entries.append(.clearCache("Удалить скачанные шрифты (\(downloadedCount))"))
        }
        let note = "После выбора любого шрифта (включая свой .ttf/.otf или сброс на системный) интерфейс FullGram автоматически перезагружается."
        entries.append(.info(note))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Шрифты"),
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
    dlState.presentNative = { vc in
        context.sharedContext.applicationBindings.presentNativeController(vc)
    }
    return controller
}

// MARK: - 2.2. Темы (без вложенных мини-вкладок, + OLED режим, + Красная/Золотая, + Своя тема с предпросмотром)

private final class FullGramThemePreviewItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let sectionId: ItemListSectionId
    let revision: Int

    init(theme: PresentationTheme, sectionId: ItemListSectionId, revision: Int) {
        self.theme = theme
        self.sectionId = sectionId
        self.revision = revision
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = FullGramThemePreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, neighbors.previous == nil, neighbors.next == nil)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            completion(node, { (nil, { _ in apply() }) })
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FullGramThemePreviewItemNode {
                let (layout, apply) = nodeValue.asyncLayout()(self, params, neighbors.previous == nil, neighbors.next == nil)
                completion(layout, { _ in apply() })
            }
        }
    }

    var selectable: Bool { return false }
}

private final class FullGramThemePreviewItemNode: ListViewItemNode {
    private let cardView = UIView()
    private let gradientLayer = CAGradientLayer()
    private let headerLabel = UILabel()
    private let incomingBubble = UIView()
    private let incomingLabel = UILabel()
    private let outgoingBubble = UIView()
    private let outgoingLabel = UILabel()
    private let accentPill = UIView()
    private let accentLabel = UILabel()
    private var didAttachCard = false

    init() {
        super.init(layerBacked: false)
        self.cardView.layer.cornerRadius = 16.0
        self.cardView.clipsToBounds = true
        self.cardView.layer.insertSublayer(self.gradientLayer, at: 0)

        self.headerLabel.font = Font.semibold(14.0)
        self.headerLabel.text = "Предпросмотр темы"

        self.incomingBubble.layer.cornerRadius = 14.0
        self.incomingLabel.font = Font.regular(15.0)
        self.incomingLabel.text = "Привет! Как выглядит новая тема?"
        self.incomingLabel.numberOfLines = 0
        self.incomingBubble.addSubview(self.incomingLabel)

        self.outgoingBubble.layer.cornerRadius = 14.0
        self.outgoingLabel.font = Font.regular(15.0)
        self.outgoingLabel.text = "Отлично, цвета сразу видны здесь!"
        self.outgoingLabel.numberOfLines = 0
        self.outgoingBubble.addSubview(self.outgoingLabel)

        self.accentPill.layer.cornerRadius = 10.0
        self.accentLabel.font = Font.semibold(12.0)
        self.accentLabel.text = "Акцент"
        self.accentLabel.textColor = .white
        self.accentPill.addSubview(self.accentLabel)

        self.cardView.addSubview(self.headerLabel)
        self.cardView.addSubview(self.incomingBubble)
        self.cardView.addSubview(self.outgoingBubble)
        self.cardView.addSubview(self.accentPill)
    }

    override func didLoad() {
        super.didLoad()
        if !self.didAttachCard {
            self.didAttachCard = true
            self.view.addSubview(self.cardView)
        }
    }

    func asyncLayout() -> (FullGramThemePreviewItem, ListViewItemLayoutParams, Bool, Bool) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params, _, _ in
            let height: CGFloat = 176.0
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height), insets: UIEdgeInsets(top: 6.0, left: 0.0, bottom: 6.0, right: 0.0))
            let apply: () -> Void = {
                guard let self else { return }
                let inset: CGFloat = params.leftInset + 16.0
                let cardWidth = max(100.0, params.width - inset * 2.0)
                let cardFrame = CGRect(x: inset, y: 6.0, width: cardWidth, height: height - 12.0)
                self.cardView.frame = cardFrame
                self.gradientLayer.frame = self.cardView.bounds

                let wp1 = FullGramThemeColors.color(.wallpaper) ?? item.theme.chatList.backgroundColor
                let wp2 = FullGramThemeColors.color(.wallpaperSecond) ?? wp1
                self.gradientLayer.colors = [wp1.cgColor, wp2.cgColor]
                self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
                self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)

                let accent = FullGramThemeColors.color(.accent) ?? item.theme.list.itemAccentColor
                let titleColor = FullGramThemeColors.color(.chatTitle) ?? item.theme.chatList.titleColor
                self.headerLabel.textColor = titleColor
                self.headerLabel.frame = CGRect(x: 14.0, y: 12.0, width: cardWidth - 100.0, height: 20.0)

                self.accentPill.backgroundColor = accent
                self.accentPill.frame = CGRect(x: cardWidth - 78.0, y: 10.0, width: 64.0, height: 24.0)
                self.accentLabel.frame = self.accentPill.bounds
                self.accentLabel.textAlignment = .center

                let inFill = FullGramThemeColors.color(.incomingBubble) ?? item.theme.chat.message.incoming.bubble.withWallpaper.fill.first ?? item.theme.list.itemBlocksBackgroundColor
                let inText = FullGramThemeColors.color(.incomingText) ?? item.theme.chat.message.incoming.primaryTextColor
                self.incomingBubble.backgroundColor = inFill
                self.incomingLabel.textColor = inText
                let inWidth = min(cardWidth - 48.0, 240.0)
                self.incomingBubble.frame = CGRect(x: 14.0, y: 44.0, width: inWidth, height: 48.0)
                self.incomingLabel.frame = self.incomingBubble.bounds.insetBy(dx: 12.0, dy: 6.0)

                let outFill = FullGramThemeColors.color(.outgoingBubble) ?? item.theme.chat.message.outgoing.bubble.withWallpaper.fill.first ?? accent
                let outText = FullGramThemeColors.color(.outgoingText) ?? item.theme.chat.message.outgoing.primaryTextColor
                self.outgoingBubble.backgroundColor = outFill
                self.outgoingLabel.textColor = outText
                let outWidth = min(cardWidth - 48.0, 240.0)
                self.outgoingBubble.frame = CGRect(x: cardWidth - outWidth - 14.0, y: 102.0, width: outWidth, height: 48.0)
                self.outgoingLabel.frame = self.outgoingBubble.bounds.insetBy(dx: 12.0, dy: 6.0)
            }
            return (layout, apply)
        }
    }
}

private struct FullGramThemesArguments {
    let toggleOled: (Bool) -> Void
    let applyPreset: (FullGramThemeColors.Preset) -> Void
    let pickColor: (FullGramThemeColors.Slot) -> Void
    let reset: () -> Void
}

private enum FullGramThemesEntry: ItemListNodeEntry {
    case oledToggle(Bool)
    case oledInfo(String)
    case preview(PresentationTheme, Int)
    case presetsHeader(String)
    case preset(Int32, FullGramThemeColors.Preset, Bool)
    case customHeader(String)
    case colorSlot(Int32, FullGramThemeColors.Slot, String?)
    case resetAction(String)

    var section: ItemListSectionId {
        switch self {
        case .oledToggle, .oledInfo: return 0
        case .preview: return 1
        case .presetsHeader, .preset: return 2
        case .customHeader, .colorSlot, .resetAction: return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .oledToggle: return 0
        case .oledInfo: return 1
        case .preview: return 10
        case .presetsHeader: return 20
        case let .preset(idx, _, _): return 21 + idx
        case .customHeader: return 100
        case let .colorSlot(idx, _, _): return 101 + idx
        case .resetAction: return 200
        }
    }

    static func ==(lhs: FullGramThemesEntry, rhs: FullGramThemesEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.oledToggle(a), .oledToggle(b)): return a == b
        case let (.oledInfo(a), .oledInfo(b)): return a == b
        case let (.preview(at, ar), .preview(bt, br)): return at === bt && ar == br
        case let (.presetsHeader(a), .presetsHeader(b)): return a == b
        case let (.preset(ai, ap, ac), .preset(bi, bp, bc)): return ai == bi && ap.id == bp.id && ac == bc
        case let (.customHeader(a), .customHeader(b)): return a == b
        case let (.colorSlot(ai, aslot, ahex), .colorSlot(bi, bslot, bhex)): return ai == bi && aslot == bslot && ahex == bhex
        case let (.resetAction(a), .resetAction(b)): return a == b
        default: return false
        }
    }

    static func <(lhs: FullGramThemesEntry, rhs: FullGramThemesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramThemesArguments
        switch self {
        case let .oledToggle(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "OLED режим",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleOled
            )
        case let .oledInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .preview(theme, rev):
            return FullGramThemePreviewItem(theme: theme, sectionId: self.section, revision: rev)
        case let .presetsHeader(text), let .customHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .preset(_, preset, checked):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: preset.title,
                style: .right,
                checked: checked,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.applyPreset(preset)
                }
            )
        case let .colorSlot(_, slot, hex):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: slot.titleRu,
                label: hex ?? "По умолчанию",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    args.pickColor(slot)
                }
            )
        case let .resetAction(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: args.reset
            )
        }
    }
}

private final class FullGramColorPickerDelegate: NSObject, UIColorPickerViewControllerDelegate {
    private let onColor: (String) -> Void
    private var retainedSelf: FullGramColorPickerDelegate?

    init(onColor: @escaping (String) -> Void) {
        self.onColor = onColor
        super.init()
        self.retainedSelf = self
    }

    @available(iOS 14.0, *)
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        self.onColor(Self.hexString(from: viewController.selectedColor))
    }

    @available(iOS 14.0, *)
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        self.retainedSelf = nil
    }

    private static func hexString(from color: UIColor) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((max(0.0, min(1.0, r)) * 255.0).rounded())
        let gi = Int((max(0.0, min(1.0, g)) * 255.0).rounded())
        let bi = Int((max(0.0, min(1.0, b)) * 255.0).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

func fullGramThemesController(context: AccountContext) -> ViewController {
    var presentNativeImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let obs1 = NotificationCenter.default.addObserver(forName: FullGramThemeColors.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }
    let obs2 = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramThemesArguments(
        toggleOled: { value in
            FullGramExtras.shared.oledMode = value
        },
        applyPreset: { preset in
            FullGramThemeColors.apply(preset)
        },
        pickColor: { slot in
            let sheet = UIAlertController(title: slot.titleRu, message: "Выберите цвет из палитры или введите HEX (#RRGGBB)", preferredStyle: .actionSheet)
            if #available(iOS 14.0, *) {
                sheet.addAction(UIAlertAction(title: "Палитра цветов", style: .default, handler: { _ in
                    let picker = UIColorPickerViewController()
                    picker.supportsAlpha = false
                    picker.selectedColor = FullGramThemeColors.color(slot) ?? .systemBlue
                    let delegate = FullGramColorPickerDelegate { hex in
                        FullGramThemeColors.markCustom()
                        FullGramThemeColors.set(slot, hex: hex)
                    }
                    picker.delegate = delegate
                    presentNativeImpl?(picker)
                }))
            }
            sheet.addAction(UIAlertAction(title: "Ввести HEX-код", style: .default, handler: { _ in
                let alert = UIAlertController(title: slot.titleRu, message: "Введите цвет в формате #RRGGBB", preferredStyle: .alert)
                alert.addTextField { tf in
                    tf.placeholder = "#0A84FF"
                    tf.text = FullGramThemeColors.hex(slot)
                    tf.autocapitalizationType = .allCharacters
                    tf.autocorrectionType = .no
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Применить", style: .default, handler: { [weak alert] _ in
                    let text = alert?.textFields?.first?.text ?? ""
                    if FullGramThemeColors.parse(text) != nil {
                        FullGramThemeColors.markCustom()
                        FullGramThemeColors.set(slot, hex: text)
                    }
                }))
                presentNativeImpl?(alert)
            }))
            if FullGramThemeColors.hex(slot) != nil {
                sheet.addAction(UIAlertAction(title: "Сбросить этот цвет", style: .destructive, handler: { _ in
                    FullGramThemeColors.markCustom()
                    FullGramThemeColors.set(slot, hex: nil)
                }))
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        reset: {
            FullGramThemeColors.reset()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramThemesEntry] = [
            .oledToggle(FullGramExtras.shared.oledMode),
            .oledInfo("Чисто чёрный фон для экранов с OLED-матрицей."),
            .preview(presentationData.theme, FullGramThemeColors.revision),
            .presetsHeader("ТЕМЫ")
        ]
        let selectedPresetId = FullGramThemeColors.selectedPresetId
        for (index, preset) in FullGramThemeColors.presets.enumerated() {
            entries.append(.preset(Int32(index), preset, selectedPresetId == preset.id))
        }
        entries.append(.customHeader("СОЗДАНИЕ СВОЕЙ ТЕМЫ"))
        for (index, slot) in FullGramThemeColors.Slot.allCases.enumerated() {
            entries.append(.colorSlot(Int32(index), slot, FullGramThemeColors.hex(slot)))
        }
        if FullGramThemeColors.hasColors {
            entries.append(.resetAction("Сбросить цвета темы"))
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Темы"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(obs1)
        NotificationCenter.default.removeObserver(obs2)
    }

    let controller = ItemListController(context: context, state: signal)
    presentNativeImpl = { vc in
        context.sharedContext.applicationBindings.presentNativeController(vc)
    }
    return controller
}

// MARK: - 2.3. Дизайн

private enum FullGramDesignToggle: Int32 {
    case classicDesign = 1
    case removeGlass = 2
    case glowingReactions = 3
    case profileNFTBubbles = 4
}

private struct FullGramDesignArguments {
    let toggle: (FullGramDesignToggle, Bool) -> Void
    let pickGlassColor: () -> Void
    let pickSlowMotion: () -> Void
    let openDebugSettings: () -> Void
}

private enum FullGramDesignEntry: ItemListNodeEntry {
    case header(String)
    case toggle(FullGramDesignToggle, String, Bool)
    case flatColor(String, String)
    case slowMotion(String, String)
    case debugSettings(String)
    case info(String)

    var section: ItemListSectionId { return 0 }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .toggle(opt, _, _):
            switch opt {
            case .profileNFTBubbles: return 1
            case .removeGlass: return 2
            case .classicDesign: return 4
            case .glowingReactions: return 5
            }
        case .flatColor: return 3
        case .slowMotion: return 20
        case .debugSettings: return 25
        case .info: return 30
        }
    }

    static func ==(lhs: FullGramDesignEntry, rhs: FullGramDesignEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a), .header(b)): return a == b
        case let (.toggle(ao, at, av), .toggle(bo, bt, bv)): return ao == bo && at == bt && av == bv
        case let (.flatColor(at, al), .flatColor(bt, bl)): return at == bt && al == bl
        case let (.slowMotion(at, al), .slowMotion(bt, bl)): return at == bt && al == bl
        case let (.debugSettings(a), .debugSettings(b)): return a == b
        case let (.info(a), .info(b)): return a == b
        default: return false
        }
    }

    static func <(lhs: FullGramDesignEntry, rhs: FullGramDesignEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramDesignArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(opt, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { args.toggle(opt, $0) }
            )
        case let .flatColor(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.pickGlassColor
            )
        case let .slowMotion(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.pickSlowMotion
            )
        case let .debugSettings(title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "Открыть",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.openDebugSettings
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramDesignController(context: AccountContext) -> ViewController {
    FullGramDesignWatchdog.markUIVerified()
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramDesignArguments(
        toggle: { opt, value in
            switch opt {
            case .classicDesign:
                FullGramExtras.shared.classicDesign = value
            case .removeGlass:
                FullGramExtras.shared.removeGlass = value
            case .glowingReactions:
                FullGramExtras.shared.glowingReactions = value
            case .profileNFTBubbles:
                FullGramExtras.shared.profileNFTBubbles = value
            }
        },
        pickGlassColor: {
            let sheet = UIAlertController(title: "Цвет заливки вместо стекла", message: "Выберите сплошной цвет для панелей, вкладок и кнопок", preferredStyle: .actionSheet)
            if #available(iOS 14.0, *) {
                sheet.addAction(UIAlertAction(title: "Палитра цветов", style: .default, handler: { _ in
                    let picker = UIColorPickerViewController()
                    picker.supportsAlpha = false
                    if let hex = FullGramExtras.shared.removeGlassColorHex, let rgb = FullGramThemeColors.parse(hex) {
                        picker.selectedColor = UIColor(rgb: rgb)
                    } else {
                        picker.selectedColor = context.sharedContext.currentPresentationData.with { $0 }.theme.list.itemBlocksBackgroundColor
                    }
                    let delegate = FullGramColorPickerDelegate { hex in
                        FullGramExtras.shared.removeGlassColorHex = hex
                        if !FullGramExtras.shared.removeGlass {
                            FullGramExtras.shared.removeGlass = true
                        }
                    }
                    picker.delegate = delegate
                    presentNativeImpl?(picker)
                }))
            }
            sheet.addAction(UIAlertAction(title: "Ввести HEX-код", style: .default, handler: { _ in
                let alert = UIAlertController(title: "Цвет заливки", message: "Введите цвет в формате #RRGGBB", preferredStyle: .alert)
                alert.addTextField { tf in
                    tf.placeholder = "#1C1C1E"
                    tf.text = FullGramExtras.shared.removeGlassColorHex
                    tf.autocapitalizationType = .allCharacters
                    tf.autocorrectionType = .no
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Применить", style: .default, handler: { [weak alert] _ in
                    let text = alert?.textFields?.first?.text ?? ""
                    if let parsed = FullGramThemeColors.parse(text) {
                        FullGramExtras.shared.removeGlassColorHex = String(format: "#%06X", parsed)
                        if !FullGramExtras.shared.removeGlass {
                            FullGramExtras.shared.removeGlass = true
                        }
                    }
                }))
                presentNativeImpl?(alert)
            }))
            if FullGramExtras.shared.removeGlassColorHex != nil {
                sheet.addAction(UIAlertAction(title: "Авто (цвет темы)", style: .destructive, handler: { _ in
                    FullGramExtras.shared.removeGlassColorHex = nil
                }))
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        pickSlowMotion: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            let items: [ActionSheetItem] = FullGramAnimationSpeed.steps.map { step in
                let label = step == 1.0 ? "Выкл. (1×)" : "\(Int(step))×"
                return ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    FullGramAnimationSpeed.factor = step
                    changed.set(version.modify { $0 + 1 })
                })
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: "Отмена", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        openDebugSettings: {
            if let debugVC = context.sharedContext.makeDebugSettingsController(context: context) {
                pushImpl?(debugVC)
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let factor = FullGramAnimationSpeed.factor
        let slowLabel = factor <= 1.0 ? "Выкл." : "\(Int(factor))×"
        let glassColorLabel = FullGramExtras.shared.removeGlassColorHex ?? "Авто"
        var entries: [FullGramDesignEntry] = [
            .header("ДИЗАЙН"),
            .toggle(.profileNFTBubbles, "Пузыри NFT в профиле (Profile V2)", FullGramExtras.shared.profileNFTBubbles),
            .toggle(.removeGlass, "Удаление стекла", FullGramExtras.shared.removeGlass),
            .flatColor("Цвет заливки вместо стекла", glassColorLabel)
        ]
        if FullGramFeatureFlags.isEnabled(.classicDesign) {
            entries.append(.toggle(.classicDesign, "Старый дизайн Telegram", FullGramExtras.shared.classicDesign))
        }
        entries.append(.toggle(.glowingReactions, "Светящиеся реакции", FullGramExtras.shared.glowingReactions))
        entries.append(.slowMotion("Замедление анимаций", slowLabel))
        entries.append(.debugSettings("Спец. настройки (Debug / Profile V2)"))
        var infoNote = "«Пузыри NFT в профиле» включает отображение коллекционных NFT в круглых пузырях вокруг аватара (Profile V2).\n\n«Удаление стекла» полностью убирает эффект жидкого стекла и заливает панели выбранным сплошным цветом. Изменения интерфейса вступают в силу после перезапуска."
        if FullGramDesignWatchdog.didAutoRollback {
            infoNote += "\n\nЗащита интерфейса автоматически вернула стандартный дизайн после сбоя предыдущего запуска."
        } else if !FullGramFeatureFlags.isEnabled(.classicDesign) {
            infoNote += "\n\nПереключатель «Старый дизайн Telegram» временно скрыт для стабильности интерфейса."
        }
        entries.append(.info(infoNote))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Дизайн"),
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
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentNativeImpl = { vc in
        context.sharedContext.applicationBindings.presentNativeController(vc)
    }
    return controller
}

// MARK: - 2.4. Иконки приложения («Монохромные иконки» + вкладка «Кастомные иконки» (заглушка))

private struct FullGramIconPreset {
    let iconName: String?
    let title: String
    let isMonochrome: Bool
    let previewResource: String?
}

private let fullGramStandardIcons: [FullGramIconPreset] = [
    FullGramIconPreset(iconName: nil, title: "Стандартная (FullGram)", isMonochrome: false, previewResource: "FullGramIcon_FullGramDefault"),
    FullGramIconPreset(iconName: "BlueClassicIcon", title: "Классическая синяя", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "BlueFilledIcon", title: "Синяя заливка", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "WhiteFilledIcon", title: "Белая (монохромная)", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "New1", title: "Ночь", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "New2", title: "Рассвет", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "Premium", title: "Премиум", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "PremiumTurbo", title: "Премиум турбо", isMonochrome: false, previewResource: nil)
]

private let fullGramCustomIcons: [FullGramIconPreset] = [
    FullGramIconPreset(iconName: "FullGramDefault", title: "FullGram Белая", isMonochrome: false, previewResource: "FullGramIcon_FullGramDefault"),
    FullGramIconPreset(iconName: "FullGramRed", title: "FullGram Красная", isMonochrome: false, previewResource: "FullGramIcon_FullGramRed"),
    FullGramIconPreset(iconName: "FullGramOrange", title: "FullGram Оранжевая", isMonochrome: false, previewResource: "FullGramIcon_FullGramOrange"),
    FullGramIconPreset(iconName: "FullGramCyan", title: "FullGram Неон", isMonochrome: false, previewResource: "FullGramIcon_FullGramCyan"),
    FullGramIconPreset(iconName: "FullGramPurple", title: "FullGram Розовая", isMonochrome: false, previewResource: "FullGramIcon_FullGramPurple"),
    FullGramIconPreset(iconName: "FullGramGold", title: "FullGram Жёлтая", isMonochrome: false, previewResource: "FullGramIcon_FullGramGold"),
    FullGramIconPreset(iconName: "FullGramEmerald", title: "FullGram Зелёная", isMonochrome: false, previewResource: "FullGramIcon_FullGramEmerald"),
    FullGramIconPreset(iconName: "FullGramSakura", title: "FullGram Сакура", isMonochrome: false, previewResource: "FullGramIcon_FullGramSakura"),
    FullGramIconPreset(iconName: "FullGramArctic", title: "FullGram Синяя", isMonochrome: false, previewResource: "FullGramIcon_FullGramArctic"),
    FullGramIconPreset(iconName: "FullGramVapor", title: "FullGram Вапор", isMonochrome: false, previewResource: "FullGramIcon_FullGramVapor"),
    FullGramIconPreset(iconName: "FullGramMidnight", title: "FullGram Индиго", isMonochrome: true, previewResource: "FullGramIcon_FullGramMidnight"),
    FullGramIconPreset(iconName: "FullGramSunset", title: "FullGram Закат", isMonochrome: false, previewResource: "FullGramIcon_FullGramSunset"),
    FullGramIconPreset(iconName: "FullGramHolo", title: "FullGram Голограмма", isMonochrome: false, previewResource: "FullGramIcon_FullGramHolo"),
    FullGramIconPreset(iconName: "FullGramMascot", title: "Mascot Classic", isMonochrome: false, previewResource: "FullGramIcon_FullGramMascot"),
    FullGramIconPreset(iconName: "FullGramMascotNeon", title: "Mascot Cyber", isMonochrome: false, previewResource: "FullGramIcon_FullGramMascotNeon"),
    FullGramIconPreset(iconName: "FullGramMascotGold", title: "Mascot Royal", isMonochrome: false, previewResource: "FullGramIcon_FullGramMascotGold"),
    FullGramIconPreset(iconName: "FullGramObsidian", title: "FullGram Обсидиан", isMonochrome: true, previewResource: "FullGramIcon_FullGramObsidian"),
    FullGramIconPreset(iconName: "FullGramAurora", title: "FullGram Аврора", isMonochrome: false, previewResource: "FullGramIcon_FullGramAurora"),
    FullGramIconPreset(iconName: "FullGramCrimson", title: "FullGram Рубин", isMonochrome: false, previewResource: "FullGramIcon_FullGramCrimson"),
    FullGramIconPreset(iconName: "FullGramMint", title: "FullGram Мята", isMonochrome: false, previewResource: "FullGramIcon_FullGramMint"),
    FullGramIconPreset(iconName: "FullGramPlasma", title: "FullGram Плазма", isMonochrome: false, previewResource: "FullGramIcon_FullGramPlasma")
]

private let fullGramIconPreviewCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 48
    return cache
}()

private func fullGramIconPreviewImage(_ resource: String?) -> UIImage? {
    guard let resource else { return nil }
    if let cached = fullGramIconPreviewCache.object(forKey: resource as NSString) {
        return cached
    }
    guard let path = Bundle.main.path(forResource: resource, ofType: "png"),
          let raw = UIImage(contentsOfFile: path) else {
        return nil
    }
    let size = CGSize(width: 29.0, height: 29.0)
    let rendered = UIGraphicsImageRenderer(size: size).image { _ in
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7.0).addClip()
        raw.draw(in: CGRect(origin: .zero, size: size))
    }.withRenderingMode(.alwaysOriginal)
    fullGramIconPreviewCache.setObject(rendered, forKey: resource as NSString)
    return rendered
}

private struct FullGramIconsArguments {
    let toggleMonochrome: (Bool) -> Void
    let switchTab: (Int) -> Void
    let selectIcon: (String?) -> Void
}

private enum FullGramIconsEntry: ItemListNodeEntry {
    case monochromeToggle(Bool)
    case tabSelector(Int)
    case iconRow(Int32, FullGramIconPreset, Bool)
    case customStub(String)

    var section: ItemListSectionId {
        switch self {
        case .monochromeToggle: return 0
        case .tabSelector, .iconRow, .customStub: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .monochromeToggle: return 0
        case .tabSelector: return 10
        case let .iconRow(idx, _, _): return 20 + idx
        case .customStub: return 100
        }
    }

    static func ==(lhs: FullGramIconsEntry, rhs: FullGramIconsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.monochromeToggle(a), .monochromeToggle(b)): return a == b
        case let (.tabSelector(a), .tabSelector(b)): return a == b
        case let (.iconRow(ai, ap, ac), .iconRow(bi, bp, bc)): return ai == bi && ap.iconName == bp.iconName && ac == bc
        case let (.customStub(a), .customStub(b)): return a == b
        default: return false
        }
    }

    static func <(lhs: FullGramIconsEntry, rhs: FullGramIconsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramIconsArguments
        switch self {
        case let .monochromeToggle(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "Монохромные иконки",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleMonochrome
            )
        case let .tabSelector(tab):
            let title = tab == 0 ? "Вкладка: Иконки (нажмите для Кастомных)" : "Вкладка: Кастомные иконки (нажмите для Иконок)"
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .center,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.switchTab(tab == 0 ? 1 : 0)
                }
            )
        case let .iconRow(_, preset, checked):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: fullGramIconPreviewImage(preset.previewResource),
                title: preset.title,
                style: .right,
                checked: checked,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.selectIcon(preset.iconName)
                }
            )
        case let .customStub(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramAppIconsController(context: AccountContext) -> ViewController {
    let tabPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramIconsArguments(
        toggleMonochrome: { value in
            FullGramExtras.shared.monochromeAppIcons = value
            if value, UIApplication.shared.supportsAlternateIcons {
                let current = UIApplication.shared.alternateIconName
                if fullGramStandardIcons.first(where: { $0.iconName == current })?.isMonochrome != true {
                    UIApplication.shared.setAlternateIconName("WhiteFilledIcon") { _ in
                        DispatchQueue.main.async {
                            changed.set(version.modify { $0 + 1 })
                        }
                    }
                }
            }
        },
        switchTab: { next in
            tabPromise.set(next)
        },
        selectIcon: { name in
            guard UIApplication.shared.supportsAlternateIcons else { return }
            UIApplication.shared.setAlternateIconName(name) { _ in
                DispatchQueue.main.async {
                    changed.set(version.modify { $0 + 1 })
                }
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, tabPromise.get(), changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, activeTab, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let monochrome = FullGramExtras.shared.monochromeAppIcons
        var entries: [FullGramIconsEntry] = [
            .monochromeToggle(monochrome),
            .tabSelector(activeTab)
        ]
        if activeTab == 0 {
            let currentIcon = UIApplication.shared.alternateIconName
            let list = monochrome ? fullGramStandardIcons.filter(\.isMonochrome) : fullGramStandardIcons
            for (index, preset) in list.enumerated() {
                entries.append(.iconRow(Int32(index), preset, preset.iconName == currentIcon))
            }
        } else {
            let currentIcon = UIApplication.shared.alternateIconName
            for (index, preset) in fullGramCustomIcons.enumerated() {
                entries.append(.iconRow(Int32(index), preset, preset.iconName == currentIcon))
            }
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Иконки приложения"),
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

    return ItemListController(context: context, state: signal)
}
