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

// MARK: - 1. Каталог коллекций NFT (обновлённый просторный интерфейс Telegram Stars / NFT)

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

private final class FullGramNFTCatalogViewController: ViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate {
    private enum CatalogFilter: Int {
        case all = 0
        case popular = 1
        case rare = 2
    }

    private let context: AccountContext
    private let targetPeerId: Int64
    private let targetDisplayName: String
    private let targetEnginePeerId: EnginePeer.Id?
    private let isSponsorSelfMode: Bool
    private var presentationData: PresentationData

    private let recipientPill = UIView()
    private let recipientLabel = UILabel()
    private let searchContainer = UIView()
    private let searchIconView = UIImageView()
    private let searchField = UITextField()
    private let filterControl = UISegmentedControl(items: ["Все", "Популярные", "Лимитированные"])
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()
    private var collectionView: UICollectionView!
    private var topConstraint: NSLayoutConstraint?

    private var allGifts: [StarGift.Gift] = []
    private var filteredGifts: [StarGift.Gift] = []
    private var searchQuery: String = ""
    private var activeFilter: CatalogFilter = .all
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
        self.title = ru ? "Коллекции NFT" : "NFT Collections"
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
        self.topConstraint?.constant = topInset + 8.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
        self.collectionView?.collectionViewLayout.invalidateLayout()
    }

    private func setupUI() {
        let theme = self.presentationData.theme
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let root = self.displayNode.view

        self.recipientPill.translatesAutoresizingMaskIntoConstraints = false
        self.recipientPill.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(theme.overallDarkAppearance ? 0.16 : 0.10)
        self.recipientPill.layer.cornerRadius = 12.0
        self.recipientPill.layer.cornerCurve = .continuous

        self.recipientLabel.translatesAutoresizingMaskIntoConstraints = false
        self.recipientLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        self.recipientLabel.textColor = theme.list.itemAccentColor
        self.recipientLabel.textAlignment = .center
        self.recipientLabel.text = ru
            ? "🎁 Получатель: \(self.targetDisplayName) · ID \(self.targetPeerId)"
            : "🎁 Recipient: \(self.targetDisplayName) · ID \(self.targetPeerId)"
        self.recipientPill.addSubview(self.recipientLabel)

        self.searchContainer.translatesAutoresizingMaskIntoConstraints = false
        self.searchContainer.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.searchContainer.layer.cornerRadius = 12.0
        self.searchContainer.layer.cornerCurve = .continuous
        self.searchContainer.layer.borderWidth = 0.5
        self.searchContainer.layer.borderColor = theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35).cgColor

        self.searchIconView.translatesAutoresizingMaskIntoConstraints = false
        self.searchIconView.image = UIImage(systemName: "magnifyingglass")?.withRenderingMode(.alwaysTemplate)
        self.searchIconView.tintColor = theme.list.itemSecondaryTextColor
        self.searchIconView.contentMode = .scaleAspectFit
        self.searchContainer.addSubview(self.searchIconView)

        self.searchField.translatesAutoresizingMaskIntoConstraints = false
        self.searchField.font = UIFont.systemFont(ofSize: 14.5)
        self.searchField.textColor = theme.list.itemPrimaryTextColor
        self.searchField.attributedPlaceholder = NSAttributedString(
            string: ru ? "Поиск коллекции (Plush Pepe, Durov's Cap…)" : "Search NFT collection…",
            attributes: [.foregroundColor: theme.list.itemSecondaryTextColor]
        )
        self.searchField.clearButtonMode = .whileEditing
        self.searchField.returnKeyType = .search
        self.searchField.autocorrectionType = .no
        self.searchField.delegate = self
        self.searchField.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.searchField.addTarget(self, action: #selector(self.searchTextChanged), for: .editingChanged)
        self.searchContainer.addSubview(self.searchField)

        self.filterControl.translatesAutoresizingMaskIntoConstraints = false
        if !ru {
            self.filterControl.setTitle("All", forSegmentAt: 0)
            self.filterControl.setTitle("Popular", forSegmentAt: 1)
            self.filterControl.setTitle("Limited", forSegmentAt: 2)
        }
        self.filterControl.selectedSegmentIndex = 0
        self.filterControl.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.filterControl.addTarget(self, action: #selector(self.filterChanged), for: .valueChanged)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8.0
        layout.minimumLineSpacing = 10.0
        layout.sectionInset = UIEdgeInsets(top: 8.0, left: 12.0, bottom: 28.0, right: 12.0)

        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView.backgroundColor = .clear
        self.collectionView.keyboardDismissMode = .onDrag
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.register(FullGramNFTComponentCell.self, forCellWithReuseIdentifier: "GiftCell")

        self.spinner.translatesAutoresizingMaskIntoConstraints = false
        self.spinner.hidesWhenStopped = true

        self.emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.emptyLabel.font = UIFont.systemFont(ofSize: 13.5, weight: .medium)
        self.emptyLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.numberOfLines = 2
        self.emptyLabel.isHidden = true

        let insertBelowNav: (UIView) -> Void = { view in
            if let navView = self.navigationBar?.view, navView.superview === root {
                root.insertSubview(view, belowSubview: navView)
            } else {
                root.insertSubview(view, at: 0)
            }
        }
        insertBelowNav(self.collectionView)
        insertBelowNav(self.emptyLabel)
        insertBelowNav(self.filterControl)
        insertBelowNav(self.searchContainer)
        insertBelowNav(self.recipientPill)
        insertBelowNav(self.spinner)

        let topC = self.recipientPill.topAnchor.constraint(equalTo: root.topAnchor, constant: 92.0)
        self.topConstraint = topC

        NSLayoutConstraint.activate([
            topC,
            self.recipientPill.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.recipientPill.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),
            self.recipientPill.heightAnchor.constraint(equalToConstant: 30.0),

            self.recipientLabel.leadingAnchor.constraint(equalTo: self.recipientPill.leadingAnchor, constant: 10.0),
            self.recipientLabel.trailingAnchor.constraint(equalTo: self.recipientPill.trailingAnchor, constant: -10.0),
            self.recipientLabel.centerYAnchor.constraint(equalTo: self.recipientPill.centerYAnchor),

            self.searchContainer.topAnchor.constraint(equalTo: self.recipientPill.bottomAnchor, constant: 8.0),
            self.searchContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.searchContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),
            self.searchContainer.heightAnchor.constraint(equalToConstant: 38.0),

            self.searchIconView.leadingAnchor.constraint(equalTo: self.searchContainer.leadingAnchor, constant: 11.0),
            self.searchIconView.centerYAnchor.constraint(equalTo: self.searchContainer.centerYAnchor),
            self.searchIconView.widthAnchor.constraint(equalToConstant: 16.0),
            self.searchIconView.heightAnchor.constraint(equalToConstant: 16.0),

            self.searchField.leadingAnchor.constraint(equalTo: self.searchIconView.trailingAnchor, constant: 8.0),
            self.searchField.trailingAnchor.constraint(equalTo: self.searchContainer.trailingAnchor, constant: -8.0),
            self.searchField.topAnchor.constraint(equalTo: self.searchContainer.topAnchor),
            self.searchField.bottomAnchor.constraint(equalTo: self.searchContainer.bottomAnchor),

            self.filterControl.topAnchor.constraint(equalTo: self.searchContainer.bottomAnchor, constant: 8.0),
            self.filterControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.filterControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),
            self.filterControl.heightAnchor.constraint(equalToConstant: 30.0),

            self.collectionView.topAnchor.constraint(equalTo: self.filterControl.bottomAnchor, constant: 6.0),
            self.collectionView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            self.spinner.centerXAnchor.constraint(equalTo: self.collectionView.centerXAnchor),
            self.spinner.centerYAnchor.constraint(equalTo: self.collectionView.centerYAnchor),

            self.emptyLabel.centerXAnchor.constraint(equalTo: self.collectionView.centerXAnchor),
            self.emptyLabel.centerYAnchor.constraint(equalTo: self.collectionView.centerYAnchor),
            self.emptyLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24.0),
            self.emptyLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24.0)
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
                if lhs.price != rhs.price { return lhs.price > rhs.price }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
            self.applyFilter()
        })
    }

    private func applyFilter() {
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let q = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = self.allGifts

        switch self.activeFilter {
        case .all:
            break
        case .popular:
            list = list.filter { ($0.availability?.resale ?? 0) > 0 || $0.price >= 100 }
        case .rare:
            list = list.filter { ($0.availability?.total ?? 0) > 0 && ($0.availability?.total ?? 999999) <= 50000 }
            if list.isEmpty {
                list = self.allGifts.filter { $0.availability != nil }
            }
        }

        if !q.isEmpty {
            list = list.filter { gift in
                let title = (gift.title ?? "").lowercased()
                return title.contains(q) || String(gift.id).contains(q)
            }
        }
        self.filteredGifts = list
        self.emptyLabel.isHidden = !list.isEmpty
        self.emptyLabel.text = self.allGifts.isEmpty
            ? (ru ? "Каталог подарков загружается из Telegram…" : "Loading gift catalog…")
            : (ru ? "Ничего не найдено по запросу." : "No collections match your search.")
        self.collectionView.reloadData()
    }

    @objc private func searchTextChanged() {
        self.searchQuery = self.searchField.text ?? ""
        self.applyFilter()
    }

    @objc private func filterChanged() {
        self.activeFilter = CatalogFilter(rawValue: self.filterControl.selectedSegmentIndex) ?? .all
        self.applyFilter()
        self.collectionView.setContentOffset(.zero, animated: false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.filteredGifts.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "GiftCell", for: indexPath) as? FullGramNFTComponentCell else {
            return UICollectionViewCell()
        }
        let gift = self.filteredGifts[indexPath.item]
        let label = (gift.title?.isEmpty == false) ? gift.title! : "NFT #\(gift.id % 10000)"
        let sub: String
        if let avail = gift.availability, avail.total > 0 {
            let kStr = avail.total >= 1000 ? "\(avail.total / 1000)K" : "\(avail.total)"
            sub = "★ \(gift.price) · \(kStr)"
        } else {
            sub = "★ \(gift.price)"
        }
        let ribbon: GiftItemComponent.Ribbon? = (gift.availability?.remains == 0)
            ? GiftItemComponent.Ribbon(text: "NFT", color: .purple)
            : nil
        cell.configure(
            context: self.context,
            presentationData: self.presentationData,
            subject: .starGift(gift: gift, price: ""),
            ribbon: ribbon,
            title: label,
            subtitle: sub,
            selected: false
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        self.searchField.resignFirstResponder()
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
        let cols: CGFloat = 3.0
        let totalSpacing: CGFloat = 24.0 + (cols - 1.0) * 8.0
        let side = floor(max(96.0, (collectionView.bounds.width - totalSpacing) / cols))
        return CGSize(width: side, height: side + 34.0)
    }
}

