import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - 1. Анимированные рамки аватара (сохраняются на профиль и синхронизируются с облаком)

public func fullGramAvatarFramesController(context: AccountContext) -> ViewController {
    return FullGramAvatarFramesViewController(context: context)
}

private final class FullGramAvatarFramesViewController: ViewController {
    private let context: AccountContext
    private let selfPeerId: Int64
    private var presentationData: PresentationData

    private let headerCard = UIView()
    private let previewAvatarCircle = UIView()
    private let previewInitialLabel = UILabel()
    private let previewFrameView = FullGramAvatarFrameView()
    private let previewTitleLabel = UILabel()
    private let enableSwitch = UISwitch()
    private let chatSwitch = UISwitch()
    private var collectionView: UICollectionView!
    private var lastPickedFrameId: String = FullGramAvatarFrames.allFrames[0].id

    public init(context: AccountContext) {
        self.context = context
        self.selfPeerId = context.account.peerId.toInt64()
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "Анимированные рамки"
        if let current = FullGramAvatarFrames.selectedFrameId(forPeerId: self.selfPeerId) {
            self.lastPickedFrameId = current
        }
        FullGramCloudCosmetics.shared.setActiveSelfPeerId(self.selfPeerId)
        FullGramCloudCosmetics.shared.refreshIfNeeded(maxAge: 15.0)
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
        self.previewTitleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.previewTitleLabel.textColor = theme.list.itemPrimaryTextColor
        self.previewTitleLabel.numberOfLines = 2
        self.headerCard.addSubview(self.previewTitleLabel)

        let enableRowLabel = UILabel()
        enableRowLabel.translatesAutoresizingMaskIntoConstraints = false
        enableRowLabel.text = "Рамка на моём профиле"
        enableRowLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        enableRowLabel.textColor = theme.list.itemPrimaryTextColor
        self.headerCard.addSubview(enableRowLabel)

        self.enableSwitch.translatesAutoresizingMaskIntoConstraints = false
        self.enableSwitch.isOn = FullGramAvatarFrames.selectedFrameId(forPeerId: self.selfPeerId) != nil
        self.enableSwitch.onTintColor = theme.list.itemAccentColor
        self.enableSwitch.addTarget(self, action: #selector(self.enableToggled), for: .valueChanged)
        self.headerCard.addSubview(self.enableSwitch)

        let chatRowLabel = UILabel()
        chatRowLabel.translatesAutoresizingMaskIntoConstraints = false
        chatRowLabel.text = "Показывать рамки в списке чатов"
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
            enableRowLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.enableSwitch.leadingAnchor, constant: -8.0),
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
        if self.enableSwitch.isOn {
            FullGramAvatarFrames.setSelectedFrame(forPeerId: self.selfPeerId, frameId: self.lastPickedFrameId)
        } else {
            if let cur = FullGramAvatarFrames.selectedFrameId(forPeerId: self.selfPeerId) {
                self.lastPickedFrameId = cur
            }
            FullGramAvatarFrames.setSelectedFrame(forPeerId: self.selfPeerId, frameId: nil)
        }
        self.refreshPreview()
        self.collectionView.reloadData()
    }

    @objc private func chatToggled() {
        FullGramAvatarFrames.showInChatListAndMessages = self.chatSwitch.isOn
    }

