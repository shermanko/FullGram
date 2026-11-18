import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - 1. Анимированные рамки аватара (16 рамок из Discord)

public func fullGramAvatarFramesController(context: AccountContext) -> ViewController {
    return FullGramAvatarFramesViewController(context: context)
}

private final class FullGramAvatarFramesViewController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData

    private let headerCard = UIView()
    private let previewAvatarCircle = UIView()
    private let previewInitialLabel = UILabel()
    private let previewFrameView = FullGramAvatarFrameView()
    private let previewTitleLabel = UILabel()
    private let enableSwitch = UISwitch()
    private let chatSwitch = UISwitch()
    private var collectionView: UICollectionView!

    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "Анимированные рамки"
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()

        self.setupUI()
    }

    private func setupUI() {
        let theme = self.presentationData.theme
        let root = self.displayNode.view

        self.headerCard.translatesAutoresizingMaskIntoConstraints = false
        self.headerCard.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.headerCard.layer.cornerRadius = 16.0
        self.headerCard.layer.cornerCurve = .continuous
        root.addSubview(self.headerCard)

        self.previewAvatarCircle.translatesAutoresizingMaskIntoConstraints = false
        self.previewAvatarCircle.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.25)
        self.previewAvatarCircle.layer.cornerRadius = 36.0
        self.previewAvatarCircle.clipsToBounds = false
        self.headerCard.addSubview(self.previewAvatarCircle)

        self.previewInitialLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewInitialLabel.text = "FG"
        self.previewInitialLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.previewInitialLabel.textColor = theme.list.itemPrimaryTextColor
        self.previewInitialLabel.textAlignment = .center
        self.previewAvatarCircle.addSubview(self.previewInitialLabel)

        self.previewFrameView.translatesAutoresizingMaskIntoConstraints = false
        self.previewAvatarCircle.addSubview(self.previewFrameView)

        self.previewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewTitleLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        self.previewTitleLabel.textColor = theme.list.itemPrimaryTextColor
        self.previewTitleLabel.numberOfLines = 2
        self.headerCard.addSubview(self.previewTitleLabel)

        let enableRowLabel = UILabel()
        enableRowLabel.translatesAutoresizingMaskIntoConstraints = false
        enableRowLabel.text = "Включить рамки"
        enableRowLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        enableRowLabel.textColor = theme.list.itemPrimaryTextColor
        self.headerCard.addSubview(enableRowLabel)

        self.enableSwitch.translatesAutoresizingMaskIntoConstraints = false
        self.enableSwitch.isOn = FullGramAvatarFrames.isEnabled
        self.enableSwitch.onTintColor = theme.list.itemAccentColor
        self.enableSwitch.addTarget(self, action: #selector(self.enableToggled), for: .valueChanged)
        self.headerCard.addSubview(self.enableSwitch)

        let chatRowLabel = UILabel()
        chatRowLabel.translatesAutoresizingMaskIntoConstraints = false
        chatRowLabel.text = "Показывать в списке чатов"
        chatRowLabel.font = UIFont.systemFont(ofSize: 14.0)
        chatRowLabel.textColor = theme.list.itemSecondaryTextColor
        self.headerCard.addSubview(chatRowLabel)

        self.chatSwitch.translatesAutoresizingMaskIntoConstraints = false
        self.chatSwitch.isOn = FullGramAvatarFrames.showInChatListAndMessages
        self.chatSwitch.onTintColor = theme.list.itemAccentColor
        self.chatSwitch.addTarget(self, action: #selector(self.chatToggled), for: .valueChanged)
        self.headerCard.addSubview(self.chatSwitch)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12.0
        layout.minimumLineSpacing = 12.0
        layout.sectionInset = UIEdgeInsets(top: 12.0, left: 16.0, bottom: 24.0, right: 16.0)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView.backgroundColor = .clear
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.register(FullGramFrameGridCell.self, forCellWithReuseIdentifier: "FrameCell")
        root.addSubview(self.collectionView)

        NSLayoutConstraint.activate([
            self.headerCard.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 12.0),
            self.headerCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16.0),
            self.headerCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16.0),

            self.previewAvatarCircle.topAnchor.constraint(equalTo: self.headerCard.topAnchor, constant: 18.0),
            self.previewAvatarCircle.leadingAnchor.constraint(equalTo: self.headerCard.leadingAnchor, constant: 18.0),
            self.previewAvatarCircle.widthAnchor.constraint(equalToConstant: 72.0),
            self.previewAvatarCircle.heightAnchor.constraint(equalToConstant: 72.0),

            self.previewInitialLabel.centerXAnchor.constraint(equalTo: self.previewAvatarCircle.centerXAnchor),
            self.previewInitialLabel.centerYAnchor.constraint(equalTo: self.previewAvatarCircle.centerYAnchor),

            self.previewFrameView.topAnchor.constraint(equalTo: self.previewAvatarCircle.topAnchor),
            self.previewFrameView.bottomAnchor.constraint(equalTo: self.previewAvatarCircle.bottomAnchor),
            self.previewFrameView.leadingAnchor.constraint(equalTo: self.previewAvatarCircle.leadingAnchor),
            self.previewFrameView.trailingAnchor.constraint(equalTo: self.previewAvatarCircle.trailingAnchor),

            self.previewTitleLabel.topAnchor.constraint(equalTo: self.headerCard.topAnchor, constant: 20.0),
            self.previewTitleLabel.leadingAnchor.constraint(equalTo: self.previewAvatarCircle.trailingAnchor, constant: 18.0),
            self.previewTitleLabel.trailingAnchor.constraint(equalTo: self.headerCard.trailingAnchor, constant: -16.0),

            enableRowLabel.topAnchor.constraint(equalTo: self.previewTitleLabel.bottomAnchor, constant: 12.0),
            enableRowLabel.leadingAnchor.constraint(equalTo: self.previewAvatarCircle.trailingAnchor, constant: 18.0),
            self.enableSwitch.centerYAnchor.constraint(equalTo: enableRowLabel.centerYAnchor),
            self.enableSwitch.trailingAnchor.constraint(equalTo: self.headerCard.trailingAnchor, constant: -16.0),

            chatRowLabel.topAnchor.constraint(equalTo: self.previewAvatarCircle.bottomAnchor, constant: 16.0),
            chatRowLabel.leadingAnchor.constraint(equalTo: self.headerCard.leadingAnchor, constant: 16.0),
            chatRowLabel.bottomAnchor.constraint(equalTo: self.headerCard.bottomAnchor, constant: -14.0),
            self.chatSwitch.centerYAnchor.constraint(equalTo: chatRowLabel.centerYAnchor),
            self.chatSwitch.trailingAnchor.constraint(equalTo: self.headerCard.trailingAnchor, constant: -16.0),

            self.collectionView.topAnchor.constraint(equalTo: self.headerCard.bottomAnchor, constant: 8.0),
            self.collectionView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        self.refreshPreview()
    }

    @objc private func enableToggled() {
        FullGramAvatarFrames.isEnabled = self.enableSwitch.isOn
        self.refreshPreview()
        self.collectionView.reloadData()
    }

    @objc private func chatToggled() {
        FullGramAvatarFrames.showInChatListAndMessages = self.chatSwitch.isOn
    }

    private func refreshPreview() {
        let selectedId = FullGramAvatarFrames.selectedFrameId
        let preset = FullGramAvatarFrames.allFrames.first(where: { $0.id == selectedId }) ?? FullGramAvatarFrames.allFrames[0]
        if FullGramAvatarFrames.isEnabled {
            self.previewTitleLabel.text = "\(preset.title) (\(preset.category))"
            self.previewFrameView.configure(with: preset)
        } else {
            self.previewTitleLabel.text = "Рамки отключены (выберите ниже)"
            self.previewFrameView.configure(with: nil)
        }
    }
}

