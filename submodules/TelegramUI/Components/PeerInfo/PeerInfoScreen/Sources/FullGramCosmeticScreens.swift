import Foundation
import UIKit
import AsyncDisplayKit
import Display
@preconcurrency import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
@preconcurrency import AccountContext

// MARK: - 1. Косметика Discord: 679+ рамок аватара, кастомные рамки и 329+ анимаций открытия профиля

public func fullGramAvatarFramesController(context: AccountContext) -> ViewController {
    return FullGramAvatarFramesViewController(context: context)
}

private final class FullGramAvatarFramesViewController: ViewController, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private enum CosmeticsTab: Int {
        case frames = 0
        case profileEffects = 1
    }

    private let context: AccountContext
    private let selfPeerId: Int64
    private var presentationData: PresentationData

    private let headerCard = UIView()
    private let headerEffectView = FullGramProfileEffectOverlayView()
    private let previewAvatarCircle = UIView()
    private let previewInitialLabel = UILabel()
    private let previewFrameView = FullGramAvatarFrameView()
    private let previewTitleLabel = UILabel()
    private let previewSubLabel = UILabel()
    private let customFrameButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let chatSwitch = UISwitch()
    private let segmentedControl = UISegmentedControl(items: ["Рамки", "Эффекты профиля"])
    private let searchContainer = UIView()
    private let searchIconView = UIImageView()
    private let searchField = UITextField()
    private let categoryScrollView = UIScrollView()
    private let categoryStackView = UIStackView()
    private var collectionView: UICollectionView!
    private var headerTopConstraint: NSLayoutConstraint?

    private var activeTab: CosmeticsTab = .frames
    private var selectedCategory: String = "Все"
    private var searchQuery: String = ""
    private nonisolated(unsafe) var searchWorkItem: DispatchWorkItem?
    private var filteredFrames: [FullGramAvatarFramePreset] = []
    private var filteredEffects: [FullGramProfileEffectPreset] = []
    private var categoryButtons: [(category: String, button: UIButton)] = []
    private nonisolated(unsafe) var catalogObserver: NSObjectProtocol?

    private static let customFrameIds: Set<String> = Set(FullGramAvatarFrames.customFullGramFrames.map(\.id))

    public init(context: AccountContext) {
        self.context = context
        self.selfPeerId = FullGramCloudCosmetics.normalizedPeerId(context.account.peerId.toInt64())
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = "Косметика и рамки"
        FullGramCloudCosmetics.shared.setActiveSelfPeerId(self.selfPeerId)
        FullGramCloudCosmetics.shared.refreshIfNeeded(maxAge: 30.0)
        FullGramDiscordCosmeticsCatalog.shared.refreshIfNeeded(maxAge: 600.0)
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.searchWorkItem?.cancel()
        if let obs = self.catalogObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    override public func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()

        self.setupUI()
        self.rebuildCategoryBar()
        self.applyFilter()
        self.catalogObserver = NotificationCenter.default.addObserver(
            forName: FullGramDiscordCosmeticsCatalog.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildCategoryBar()
                self?.applyFilter()
                self?.refreshPreview()
            }
        }
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.headerTopConstraint?.constant = topInset + 8.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
        self.collectionView?.collectionViewLayout.invalidateLayout()
    }

    private func setupUI() {
        let theme = self.presentationData.theme
        let root = self.displayNode.view

        self.headerCard.translatesAutoresizingMaskIntoConstraints = false
        self.headerCard.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.headerCard.layer.cornerRadius = 16.0
        self.headerCard.layer.cornerCurve = .continuous
        self.headerCard.clipsToBounds = true

        self.headerEffectView.translatesAutoresizingMaskIntoConstraints = false
        self.headerCard.addSubview(self.headerEffectView)

        self.previewAvatarCircle.translatesAutoresizingMaskIntoConstraints = false
        self.previewAvatarCircle.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.25)
        self.previewAvatarCircle.layer.cornerRadius = 28.0
        self.previewAvatarCircle.clipsToBounds = false
        self.headerCard.addSubview(self.previewAvatarCircle)

        self.previewInitialLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewInitialLabel.text = "FG"
        self.previewInitialLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .bold)
        self.previewInitialLabel.textColor = theme.list.itemPrimaryTextColor
        self.previewInitialLabel.textAlignment = .center
        self.previewAvatarCircle.addSubview(self.previewInitialLabel)

        self.previewFrameView.translatesAutoresizingMaskIntoConstraints = false
        self.previewAvatarCircle.addSubview(self.previewFrameView)

        self.previewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewTitleLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .bold)
        self.previewTitleLabel.textColor = theme.list.itemPrimaryTextColor
        self.previewTitleLabel.numberOfLines = 1
        self.headerCard.addSubview(self.previewTitleLabel)

        self.previewSubLabel.translatesAutoresizingMaskIntoConstraints = false
        self.previewSubLabel.font = UIFont.systemFont(ofSize: 12.0)
        self.previewSubLabel.textColor = theme.list.itemSecondaryTextColor
        self.previewSubLabel.numberOfLines = 1
        self.headerCard.addSubview(self.previewSubLabel)

        var customCfg = UIButton.Configuration.filled()
        var customTitle = AttributedString("+ Своя рамка")
        customTitle.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        customCfg.attributedTitle = customTitle
        customCfg.cornerStyle = .capsule
        customCfg.baseBackgroundColor = theme.list.itemAccentColor
        customCfg.baseForegroundColor = .white
        customCfg.contentInsets = NSDirectionalEdgeInsets(top: 5.0, leading: 10.0, bottom: 5.0, trailing: 10.0)
        self.customFrameButton.configuration = customCfg
        self.customFrameButton.translatesAutoresizingMaskIntoConstraints = false
        self.customFrameButton.addTarget(self, action: #selector(self.addCustomFrameTapped), for: .touchUpInside)
        self.headerCard.addSubview(self.customFrameButton)

        var resetCfg = UIButton.Configuration.tinted()
        var resetTitle = AttributedString("Снять")
        resetTitle.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        resetCfg.attributedTitle = resetTitle
        resetCfg.cornerStyle = .capsule
        resetCfg.baseBackgroundColor = UIColor.systemRed
        resetCfg.baseForegroundColor = UIColor.systemRed
        resetCfg.contentInsets = NSDirectionalEdgeInsets(top: 5.0, leading: 10.0, bottom: 5.0, trailing: 10.0)
        self.resetButton.configuration = resetCfg
        self.resetButton.translatesAutoresizingMaskIntoConstraints = false
        self.resetButton.addTarget(self, action: #selector(self.resetActiveTapped), for: .touchUpInside)
        self.headerCard.addSubview(self.resetButton)

        let chatRowLabel = UILabel()
        chatRowLabel.translatesAutoresizingMaskIntoConstraints = false
        chatRowLabel.text = "Рамки в списке чатов"
        chatRowLabel.font = UIFont.systemFont(ofSize: 13.0)
        chatRowLabel.textColor = theme.list.itemSecondaryTextColor
        self.headerCard.addSubview(chatRowLabel)

        self.chatSwitch.translatesAutoresizingMaskIntoConstraints = false
        self.chatSwitch.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        self.chatSwitch.isOn = FullGramAvatarFrames.showInChatListAndMessages
        self.chatSwitch.onTintColor = theme.list.itemAccentColor
        self.chatSwitch.addTarget(self, action: #selector(self.chatToggled), for: .valueChanged)
        self.headerCard.addSubview(self.chatSwitch)

        self.segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        self.segmentedControl.selectedSegmentIndex = 0
        self.segmentedControl.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.segmentedControl.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)

        // Clean custom search bar container (fixes UISearchBar vertical overflow overlapping adjacent views)
        self.searchContainer.translatesAutoresizingMaskIntoConstraints = false
        self.searchContainer.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.searchContainer.layer.cornerRadius = 10.0
        self.searchContainer.layer.cornerCurve = .continuous
        self.searchContainer.layer.borderWidth = 0.5
        self.searchContainer.layer.borderColor = theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35).cgColor
        self.searchContainer.clipsToBounds = true

        self.searchIconView.translatesAutoresizingMaskIntoConstraints = false
        self.searchIconView.image = UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate)
        self.searchIconView.tintColor = UIColor(rgb: 0x8E8E93)
        self.searchIconView.tintColor = theme.list.itemSecondaryTextColor
        self.searchIconView.contentMode = .scaleAspectFit
        self.searchContainer.addSubview(self.searchIconView)

        self.searchField.translatesAutoresizingMaskIntoConstraints = false
        self.searchField.font = UIFont.systemFont(ofSize: 14.0)
        self.searchField.textColor = theme.list.itemPrimaryTextColor
        self.searchField.attributedPlaceholder = NSAttributedString(
            string: "Поиск по названию или категории…",
            attributes: [.foregroundColor: theme.list.itemSecondaryTextColor]
        )
        self.searchField.clearButtonMode = .whileEditing
        self.searchField.returnKeyType = .search
        self.searchField.autocorrectionType = .no
        self.searchField.delegate = self
        self.searchField.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.searchField.addTarget(self, action: #selector(self.searchTextChanged), for: .editingChanged)
        self.searchContainer.addSubview(self.searchField)

        // Horizontal category chip bar
        self.categoryScrollView.translatesAutoresizingMaskIntoConstraints = false
        self.categoryScrollView.showsHorizontalScrollIndicator = false
        self.categoryScrollView.alwaysBounceHorizontal = true
        self.categoryScrollView.clipsToBounds = true
        self.categoryScrollView.contentInset = UIEdgeInsets(top: 0.0, left: 12.0, bottom: 0.0, right: 12.0)

        self.categoryStackView.translatesAutoresizingMaskIntoConstraints = false
        self.categoryStackView.axis = .horizontal
        self.categoryStackView.alignment = .center
        self.categoryStackView.spacing = 6.0
        self.categoryScrollView.addSubview(self.categoryStackView)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8.0
        layout.minimumLineSpacing = 8.0
        layout.sectionInset = UIEdgeInsets(top: 6.0, left: 12.0, bottom: 24.0, right: 12.0)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView.backgroundColor = .clear
        self.collectionView.clipsToBounds = true
        self.collectionView.keyboardDismissMode = .onDrag
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.prefetchDataSource = self
        self.collectionView.register(FullGramFrameGridCell.self, forCellWithReuseIdentifier: "FrameCell")
        self.collectionView.register(FullGramProfileEffectGridCell.self, forCellWithReuseIdentifier: "EffectCell")

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        insertBelowNav(self.collectionView)
        insertBelowNav(self.categoryScrollView)
        insertBelowNav(self.searchContainer)
        insertBelowNav(self.segmentedControl)
        insertBelowNav(self.headerCard)

        let topConstraint = self.headerCard.topAnchor.constraint(equalTo: root.topAnchor, constant: 96.0)
        self.headerTopConstraint = topConstraint

        NSLayoutConstraint.activate([
            topConstraint,
            self.headerCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.headerCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),

            self.headerEffectView.topAnchor.constraint(equalTo: self.headerCard.topAnchor),
            self.headerEffectView.bottomAnchor.constraint(equalTo: self.headerCard.bottomAnchor),
            self.headerEffectView.leadingAnchor.constraint(equalTo: self.headerCard.leadingAnchor),
            self.headerEffectView.trailingAnchor.constraint(equalTo: self.headerCard.trailingAnchor),

            self.previewAvatarCircle.topAnchor.constraint(equalTo: self.headerCard.topAnchor, constant: 14.0),
            self.previewAvatarCircle.leadingAnchor.constraint(equalTo: self.headerCard.leadingAnchor, constant: 14.0),
            self.previewAvatarCircle.widthAnchor.constraint(equalToConstant: 56.0),
            self.previewAvatarCircle.heightAnchor.constraint(equalToConstant: 56.0),

            self.previewInitialLabel.centerXAnchor.constraint(equalTo: self.previewAvatarCircle.centerXAnchor),
            self.previewInitialLabel.centerYAnchor.constraint(equalTo: self.previewAvatarCircle.centerYAnchor),

            self.previewFrameView.topAnchor.constraint(equalTo: self.previewAvatarCircle.topAnchor),
            self.previewFrameView.bottomAnchor.constraint(equalTo: self.previewAvatarCircle.bottomAnchor),
            self.previewFrameView.leadingAnchor.constraint(equalTo: self.previewAvatarCircle.leadingAnchor),
            self.previewFrameView.trailingAnchor.constraint(equalTo: self.previewAvatarCircle.trailingAnchor),

            self.previewTitleLabel.topAnchor.constraint(equalTo: self.headerCard.topAnchor, constant: 12.0),
            self.previewTitleLabel.leadingAnchor.constraint(equalTo: self.previewAvatarCircle.trailingAnchor, constant: 14.0),
            self.previewTitleLabel.trailingAnchor.constraint(equalTo: self.headerCard.trailingAnchor, constant: -12.0),

            self.previewSubLabel.topAnchor.constraint(equalTo: self.previewTitleLabel.bottomAnchor, constant: 2.0),
            self.previewSubLabel.leadingAnchor.constraint(equalTo: self.previewTitleLabel.leadingAnchor),
            self.previewSubLabel.trailingAnchor.constraint(equalTo: self.headerCard.trailingAnchor, constant: -12.0),

            self.customFrameButton.topAnchor.constraint(equalTo: self.previewSubLabel.bottomAnchor, constant: 8.0),
            self.customFrameButton.leadingAnchor.constraint(equalTo: self.previewTitleLabel.leadingAnchor),

            self.resetButton.centerYAnchor.constraint(equalTo: self.customFrameButton.centerYAnchor),
            self.resetButton.leadingAnchor.constraint(equalTo: self.customFrameButton.trailingAnchor, constant: 6.0),

            chatRowLabel.topAnchor.constraint(equalTo: self.previewAvatarCircle.bottomAnchor, constant: 12.0),
            chatRowLabel.leadingAnchor.constraint(equalTo: self.headerCard.leadingAnchor, constant: 14.0),
            chatRowLabel.bottomAnchor.constraint(equalTo: self.headerCard.bottomAnchor, constant: -10.0),
            self.chatSwitch.centerYAnchor.constraint(equalTo: chatRowLabel.centerYAnchor),
            self.chatSwitch.trailingAnchor.constraint(equalTo: self.headerCard.trailingAnchor, constant: -10.0),

            self.segmentedControl.topAnchor.constraint(equalTo: self.headerCard.bottomAnchor, constant: 8.0),
            self.segmentedControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.segmentedControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),
            self.segmentedControl.heightAnchor.constraint(equalToConstant: 30.0),

            self.searchContainer.topAnchor.constraint(equalTo: self.segmentedControl.bottomAnchor, constant: 8.0),
            self.searchContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.searchContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),
            self.searchContainer.heightAnchor.constraint(equalToConstant: 36.0),

            self.searchIconView.leadingAnchor.constraint(equalTo: self.searchContainer.leadingAnchor, constant: 10.0),
            self.searchIconView.centerYAnchor.constraint(equalTo: self.searchContainer.centerYAnchor),
            self.searchIconView.widthAnchor.constraint(equalToConstant: 16.0),
            self.searchIconView.heightAnchor.constraint(equalToConstant: 16.0),

            self.searchField.leadingAnchor.constraint(equalTo: self.searchIconView.trailingAnchor, constant: 8.0),
            self.searchField.trailingAnchor.constraint(equalTo: self.searchContainer.trailingAnchor, constant: -8.0),
            self.searchField.topAnchor.constraint(equalTo: self.searchContainer.topAnchor),
            self.searchField.bottomAnchor.constraint(equalTo: self.searchContainer.bottomAnchor),

            self.categoryScrollView.topAnchor.constraint(equalTo: self.searchContainer.bottomAnchor, constant: 8.0),
            self.categoryScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.categoryScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.categoryScrollView.heightAnchor.constraint(equalToConstant: 32.0),

            self.categoryStackView.topAnchor.constraint(equalTo: self.categoryScrollView.contentLayoutGuide.topAnchor),
            self.categoryStackView.bottomAnchor.constraint(equalTo: self.categoryScrollView.contentLayoutGuide.bottomAnchor),
            self.categoryStackView.leadingAnchor.constraint(equalTo: self.categoryScrollView.contentLayoutGuide.leadingAnchor),
            self.categoryStackView.trailingAnchor.constraint(equalTo: self.categoryScrollView.contentLayoutGuide.trailingAnchor),
            self.categoryStackView.heightAnchor.constraint(equalTo: self.categoryScrollView.frameLayoutGuide.heightAnchor),

            self.collectionView.topAnchor.constraint(equalTo: self.categoryScrollView.bottomAnchor, constant: 6.0),
            self.collectionView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        self.refreshPreview()
    }

    private func availableCategories() -> [(name: String, count: Int)] {
        if self.activeTab == .frames {
            let allF = FullGramAvatarFrames.allFrames
            var counts: [String: Int] = [:]
            for item in allF {
                counts[item.category, default: 0] += 1
            }
            let preferredOrder = ["FullGram", "Кибер", "Неон", "Аниме", "Милые", "Стихия", "Космос", "Природа", "Игры", "Эмоции", "Эффект", "Флаги", "Discord"]
            let favCount = FullGramAvatarFrames.favoriteFrameIds.count
            let userUploadedCount = FullGramAvatarFrames.userUploadedPresets(forPeerId: self.selfPeerId).count
            var result: [(String, Int)] = [
                ("Все", allF.count + userUploadedCount),
                ("★ Избранное", favCount),
                ("⭐ Свои", FullGramAvatarFrames.customFullGramFrames.count + userUploadedCount)
            ]
            var seen: Set<String> = ["Все", "★ Избранное", "⭐ Свои"]
            for cat in preferredOrder {
                if let c = counts[cat], c > 0 {
                    result.append((cat, c))
                    seen.insert(cat)
                }
            }
            for (cat, c) in counts.sorted(by: { $0.key < $1.key }) where !seen.contains(cat) && c > 0 {
                result.append((cat, c))
            }
            return result
        } else {
            let allE = FullGramProfileEffects.allEffects
            var counts: [String: Int] = [:]
            for item in allE {
                counts[item.category, default: 0] += 1
            }
            let preferredOrder = ["Кибер", "Аниме", "Милые", "Стихия", "Космос", "Природа", "Игры", "Discord"]
            let favCount = FullGramProfileEffects.favoriteEffectIds.count
            var result: [(String, Int)] = [
                ("Все", allE.count),
                ("★ Избранное", favCount)
            ]
            var seen: Set<String> = ["Все", "★ Избранное"]
            for cat in preferredOrder {
                if let c = counts[cat], c > 0 {
                    result.append((cat, c))
                    seen.insert(cat)
                }
            }
            for (cat, c) in counts.sorted(by: { $0.key < $1.key }) where !seen.contains(cat) && c > 0 {
                result.append((cat, c))
            }
            return result
        }
    }

    private func rebuildCategoryBar() {
        let categories = self.availableCategories()
        if !categories.contains(where: { $0.name == self.selectedCategory }) {
            self.selectedCategory = "Все"
        }
        for sub in self.categoryStackView.arrangedSubviews {
            self.categoryStackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        self.categoryButtons.removeAll()

        for (index, item) in categories.enumerated() {
            let btn = UIButton(type: .system)
            btn.tag = index
            btn.accessibilityIdentifier = item.name
            btn.addTarget(self, action: #selector(self.categoryChipTapped(_:)), for: .touchUpInside)
            self.styleCategoryButton(btn, title: "\(item.name) (\(item.count))", active: item.name == self.selectedCategory)
            self.categoryStackView.addArrangedSubview(btn)
            self.categoryButtons.append((item.name, btn))
        }
    }

    private func styleCategoryButton(_ btn: UIButton, title: String, active: Bool) {
        let theme = self.presentationData.theme
        var cfg = active ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        var attr = AttributedString(title)
        attr.font = UIFont.systemFont(ofSize: 12.0, weight: active ? .bold : .medium)
        cfg.attributedTitle = attr
        cfg.cornerStyle = .capsule
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 5.0, leading: 11.0, bottom: 5.0, trailing: 11.0)
        if active {
            cfg.baseBackgroundColor = theme.list.itemAccentColor
            cfg.baseForegroundColor = .white
        } else {
            cfg.baseBackgroundColor = theme.list.itemBlocksBackgroundColor
            cfg.baseForegroundColor = theme.list.itemPrimaryTextColor
            cfg.background.backgroundColor = theme.list.itemBlocksBackgroundColor
            cfg.background.strokeColor = theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)
            cfg.background.strokeWidth = 0.5
        }
        btn.configuration = cfg
    }

    @objc private func categoryChipTapped(_ sender: UIButton) {
        guard let cat = sender.accessibilityIdentifier, cat != self.selectedCategory else { return }
        self.selectedCategory = cat
        for entry in self.categoryButtons {
            let currentTitle = entry.button.configuration?.attributedTitle.map { String($0.characters) } ?? entry.category
            self.styleCategoryButton(entry.button, title: currentTitle, active: entry.category == self.selectedCategory)
        }
        self.applyFilter()
        self.collectionView.setContentOffset(.zero, animated: false)
    }

    private func currentActiveFrameSelectionId() -> String? {
        guard let cos = FullGramCloudCosmetics.shared.cosmetics(forPeerId: self.selfPeerId, selfPeerId: self.selfPeerId) else {
            return nil
        }
        if let url = cos.customFrameUrl, !url.isEmpty {
            return "custom_url"
        }
        return cos.frameId
    }

    private func applyFilter() {
        let userCustom = FullGramAvatarFrames.userUploadedPresets(forPeerId: self.selfPeerId)
        let allF = userCustom + FullGramAvatarFrames.allFrames
        let allE = FullGramProfileEffects.allEffects
        self.segmentedControl.setTitle("Рамки (\(allF.count))", forSegmentAt: 0)
        self.segmentedControl.setTitle("Эффекты (\(allE.count))", forSegmentAt: 1)

        let q = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cat = self.selectedCategory

        var frames = allF
        if self.activeTab == .frames && cat != "Все" {
            if cat == "★ Избранное" {
                let favSet = Set(FullGramAvatarFrames.favoriteFrameIds)
                frames = frames.filter { favSet.contains($0.id) }
            } else if cat == "⭐ Свои" {
                let userIds = Set(userCustom.map(\.id))
                frames = frames.filter { userIds.contains($0.id) || Self.customFrameIds.contains($0.id) }
            } else {
                frames = frames.filter { $0.category == cat }
            }
        }
        if !q.isEmpty {
            frames = frames.filter {
                $0.title.lowercased().contains(q) || $0.category.lowercased().contains(q)
            }
        }
        self.filteredFrames = frames

        var effects = allE
        if self.activeTab == .profileEffects && cat != "Все" {
            if cat == "★ Избранное" {
                let favSet = Set(FullGramProfileEffects.favoriteEffectIds)
                effects = effects.filter { favSet.contains($0.id) }
            } else {
                effects = effects.filter { $0.category == cat }
            }
        }
        if !q.isEmpty {
            effects = effects.filter {
                $0.title.lowercased().contains(q) || $0.category.lowercased().contains(q)
            }
        }
        self.filteredEffects = effects

        self.collectionView.reloadData()
    }

    @objc private func tabChanged() {
        self.activeTab = CosmeticsTab(rawValue: self.segmentedControl.selectedSegmentIndex) ?? .frames
        self.selectedCategory = "Все"
        self.rebuildCategoryBar()
        self.applyFilter()
        self.collectionView.setContentOffset(.zero, animated: false)
    }

    @objc private func chatToggled() {
        FullGramAvatarFrames.showInChatListAndMessages = self.chatSwitch.isOn
    }

    @objc private func resetActiveTapped() {
        if self.activeTab == .frames {
            FullGramAvatarFrames.setSelectedFrame(forPeerId: self.selfPeerId, frameId: nil)
        } else {
            FullGramProfileEffects.setSelectedEffect(forPeerId: self.selfPeerId, effectId: nil)
        }
        self.refreshPreview()
        self.updateVisibleCellSelectionStates()
    }

    @objc private func addCustomFrameTapped() {
        let sheet = UIAlertController(
            title: "Кастомная рамка аватара",
            message: "Загрузите свою PNG/APNG/GIF рамку из галереи или по прямой HTTPS-ссылке (ссылка видна всем в FullGram).",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Выбрать из Фото / Галереи", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.delegate = self
            self.context.sharedContext.applicationBindings.presentNativeController(picker)
        }))
        sheet.addAction(UIAlertAction(title: "Вставить ссылку PNG / APNG (URL)", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let alert = UIAlertController(
                title: "Ссылка на рамку",
                message: "Укажите прямую https:// ссылку на прозрачный PNG/APNG/GIF:",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "https://cdn.discordapp.com/avatar-decoration-presets/..."
                tf.keyboardType = .URL
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
                if let existingUrl = FullGramCloudCosmetics.shared.localCosmetics(forPeerId: self.selfPeerId)?.customFrameUrl {
                    tf.text = existingUrl
                }
            }
            alert.addAction(UIAlertAction(title: "Применить", style: .default, handler: { [weak self] _ in
                guard let self else { return }
                let raw = alert.textFields?.first?.text ?? ""
                FullGramAvatarFrames.setCustomURLFrame(urlString: raw, forPeerId: self.selfPeerId)
                self.rebuildCategoryBar()
                self.applyFilter()
                self.refreshPreview()
                self.updateVisibleCellSelectionStates()
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            self.context.sharedContext.applicationBindings.presentNativeController(alert)
        }))
        sheet.addAction(UIAlertAction(title: "Обновить каталог Discord", style: .default, handler: { _ in
            FullGramDiscordCosmeticsCatalog.shared.refreshNow { _ in }
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.context.sharedContext.applicationBindings.presentNativeController(sheet)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        var pickedData: Data?
        var isGif = false
        if let fileURL = info[.imageURL] as? URL, let rawData = try? Data(contentsOf: fileURL), !rawData.isEmpty {
            pickedData = rawData
            isGif = rawData.prefix(3) == Data([0x47, 0x49, 0x46])
        } else if let img = info[.originalImage] as? UIImage, let png = img.pngData() {
            pickedData = png
        }
        if let pickedData {
            FullGramAvatarFrames.saveCustomLocalFrame(data: pickedData, forPeerId: self.selfPeerId)
            FullGramCloudCosmetics.shared.uploadCustomFrame(peerId: self.selfPeerId, data: pickedData, isGif: isGif) { [weak self] _ in
                Task { @MainActor in
                    self?.rebuildCategoryBar()
                    self?.applyFilter()
                    self?.refreshPreview()
                }
            }
        }
        self.rebuildCategoryBar()
        self.applyFilter()
        self.refreshPreview()
        self.updateVisibleCellSelectionStates()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    @objc private func searchTextChanged() {
        self.searchWorkItem?.cancel()
        let query = self.searchField.text ?? ""
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchQuery = query
            self.applyFilter()
        }
        self.searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func refreshPreview() {
        let activeFrame = FullGramAvatarFrames.frame(forPeerId: self.selfPeerId, selfPeerId: self.selfPeerId)
        let activeEffect = FullGramProfileEffects.effect(forPeerId: self.selfPeerId, selfPeerId: self.selfPeerId)

        self.previewFrameView.configure(with: activeFrame)
        self.headerEffectView.configure(with: activeEffect, forceReplay: true)
        self.headerCard.sendSubviewToBack(self.headerEffectView)

        self.previewTitleLabel.text = activeFrame.map { "Рамка: \($0.title)" } ?? "Рамка: не выбрана"
        self.previewSubLabel.text = activeEffect.map { "Эффект профиля: \($0.title)" } ?? "Эффект профиля: нет"
    }

    private func updateVisibleCellSelectionStates() {
        let theme = self.presentationData.theme
        if self.activeTab == .frames {
            let activeId = self.currentActiveFrameSelectionId()
            for cell in self.collectionView.visibleCells {
                if let frameCell = cell as? FullGramFrameGridCell,
                   let idx = self.collectionView.indexPath(for: frameCell),
                   idx.item < self.filteredFrames.count {
                    let preset = self.filteredFrames[idx.item]
                    frameCell.updateSelection(selected: activeId == preset.id, favorite: FullGramAvatarFrames.isFavoriteFrame(preset.id), preset: preset, theme: theme)
                }
            }
        } else {
            let activeId = FullGramProfileEffects.selectedEffectId(forPeerId: self.selfPeerId)
            for cell in self.collectionView.visibleCells {
                if let effectCell = cell as? FullGramProfileEffectGridCell,
                   let idx = self.collectionView.indexPath(for: effectCell),
                   idx.item < self.filteredEffects.count {
                    let preset = self.filteredEffects[idx.item]
                    effectCell.updateSelection(selected: activeId == preset.id, favorite: FullGramProfileEffects.isFavoriteEffect(preset.id), preset: preset, theme: theme)
                }
            }
        }
    }
}

extension FullGramAvatarFramesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.activeTab == .frames ? self.filteredFrames.count : self.filteredEffects.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if self.activeTab == .frames {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FrameCell", for: indexPath) as! FullGramFrameGridCell
            let preset = self.filteredFrames[indexPath.item]
            let activeId = self.currentActiveFrameSelectionId()
            let animatePreview = (activeId == preset.id) || preset.id.hasPrefix("fg_") || preset.isBundled || preset.category == "Кастом"
            cell.configure(
                preset: preset,
                selected: activeId == preset.id,
                animate: animatePreview,
                favorite: FullGramAvatarFrames.isFavoriteFrame(preset.id),
                theme: self.presentationData.theme
            ) { [weak self] in
                FullGramAvatarFrames.toggleFavoriteFrame(preset.id)
                self?.rebuildCategoryBar()
                if self?.selectedCategory == "★ Избранное" {
                    self?.applyFilter()
                } else {
                    self?.updateVisibleCellSelectionStates()
                }
            }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EffectCell", for: indexPath) as! FullGramProfileEffectGridCell
            let preset = self.filteredEffects[indexPath.item]
            let activeId = FullGramProfileEffects.selectedEffectId(forPeerId: self.selfPeerId)
            cell.configure(preset: preset, selected: activeId == preset.id, favorite: FullGramProfileEffects.isFavoriteEffect(preset.id), theme: self.presentationData.theme) { [weak self] in
                FullGramProfileEffects.toggleFavoriteEffect(preset.id)
                self?.rebuildCategoryBar()
                if self?.selectedCategory == "★ Избранное" {
                    self?.applyFilter()
                } else {
                    self?.updateVisibleCellSelectionStates()
                }
            }
            return cell
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let frameCell = cell as? FullGramFrameGridCell {
            frameCell.cancelLoads()
        } else if let effectCell = cell as? FullGramProfileEffectGridCell {
            effectCell.cancelLoads()
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.searchField.resignFirstResponder()
        if self.activeTab == .frames {
            guard indexPath.item < self.filteredFrames.count else { return }
            let preset = self.filteredFrames[indexPath.item]
            let current = self.currentActiveFrameSelectionId()
            if current == preset.id {
                FullGramAvatarFrames.setSelectedFrame(forPeerId: self.selfPeerId, frameId: nil)
            } else if preset.id == "custom_url", let url = preset.remoteURLs.first {
                FullGramAvatarFrames.setCustomURLFrame(urlString: url, forPeerId: self.selfPeerId)
            } else {
                FullGramAvatarFrames.setSelectedFrame(forPeerId: self.selfPeerId, frameId: preset.id)
            }
        } else {
            guard indexPath.item < self.filteredEffects.count else { return }
            let preset = self.filteredEffects[indexPath.item]
            let current = FullGramProfileEffects.selectedEffectId(forPeerId: self.selfPeerId)
            FullGramProfileEffects.setSelectedEffect(forPeerId: self.selfPeerId, effectId: current == preset.id ? nil : preset.id)
        }
        self.refreshPreview()
        self.updateVisibleCellSelectionStates()
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cols: CGFloat = 3.0
        let available = collectionView.bounds.width - 24.0 - (cols - 1.0) * 8.0
        let width = floor(max(96.0, available / cols))
        return CGSize(width: width, height: self.activeTab == .frames ? 104.0 : 122.0)
    }
}

extension FullGramAvatarFramesViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        if self.activeTab == .frames {
            for indexPath in indexPaths where indexPath.item < self.filteredFrames.count {
                FullGramAnimatedImageDecoder.prefetchThumbnail(for: self.filteredFrames[indexPath.item], maxPixelSize: 180)
            }
        } else {
            for indexPath in indexPaths where indexPath.item < self.filteredEffects.count {
                let effect = self.filteredEffects[indexPath.item]
                if !effect.layerURLs.isEmpty {
                    FullGramAnimatedImageDecoder.prefetchProfileEffectThumbnail(effectId: effect.id, layerURLs: effect.layerURLs, maxPixelSize: 320)
                }
            }
        }
    }
}

private final class FullGramFrameGridCell: UICollectionViewCell {
    private let avatarCircle = UIView()
    private let avatarGlyphLabel = UILabel()
    private let frameView = FullGramAvatarFrameView()
    private let loadingSpinner = UIActivityIndicatorView(style: .medium)
    private let starButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let catLabel = UILabel()
    private var onToggleFavorite: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layer.cornerRadius = 14.0
        self.contentView.layer.cornerCurve = .continuous

        self.avatarCircle.translatesAutoresizingMaskIntoConstraints = false
        self.avatarCircle.layer.cornerRadius = 23.0
        self.avatarCircle.backgroundColor = UIColor(rgb: 0x262B3D)
        self.contentView.addSubview(self.avatarCircle)

        self.avatarGlyphLabel.translatesAutoresizingMaskIntoConstraints = false
        self.avatarGlyphLabel.text = "FG"
        self.avatarGlyphLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .bold)
        self.avatarGlyphLabel.textColor = UIColor.white.withAlphaComponent(0.65)
        self.avatarGlyphLabel.textAlignment = .center
        self.avatarCircle.addSubview(self.avatarGlyphLabel)

        self.frameView.translatesAutoresizingMaskIntoConstraints = false
        self.avatarCircle.addSubview(self.frameView)

        self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        self.loadingSpinner.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
        self.loadingSpinner.hidesWhenStopped = true
        self.avatarCircle.addSubview(self.loadingSpinner)
        self.frameView.onLoadingStateChanged = { [weak self] loading in
            guard let self else { return }
            if loading {
                self.loadingSpinner.startAnimating()
            } else {
                self.loadingSpinner.stopAnimating()
            }
        }

        self.starButton.translatesAutoresizingMaskIntoConstraints = false
        self.starButton.titleLabel?.font = UIFont.systemFont(ofSize: 13.0)
        self.starButton.addTarget(self, action: #selector(self.starTapped), for: .touchUpInside)
        self.contentView.addSubview(self.starButton)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)

        self.catLabel.translatesAutoresizingMaskIntoConstraints = false
        self.catLabel.font = UIFont.systemFont(ofSize: 9.5, weight: .medium)
        self.catLabel.textAlignment = .center
        self.contentView.addSubview(self.catLabel)

        NSLayoutConstraint.activate([
            self.avatarCircle.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 12.0),
            self.avatarCircle.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.avatarCircle.widthAnchor.constraint(equalToConstant: 46.0),
            self.avatarCircle.heightAnchor.constraint(equalToConstant: 46.0),

            self.avatarGlyphLabel.centerXAnchor.constraint(equalTo: self.avatarCircle.centerXAnchor),
            self.avatarGlyphLabel.centerYAnchor.constraint(equalTo: self.avatarCircle.centerYAnchor),

            self.frameView.topAnchor.constraint(equalTo: self.avatarCircle.topAnchor),
            self.frameView.bottomAnchor.constraint(equalTo: self.avatarCircle.bottomAnchor),
            self.frameView.leadingAnchor.constraint(equalTo: self.avatarCircle.leadingAnchor),
            self.frameView.trailingAnchor.constraint(equalTo: self.avatarCircle.trailingAnchor),

            self.loadingSpinner.centerXAnchor.constraint(equalTo: self.avatarCircle.centerXAnchor),
            self.loadingSpinner.centerYAnchor.constraint(equalTo: self.avatarCircle.centerYAnchor),

            self.starButton.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 2.0),
            self.starButton.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -2.0),
            self.starButton.widthAnchor.constraint(equalToConstant: 24.0),
            self.starButton.heightAnchor.constraint(equalToConstant: 24.0),

            self.titleLabel.topAnchor.constraint(equalTo: self.avatarCircle.bottomAnchor, constant: 9.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),

            self.catLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 1.0),
            self.catLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.catLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func starTapped() {
        self.onToggleFavorite?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.onToggleFavorite = nil
        self.frameView.cancelPendingLoad()
        self.loadingSpinner.stopAnimating()
    }

    func cancelLoads() {
        self.frameView.cancelPendingLoad()
        self.loadingSpinner.stopAnimating()
    }

    func configure(preset: FullGramAvatarFramePreset, selected: Bool, animate: Bool, favorite: Bool, theme: PresentationTheme, onToggleFavorite: @escaping () -> Void) {
        self.onToggleFavorite = onToggleFavorite
        self.titleLabel.text = preset.title
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.avatarCircle.backgroundColor = UIColor(rgb: preset.accentHex).withAlphaComponent(theme.overallDarkAppearance ? 0.20 : 0.16)
        self.avatarGlyphLabel.textColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.55)
        self.updateSelection(selected: selected, favorite: favorite, preset: preset, theme: theme)
        if animate {
            self.frameView.configure(with: preset)
        } else {
            self.frameView.configureThumbnail(with: preset)
        }
    }

    func updateSelection(selected: Bool, favorite: Bool, preset: FullGramAvatarFramePreset, theme: PresentationTheme) {
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderWidth = selected ? 2.0 : 0.5
        self.contentView.layer.borderColor = (selected ? UIColor(rgb: preset.accentHex) : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)).cgColor
        self.starButton.setTitle(favorite ? "★" : "☆", for: .normal)
        self.starButton.setTitleColor(favorite ? UIColor(rgb: 0xFFCC00) : theme.list.itemSecondaryTextColor, for: .normal)
        self.catLabel.text = selected ? "✓ Активна" : preset.category
        self.catLabel.textColor = selected ? UIColor(rgb: preset.accentHex) : theme.list.itemSecondaryTextColor
    }
}

