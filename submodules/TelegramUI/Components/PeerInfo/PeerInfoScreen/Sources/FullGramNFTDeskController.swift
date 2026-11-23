import Foundation
import UIKit
import AsyncDisplayKit
import Display
import ComponentFlow
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import GiftItemComponent
import UndoUI

// MARK: - 1. Каталог коллекций NFT (компактная сетка 4 колонки)

public func fullGramNFTCatalogController(
    context: AccountContext,
    targetPeerId: Int64,
    targetDisplayName: String,
    targetEnginePeerId: EnginePeer.Id? = nil,
    isSponsorSelfMode: Bool = false
) -> ViewController {
    let cleanId = FullGramGrantedNFTStore.normalizedTelegramId(for: targetPeerId)
    return FullGramNFTCatalogViewController(
        context: context,
        targetPeerId: cleanId,
        targetDisplayName: targetDisplayName,
        targetEnginePeerId: targetEnginePeerId,
        isSponsorSelfMode: isSponsorSelfMode
    )
}

private final class FullGramNFTCatalogViewController: ViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchBarDelegate {
    private let context: AccountContext
    private let targetPeerId: Int64
    private let targetDisplayName: String
    private let targetEnginePeerId: EnginePeer.Id?
    private let isSponsorSelfMode: Bool
    private var presentationData: PresentationData

    private let searchBar = UISearchBar()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var collectionView: UICollectionView!
    private var topConstraint: NSLayoutConstraint?

    private var allGifts: [StarGift.Gift] = []
    private var filteredGifts: [StarGift.Gift] = []
    private var searchQuery: String = ""
    private var loadDisposable: Disposable?

    init(
        context: AccountContext,
        targetPeerId: Int64,
        targetDisplayName: String,
        targetEnginePeerId: EnginePeer.Id?,
        isSponsorSelfMode: Bool = false
    ) {
        self.context = context
        self.targetPeerId = targetPeerId
        self.targetDisplayName = targetDisplayName
        self.targetEnginePeerId = targetEnginePeerId
        self.isSponsorSelfMode = isSponsorSelfMode
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        self.title = ru ? "Выбрать NFT" : "Choose NFT"
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.loadDisposable?.dispose()
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
        self.setupUI()
        self.loadCatalog()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.topConstraint?.constant = topInset + 2.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
        self.collectionView?.collectionViewLayout.invalidateLayout()
    }

    private func setupUI() {
        let theme = self.presentationData.theme
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let root = self.displayNode.view

        self.searchBar.translatesAutoresizingMaskIntoConstraints = false
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.placeholder = ru ? "Поиск NFT (Plush Pepe, Durov's Cap…)" : "Search NFT…"
        self.searchBar.delegate = self
        self.searchBar.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light

        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel.font = UIFont.systemFont(ofSize: 12.0)
        self.statusLabel.textColor = theme.list.itemSecondaryTextColor
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 1
        self.statusLabel.text = ru ? "Кому: \(self.targetDisplayName) (ID \(self.targetPeerId))" : "To: \(self.targetDisplayName) (ID \(self.targetPeerId))"

        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.hidesWhenStopped = true

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6.0
        layout.minimumLineSpacing = 6.0
        layout.sectionInset = UIEdgeInsets(top: 6.0, left: 10.0, bottom: 20.0, right: 10.0)

        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView.backgroundColor = .clear
        self.collectionView.keyboardDismissMode = .onDrag
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.register(FullGramNFTComponentCell.self, forCellWithReuseIdentifier: "GiftCell")

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        insertBelowNav(self.collectionView)
        insertBelowNav(self.statusLabel)
        insertBelowNav(self.searchBar)
        insertBelowNav(self.spinner)

        let topC = self.searchBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 90.0)
        self.topConstraint = topC

        NSLayoutConstraint.activate([
            topC,
            self.searchBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6.0),
            self.searchBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6.0),
            self.searchBar.heightAnchor.constraint(equalToConstant: 44.0),

