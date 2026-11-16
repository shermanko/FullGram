import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ItemListUI
import PresentationDataUtils
import TelegramPresentationData

// MARK: - 2.1. Шрифты (локальные в сурскоде приложения)

private struct FullGramFontsArguments {
    let select: (String) -> Void
}

private enum FullGramFontsEntry: ItemListNodeEntry {
    case header(String)
    case font(Int32, FullGramFonts.Option, Bool)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .font(idx, _, _): return 10 + idx
        case .info: return 100
        }
    }

    static func ==(lhs: FullGramFontsEntry, rhs: FullGramFontsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a), .header(b)): return a == b
        case let (.font(ai, ao, ac), .font(bi, bo, bc)): return ai == bi && ao.id == bo.id && ac == bc
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
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .font(_, option, selected):
            let previewFont: UIFont
            if let psName = option.postScriptName, let custom = UIFont(name: psName, size: 16.0) {
                previewFont = custom
            } else {
                previewFont = Font.regular(16.0)
            }
            let titleAttr = NSAttributedString(
                string: "\(option.title)  —  \(option.sample)",
                attributes: [
                    .font: previewFont,
                    .foregroundColor: presentationData.theme.list.itemPrimaryTextColor
                ]
            )
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: option.title,
                attributedTitle: titleAttr,
                style: .right,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.select(option.id)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramFontsController(context: AccountContext) -> ViewController {
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let observer = NotificationCenter.default.addObserver(forName: FullGramFonts.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }

    let args = FullGramFontsArguments(select: { id in
        FullGramFonts.selectedId = id
    })

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramFontsEntry] = [
            .header("ВСТРОЕННЫЕ ШРИФТЫ")
        ]
        let selected = FullGramFonts.selectedId
        for (index, option) in FullGramFonts.options.enumerated() {
            entries.append(.font(Int32(index), option, option.id == selected))
        }
        let note = FullGramFonts.needsRelaunch
            ? "Выбран новый шрифт. Перезапустите приложение, чтобы применить его ко всему интерфейсу."
            : "Все шрифты хранятся локально в приложении. Новый шрифт применяется после перезапуска."
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

    return ItemListController(context: context, state: signal)
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

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = FullGramThemePreviewItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, previousItem == nil, nextItem == nil)
            Queue.mainQueue().async {
                completion(node, { (nil, { _ in apply() }) })
            }
            _ = layout
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FullGramThemePreviewItemNode {
                let (layout, apply) = nodeValue.asyncLayout()(self, params, previousItem == nil, nextItem == nil)
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
        self.view.addSubview(self.cardView)
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
    private let slot: FullGramThemeColors.Slot
    private var retainedSelf: FullGramColorPickerDelegate?

    init(slot: FullGramThemeColors.Slot) {
        self.slot = slot
        super.init()
        self.retainedSelf = self
    }

    @available(iOS 14.0, *)
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        let hex = Self.hexString(from: viewController.selectedColor)
        FullGramThemeColors.markCustom()
        FullGramThemeColors.set(self.slot, hex: hex)
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
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

func fullGramThemesController(context: AccountContext) -> ViewController {
    var presentNativeImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let obs1 = NotificationCenter.default.addObserver(forName: FullGramThemeColors.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let obs2 = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
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
                    let delegate = FullGramColorPickerDelegate(slot: slot)
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
    case glowingReactions = 2
}

private struct FullGramDesignArguments {
    let toggle: (FullGramDesignToggle, Bool) -> Void
    let pickSlowMotion: () -> Void
}

private enum FullGramDesignEntry: ItemListNodeEntry {
    case header(String)
    case toggle(FullGramDesignToggle, String, Bool)
    case slowMotion(String, String)
    case info(String)

    var section: ItemListSectionId { return 0 }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .toggle(opt, _, _): return opt.rawValue
        case .slowMotion: return 10
        case .info: return 20
        }
    }

    static func ==(lhs: FullGramDesignEntry, rhs: FullGramDesignEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a), .header(b)): return a == b
        case let (.toggle(ao, at, av), .toggle(bo, bt, bv)): return ao == bo && at == bt && av == bv
        case let (.slowMotion(at, al), .slowMotion(bt, bl)): return at == bt && al == bl
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
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramDesignController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }

    let args = FullGramDesignArguments(
        toggle: { opt, value in
            switch opt {
            case .classicDesign:
                FullGramExtras.shared.classicDesign = value
            case .glowingReactions:
                FullGramExtras.shared.glowingReactions = value
            }
        },
        pickSlowMotion: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            let items: [ActionSheetItem] = FullGramAnimationSpeed.steps.map { step in
                let label = step == 1.0 ? "Выкл. (1×)" : "\(Int(step))×"
                return ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    FullGramAnimationSpeed.factor = step
                    version += 1
                    changed.set(version)
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
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let factor = FullGramAnimationSpeed.factor
        let slowLabel = factor <= 1.0 ? "Выкл." : "\(Int(factor))×"
        let entries: [FullGramDesignEntry] = [
            .header("ДИЗАЙН"),
            .toggle(.classicDesign, "Старый дизайн Telegram", FullGramExtras.shared.classicDesign),
            .toggle(.glowingReactions, "Светящиеся реакции", FullGramExtras.shared.glowingReactions),
            .slowMotion("Замедление анимаций", slowLabel),
            .info("«Старый дизайн Telegram» отключает жидкое стекло и применяет классические плоские панели после перезапуска.")
        ]

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
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
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
    FullGramIconPreset(iconName: nil, title: "Стандартная (Синяя)", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "BlueClassicIcon", title: "Классическая синяя", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "BlueFilledIcon", title: "Синяя заливка", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "BlackIcon", title: "Чёрная", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "BlackClassicIcon", title: "Классическая чёрная", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "BlackFilledIcon", title: "Чёрная заливка", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "WhiteFilledIcon", title: "Белая (монохромная)", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "New1", title: "Ночь", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "New2", title: "Рассвет", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "Premium", title: "Премиум", isMonochrome: false, previewResource: nil),
    FullGramIconPreset(iconName: "PremiumBlack", title: "Премиум чёрная", isMonochrome: true, previewResource: nil),
    FullGramIconPreset(iconName: "PremiumTurbo", title: "Премиум турбо", isMonochrome: false, previewResource: nil)
]

private let fullGramCustomIcons: [FullGramIconPreset] = [
    FullGramIconPreset(iconName: "FullGramDefault", title: "default", isMonochrome: false, previewResource: "FullGramIcon_FullGramDefault"),
    FullGramIconPreset(iconName: "FullGramRed", title: "red", isMonochrome: false, previewResource: "FullGramIcon_FullGramRed"),
    FullGramIconPreset(iconName: "FullGramMascot", title: "mascot", isMonochrome: false, previewResource: "FullGramIcon_FullGramMascot"),
    FullGramIconPreset(iconName: "FullGramOrange", title: "orange", isMonochrome: false, previewResource: "FullGramIcon_FullGramOrange")
]

private func fullGramIconPreviewImage(_ resource: String?) -> UIImage? {
    guard let resource,
          let path = Bundle.main.path(forResource: resource, ofType: "png"),
          let raw = UIImage(contentsOfFile: path) else {
        return nil
    }
    let size = CGSize(width: 29.0, height: 29.0)
    return UIGraphicsImageRenderer(size: size).image { _ in
        UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 7.0).addClip()
        raw.draw(in: CGRect(origin: .zero, size: size))
    }.withRenderingMode(.alwaysOriginal)
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
    var version = 0
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }

    let args = FullGramIconsArguments(
        toggleMonochrome: { value in
            FullGramExtras.shared.monochromeAppIcons = value
            if value, UIApplication.shared.supportsAlternateIcons {
                let current = UIApplication.shared.alternateIconName
                if fullGramStandardIcons.first(where: { $0.iconName == current })?.isMonochrome != true {
                    UIApplication.shared.setAlternateIconName("BlackIcon") { _ in
                        DispatchQueue.main.async {
                            version += 1
                            changed.set(version)
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
                    version += 1
                    changed.set(version)
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