extension FullGramAvatarFramesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return FullGramAvatarFrames.allFrames.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FrameCell", for: indexPath) as! FullGramFrameGridCell
        let preset = FullGramAvatarFrames.allFrames[indexPath.item]
        let isSelected = FullGramAvatarFrames.isEnabled && FullGramAvatarFrames.selectedFrameId == preset.id
        cell.configure(preset: preset, selected: isSelected, theme: self.presentationData.theme)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let preset = FullGramAvatarFrames.allFrames[indexPath.item]
        FullGramAvatarFrames.selectedFrameId = preset.id
        if !FullGramAvatarFrames.isEnabled {
            FullGramAvatarFrames.isEnabled = true
            self.enableSwitch.setOn(true, animated: true)
        }
        self.refreshPreview()
        collectionView.reloadData()
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let available = collectionView.bounds.width - 32.0 - 12.0
        let width = floor(max(120.0, available * 0.5))
        return CGSize(width: width, height: 122.0)
    }
}

private final class FullGramFrameGridCell: UICollectionViewCell {
    private let avatarCircle = UIView()
    private let frameView = FullGramAvatarFrameView()
    private let titleLabel = UILabel()
    private let catLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layer.cornerRadius = 14.0
        self.contentView.layer.cornerCurve = .continuous