            self.statusLabel.topAnchor.constraint(equalTo: self.searchBar.bottomAnchor, constant: 1.0),
            self.statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),

            self.collectionView.topAnchor.constraint(equalTo: self.statusLabel.bottomAnchor, constant: 4.0),
            self.collectionView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            self.spinner.centerXAnchor.constraint(equalTo: self.collectionView.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: self.collectionView.centerYAnchor)
        ])
    }

    private func loadCatalog() {
        self.spinner.startAnimating()
        self.loadDisposable?.dispose()
        self.loadDisposable = (self.context.engine.payments.cachedStarGifts()
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] items in
            guard let self else { return }
            self.spinner.stopAnimating()
            let generic: [StarGift.Gift] = (items ?? []).compactMap { entry in
                if case let .generic(gift) = entry {
                    return gift
                }
                return nil
            }
            let upgradable = generic.filter { $0.upgradeStars != nil || ($0.availability?.resale ?? 0) > 0 }
            let source = upgradable.isEmpty ? generic : upgradable
            self.allGifts = source.sorted { lhs, rhs in
                let lResale = lhs.availability?.resale ?? 0
                let rResale = rhs.availability?.resale ?? 0
                if lResale != rResale { return lResale > rResale }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
            self.applyFilter()
            if self.allGifts.isEmpty {
                let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
                self.statusLabel.text = ru ? "Telegram не вернул каталог подарков." : "Telegram returned no gift catalog."
            }
        })
    }

    private func applyFilter() {
        let q = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            self.filteredGifts = self.allGifts
        } else {
            self.filteredGifts = self.allGifts.filter { gift in
                let title = (gift.title ?? "").lowercased()
                return title.contains(q) || String(gift.id).contains(q)
            }
        }
        self.collectionView.reloadData()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchQuery = searchText
        self.applyFilter()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.filteredGifts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GiftCell", for: indexPath) as? FullGramNFTComponentCell else {
            return UICollectionViewCell()
        }
        let gift = self.filteredGifts[indexPath.item]
        let label = (gift.title?.isEmpty == false) ? gift.title! : "Gift #\(gift.id)"
        cell.configure(
            context: self.context,
            presentationData: self.presentationData,
            subject: .starGift(gift: gift, price: ""),
            ribbon: nil,
            title: label,
            selected: false
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.searchBar.resignFirstResponder()
        let gift = self.filteredGifts[indexPath.item]
        let studio = FullGramNFTStudioViewController(
            context: self.context,
            targetPeerId: self.targetPeerId,
            targetDisplayName: self.targetDisplayName,
            targetEnginePeerId: self.targetEnginePeerId,
            gift: gift,
            isSponsorSelfMode: self.isSponsorSelfMode
        )
        self.push(studio)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cols: CGFloat = 4.0
        let totalSpacing: CGFloat = 20.0 + (cols - 1.0) * 6.0
        let side = floor(max(72.0, (collectionView.bounds.width - totalSpacing) / cols))
        return CGSize(width: side, height: side + 18.0)
    }
}

// MARK: - 2. Компактная студия NFT (без перекрытий, 4 колонки, отправка в чат)