// MARK: - 2. Студия конструктора NFT (живой радиальный градиент, редкости %, комментарий, плашка в чат)

private final class FullGramNFTStudioViewController: ViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextFieldDelegate {
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
    private var giftComment: String = ""
    private var activeTab: PickerTab = .models
    private var notifyInChat: Bool = true
    private var isGranting = false

    private let heroCard = FullGramRadialGradientView()
    private let previewCardContainer = UIView()
    private let previewHost = ComponentView<Empty>()
    private let previewTitleLabel = UILabel()
    private let previewDetailsLabel = UILabel()
    private let commentButton = UIButton(type: .system)
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
        self.headerTopConstraint?.constant = topInset + 8.0
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
        self.collectionView?.collectionViewLayout.invalidateLayout()
    }

    private static func formatRarity(_ rarity: StarGift.UniqueGift.Attribute.Rarity?) -> String {
        guard let rarity else { return "" }
        switch rarity {
        case let .permille(val):
            let pct = Double(val) / 10.0
            if pct < 1.0 {
                return String(format: "%.2f%%", pct).replacingOccurrences(of: "0%", with: "%")
            }
            return String(format: "%.1f%%", pct)
        default:
            return "Rare"
        }
    }

    private func setupUI() {
        let theme = self.presentationData.theme
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let root = self.displayNode.view

        self.heroCard.translatesAutoresizingMaskIntoConstraints = false
        self.heroCard.layer.cornerRadius = 20.0
        self.heroCard.layer.cornerCurve = .continuous
        self.heroCard.clipsToBounds = true
        self.heroCard.updateColors(inner: UIColor(rgb: 0x3E7BF2), outer: UIColor(rgb: 0x182C61))

        self.previewCardContainer.translatesAutoresizingMaskIntoConstraints = false
        self.previewCardContainer.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        self.previewCardContainer.clipsToBounds = true
        self.previewCardContainer.layer.cornerRadius = 16.0
        self.previewCardContainer.layer.cornerCurve = .continuous
        self.previewCardContainer.layer.borderWidth = 1.0
        self.previewCardContainer.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor

        self.previewTitleLabel.font = UIFont.systemFont(ofSize: 16.5, weight: .bold)
        self.previewTitleLabel.textColor = .white
        self.previewTitleLabel.numberOfLines = 1
        self.previewTitleLabel.lineBreakMode = .byTruncatingTail

        self.previewDetailsLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        self.previewDetailsLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        self.previewDetailsLabel.numberOfLines = 2
        self.previewDetailsLabel.lineBreakMode = .byTruncatingTail

        let stylePill: (UIButton, String) -> Void = { btn, text in
            var cfg = UIButton.Configuration.plain()
            var attr = AttributedString(text)
            attr.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
            cfg.attributedTitle = attr
            cfg.cornerStyle = .capsule
            cfg.baseForegroundColor = .white
            cfg.background.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 5.0, leading: 10.0, bottom: 5.0, trailing: 10.0)
            btn.configuration = cfg
        }

        stylePill(self.numberButton, "#\(self.collectionNumber)")
        self.numberButton.addTarget(self, action: #selector(self.editNumberTapped), for: .touchUpInside)

        stylePill(self.randomButton, ru ? "🎲 Случайно" : "🎲 Random")
        self.randomButton.addTarget(self, action: #selector(self.randomizeTapped), for: .touchUpInside)

        stylePill(self.commentButton, ru ? "✍️ Подпись" : "✍️ Note")
        self.commentButton.addTarget(self, action: #selector(self.editCommentTapped), for: .touchUpInside)

        self.chatToggleButton.addTarget(self, action: #selector(self.toggleNotifyInChat), for: .touchUpInside)
        self.updateChatToggleAppearance()

        let chipsRow = UIStackView(arrangedSubviews: [self.numberButton, self.randomButton, self.commentButton])
        chipsRow.axis = .horizontal
        chipsRow.spacing = 6.0
        chipsRow.alignment = .center
        chipsRow.distribution = .fillProportionally

        var grantCfg = UIButton.Configuration.filled()
        var grantTitle = AttributedString(ru ? "🎁 Отправить NFT" : "🎁 Send NFT")
        grantTitle.font = UIFont.systemFont(ofSize: 13.5, weight: .bold)
        grantCfg.attributedTitle = grantTitle
        grantCfg.cornerStyle = .capsule
        grantCfg.baseBackgroundColor = .white
        grantCfg.baseForegroundColor = UIColor(rgb: 0x162242)
        grantCfg.contentInsets = NSDirectionalEdgeInsets(top: 7.0, leading: 14.0, bottom: 7.0, trailing: 14.0)
        self.grantButton.configuration = grantCfg
        self.grantButton.addTarget(self, action: #selector(self.grantTapped), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [self.chatToggleButton, self.grantButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 6.0
        actionRow.alignment = .center
        actionRow.distribution = .fill

        let rightStack = UIStackView(arrangedSubviews: [self.previewTitleLabel, self.previewDetailsLabel, chipsRow, actionRow])
        rightStack.axis = .vertical
        rightStack.spacing = 6.0
        rightStack.alignment = .leading
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        self.heroCard.addSubview(self.previewCardContainer)
        self.heroCard.addSubview(rightStack)

        self.segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        self.segmentedControl.setTitle(ru ? "Модели" : "Models", forSegmentAt: 0)
        self.segmentedControl.setTitle(ru ? "Фоны" : "Backdrops", forSegmentAt: 1)
        self.segmentedControl.setTitle(ru ? "Узоры" : "Patterns", forSegmentAt: 2)
        self.segmentedControl.selectedSegmentIndex = 0
        self.segmentedControl.overrideUserInterfaceStyle = theme.overallDarkAppearance ? .dark : .light
        self.segmentedControl.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8.0
        layout.minimumLineSpacing = 10.0
        layout.sectionInset = UIEdgeInsets(top: 8.0, left: 12.0, bottom: 26.0, right: 12.0)

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
        insertBelowNav(self.heroCard)
        insertBelowNav(self.spinner)

        let topC = self.heroCard.topAnchor.constraint(equalTo: root.topAnchor, constant: 92.0)
        self.headerTopConstraint = topC

        NSLayoutConstraint.activate([
            topC,
            self.heroCard.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.heroCard.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),

            self.previewCardContainer.centerYAnchor.constraint(equalTo: self.heroCard.centerYAnchor),
            self.previewCardContainer.leadingAnchor.constraint(equalTo: self.heroCard.leadingAnchor, constant: 12.0),
            self.previewCardContainer.widthAnchor.constraint(equalToConstant: 102.0),
            self.previewCardContainer.heightAnchor.constraint(equalToConstant: 102.0),

            rightStack.topAnchor.constraint(equalTo: self.heroCard.topAnchor, constant: 12.0),
            rightStack.leadingAnchor.constraint(equalTo: self.previewCardContainer.trailingAnchor, constant: 12.0),
            rightStack.trailingAnchor.constraint(equalTo: self.heroCard.trailingAnchor, constant: -12.0),
            rightStack.bottomAnchor.constraint(equalTo: self.heroCard.bottomAnchor, constant: -12.0),

            self.segmentedControl.topAnchor.constraint(equalTo: self.heroCard.bottomAnchor, constant: 8.0),
            self.segmentedControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12.0),
            self.segmentedControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12.0),
            self.segmentedControl.heightAnchor.constraint(equalToConstant: 32.0),

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
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        var cfg = UIButton.Configuration.plain()
        let text = self.notifyInChat ? (ru ? "💬 В чат ✓" : "💬 Chat ✓") : (ru ? "💬 Без чата" : "💬 No chat")
        var title = AttributedString(text)
        title.font = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        cfg.attributedTitle = title
        cfg.cornerStyle = .capsule
        cfg.baseForegroundColor = .white
        cfg.background.backgroundColor = self.notifyInChat
            ? UIColor(rgb: 0x10B981).withAlphaComponent(0.45)
            : UIColor.white.withAlphaComponent(0.15)
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6.0, leading: 10.0, bottom: 6.0, trailing: 10.0)
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
            self.segmentedControl.setTitle("\(ru ? "Модели" : "Models") (\(self.models.count))", forSegmentAt: 0)
            self.segmentedControl.setTitle("\(ru ? "Фоны" : "Backdrops") (\(self.backdrops.count))", forSegmentAt: 1)
            self.segmentedControl.setTitle("\(ru ? "Узоры" : "Patterns") (\(self.patterns.count))", forSegmentAt: 2)

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

        var numCfg = self.numberButton.configuration ?? UIButton.Configuration.plain()
        var numAttr = AttributedString("#\(self.collectionNumber)")
        numAttr.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        numCfg.attributedTitle = numAttr
        self.numberButton.configuration = numCfg

        var noteCfg = self.commentButton.configuration ?? UIButton.Configuration.plain()
        var noteAttr = AttributedString(self.giftComment.isEmpty ? (ru ? "✍️ Подпись" : "✍️ Note") : "✍️ ✓")
        noteAttr.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        noteCfg.attributedTitle = noteAttr
        self.commentButton.configuration = noteCfg

        guard let model = self.selectedModel,
              let backdrop = self.selectedBackdrop,
              let pattern = self.selectedPattern else {
            self.previewDetailsLabel.text = ru ? "Загрузка 3D-моделей, фонов и узоров…" : "Loading…"
            return
        }

        let modelName: String
        var modelRar = ""
        if case let .model(name, _, r, _) = model {
            modelName = name
            let f = Self.formatRarity(r)
            if !f.isEmpty { modelRar = " \(f)" }
        } else {
            modelName = "—"
        }

        let backdropName: String
        var ribbonColor: GiftItemComponent.Ribbon.Color = .blue
        if case let .backdrop(name, _, inner, outer, _, _, _) = backdrop {
            backdropName = name
            ribbonColor = .custom(outer, inner)
            self.heroCard.updateColors(
                inner: UIColor(rgb: UInt32(bitPattern: inner)),
                outer: UIColor(rgb: UInt32(bitPattern: outer))
            )
        } else {
            backdropName = "—"
        }

        let patternName: String
        if case let .pattern(name, _, _) = pattern { patternName = name } else { patternName = "—" }

        self.previewDetailsLabel.text = "\(modelName)\(modelRar) • \(backdropName) • \(patternName)"

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

        let previewSize = CGSize(width: 102.0, height: 102.0)
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
            message: ru ? "Введите номер экземпляра (например 1, 777, 1337):" : "Enter number (e.g. 1, 777, 1337):",
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

    @objc private func editCommentTapped() {
        let ru = self.presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let alert = UIAlertController(
            title: ru ? "Подпись к подарку" : "Gift Message",
            message: ru ? "Текст отобразится прямо на плашке подарка в чате и в карточке NFT:" : "Displayed on the gift plaque in chat:",
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] tf in
            tf.text = self?.giftComment ?? ""
            tf.placeholder = ru ? "Например: С любовью от FullGram ✨" : "Optional message…"
        }
        alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.giftComment = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.refreshPreview()
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
        var innerHex: UInt32 = 0x3E7BF2
        var outerHex: UInt32 = 0x1A397A
        if case let .backdrop(name, id, inner, outer, _, _, _) = backdrop {
            backdropName = name
            backdropId = id
            innerHex = UInt32(bitPattern: inner)
            outerHex = UInt32(bitPattern: outer)
        } else {
            backdropName = ""
            backdropId = nil
        }
        let patternName: String
        if case let .pattern(name, _, _) = pattern { patternName = name } else { patternName = "" }

        self.isGranting = true
        self.grantButton.isEnabled = false
        var cfg = self.grantButton.configuration ?? UIButton.Configuration.filled()
        var waitTitle = AttributedString("⏳…")
        waitTitle.font = UIFont.systemFont(ofSize: 13.5, weight: .bold)
        cfg.attributedTitle = waitTitle
        self.grantButton.configuration = cfg

        let cleanPeerId = FullGramGrantedNFTStore.normalizedTelegramId(for: self.targetPeerId)
        let giftId = self.gift.id
        let title = self.collectionTitle
        let number = self.collectionNumber
        let noteText = self.giftComment
        let shouldNotifyChat = self.notifyInChat
        let capturedInnerHex = innerHex
        let capturedOuterHex = outerHex

        let handleGrantResult: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isGranting = false
                    self.grantButton.isEnabled = true
                    var resetCfg = self.grantButton.configuration ?? UIButton.Configuration.filled()
                    var resetTitle = AttributedString(ru ? "🎁 Отправить NFT" : "🎁 Send NFT")
                    resetTitle.font = UIFont.systemFont(ofSize: 13.5, weight: .bold)
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
                            note: noteText,
                            pinned: true
                        )
                        FullGramGrantedNFTStore.shared.appendLocal(peerId: cleanPeerId, nft: localNFT)
                        FullGramGrantedNFTStore.shared.refreshNow { _ in }

                        if shouldNotifyChat {
                            let resolvedChatPeerId = self.targetEnginePeerId
                                ?? EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(cleanPeerId))
                            let displayTitle = FullGramGrantedNFT.decoratedTitle(title)
                            let payload = FullGramChatGiftPayload(
                                kind: .nft,
                                giftRecordId: localNFT.id,
                                title: displayTitle,
                                emoji: "🎁",
                                number: number,
                                starsPrice: 0,
                                modelName: modelName,
                                backdropName: backdropName,
                                backdropInnerHex: capturedInnerHex,
                                backdropOuterHex: capturedOuterHex,
                                patternName: patternName,
                                rarityText: "Коллекционный NFT",
                                comment: noteText,
                                canUpgrade: false,
                                senderName: "FullGram",
                                slug: "FullGram-\(giftId)-\(number)",
                                realGiftId: giftId,
                                backdropId: backdropId
                            )
                            let (msgText, msgEntities) = payload.encodeMessageWithEntities()
                            let _ = enqueueMessages(
                                account: self.context.account,
                                peerId: resolvedChatPeerId,
                                messages: [
                                    .message(
                                        text: msgText,
                                        attributes: [TextEntitiesMessageAttribute(entities: msgEntities)],
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
                note: noteText,
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
                note: noteText,
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
                subtitle: Self.formatRarity(rarity),
                selected: indexPath.item == self.selectedModelIndex
            )
            return cell

        case .backdrops:
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "BackdropCell", for: indexPath) as? FullGramNFTBackdropCell else {
                return UICollectionViewCell()
            }
            let attr = self.backdrops[indexPath.item]
            if case let .backdrop(name, _, inner, outer, _, _, rarity) = attr {
                cell.configure(
                    title: name,
                    subtitle: Self.formatRarity(rarity),
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
                subtitle: Self.formatRarity(rarity),
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
        let cols: CGFloat = 3.0
        let totalSpacing: CGFloat = 24.0 + (cols - 1.0) * 8.0
        let side = floor(max(96.0, (collectionView.bounds.width - totalSpacing) / cols))
        return CGSize(width: side, height: side + 34.0)
    }
}

// MARK: - 3. Ячейки превью коллекций и атрибутов (просторная сетка 3 колонки)

private final class FullGramNFTComponentCell: UICollectionViewCell {
    private let host = ComponentView<Empty>()
    private let cardContainer = UIView()
    private let titleLabel = UILabel()
    private let subLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layer.cornerRadius = 15.0
        self.contentView.layer.cornerCurve = .continuous
        self.contentView.clipsToBounds = true

        self.cardContainer.translatesAutoresizingMaskIntoConstraints = false
        self.cardContainer.clipsToBounds = true
        self.cardContainer.layer.cornerRadius = 12.0
        self.cardContainer.layer.cornerCurve = .continuous
        self.contentView.addSubview(self.cardContainer)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)

        self.subLabel.translatesAutoresizingMaskIntoConstraints = false
        self.subLabel.font = UIFont.systemFont(ofSize: 10.0, weight: .medium)
        self.subLabel.textAlignment = .center
        self.subLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.subLabel)

        NSLayoutConstraint.activate([
            self.cardContainer.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 4.0),
            self.cardContainer.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.cardContainer.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),
            self.cardContainer.heightAnchor.constraint(equalTo: self.cardContainer.widthAnchor),

            self.titleLabel.topAnchor.constraint(equalTo: self.cardContainer.bottomAnchor, constant: 4.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),

            self.subLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 1.0),
            self.subLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.subLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0)
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
        subtitle: String,
        selected: Bool
    ) {
        let theme = presentationData.theme
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderWidth = selected ? 2.0 : 0.5
        self.contentView.layer.borderColor = (selected ? theme.list.itemAccentColor : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)).cgColor
        self.titleLabel.text = title
        self.titleLabel.textColor = selected ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
        self.subLabel.text = subtitle.isEmpty ? "NFT" : subtitle
        self.subLabel.textColor = selected ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor

        let side = max(76.0, self.bounds.width - 8.0)
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
            gl.startPoint = CGPoint(x: 0.5, y: 0.45)
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
            gl.startPoint = CGPoint(x: 0.5, y: 0.45)
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
    private let subLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentView.layer.cornerRadius = 15.0
        self.contentView.layer.cornerCurve = .continuous
        self.contentView.clipsToBounds = true

        self.swatchView.translatesAutoresizingMaskIntoConstraints = false
        self.swatchView.layer.cornerRadius = 12.0
        self.swatchView.layer.cornerCurve = .continuous
        self.swatchView.clipsToBounds = true
        self.contentView.addSubview(self.swatchView)

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)

        self.subLabel.translatesAutoresizingMaskIntoConstraints = false
        self.subLabel.font = UIFont.systemFont(ofSize: 10.0, weight: .medium)
        self.subLabel.textAlignment = .center
        self.subLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.subLabel)

        NSLayoutConstraint.activate([
            self.swatchView.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 4.0),
            self.swatchView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.swatchView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),
            self.swatchView.heightAnchor.constraint(equalTo: self.swatchView.widthAnchor),

            self.titleLabel.topAnchor.constraint(equalTo: self.swatchView.bottomAnchor, constant: 4.0),
            self.titleLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.titleLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0),

            self.subLabel.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor, constant: 1.0),
            self.subLabel.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 4.0),
            self.subLabel.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -4.0)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String, innerColor: UIColor, outerColor: UIColor, selected: Bool, theme: PresentationTheme) {
        self.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.contentView.layer.borderWidth = selected ? 2.0 : 0.5
        self.contentView.layer.borderColor = (selected ? theme.list.itemAccentColor : theme.list.itemBlocksSeparatorColor.withAlphaComponent(0.35)).cgColor
        self.swatchView.updateColors(inner: innerColor, outer: outerColor)
        self.titleLabel.text = title
        self.titleLabel.textColor = selected ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
        self.subLabel.text = subtitle.isEmpty ? "Backdrop" : subtitle
        self.subLabel.textColor = selected ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor
        self.setNeedsLayout()
    }
}