        self.avatarCircle.translatesAutoresizingMaskIntoConstraints = false
        self.avatarCircle.layer.cornerRadius = 26.0
        self.avatarCircle.backgroundColor = UIColor(white: 0.5, alpha: 0.16)
        self.contentView.addSubview(self.avatarCircle)

        self.frameView.translatesAutoresizingMaskIntoConstraints = false
        self.avatarCircle.addSubview(self.frameView)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.contentView.addSubview(self.titleLabel)

        self.catLabel.translatesAutoresizingMaskIntoConstraints = false
        self.catLabel.font = UIFont.systemFont(ofSize: 11.0)
        self.catLabel.textAlignment = .center
        self.contentView.addSubview(self.catLabel)

        NSLayoutConstraint.activate([
            self.avatarCircle.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 14.0),
            self.avatarCircle.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.avatarCircle.widthAnchor.constraint(equalToConstant: 52.0),
            self.avatarCircle.heightAnchor.constraint(equalToConstant: 52.0),

            self.frameView.topAnchor.constraint(equalTo: self.avatarCircle.topAnchor),
            self.frameView.bottomAnchor.constraint(equalTo: self.avatarCircle.bottomAnchor),
            self.frameView.leadingAnchor.constraint(equalTo: self.avatarCircle.leadingAnchor),
            self.frameView.trailingAnchor.constraint(equalTo: self.avatarCircle.trailingAnchor),

            self.titleLabel.topAnchor.constraint(equalTo: self.avatarCircle.bottomAnchor, constant: 10.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 8.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -8.0),

            self.catLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 2.0),
            self.catLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 8.0),
            self.catLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -8.0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(preset: FullGramAvatarFramePreset, selected: Bool, theme: PresentationTheme) {
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderWidth = selected ? 2.0 : 0.5
        self.contentView.layer.borderColor = (selected ? UIColor(rgb: preset.accentHex) : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)).cgColor
        self.titleLabel.text = preset.title
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.catLabel.text = selected ? "✓ Выбрано" : preset.category
        self.catLabel.textColor = selected ? UIColor(rgb: preset.accentHex) : theme.list.itemSecondaryTextColor
        self.frameView.configure(with: preset)
    }
}

// MARK: - 2. Кастомные стили ников

private final class FullGramNicknameArguments {
    let toggleGlow: (Bool) -> Void
    let toggleApplyChats: (Bool) -> Void
    let selectPreset: (String) -> Void

    init(
        toggleGlow: @escaping (Bool) -> Void,
        toggleApplyChats: @escaping (Bool) -> Void,
        selectPreset: @escaping (String) -> Void
    ) {
        self.toggleGlow = toggleGlow
        self.toggleApplyChats = toggleApplyChats
        self.selectPreset = selectPreset
    }
}