private final class FullGramProfileEffectGridCell: UICollectionViewCell {
    private let previewBox = UIView()
    private let effectView = FullGramProfileEffectOverlayView()
    private let loadingSpinner = UIActivityIndicatorView(style: .medium)
    private let starButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let catLabel = UILabel()
    private var onToggleFavorite: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layer.cornerRadius = 12.0
        self.contentView.layer.cornerCurve = .continuous
        self.contentView.clipsToBounds = true

        self.previewBox.translatesAutoresizingMaskIntoConstraints = false
        self.previewBox.layer.cornerRadius = 9.0
        self.previewBox.layer.cornerCurve = .continuous
        self.previewBox.clipsToBounds = true
        self.previewBox.backgroundColor = UIColor(rgb: 0x161925)
        self.contentView.addSubview(self.previewBox)

        self.effectView.translatesAutoresizingMaskIntoConstraints = false
        self.previewBox.addSubview(self.effectView)

        self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        self.loadingSpinner.color = .white
        self.loadingSpinner.hidesWhenStopped = true
        self.previewBox.addSubview(self.loadingSpinner)
        self.effectView.onLoadingStateChanged = { [weak self] loading in
            guard let self else { return }
            if loading {
                self.loadingSpinner.startAnimating()
            } else {
                self.loadingSpinner.stopAnimating()
            }
        }