private final class FullGramNFTStudioViewController: ViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private enum PickerTab: Int {
        case models = 0
        case backdrops = 1
        case patterns = 2
    }

    private let context: AccountContext
    private let targetPeerId: Int64
    private let targetDisplayName: String
    private let targetEnginePeerId: EnginePeer.Id?
    private let gift: StarGift.Gift
    private let isSponsorSelfMode: Bool
    private var presentationData: PresentationData

    private var models: [StarGift.UniqueGift.Attribute] = []
    private var backdrops: [StarGift.UniqueGift.Attribute] = []
    private var patterns: [StarGift.UniqueGift.Attribute] = []

    private var selectedModelIndex: Int = 0
    private var selectedBackdropIndex: Int = 0
    private var selectedPatternIndex: Int = 0
    private var collectionNumber: Int32 = Int32.random(in: 1 ... 9999)
    private var activeTab: PickerTab = .models
    private var notifyInChat: Bool = true
    private var isGranting = false

    private let previewCardContainer = UIView()
    private let previewHost = ComponentView<Empty>()
    private let previewTitleLabel = UILabel()
    private let previewDetailsLabel = UILabel()
    private let numberButton = UIButton(type: .system)
    private let randomButton = UIButton(type: .system)
    private let chatToggleButton = UIButton(type: .system)
    private let grantButton = UIButton(type: .system)
    private let segmentedControl = UISegmentedControl(items: ["Модели", "Фоны", "Узоры"])
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var collectionView: UICollectionView!
    private var headerTopConstraint: NSLayoutConstraint?

    private var attributesDisposable: Disposable?

    private var collectionTitle: String {
        let raw = (self.gift.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "NFT" : raw
    }

    init(
        context: AccountContext,
        targetPeerId: Int64,
        targetDisplayName: String,
        targetEnginePeerId: EnginePeer.Id?,
        gift: StarGift.Gift,
        isSponsorSelfMode: Bool = false
    ) {
        self.context = context
        self.targetPeerId = targetPeerId
        self.targetDisplayName = targetDisplayName
        self.targetEnginePeerId = targetEnginePeerId
        self.gift = gift
        self.isSponsorSelfMode = isSponsorSelfMode
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = self.collectionTitle
    }

    @available(*, unavailable)
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.attributesDisposable?.dispose()
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
        self.setupUI()
        self.loadAttributes()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.headerTopConstraint?.constant = topInset + 6.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
        self.collectionView?.collectionViewLayout.invalidateLayout()
    }

    private func setupUI() {
        let theme = self.presentationData.theme
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let root = self.displayNode.view

        let headerCard = UIView()
        headerCard.translatesAutoresizingMaskIntoConstraints = false
        headerCard.backgroundColor = theme.list.itemBlocksBackgroundColor
        headerCard.layer.cornerRadius = 14.0
        headerCard.layer.cornerCurve = .continuous

        self.previewCardContainer.translatesAutoresizingMaskIntoConstraints = false
        self.previewCardContainer.backgroundColor = .clear
        self.previewCardContainer.clipsToBounds = true
        self.previewCardContainer.layer.cornerRadius = 12.0

        self.previewTitleLabel.font = UIFont.systemFont(ofSize: 14.5, weight: .bold)
        self.previewTitleLabel.textColor = theme.list.itemPrimaryTextColor
        self.previewTitleLabel.numberOfLines = 1
        self.previewTitleLabel.lineBreakMode = .byTruncatingTail

        self.previewDetailsLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        self.previewDetailsLabel.textColor = theme.list.itemSecondaryTextColor
        self.previewDetailsLabel.numberOfLines = 2
        self.previewDetailsLabel.lineBreakMode = .byTruncatingTail

        var numCfg = UIButton.Configuration.tinted()
        var numTitle = AttributedString("#\(self.collectionNumber)")
        numTitle.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        numCfg.attributedTitle = numTitle
        numCfg.cornerStyle = .capsule
        numCfg.baseBackgroundColor = theme.list.itemAccentColor
        numCfg.baseForegroundColor = theme.list.itemAccentColor
        numCfg.contentInsets = NSDirectionalEdgeInsets(top: 4.0, leading: 8.0, bottom: 4.0, trailing: 8.0)
        self.numberButton.configuration = numCfg
        self.numberButton.setContentHuggingPriority(.required, for: .horizontal)
        self.numberButton.addTarget(self, action: #selector(self.editNumberTapped), for: .touchUpInside)

        var randCfg = UIButton.Configuration.tinted()
        var randTitle = AttributedString("🎲")
        randTitle.font = UIFont.systemFont(ofSize: 12.5)
        randCfg.attributedTitle = randTitle
        randCfg.cornerStyle = .capsule
        randCfg.baseBackgroundColor = theme.list.itemSecondaryTextColor
        randCfg.baseForegroundColor = theme.list.itemPrimaryTextColor
        randCfg.contentInsets = NSDirectionalEdgeInsets(top: 4.0, leading: 8.0, bottom: 4.0, trailing: 8.0)
        self.randomButton.configuration = randCfg
        self.randomButton.setContentHuggingPriority(.required, for: .horizontal)
        self.randomButton.addTarget(self, action: #selector(self.randomizeTapped), for: .touchUpInside)

        self.chatToggleButton.setContentHuggingPriority(.required, for: .horizontal)
        self.chatToggleButton.addTarget(self, action: #selector(self.toggleNotifyInChat), for: .touchUpInside)
        self.updateChatToggleAppearance()

        var grantCfg = UIButton.Configuration.filled()
        var grantTitle = AttributedString(ru ? "Выдать" : "Grant")
        grantTitle.font = UIFont.systemFont(ofSize: 12.5, weight: .bold)
        grantCfg.attributedTitle = grantTitle
        grantCfg.cornerStyle = .capsule
        grantCfg.baseBackgroundColor = theme.list.itemAccentColor
        grantCfg.baseForegroundColor = .white
        grantCfg.contentInsets = NSDirectionalEdgeInsets(top: 5.0, leading: 10.0, bottom: 5.0, trailing: 10.0)
        self.grantButton.configuration = grantCfg
        self.grantButton.addTarget(self, action: #selector(self.grantTapped), for: .touchUpInside)

        let controlsRow = UIStackView(arrangedSubviews: [self.numberButton, self.randomButton, self.chatToggleButton, self.grantButton])
        controlsRow.axis = .horizontal
        controlsRow.spacing = 5.0
        controlsRow.alignment = .center
        controlsRow.distribution = .fill

        let rightStack = UIStackView(arrangedSubviews: [self.previewTitleLabel, self.previewDetailsLabel, controlsRow])
        rightStack.axis = .vertical
        rightStack.spacing = 5.0
        rightStack.alignment = .fill
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        headerCard.addSubview(self.previewCardContainer)
        headerCard.addSubview(rightStack)

        self.segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        self.segmentedControl.setTitle(ru ? "Модели" : "Models", forSegmentAt: 0)
        self.segmentedControl.setTitle(ru ? "Фоны" : "Backdrops", forSegmentAt: 1)
        self.segmentedControl.setTitle(ru ? "Узоры" : "Patterns", forSegmentAt: 2)
        self.segmentedControl.selectedSegmentIndex = 0
        self.segmentedControl.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.segmentedControl.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 6.0
        layout.minimumLineSpacing = 6.0
        layout.sectionInset = UIEdgeInsets(top: 6.0, left: 10.0, bottom: 20.0, right: 10.0)

        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView.backgroundColor = .clear
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.register(FullGramNFTComponentCell.self, forCellWithReuseIdentifier: "AttrCell")
        self.collectionView.register(FullGramNFTBackdropCell.self, forCellWithReuseIdentifier: "BackdropCell")

        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.hidesWhenStopped = true

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        insertBelowNav(self.collectionView)
        insertBelowNav(self.segmentedControl)
        insertBelowNav(headerCard)
        insertBelowNav(self.spinner)

        let topC = headerCard.topAnchor.constraint(equalTo: root.topAnchor, constant: 92.0)
        self.headerTopConstraint = topC

        NSLayoutConstraint.activate([
            topC,
            headerCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10.0),
            headerCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10.0),

            self.previewCardContainer.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 8.0),
            self.previewCardContainer.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 8.0),
            self.previewCardContainer.bottomAnchor.constraint(lessThanOrEqualTo: headerCard.bottomAnchor, constant: -8.0),
            self.previewCardContainer.widthAnchor.constraint(equalToConstant: 86.0),
            self.previewCardContainer.heightAnchor.constraint(equalToConstant: 86.0),

            rightStack.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 8.0),
            rightStack.leadingAnchor.constraint(equalTo: self.previewCardContainer.trailingAnchor, constant: 10.0),
            rightStack.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -8.0),
            rightStack.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -8.0),

            self.segmentedControl.topAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: 6.0),
            self.segmentedControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10.0),
            self.segmentedControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10.0),
            self.segmentedControl.heightAnchor.constraint(equalToConstant: 30.0),

            self.collectionView.topAnchor.constraint(equalTo: self.segmentedControl.bottomAnchor, constant: 4.0),
            self.collectionView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            self.spinner.centerXAnchor.constraint(equalTo: self.collectionView.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: self.collectionView.centerYAnchor)
        ])

        self.refreshPreview()
    }

    private func updateChatToggleAppearance() {
        let theme = self.presentationData.theme
        var cfg = UIButton.Configuration.tinted()
        var title = AttributedString(self.notifyInChat ? "💬✓" : "💬")
        title.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        cfg.attributedTitle = title
        cfg.cornerStyle = .capsule
        cfg.baseBackgroundColor = self.notifyInChat ? UIColor.systemGreen : theme.list.itemSecondaryTextColor
        cfg.baseForegroundColor = self.notifyInChat ? UIColor.systemGreen : theme.list.itemSecondaryTextColor
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 4.0, leading: 7.0, bottom: 4.0, trailing: 7.0)
        self.chatToggleButton.configuration = cfg
    }

    @objc private func toggleNotifyInChat() {
        self.notifyInChat.toggle()
        self.updateChatToggleAppearance()
    }

    private func loadAttributes() {
        self.spinner.startAnimating()
        self.grantButton.isEnabled = false
        self.attributesDisposable?.dispose()
        self.attributesDisposable = (self.context.engine.payments.getStarGiftUpgradeAttributes(giftId: self.gift.id)
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] attributes in
            guard let self else { return }
            self.spinner.stopAnimating()
            let list = attributes ?? []
            self.models = list.filter { if case .model = $0 { return true } else { return false } }
            self.backdrops = list.filter { if case .backdrop = $0 { return true } else { return false } }
            self.patterns = list.filter { if case .pattern = $0 { return true } else { return false } }
            self.selectedModelIndex = 0
            self.selectedBackdropIndex = 0
            self.selectedPatternIndex = 0

            let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
            self.segmentedControl.setTitle("\(ru ? "Модели" : "Models") \(self.models.count)", forSegmentAt: 0)
            self.segmentedControl.setTitle("\(ru ? "Фоны" : "Backdrops") \(self.backdrops.count)", forSegmentAt: 1)
            self.segmentedControl.setTitle("\(ru ? "Узоры" : "Patterns") \(self.patterns.count)", forSegmentAt: 2)

            self.grantButton.isEnabled = !self.models.isEmpty && !self.backdrops.isEmpty && !self.patterns.isEmpty
            self.refreshPreview()
            self.collectionView.reloadData()
        })
    }

    private var selectedModel: StarGift.UniqueGift.Attribute? {
        guard self.selectedModelIndex >= 0 && self.selectedModelIndex < self.models.count else { return nil }
        return self.models[self.selectedModelIndex]
    }

    private var selectedBackdrop: StarGift.UniqueGift.Attribute? {
        guard self.selectedBackdropIndex >= 0 && self.selectedBackdropIndex < self.backdrops.count else { return nil }
        return self.backdrops[self.selectedBackdropIndex]
    }

    private var selectedPattern: StarGift.UniqueGift.Attribute? {
        guard self.selectedPatternIndex >= 0 && self.selectedPatternIndex < self.patterns.count else { return nil }
        return self.patterns[self.selectedPatternIndex]
    }

    private func refreshPreview() {
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        self.previewTitleLabel.text = "\(self.collectionTitle) #\(self.collectionNumber)"

        var numCfg = self.numberButton.configuration ?? UIButton.Configuration.tinted()
        var numAttr = AttributedString("#\(self.collectionNumber)")
        numAttr.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        numCfg.attributedTitle = numAttr
        self.numberButton.configuration = numCfg

        guard let model = self.selectedModel,
              let backdrop = self.selectedBackdrop,
              let pattern = self.selectedPattern else {
            self.previewDetailsLabel.text = ru ? "Загрузка моделей, фонов и узоров…" : "Loading…"
            return
        }

        let modelName: String
        if case let .model(name, _, _, _) = model { modelName = name } else { modelName = "—" }
        let backdropName: String
        var ribbonColor: GiftItemComponent.Ribbon.Color = .blue
        if case let .backdrop(name, _, inner, outer, _, _, _) = backdrop {
            backdropName = name
            ribbonColor = .custom(outer, inner)
        } else {
            backdropName = "—"
        }
        let patternName: String
        if case let .pattern(name, _, _) = pattern { patternName = name } else { patternName = "—" }

        self.previewDetailsLabel.text = "\(modelName) • \(backdropName) • \(patternName)"

        let unique = StarGift.UniqueGift(
            id: self.gift.id &+ Int64(self.collectionNumber),
            giftId: self.gift.id,
            title: self.collectionTitle,
            number: self.collectionNumber,
            slug: "FullGram-\(self.gift.id)-\(self.collectionNumber)",
            owner: .name(self.targetDisplayName),
            attributes: [model, pattern, backdrop],
            availability: StarGift.UniqueGift.Availability(issued: max(1, self.collectionNumber), total: max(self.collectionNumber, 10000)),
            giftAddress: nil,
            resellAmounts: nil,
            resellForTonOnly: false,
            releasedBy: nil,
            valueAmount: nil,
            valueCurrency: nil,
            valueUsdAmount: nil,
            flags: [],
            themePeerId: nil,
            peerColor: nil,
            hostPeerId: nil,
            minOfferStars: nil,
            craftChancePermille: nil
        )

        let previewSize = CGSize(width: 86.0, height: 86.0)
        let _ = self.previewHost.update(
            transition: .immediate,
            component: AnyComponent(GiftItemComponent(
                context: self.context,
                theme: self.presentationData.theme,
                strings: self.presentationData.strings,
                subject: .uniqueGift(gift: unique, price: nil),
                ribbon: GiftItemComponent.Ribbon(text: "#\(self.collectionNumber)", color: ribbonColor),
                mode: .profile
            )),
            environment: {},
            containerSize: previewSize
        )
        if let view = self.previewHost.view {
            if view.superview !== self.previewCardContainer {
                view.removeFromSuperview()
                self.previewCardContainer.addSubview(view)
            }
            view.frame = CGRect(origin: .zero, size: previewSize)
            view.isUserInteractionEnabled = false
        }
    }

    @objc private func tabChanged() {
        self.activeTab = PickerTab(rawValue: self.segmentedControl.selectedSegmentIndex) ?? .models
        self.collectionView.reloadData()
        self.collectionView.setContentOffset(.zero, animated: false)
    }

    @objc private func editNumberTapped() {
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let alert = UIAlertController(
            title: ru ? "Номер коллекции NFT" : "NFT collection number",
            message: ru ? "Введите номер (например 1, 777, 1337):" : "Enter number (e.g. 1, 777, 1337):",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = String(self.collectionNumber)
            tf.keyboardType = .numberPad
            tf.placeholder = "777"
        }
        alert.addAction(UIAlertAction(title: ru ? "Применить" : "Apply", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let raw = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let num = Int32(raw), num >= 1 {
                self.collectionNumber = min(9_999_999, num)
                self.refreshPreview()
            }
        }))
        alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
        self.present(alert, animated: true)
    }

    @objc private func randomizeTapped() {
        if !self.models.isEmpty {
            self.selectedModelIndex = Int.random(in: 0 ..< self.models.count)
        }
        if !self.backdrops.isEmpty {
            self.selectedBackdropIndex = Int.random(in: 0 ..< self.backdrops.count)
        }
        if !self.patterns.isEmpty {
            self.selectedPatternIndex = Int.random(in: 0 ..< self.patterns.count)
        }
        self.collectionNumber = Int32.random(in: 1 ... 9999)
        self.refreshPreview()
        self.collectionView.reloadData()
    }

    @objc private func grantTapped() {
        guard !self.isGranting,
              let model = self.selectedModel,
              let backdrop = self.selectedBackdrop,
              let pattern = self.selectedPattern else {
            return
        }
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")

        let modelName: String
        if case let .model(name, _, _, _) = model { modelName = name } else { modelName = "" }
        let backdropName: String
        let backdropId: Int32?
        if case let .backdrop(name, id, _, _, _, _, _) = backdrop {
            backdropName = name
            backdropId = id
        } else {
            backdropName = ""
            backdropId = nil
        }
        let patternName: String
        if case let .pattern(name, _, _) = pattern { patternName = name } else { patternName = "" }

        self.isGranting = true
        self.grantButton.isEnabled = false
        var cfg = self.grantButton.configuration ?? UIButton.Configuration.filled()
        var waitTitle = AttributedString("…")
        waitTitle.font = UIFont.systemFont(ofSize: 12.5, weight: .bold)
        cfg.attributedTitle = waitTitle
        self.grantButton.configuration = cfg

        let cleanPeerId = FullGramGrantedNFTStore.normalizedTelegramId(for: self.targetPeerId)
        let giftId = self.gift.id
        let title = self.collectionTitle
        let number = self.collectionNumber
        let shouldNotifyChat = self.notifyInChat

        let handleGrantResult: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isGranting = false
                    self.grantButton.isEnabled = true
                    var resetCfg = self.grantButton.configuration ?? UIButton.Configuration.filled()
                    var resetTitle = AttributedString(ru ? "Выдать" : "Grant")
                    resetTitle.font = UIFont.systemFont(ofSize: 12.5, weight: .bold)
                    resetCfg.attributedTitle = resetTitle
                    self.grantButton.configuration = resetCfg

                    switch result {
                    case let .success(entryId):
                        let localNFT = FullGramGrantedNFT(
                            id: entryId,
                            giftId: String(giftId),
                            title: title,
                            modelName: modelName,
                            backdropName: backdropName,
                            backdropId: backdropId,
                            patternName: patternName,
                            number: number,
                            note: "",
                            pinned: true
                        )
                        FullGramGrantedNFTStore.shared.appendLocal(peerId: cleanPeerId, nft: localNFT)
                        FullGramGrantedNFTStore.shared.refreshNow { _ in }

                        if shouldNotifyChat, let chatPeerId = self.targetEnginePeerId {
                            let displayTitle = FullGramGrantedNFT.decoratedTitle(title)
                            let chatMsg = FullGramChatGiftPayload(
                                kind: .nft,
                                giftRecordId: localNFT.id,
                                title: displayTitle,
                                emoji: "🎁",
                                number: number,
                                starsPrice: 0,
                                modelName: modelName,
                                backdropName: backdropName,
                                backdropInnerHex: 0x3E7BF2,
                                backdropOuterHex: 0x1A397A,
                                patternName: patternName,
                                rarityText: "Редкий NFT FullGram",
                                comment: "",
                                canUpgrade: true,
                                senderName: "FullGram",
                                slug: "FullGram-\(giftId)-\(number)"
                            ).encodeMessageText()
                            let _ = enqueueMessages(
                                account: self.context.account,
                                peerId: chatPeerId,
                                messages: [
                                    .message(
                                        text: chatMsg,
                                        attributes: [],
                                        inlineStickers: [:],
                                        mediaReference: nil,
                                        threadId: nil,
                                        replyToMessageId: nil,
                                        replyToStoryId: nil,
                                        localGroupingKey: nil,
                                        correlationId: nil,
                                        bubbleUpEmojiOrStickersets: []
                                    )
                                ]
                            ).startStandalone()
                        }

                        let decorated = FullGramGrantedNFT.decoratedTitle(title)
                        let banner = UndoOverlayController(
                            presentationData: self.presentationData,
                            content: .succeed(
                                text: ru
                                    ? "NFT «\(decorated) #\(number)» выдан пользователю \(self.targetDisplayName)!"
                                    : "NFT \"\(decorated) #\(number)\" granted to \(self.targetDisplayName)!",
                                timeout: 4.0,
                                customUndoText: nil
                            ),
                            elevatedLayout: false,
                            action: { _ in return false }
                        )
                        self.present(banner, in: .window(.root))
                    case let .failure(error):
                        let alert = UIAlertController(
                            title: ru ? "Ошибка выдачи NFT" : "Failed to grant NFT",
                            message: error.localizedDescription,
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }

        if self.isSponsorSelfMode {
            FullGramAdmin.shared.grantSponsorNFT(
                actorPeerId: self.context.account.peerId.id._internalGetInt64Value(),
                targetPeerId: cleanPeerId,
                giftId: giftId,
                title: title,
                modelName: modelName,
                backdropName: backdropName,
                backdropId: backdropId,
                patternName: patternName,
                number: number,
                note: "",
                pinned: true,
                completion: handleGrantResult
            )
        } else {
            FullGramAdmin.shared.grantNFT(
                peerId: cleanPeerId,
                giftId: giftId,
                title: title,
                modelName: modelName,
                backdropName: backdropName,
                backdropId: backdropId,
                patternName: patternName,
                number: number,
                note: "",
                pinned: true,
                completion: handleGrantResult
            )
        }
    }

    // MARK: - UICollectionViewDataSource / Delegate

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch self.activeTab {
        case .models: return self.models.count
        case .backdrops: return self.backdrops.count
        case .patterns: return self.patterns.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch self.activeTab {
        case .models:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AttrCell", for: indexPath) as? FullGramNFTComponentCell else {
                return UICollectionViewCell()
            }
            let attr = self.models[indexPath.item]
            var name = ""
            var rarity: StarGift.UniqueGift.Attribute.Rarity?
            if case let .model(n, _, r, _) = attr {
                name = n
                rarity = r
            }
            var previewAttrs: [StarGift.UniqueGift.Attribute] = [attr]
            if let backdrop = self.selectedBackdrop { previewAttrs.append(backdrop) }
            if let pattern = self.selectedPattern { previewAttrs.append(pattern) }
            cell.configure(
                context: self.context,
                presentationData: self.presentationData,
                subject: .preview(attributes: previewAttrs, rarity: rarity),
                ribbon: nil,
                title: name,
                selected: indexPath.item == self.selectedModelIndex
            )
            return cell

        case .backdrops:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "BackdropCell", for: indexPath) as? FullGramNFTBackdropCell else {
                return UICollectionViewCell()
            }
            let attr = self.backdrops[indexPath.item]
            if case let .backdrop(name, _, inner, outer, _, _, _) = attr {
                cell.configure(
                    title: name,
                    innerColor: UIColor(rgb: UInt32(bitPattern: inner)),
                    outerColor: UIColor(rgb: UInt32(bitPattern: outer)),
                    selected: indexPath.item == self.selectedBackdropIndex,
                    theme: self.presentationData.theme
                )
            }
            return cell

        case .patterns:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AttrCell", for: indexPath) as? FullGramNFTComponentCell else {
                return UICollectionViewCell()
            }
            let attr = self.patterns[indexPath.item]
            var name = ""
            var rarity: StarGift.UniqueGift.Attribute.Rarity?
            if case let .pattern(n, _, r) = attr {
                name = n
                rarity = r
            }
            var previewAttrs: [StarGift.UniqueGift.Attribute] = [attr]
            if let backdrop = self.selectedBackdrop { previewAttrs.append(backdrop) }
            cell.configure(
                context: self.context,
                presentationData: self.presentationData,
                subject: .preview(attributes: previewAttrs, rarity: rarity),
                ribbon: nil,
                title: name,
                selected: indexPath.item == self.selectedPatternIndex
            )
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch self.activeTab {
        case .models:
            self.selectedModelIndex = indexPath.item
        case .backdrops:
            self.selectedBackdropIndex = indexPath.item
        case .patterns:
            self.selectedPatternIndex = indexPath.item
        }
        self.refreshPreview()
        collectionView.reloadData()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cols: CGFloat = 4.0
        let totalSpacing: CGFloat = 20.0 + (cols - 1.0) * 6.0
        let side = floor(max(72.0, (collectionView.bounds.width - totalSpacing) / cols))
        return CGSize(width: side, height: side + 18.0)
    }
}