private enum FullGramNicknameEntry: ItemListNodeEntry {
    case optionsHeader(String)
    case glow(Bool)
    case applyChats(Bool)
    case presetsHeader(String)
    case preset(Int32, FullGramNicknamePreset, Bool)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .optionsHeader, .glow, .applyChats: return 0
        case .presetsHeader, .preset, .info: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .optionsHeader: return 0
        case .glow: return 1
        case .applyChats: return 2
        case .presetsHeader: return 100
        case let .preset(idx, _, _): return 101 + idx
        case .info: return 300
        }
    }

    static func < (lhs: FullGramNicknameEntry, rhs: FullGramNicknameEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramNicknameArguments
        switch self {
        case let .optionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .glow(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Неоновое свечение ника", value: val, sectionId: self.section, style: .blocks, updated: args.toggleGlow)
        case let .applyChats(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Применять к названиям в чатах", value: val, sectionId: self.section, style: .blocks, updated: args.toggleApplyChats)
        case let .presetsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .preset(_, preset, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: preset.title,
                style: .left,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.selectPreset(preset.id)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramNicknameStyleController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let bump: () -> Void = {
        let next = version.modify { $0 + 1 }
        refresh.set(next)
    }

    let observer = NotificationCenter.default.addObserver(
        forName: FullGramNicknameStyle.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        bump()
    }

    let args = FullGramNicknameArguments(
        toggleGlow: { FullGramNicknameStyle.glowEnabled = $0 },
        toggleApplyChats: { FullGramNicknameStyle.applyToChatTitles = $0 },
        selectPreset: { FullGramNicknameStyle.selectedPresetId = $0 }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramNicknameEntry] = [
            .optionsHeader("ПАРАМЕТРЫ СТИЛЯ НИКОВ"),
            .glow(FullGramNicknameStyle.glowEnabled),
            .applyChats(FullGramNicknameStyle.applyToChatTitles),
            .presetsHeader("ВЫБЕРИТЕ СТИЛЬ НИКА")
        ]
        let currentId = FullGramNicknameStyle.selectedPresetId
        for (idx, preset) in FullGramNicknameStyle.presets.enumerated() {
            entries.append(.preset(Int32(idx), preset, preset.id == currentId))
        }
        entries.append(.info("Стиль применяется к вашему имени в профиле и названиям чатов."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Стили ников"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks), args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - 3. Скины раскраски

private final class FullGramSkinsArguments {
    let applySkin: (FullGramColorSkin) -> Void
    let resetAll: () -> Void

    init(applySkin: @escaping (FullGramColorSkin) -> Void, resetAll: @escaping () -> Void) {
        self.applySkin = applySkin
        self.resetAll = resetAll
    }
}

private enum FullGramSkinsEntry: ItemListNodeEntry {
    case header(String)
    case skin(Int32, FullGramColorSkin, Bool)
    case reset(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .skin: return 0
        case .reset, .footer: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .skin(idx, _, _): return 1 + idx
        case .reset: return 100
        case .footer: return 101
        }
    }

    static func < (lhs: FullGramSkinsEntry, rhs: FullGramSkinsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramSkinsArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .skin(_, skin, selected):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "\(skin.title)\n\(skin.subtitle)",
                label: selected ? "Активен" : "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    args.applySkin(skin)
                }
            )
        case let .reset(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: args.resetAll)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramColorSkinsController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let bump: () -> Void = {
        let next = version.modify { $0 + 1 }
        refresh.set(next)
    }

    let observer = NotificationCenter.default.addObserver(
        forName: FullGramThemeColors.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        bump()
    }

    let args = FullGramSkinsArguments(
        applySkin: { skin in
            FullGramColorSkins.apply(skin)
            bump()
        },
        resetAll: {
            FullGramColorSkins.resetAll()
            bump()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramSkinsEntry] = [
            .header("СКИНЫ РАСКРАСКИ (ВСЕ ЦВЕТА + ПУЗЫРИ + НИК)")
        ]
        let activeId = FullGramColorSkins.selectedSkinId
        for (idx, skin) in FullGramColorSkins.skins.enumerated() {
            entries.append(.skin(Int32(idx), skin, skin.id == activeId))
        }
        entries.append(.reset("Сбросить скин по умолчанию"))
        entries.append(.footer("Скин в одно нажатие настраивает цвета темы, фон чата, стиль пузырей и цвет ника."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Скины раскраски"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks), args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - 4. Настройка пузырей сообщений

private final class FullGramBubblesArguments {
    let selectRadius: () -> Void
    let selectOpacity: () -> Void
    let toggleHideTail: (Bool) -> Void
    let toggleOutline: (Bool) -> Void
    let editOutlineColor: () -> Void
    let reset: () -> Void

    init(
        selectRadius: @escaping () -> Void,
        selectOpacity: @escaping () -> Void,
        toggleHideTail: @escaping (Bool) -> Void,
        toggleOutline: @escaping (Bool) -> Void,
        editOutlineColor: @escaping () -> Void,
        reset: @escaping () -> Void
    ) {
        self.selectRadius = selectRadius
        self.selectOpacity = selectOpacity
        self.toggleHideTail = toggleHideTail
        self.toggleOutline = toggleOutline
        self.editOutlineColor = editOutlineColor
        self.reset = reset
    }
}

private enum FullGramBubblesEntry: ItemListNodeEntry {
    case header(String)
    case radius(String, String)
    case opacity(String, String)
    case hideTail(Bool)
    case outline(Bool)
    case outlineColor(String, String)
    case reset(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .radius, .opacity, .hideTail, .outline, .outlineColor: return 0
        case .reset, .footer: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .radius: return 1
        case .opacity: return 2
        case .hideTail: return 3
        case .outline: return 4
        case .outlineColor: return 5
        case .reset: return 10
        case .footer: return 11
        }
    }

    static func < (lhs: FullGramBubblesEntry, rhs: FullGramBubblesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramBubblesArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .radius(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.selectRadius)
        case let .opacity(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.selectOpacity)
        case let .hideTail(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Убрать хвостики пузырей", value: val, sectionId: self.section, style: .blocks, updated: args.toggleHideTail)
        case let .outline(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Контур (обводка) пузырей", value: val, sectionId: self.section, style: .blocks, updated: args.toggleOutline)
        case let .outlineColor(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editOutlineColor)
        case let .reset(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: args.reset)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramBubblesController(context: AccountContext) -> ViewController {
    var presentNativeImpl: ((UIViewController) -> Void)?
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let bump: () -> Void = {
        let next = version.modify { $0 + 1 }
        refresh.set(next)
    }

    let observer = NotificationCenter.default.addObserver(
        forName: FullGramBubbleCustomization.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        bump()
    }

    let args = FullGramBubblesArguments(
        selectRadius: {
            let sheet = UIAlertController(title: "Скругление пузырей", message: nil, preferredStyle: .actionSheet)
            for (title, val) in [("Острые (6 pt)", 6.0), ("Средние (12 pt)", 12.0), ("Стандарт (17 pt)", 17.0), ("Пилюли (22 pt)", 22.0)] {
                sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                    FullGramBubbleCustomization.cornerRadius = CGFloat(val)
                }))
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        selectOpacity: {
            let sheet = UIAlertController(title: "Прозрачность пузырей", message: nil, preferredStyle: .actionSheet)
            for (title, val) in [("Полупрозрачные (55%)", 0.55), ("Мягкие (75%)", 0.75), ("Лёгкие (90%)", 0.90), ("Непрозрачные (100%)", 1.0)] {
                sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                    FullGramBubbleCustomization.opacity = CGFloat(val)
                }))
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        toggleHideTail: { FullGramBubbleCustomization.hideTail = $0 },
        toggleOutline: { FullGramBubbleCustomization.outlineEnabled = $0 },
        editOutlineColor: {
            let alert = UIAlertController(title: "Цвет обводки (HEX)", message: "Например: #00E5FF или #FF2A85", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.text = FullGramBubbleCustomization.outlineColorHex ?? ""
                tf.placeholder = "#00E5FF"
                tf.autocapitalizationType = .allCharacters
            }
            alert.addAction(UIAlertAction(title: "Применить", style: .default, handler: { _ in
                let raw = alert.textFields?.first?.text ?? ""
                if let parsed = FullGramThemeColors.parse(raw) {
                    FullGramBubbleCustomization.outlineColorHex = String(format: "#%06X", parsed)
                    FullGramBubbleCustomization.outlineEnabled = true
                } else {
                    FullGramBubbleCustomization.outlineColorHex = nil
                }
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        reset: {
            FullGramBubbleCustomization.reset()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let r = Int(FullGramBubbleCustomization.cornerRadius.rounded())
        let op = Int((FullGramBubbleCustomization.opacity * 100.0).rounded())
        let hex = FullGramBubbleCustomization.outlineColorHex ?? "Авто"

        let entries: [FullGramBubblesEntry] = [
            .header("ФОРМА И СТИЛЬ ПУЗЫРЕЙ"),
            .radius("Скругление углов", "\(r) pt"),
            .opacity("Прозрачность пузырей", "\(op)%"),
            .hideTail(FullGramBubbleCustomization.hideTail),
            .outline(FullGramBubbleCustomization.outlineEnabled),
            .outlineColor("Цвет обводки", hex),
            .reset("Сбросить настройки пузырей"),
            .footer("Изменения применяются ко всем пузырям сообщений в чатах.")
        ]

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Настройка пузырей"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks), args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    let controller = ItemListController(context: context, state: signal)
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}

// MARK: - 5. Приватный режим (режим стримера)

private final class FullGramPrivateModeArguments {
    let toggleMaster: (Bool) -> Void
    let toggleHidePreviews: (Bool) -> Void
    let toggleHideUsername: (Bool) -> Void
    let toggleHidePhone: (Bool) -> Void

    init(
        toggleMaster: @escaping (Bool) -> Void,
        toggleHidePreviews: @escaping (Bool) -> Void,
        toggleHideUsername: @escaping (Bool) -> Void,
        toggleHidePhone: @escaping (Bool) -> Void
    ) {
        self.toggleMaster = toggleMaster
        self.toggleHidePreviews = toggleHidePreviews
        self.toggleHideUsername = toggleHideUsername
        self.toggleHidePhone = toggleHidePhone
    }
}

private enum FullGramPrivateModeEntry: ItemListNodeEntry {
    case header(String)
    case master(Bool)
    case optionsHeader(String)
    case hidePreviews(Bool)
    case hideUsername(Bool)
    case hidePhone(Bool)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .master: return 0
        case .optionsHeader, .hidePreviews, .hideUsername, .hidePhone, .footer: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .master: return 1
        case .optionsHeader: return 10
        case .hidePreviews: return 11
        case .hideUsername: return 12
        case .hidePhone: return 13
        case .footer: return 14
        }
    }

    static func < (lhs: FullGramPrivateModeEntry, rhs: FullGramPrivateModeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramPrivateModeArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .master(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Приватный режим", value: val, sectionId: self.section, style: .blocks, updated: args.toggleMaster)
        case let .optionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .hidePreviews(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Скрывать превью сообщений в чатах", value: val, sectionId: self.section, style: .blocks, updated: args.toggleHidePreviews)
        case let .hideUsername(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Маскировать @username", value: val, sectionId: self.section, style: .blocks, updated: args.toggleHideUsername)
        case let .hidePhone(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Скрывать номер телефона", value: val, sectionId: self.section, style: .blocks, updated: args.toggleHidePhone)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramPrivateModeController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let bump: () -> Void = {
        let next = version.modify { $0 + 1 }
        refresh.set(next)
    }

    let observer = NotificationCenter.default.addObserver(
        forName: FullGramExtras.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        bump()
    }

    let args = FullGramPrivateModeArguments(
        toggleMaster: { FullGramExtras.shared.privateMode = $0 },
        toggleHidePreviews: { FullGramExtras.shared.privateModeHidePreviews = $0 },
        toggleHideUsername: { FullGramExtras.shared.privateModeHideUsername = $0 },
        toggleHidePhone: { FullGramExtras.shared.hidePhoneNumber = $0 }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let extras = FullGramExtras.shared
        let entries: [FullGramPrivateModeEntry] = [
            .header("БЫСТРАЯ ЗАЩИТА ЭКРАНА"),
            .master(extras.privateMode),
            .optionsHeader("ЧТО СКРЫВАТЬ ПРИ АКТИВНОМ РЕЖИМЕ"),
            .hidePreviews(extras.privateModeHidePreviews),
            .hideUsername(extras.privateModeHideUsername),
            .hidePhone(extras.hidePhoneNumber),
            .footer("Приватный режим скрывает конфиденциальные данные (номер телефона, @username и текст последних сообщений в списке чатов) во время демонстрации экрана или стрима.")
        ]

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Приватный режим"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks), args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    return ItemListController(context: context, state: signal)
}