    private func refreshPreview() {
        if let selectedId = FullGramAvatarFrames.selectedFrameId(forPeerId: self.selfPeerId),
           let preset = FullGramAvatarFrames.allFrames.first(where: { $0.id == selectedId }) {
            self.previewTitleLabel.text = "\(preset.title) (\(preset.category))\nID: \(self.selfPeerId)"
            self.previewFrameView.configure(with: preset)
        } else {
            self.previewTitleLabel.text = "Рамка не установлена (выберите ниже)"
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
        let activeId = FullGramAvatarFrames.selectedFrameId(forPeerId: self.selfPeerId)
        let isSelected = (activeId == preset.id)
        cell.configure(preset: preset, selected: isSelected, theme: self.presentationData.theme)
        return cell
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let preset = FullGramAvatarFrames.allFrames[indexPath.item]
        let current = FullGramAvatarFrames.selectedFrameId(forPeerId: self.selfPeerId)
        if current == preset.id {
            FullGramAvatarFrames.setSelectedFrame(forPeerId: self.selfPeerId, frameId: nil)
            self.enableSwitch.setOn(false, animated: true)
        } else {
            self.lastPickedFrameId = preset.id
            FullGramAvatarFrames.setSelectedFrame(forPeerId: self.selfPeerId, frameId: preset.id)
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
        self.catLabel.text = selected ? "✓ На профиле" : preset.category
        self.catLabel.textColor = selected ? UIColor(rgb: preset.accentHex) : theme.list.itemSecondaryTextColor
        self.frameView.configure(with: preset)
    }
}

// MARK: - 2. Стиль ника (палитра цветов + неоновое свечение на профиль)

@available(iOS 14.0, *)
@MainActor
private final class FullGramNickColorPickerDelegate: NSObject, UIColorPickerViewControllerDelegate {
    private static var retained: FullGramNickColorPickerDelegate?
    private let onPick: (String) -> Void

    init(onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        super.init()
        Self.retained = self
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        self.emit(viewController.selectedColor)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        self.emit(viewController.selectedColor)
        Self.retained = nil
    }

    private func emit(_ color: UIColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let hex = String(
            format: "#%02X%02X%02X",
            Int((max(0, min(1, r)) * 255.0).rounded()),
            Int((max(0, min(1, g)) * 255.0).rounded()),
            Int((max(0, min(1, b)) * 255.0).rounded())
        )
        self.onPick(hex)
    }
}

private final class FullGramNickStyleUIState: @unchecked Sendable {
    var presentNative: ((UIViewController) -> Void)?
}

private final class FullGramNicknameArguments {
    let toggleGlow: (Bool) -> Void
    let openSystemPalette: () -> Void
    let enterHex: () -> Void
    let resetDefault: () -> Void
    let selectSwatch: (String) -> Void

    init(
        toggleGlow: @escaping (Bool) -> Void,
        openSystemPalette: @escaping () -> Void,
        enterHex: @escaping () -> Void,
        resetDefault: @escaping () -> Void,
        selectSwatch: @escaping (String) -> Void
    ) {
        self.toggleGlow = toggleGlow
        self.openSystemPalette = openSystemPalette
        self.enterHex = enterHex
        self.resetDefault = resetDefault
        self.selectSwatch = selectSwatch
    }
}

private func fullGramColorSwatchIcon(_ hex: String) -> UIImage? {
    guard let rgb = FullGramThemeColors.parse(hex) else { return nil }
    let color = UIColor(rgb: rgb)
    let size = CGSize(width: 26.0, height: 26.0)
    return UIGraphicsImageRenderer(size: size).image { _ in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
        let path = UIBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        UIColor(white: 1.0, alpha: 0.25).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }
}

private enum FullGramNicknameEntry: ItemListNodeEntry {
    case optionsHeader(String)
    case glow(Bool)
    case customPalette(String, String)
    case customHex(String, String)
    case resetColor(String)
    case paletteHeader(String)
    case swatch(Int32, FullGramNicknameColorOption, Bool)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .optionsHeader, .glow, .customPalette, .customHex, .resetColor: return 0
        case .paletteHeader, .swatch, .info: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .optionsHeader: return 0
        case .glow: return 1
        case .customPalette: return 2
        case .customHex: return 3
        case .resetColor: return 4
        case .paletteHeader: return 100
        case let .swatch(idx, _, _): return 101 + idx
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
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "Неоновое свечение ника",
                value: val,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleGlow
            )
        case let .customPalette(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.openSystemPalette
            )
        case let .customHex(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.enterHex
            )
        case let .resetColor(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .center,
                sectionId: self.section,
                style: .blocks,
                action: args.resetDefault
            )
        case let .paletteHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .swatch(_, option, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: fullGramColorSwatchIcon(option.hex),
                title: option.title,
                style: .right,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.selectSwatch(option.hex)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramNicknameStyleController(context: AccountContext) -> ViewController {
    let selfPeerId = context.account.peerId.toInt64()
    FullGramCloudCosmetics.shared.setActiveSelfPeerId(selfPeerId)
    FullGramCloudCosmetics.shared.refreshIfNeeded(maxAge: 15.0)

    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let uiState = FullGramNickStyleUIState()
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
        toggleGlow: { enabled in
            let currentHex = FullGramNicknameStyle.colorHex(forPeerId: selfPeerId, selfPeerId: selfPeerId) ?? "#00F5D4"
            FullGramNicknameStyle.setOwnStyle(peerId: selfPeerId, colorHex: currentHex, glowEnabled: enabled)
        },
        openSystemPalette: {
            if #available(iOS 14.0, *) {
                let picker = UIColorPickerViewController()
                picker.supportsAlpha = false
                if let hex = FullGramNicknameStyle.colorHex(forPeerId: selfPeerId, selfPeerId: selfPeerId),
                   let rgb = FullGramThemeColors.parse(hex) {
                    picker.selectedColor = UIColor(rgb: rgb)
                } else {
                    picker.selectedColor = UIColor(rgb: 0x00F5D4)
                }
                let delegate = FullGramNickColorPickerDelegate { hex in
                    let glow = FullGramNicknameStyle.glowEnabled(forPeerId: selfPeerId, selfPeerId: selfPeerId)
                    FullGramNicknameStyle.setOwnStyle(peerId: selfPeerId, colorHex: hex, glowEnabled: glow)
                }
                picker.delegate = delegate
                uiState.presentNative?(picker)
            }
        },
        enterHex: {
            let alert = UIAlertController(title: "Цвет ника (HEX)", message: "Введите цвет в формате #RRGGBB", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.text = FullGramNicknameStyle.colorHex(forPeerId: selfPeerId, selfPeerId: selfPeerId) ?? ""
                tf.placeholder = "#00F5D4"
                tf.autocapitalizationType = .allCharacters
                tf.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "Применить", style: .default, handler: { _ in
                let raw = alert.textFields?.first?.text ?? ""
                if let parsed = FullGramThemeColors.parse(raw) {
                    let hex = String(format: "#%06X", parsed)
                    let glow = FullGramNicknameStyle.glowEnabled(forPeerId: selfPeerId, selfPeerId: selfPeerId)
                    FullGramNicknameStyle.setOwnStyle(peerId: selfPeerId, colorHex: hex, glowEnabled: glow)
                }
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            uiState.presentNative?(alert)
        },
        resetDefault: {
            FullGramNicknameStyle.setOwnStyle(peerId: selfPeerId, colorHex: nil, glowEnabled: false)
        },
        selectSwatch: { hex in
            let glow = FullGramNicknameStyle.glowEnabled(forPeerId: selfPeerId, selfPeerId: selfPeerId)
            FullGramNicknameStyle.setOwnStyle(peerId: selfPeerId, colorHex: hex, glowEnabled: glow)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let currentHex = FullGramNicknameStyle.colorHex(forPeerId: selfPeerId, selfPeerId: selfPeerId)
        let glow = FullGramNicknameStyle.glowEnabled(forPeerId: selfPeerId, selfPeerId: selfPeerId)
        var entries: [FullGramNicknameEntry] = [
            .optionsHeader("НАСТРОЙКА НИКА ДЛЯ ВАШЕГО АККАУНТА"),
            .glow(glow),
            .customPalette("Палитра цветов", currentHex ?? "Выбрать"),
            .customHex("Ввести HEX-код", currentHex ?? "Авто"),
            .resetColor("Сбросить цвет ника (Стандартный)"),
            .paletteHeader("ГОТОВЫЕ ЦВЕТА")
        ]
        for (idx, option) in FullGramNicknameStyle.palette.enumerated() {
            let isSelected = currentHex?.caseInsensitiveCompare(option.hex) == .orderedSame
            entries.append(.swatch(Int32(idx), option, isSelected))
        }
        entries.append(.info("Цвет и неоновое свечение привязываются к вашему ID (\(selfPeerId)) и видны другим пользователям FullGram в вашем профиле и списке чатов."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Стиль ника"),
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
    uiState.presentNative = { vc in
        context.sharedContext.applicationBindings.presentNativeController(vc)
    }
    return controller
}

// MARK: - 3. Приватный режим (режим стримера)

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
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Приватный режим (режим стримера)", value: val, sectionId: self.section, style: .blocks, updated: args.toggleMaster)
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
            .header("ЗАЩИТА ПРИ ЗАПИСИ И ДЕМОНСТРАЦИИ ЭКРАНА"),
            .master(extras.privateMode),
            .optionsHeader("ЧТО СКРЫВАТЬ ВО ВРЕМЯ ЗАХВАТА ЭКРАНА"),
            .hidePreviews(extras.privateModeHidePreviews),
            .hideUsername(extras.privateModeHideUsername),
            .hidePhone(extras.hidePhoneNumber),
            .footer("Скрытие активируется автоматически только во время записи видео с экрана, демонстрации экрана или после скриншота. «Скрывать превью сообщений в чатах» заменяет текст последнего сообщения в списке чатов на заглушку.")
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