        self.starButton.translatesAutoresizingMaskIntoConstraints = false
        self.starButton.titleLabel?.font = UIFont.systemFont(ofSize: 13.0)
        self.starButton.addTarget(self, action: #selector(self.starTapped), for: .touchUpInside)
        self.contentView.addSubview(self.starButton)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)

        self.catLabel.translatesAutoresizingMaskIntoConstraints = false
        self.catLabel.font = UIFont.systemFont(ofSize: 9.5)
        self.catLabel.textAlignment = .center
        self.contentView.addSubview(self.catLabel)

        NSLayoutConstraint.activate([
            self.previewBox.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 6.0),
            self.previewBox.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 6.0),
            self.previewBox.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -6.0),
            self.previewBox.heightAnchor.constraint(equalToConstant: 74.0),

            self.effectView.topAnchor.constraint(equalTo: self.previewBox.topAnchor),
            self.effectView.bottomAnchor.constraint(equalTo: self.previewBox.bottomAnchor),
            self.effectView.leadingAnchor.constraint(equalTo: self.previewBox.leadingAnchor),
            self.effectView.trailingAnchor.constraint(equalTo: self.previewBox.trailingAnchor),

            self.loadingSpinner.centerXAnchor.constraint(equalTo: self.previewBox.centerXAnchor),
            self.loadingSpinner.centerYAnchor.constraint(equalTo: self.previewBox.centerYAnchor),

            self.starButton.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 4.0),
            self.starButton.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),
            self.starButton.widthAnchor.constraint(equalToConstant: 24.0),
            self.starButton.heightAnchor.constraint(equalToConstant: 24.0),

            self.titleLabel.topAnchor.constraint(equalTo: self.previewBox.bottomAnchor, constant: 5.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),

            self.catLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 1.0),
            self.catLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.catLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func starTapped() {
        self.onToggleFavorite?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.onToggleFavorite = nil
        self.effectView.cancelPendingLoad()
        self.loadingSpinner.stopAnimating()
    }

    func cancelLoads() {
        self.effectView.cancelPendingLoad()
        self.loadingSpinner.stopAnimating()
    }

    func configure(preset: FullGramProfileEffectPreset, selected: Bool, favorite: Bool, theme: PresentationTheme, onToggleFavorite: @escaping () -> Void) {
        self.onToggleFavorite = onToggleFavorite
        self.titleLabel.text = preset.title
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.updateSelection(selected: selected, favorite: favorite, preset: preset, theme: theme)
        self.effectView.configureThumbnail(with: preset)
    }

    func updateSelection(selected: Bool, favorite: Bool, preset: FullGramProfileEffectPreset, theme: PresentationTheme) {
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderWidth = selected ? 2.0 : 0.5
        self.contentView.layer.borderColor = (selected ? UIColor(rgb: preset.accentHex) : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)).cgColor
        self.starButton.setTitle(favorite ? "★" : "☆", for: .normal)
        self.starButton.setTitleColor(favorite ? UIColor(rgb: 0xFFCC00) : .white, for: .normal)
        self.catLabel.text = selected ? "✓ В профиле" : preset.category
        self.catLabel.textColor = selected ? UIColor(rgb: preset.accentHex) : theme.list.itemSecondaryTextColor
    }
}