// MARK: - 3. Компактные ячейки сетки превью (4 колонки)

private final class FullGramNFTComponentCell: UICollectionViewCell {
    private let host = ComponentView<Empty>()
    private let cardContainer = UIView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layer.cornerRadius = 11.0
        self.contentView.layer.cornerCurve = .continuous
        self.contentView.clipsToBounds = true

        self.cardContainer.translatesAutoresizingMaskIntoConstraints = false
        self.cardContainer.clipsToBounds = true
        self.cardContainer.layer.cornerRadius = 9.0
        self.cardContainer.layer.cornerCurve = .continuous
        self.contentView.addSubview(self.cardContainer)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 10.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)

        NSLayoutConstraint.activate([
            self.cardContainer.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 3.0),
            self.cardContainer.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 3.0),
            self.cardContainer.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -3.0),
            self.cardContainer.heightAnchor.constraint(equalTo: self.cardContainer.widthAnchor),

            self.titleLabel.topAnchor.constraint(equalTo: self.cardContainer.bottomAnchor, constant: 2.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 2.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -2.0),
            self.titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: self.contentView.bottomAnchor, constant: -2.0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let v = self.host.view {
            v.frame = self.cardContainer.bounds
        }
    }

    func configure(
        context: AccountContext,
        presentationData: PresentationData,
        subject: GiftItemComponent.Subject,
        ribbon: GiftItemComponent.Ribbon?,
        title: String,
        selected: Bool
    ) {
        let theme = presentationData.theme
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderWidth = selected ? 2.0 : 0.5
        self.contentView.layer.borderColor = (selected ? theme.list.itemAccentColor : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)).cgColor
        self.titleLabel.text = title
        self.titleLabel.textColor = selected ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor

        let side = max(64.0, self.bounds.width - 6.0)
        let size = CGSize(width: side, height: side)
        let _ = self.host.update(
            transition: .immediate,
            component: AnyComponent(GiftItemComponent(
                context: context,
                theme: theme,
                strings: presentationData.strings,
                subject: subject,
                ribbon: ribbon,
                mode: .profile
            )),
            environment: {},
            containerSize: size
        )
        if let v = self.host.view {
            if v.superview !== self.cardContainer {
                v.removeFromSuperview()
                self.cardContainer.addSubview(v)
            }
            v.frame = CGRect(origin: .zero, size: size)
            v.isUserInteractionEnabled = false
        }
    }
}