// MARK: - 2. Стиль ника (палитра цветов + неоновое свечение на профиль)

@available(iOS 14.0, *)
private final class FullGramNickColorPickerDelegate: NSObject, UIColorPickerViewControllerDelegate {
    private var retainedSelf: FullGramNickColorPickerDelegate?
    private let onPick: (String) -> Void

    init(onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        super.init()
        self.retainedSelf = self
    }

    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        self.emit(viewController.selectedColor)
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        self.emit(viewController.selectedColor)
        self.retainedSelf = nil
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

private let fullGramColorSwatchCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 64
    return cache
}()

private func fullGramColorSwatchIcon(_ hex: String) -> UIImage? {
    let key = hex.uppercased() as NSString
    if let cached = fullGramColorSwatchCache.object(forKey: key) {
        return cached
    }
    guard let rgb = FullGramThemeColors.parse(hex) else { return nil }
    let color = UIColor(rgb: rgb)
    let size = CGSize(width: 26.0, height: 26.0)
    let rendered = UIGraphicsImageRenderer(size: size).image { _ in
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
        let path = UIBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()
        UIColor(white: 1.0, alpha: 0.25).setStroke()
        path.lineWidth = 1.0
        path.stroke()
    }
    fullGramColorSwatchCache.setObject(rendered, forKey: key)
    return rendered
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