private final class FullGramRadialGradientView: UIView {
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }

    var gradientLayer: CAGradientLayer? {
        return self.layer as? CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        if let gl = self.gradientLayer {
            gl.type = .radial
            gl.startPoint = CGPoint(x: 0.5, y: 0.5)
            gl.endPoint = CGPoint(x: 1.0, y: 1.0)
            gl.locations = [0.0, 1.0]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateColors(inner: UIColor, outer: UIColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let gl = self.gradientLayer {
            gl.type = .radial
            gl.startPoint = CGPoint(x: 0.5, y: 0.5)
            gl.endPoint = CGPoint(x: 1.0, y: 1.0)
            gl.locations = [0.0, 1.0]
            gl.colors = [inner.cgColor, outer.cgColor]
        }
        CATransaction.commit()
    }
}

private final class FullGramNFTBackdropCell: UICollectionViewCell {
    private let swatchView = FullGramRadialGradientView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layer.cornerRadius = 11.0
        self.contentView.layer.cornerCurve = .continuous
        self.contentView.clipsToBounds = true

        self.swatchView.translatesAutoresizingMaskIntoConstraints = false
        self.swatchView.layer.cornerRadius = 9.0
        self.swatchView.layer.cornerCurve = .continuous
        self.swatchView.clipsToBounds = true
        self.contentView.addSubview(self.swatchView)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 10.0, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)

        NSLayoutConstraint.activate([
            self.swatchView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 3.0),
            self.swatchView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 3.0),
            self.swatchView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -3.0),
            self.swatchView.heightAnchor.constraint(equalTo: self.swatchView.widthAnchor),

            self.titleLabel.topAnchor.constraint(equalTo: self.swatchView.bottomAnchor, constant: 2.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 2.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -2.0),
            self.titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: self.contentView.bottomAnchor, constant: -2.0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, innerColor: UIColor, outerColor: UIColor, selected: Bool, theme: PresentationTheme) {
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderWidth = selected ? 2.0 : 0.5
        self.contentView.layer.borderColor = (selected ? theme.list.itemAccentColor : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)).cgColor
        self.swatchView.updateColors(inner: innerColor, outer: outerColor)
        self.titleLabel.text = title
        self.titleLabel.textColor = selected ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
        self.setNeedsLayout()
    }
}
