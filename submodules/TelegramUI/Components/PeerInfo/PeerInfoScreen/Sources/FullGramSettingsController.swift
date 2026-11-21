import Foundation
import UIKit
import UniformTypeIdentifiers
import QuickLook
import AVFoundation
import AVKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import ItemListUI
import PresentationDataUtils
import TelegramPresentationData
import TelegramUIPreferences

/// Shared Telegram `ViewController` wrapper that hosts an embedded UIKit `UIViewController`
/// with navigation bar presentation data and safe-area inset propagation.
internal class FullGramHostedViewController<Content: UIViewController>: ViewController {
    let accountContext: AccountContext
    let hosted: Content
    private let hostTheme: PresentationTheme
    private var didAttachHosted = false

    init(context: AccountContext, title: String, makeContent: (PresentationTheme) -> Content) {
        self.accountContext = context
        let data = context.sharedContext.currentPresentationData.with { $0 }
        self.hostTheme = data.theme
        self.hosted = makeContent(data.theme)
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: data))
        self.isOpaqueWhenInOverlay = true
        self.blocksBackgroundWhenInOverlay = true
        self.title = title
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = self.hostTheme.list.blocksBackgroundColor
        self.displayNode = node
        self.displayNodeDidLoad()
    }

    override func displayNodeDidLoad() {
        super.displayNodeDidLoad()
        self.attachHostedIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.attachHostedIfNeeded()
    }

    private func attachHostedIfNeeded() {
        guard !self.didAttachHosted else { return }
        self.didAttachHosted = true
        self.addChild(self.hosted)
        self.hosted.view.frame = self.displayNode.view.bounds
        self.hosted.view.autoresizingMask = []
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.insertSubview(self.hosted.view, belowSubview: navView)
        } else {
            self.displayNode.view.insertSubview(self.hosted.view, at: 0)
        }
        self.hosted.didMove(toParent: self)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.attachHostedIfNeeded()
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bottomInset = layout.intrinsicInsets.bottom
        self.hosted.additionalSafeAreaInsets = .zero
        self.hosted.view.frame = CGRect(
            x: layout.safeInsets.left,
            y: topInset,
            width: max(0.0, layout.size.width - layout.safeInsets.left - layout.safeInsets.right),
            height: max(0.0, layout.size.height - topInset - bottomInset)
        )
        if let navView = self.navigationBar?.view, navView.superview === self.displayNode.view {
            self.displayNode.view.bringSubviewToFront(navView)
        }
    }
}

enum FullGramSettingsIcons {
    private static let iconSize = CGSize(width: 30.0, height: 30.0)
    private static let cornerRadius: CGFloat = 8.0
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 128
        return c
    }()

    static func bundleGlyph(_ bundleName: String, color: UIColor, side: CGFloat = 20.0, fallbackSystemName: String? = nil) -> UIImage? {
        let key = "fg:\(bundleName):\(color.description):\(side)" as NSString
        if let cached = self.cache.object(forKey: key) {
            return cached
        }
        let img = generateImage(Self.iconSize, rotatedContext: { size, ctx in
            let bounds = CGRect(origin: .zero, size: size)
            ctx.clear(bounds)
            ctx.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: Self.cornerRadius).cgPath)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            let glyph = UIImage(bundleImageName: bundleName)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                ?? fallbackSystemName.flatMap { UIImage(systemName: $0)?.withTintColor(.white, renderingMode: .alwaysOriginal) }
            if let glyph {
                UIGraphicsPushContext(ctx)
                let rect = CGRect(
                    x: (size.width - side) * 0.5,
                    y: (size.height - side) * 0.5,
                    width: side,
                    height: side
                )
                glyph.draw(in: rect)
                UIGraphicsPopContext()
            }
        })
        if let img {
            self.cache.setObject(img, forKey: key)
        }
        return img
    }

    static func symbol(_ systemName: String, color: UIColor, pointSize: CGFloat = 15.0) -> UIImage? {
        let key = "sym:\(systemName):\(color.description):\(pointSize)" as NSString
        if let cached = self.cache.object(forKey: key) {
            return cached
        }
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let img = generateImage(Self.iconSize, rotatedContext: { size, ctx in
            let bounds = CGRect(origin: .zero, size: size)
            ctx.clear(bounds)
            ctx.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: Self.cornerRadius).cgPath)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            if let sym = UIImage(systemName: systemName, withConfiguration: cfg)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                UIGraphicsPushContext(ctx)
                let symSize = sym.size
                let maxSide: CGFloat = 20.0
                let scale = min(1.0, min(maxSide / max(1.0, symSize.width), maxSide / max(1.0, symSize.height)))
                let drawSize = CGSize(width: symSize.width * scale, height: symSize.height * scale)
                let rect = CGRect(
                    x: (size.width - drawSize.width) * 0.5,
                    y: (size.height - drawSize.height) * 0.5,
                    width: drawSize.width,
                    height: drawSize.height
                )
                sym.draw(in: rect)
                UIGraphicsPopContext()
            }
        })
        if let img {
            self.cache.setObject(img, forKey: key)
        }
        return img
    }
}

public enum FullGramCategory: Int32, CaseIterable {
    case appearance = 0
    case chats = 1
    case privacy = 2
    case security = 3
    case antiScam = 4
    case mediaAndAudio = 5
    case plugins = 6
    case aiAssistant = 7
    case other = 8

    var title: String {
        switch self {
        case .appearance:
            return "Оформление"
        case .chats:
            return "Чаты"
        case .privacy:
            return "Приватность"
        case .security:
            return "Безопасность"
        case .antiScam:
            return "Анти-скам"
        case .mediaAndAudio:
            return "Медиа и Аудио"
        case .plugins:
            return "Плагины"
        case .aiAssistant:
            return "ИИ Ассистент"
        case .other:
            return "Прочее"
        }
    }

    var icon: UIImage? {
        switch self {
        case .appearance:
            return FullGramSettingsIcons.symbol("paintbrush.fill", color: UIColor(rgb: 0xAF52DE))
        case .chats:
            return FullGramSettingsIcons.bundleGlyph("FullGram/Chats", color: UIColor(rgb: 0x007AFF), side: 20.0, fallbackSystemName: "bubble.left.and.bubble.right.fill")
        case .privacy:
            return FullGramSettingsIcons.bundleGlyph("FullGram/Ghost", color: UIColor(rgb: 0x34C759), side: 20.0, fallbackSystemName: "hand.raised.fill")
        case .security:
            return FullGramSettingsIcons.symbol("lock.shield.fill", color: UIColor(rgb: 0xFF9500))
        case .antiScam:
            return FullGramSettingsIcons.symbol("checkmark.shield.fill", color: UIColor(rgb: 0xFF3B30))
        case .mediaAndAudio:
            return FullGramSettingsIcons.symbol("waveform", color: UIColor(rgb: 0xFF2D55))
        case .plugins:
            return FullGramSettingsIcons.bundleGlyph("FullGram/Plugins", color: UIColor(rgb: 0x5856D6), side: 20.0, fallbackSystemName: "puzzlepiece.extension.fill")
        case .aiAssistant:
            return FullGramSettingsIcons.symbol("sparkles", color: UIColor(rgb: 0x6750A4))
        case .other:
            return FullGramSettingsIcons.symbol("gearshape.fill", color: UIColor(rgb: 0x8E8E93))
        }
    }
}

private final class FullGramSettingsControllerArguments {
    let context: AccountContext
    let openSearch: () -> Void
    let openAdmin: () -> Void
    let openSponsorPanel: () -> Void
    let openCategory: (FullGramCategory) -> Void
    let openLink: (String) -> Void

    init(
        context: AccountContext,
        openSearch: @escaping () -> Void,
        openAdmin: @escaping () -> Void,
        openSponsorPanel: @escaping () -> Void,
        openCategory: @escaping (FullGramCategory) -> Void,
        openLink: @escaping (String) -> Void
    ) {
        self.context = context
        self.openSearch = openSearch
        self.openAdmin = openAdmin
        self.openSponsorPanel = openSponsorPanel
        self.openCategory = openCategory
        self.openLink = openLink
    }
}

private enum FullGramSettingsSection: Int32 {
    case header
    case search
    case admin
    case categories
    case links
}

private enum FullGramSettingsEntry: ItemListNodeEntry {
    case header(PresentationTheme)
    case search(PresentationTheme)
    case adminPanel(PresentationTheme, String)
    case sponsorPanel(PresentationTheme, String)
    case categoriesHeader(PresentationTheme, String)
    case category(Int32, PresentationTheme, FullGramCategory)
    case linksHeader(PresentationTheme, String)
    case link(Int32, PresentationTheme, UIImage?, String, String, String)

    var section: ItemListSectionId {
        switch self {
        case .header:
            return FullGramSettingsSection.header.rawValue
        case .search:
            return FullGramSettingsSection.search.rawValue
        case .adminPanel, .sponsorPanel:
            return FullGramSettingsSection.admin.rawValue
        case .categoriesHeader, .category:
            return FullGramSettingsSection.categories.rawValue
        case .linksHeader, .link:
            return FullGramSettingsSection.links.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case .search:
            return 1
        case .adminPanel:
            return 2
        case .sponsorPanel:
            return 3
        case .categoriesHeader:
            return 4
        case let .category(index, _, _):
            return 5 + index
        case .linksHeader:
            return 100
        case let .link(index, _, _, _, _, _):
            return 101 + index
        }
    }

    static func ==(lhs: FullGramSettingsEntry, rhs: FullGramSettingsEntry) -> Bool {
        switch lhs {
        case let .header(lhsTheme):
            if case let .header(rhsTheme) = rhs {
                return lhsTheme === rhsTheme
            }
            return false
        case let .search(lhsTheme):
            if case let .search(rhsTheme) = rhs {
                return lhsTheme === rhsTheme
            }
            return false
        case let .adminPanel(lhsTheme, lhsTitle):
            if case let .adminPanel(rhsTheme, rhsTitle) = rhs {
                return lhsTheme === rhsTheme && lhsTitle == rhsTitle
            }
            return false
        case let .sponsorPanel(lhsTheme, lhsTitle):
            if case let .sponsorPanel(rhsTheme, rhsTitle) = rhs {
                return lhsTheme === rhsTheme && lhsTitle == rhsTitle
            }
            return false
        case let .categoriesHeader(lhsTheme, lhsText):
            if case let .categoriesHeader(rhsTheme, rhsText) = rhs {
                return lhsTheme === rhsTheme && lhsText == rhsText
            }
            return false
        case let .category(lhsIndex, lhsTheme, lhsCategory):
            if case let .category(rhsIndex, rhsTheme, rhsCategory) = rhs {
                return lhsIndex == rhsIndex && lhsTheme === rhsTheme && lhsCategory == rhsCategory
            }
            return false
        case let .linksHeader(lhsTheme, lhsText):
            if case let .linksHeader(rhsTheme, rhsText) = rhs {
                return lhsTheme === rhsTheme && lhsText == rhsText
            }
            return false
        case let .link(lhsIndex, lhsTheme, _, lhsTitle, lhsValue, lhsUrl):
            if case let .link(rhsIndex, rhsTheme, _, rhsTitle, rhsValue, rhsUrl) = rhs {
                return lhsIndex == rhsIndex && lhsTheme === rhsTheme && lhsTitle == rhsTitle && lhsValue == rhsValue && lhsUrl == rhsUrl
            }
            return false
        }
    }

    static func <(lhs: FullGramSettingsEntry, rhs: FullGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramSettingsControllerArguments
        switch self {
        case .header:
            return FullGramHeaderItem(theme: presentationData.theme, sectionId: self.section)
        case .search:
            let icon = FullGramSettingsIcons.symbol("magnifyingglass", color: UIColor(rgb: 0x007AFF))
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: icon,
                title: "Поиск по настройкам",
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openSearch()
                }
            )
        case let .adminPanel(_, title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: fullGramBadgeMenuIcon(),
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openAdmin()
                }
            )
        case let .sponsorPanel(_, title):
            let icon = FullGramSettingsIcons.symbol("sparkles.rectangle.stack.fill", color: UIColor(rgb: 0x5856D6))
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: icon,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openSponsorPanel()
                }
            )
        case let .categoriesHeader(_, text):
            return ItemListSectionHeaderItem(
                presentationData: presentationData,
                text: text,
                sectionId: self.section
            )
        case let .category(_, _, category):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: category.icon,
                title: category.title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openCategory(category)
                }
            )
        case let .linksHeader(_, text):
            return ItemListSectionHeaderItem(
                presentationData: presentationData,
                text: text,
                sectionId: self.section
            )
        case let .link(_, _, icon, title, value, url):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: icon,
                title: title,
                label: value,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openLink(url)
                }
            )
        }
    }
}

private final class FullGramHeaderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let sectionId: ItemListSectionId
    let isAlwaysPlain: Bool = true

    init(theme: PresentationTheme, sectionId: ItemListSectionId) {
        self.theme = theme
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = FullGramHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply() }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FullGramHeaderItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in apply() })
                    }
                }
            }
        }
    }
}

private final class FullGramHeaderItemNode: ListViewItemNode {
    private let iconNode: ASImageNode
    private let titleNode: TextNode
    private let versionNode: TextNode

    init() {
        self.iconNode = ASImageNode()
        self.iconNode.displaysAsynchronously = false
        self.iconNode.contentMode = .scaleAspectFill
        self.iconNode.cornerRadius = 40.0
        self.iconNode.clipsToBounds = true

        self.titleNode = TextNode()
        self.versionNode = TextNode()

        super.init(layerBacked: false, rotated: false, seeThrough: false)

        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.versionNode)
    }

    func asyncLayout() -> (_ item: FullGramHeaderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeVersionLayout = TextNode.asyncLayout(self.versionNode)

        return { [weak self] item, params, neighbors in
            let iconSize = CGSize(width: 80.0, height: 80.0)
            let topInset: CGFloat = 20.0
            let titleSpacing: CGFloat = 14.0
            let versionSpacing: CGFloat = 4.0
            let bottomInset: CGFloat = 16.0

            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(
                    string: "FullGram",
                    font: Font.bold(22.0),
                    textColor: item.theme.list.itemPrimaryTextColor
                ),
                backgroundColor: nil,
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: CGSize(width: params.width - params.leftInset - params.rightInset - 32.0, height: CGFloat.greatestFiniteMagnitude),
                alignment: .center,
                cutout: nil,
                insets: UIEdgeInsets()
            ))

            let (versionLayout, versionApply) = makeVersionLayout(TextNodeLayoutArguments(
                attributedString: NSAttributedString(
                    string: "1.6.1",
                    font: Font.regular(15.0),
                    textColor: item.theme.list.itemSecondaryTextColor
                ),
                backgroundColor: nil,
                maximumNumberOfLines: 1,
                truncationType: .end,
                constrainedSize: CGSize(width: params.width - params.leftInset - params.rightInset - 32.0, height: CGFloat.greatestFiniteMagnitude),
                alignment: .center,
                cutout: nil,
                insets: UIEdgeInsets()
            ))

            let contentHeight = topInset + iconSize.height + titleSpacing + titleLayout.size.height + versionSpacing + versionLayout.size.height + bottomInset
            let contentSize = CGSize(width: params.width, height: contentHeight)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)

            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, {
                guard let self else {
                    return
                }
                self.iconNode.image = UIImage(named: "FullGramMascotPortrait") ?? UIImage(named: "AppIcon") ?? PresentationResourcesSettings.support
                self.iconNode.frame = CGRect(
                    x: floor((params.width - iconSize.width) / 2.0),
                    y: topInset,
                    width: iconSize.width,
                    height: iconSize.height
                )

                let _ = titleApply()
                self.titleNode.frame = CGRect(
                    x: floor((params.width - titleLayout.size.width) / 2.0),
                    y: topInset + iconSize.height + titleSpacing,
                    width: titleLayout.size.width,
                    height: titleLayout.size.height
                )

                let _ = versionApply()
                self.versionNode.frame = CGRect(
                    x: floor((params.width - versionLayout.size.width) / 2.0),
                    y: self.titleNode.frame.maxY + versionSpacing,
                    width: versionLayout.size.width,
                    height: versionLayout.size.height
                )
            })
        }
    }
}

public func fullGramOpenFontsStack(context: AccountContext, in navigationController: NavigationController?) {
    guard let navigationController else {
        return
    }
    let rootControllers: [ViewController]
    if let first = navigationController.viewControllers.first {
        rootControllers = [first]
    } else {
        rootControllers = []
    }
    let stack = rootControllers + [
        fullGramSettingsController(context: context),
        fullGramAppearanceCategoryController(context: context),
        fullGramFontsController(context: context)
    ]
    navigationController.setViewControllers(stack, animated: false)
}

public func fullGramSettingsController(context: AccountContext) -> ViewController {
    FullGramDesignWatchdog.markUIVerified()
    var pushControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?

    let sponsorsTick = ValuePromise<Int>(0, ignoreRepeated: false)
    let sponsorsCounter = Atomic<Int>(value: 0)
    let sponsorsObserver = NotificationCenter.default.addObserver(forName: FullGramSponsors.didChangeNotification, object: nil, queue: .main) { _ in
        sponsorsTick.set(sponsorsCounter.modify { $0 + 1 })
    }
    FullGramSponsors.shared.refreshIfNeeded(maxAge: 20.0)

    let arguments = FullGramSettingsControllerArguments(
        context: context,
        openSearch: {
            pushControllerImpl?(fullGramSettingsSearchController(context: context))
        },
        openAdmin: {
            pushControllerImpl?(fullGramAdminController(context: context))
        },
        openSponsorPanel: {
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
            |> deliverOnMainQueue).startStandalone(next: { peer in
                guard let peer else { return }
                pushControllerImpl?(fullGramBadgeDeskController(
                    context: context,
                    peer: peer,
                    peerId: peer.id.toInt64(),
                    username: peer.addressName,
                    isSponsorSelfMode: true
                ))
            })
        },
        openCategory: { category in
            switch category {
            case .privacy:
                pushControllerImpl?(fullGramPrivacyCategoryController(context: context))
            case .chats:
                pushControllerImpl?(fullGramChatsCategoryController(context: context))
            case .appearance:
                pushControllerImpl?(fullGramAppearanceCategoryController(context: context))
            case .security:
                pushControllerImpl?(fullGramSecurityCategoryController(context: context))
            case .antiScam:
                pushControllerImpl?(fullGramAntiScamController(context: context))
            case .mediaAndAudio:
                pushControllerImpl?(fullGramMediaAudioCategoryController(context: context))
            case .other:
                pushControllerImpl?(fullGramOtherCategoryController(context: context))
            case .plugins:
                pushControllerImpl?(fullGramPluginsController(context: context))
            case .aiAssistant:
                pushControllerImpl?(fullGramAIAssistantController(context: context))
            }
        },
        openLink: { url in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            context.sharedContext.openExternalUrl(
                context: context,
                urlContext: .generic,
                url: url,
                forceExternal: false,
                presentationData: presentationData,
                navigationController: navigationControllerImpl?(),
                dismissInput: {}
            )
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, sponsorsTick.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramSettingsEntry] = [
            .header(presentationData.theme),
            .search(presentationData.theme)
        ]
        if fullGramCanOpenAdmin(context: context) {
            let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            entries.append(.adminPanel(presentationData.theme, ru ? "Админ-панель FullGram" : "FullGram Admin"))
        } else if fullGramIsSelfSponsor(context: context) {
            let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let isPlus = fullGramIsSelfSponsorPlus(context: context)
            entries.append(.sponsorPanel(
                presentationData.theme,
                isPlus
                    ? (ru ? "Панель Спонсор+ (Бейдж и NFT)" : "Sponsor+ Panel (Badge & NFT)")
                    : (ru ? "Панель спонсора (Бейдж и NFT)" : "Sponsor Panel (Badge & NFT)")
            ))
        }
        entries.append(.categoriesHeader(presentationData.theme, "КАТЕГОРИИ"))

        var index: Int32 = 0
        for category in FullGramCategory.allCases {
            entries.append(.category(index, presentationData.theme, category))
            index += 1
        }

        entries.append(.linksHeader(presentationData.theme, "ССЫЛКИ"))
        entries.append(.link(0, presentationData.theme, PresentationResourcesSettings.channels, "Канал", "@fullgram_mod", "https://t.me/fullgram_mod"))
        entries.append(.link(1, presentationData.theme, PresentationResourcesSettings.groups, "Официальная группа", "@fullgramgroup", "https://t.me/fullgramgroup"))
        entries.append(.link(2, presentationData.theme, PresentationResourcesSettings.privateChats, "Создатель мода", "@shermanko", "https://t.me/shermanko"))

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("FullGram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(sponsorsObserver)
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}

private struct FullGramPrivacyCategoryArguments {
    let openGhostMode: () -> Void
    let openPrivateMode: () -> Void
    let openActivityAndTraces: () -> Void
    let openDeleted: () -> Void
}

private enum FullGramPrivacyCategoryEntry: ItemListNodeEntry {
    case ghostModeLink(PresentationTheme, Bool)
    case privateModeLink(PresentationTheme, Bool)
    case activityAndTracesLink(PresentationTheme)
    case deletedLink(PresentationTheme)

    var section: ItemListSectionId {
        switch self {
        case .ghostModeLink, .privateModeLink, .activityAndTracesLink:
            return 0
        case .deletedLink:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostModeLink: return 0
        case .privateModeLink: return 1
        case .activityAndTracesLink: return 2
        case .deletedLink: return 3
        }
    }

    static func ==(lhs: FullGramPrivacyCategoryEntry, rhs: FullGramPrivacyCategoryEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.ghostModeLink(lhsTheme, lhsActive), .ghostModeLink(rhsTheme, rhsActive)):
            return lhsTheme === rhsTheme && lhsActive == rhsActive
        case let (.privateModeLink(lhsTheme, lhsActive), .privateModeLink(rhsTheme, rhsActive)):
            return lhsTheme === rhsTheme && lhsActive == rhsActive
        case let (.activityAndTracesLink(lhsTheme), .activityAndTracesLink(rhsTheme)):
            return lhsTheme === rhsTheme
        case let (.deletedLink(lhsTheme), .deletedLink(rhsTheme)):
            return lhsTheme === rhsTheme
        default:
            return false
        }
    }

    static func <(lhs: FullGramPrivacyCategoryEntry, rhs: FullGramPrivacyCategoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramPrivacyCategoryArguments
        switch self {
        case let .ghostModeLink(_, isActive):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.bundleGlyph("FullGram/Ghost", color: UIColor(rgb: 0x34C759), side: 20.0, fallbackSystemName: "eye.slash.fill"),
                title: "Режим призрака (Ghost Mode)",
                label: isActive ? "Вкл." : "Выкл.",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openGhostMode
            )
        case let .privateModeLink(_, isActive):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("eye.slash.fill", color: UIColor(rgb: 0x5856D6)),
                title: "Приватный режим",
                label: isActive ? "Вкл." : "Выкл.",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openPrivateMode
            )
        case .activityAndTracesLink:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("lock.fill", color: UIColor(rgb: 0xFF9500)),
                title: "Деятельность и следы",
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openActivityAndTraces
            )
        case .deletedLink:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: FullGramSettingsIcons.symbol("trash.fill", color: UIColor(rgb: 0xFF3B30)),
                title: "Удалённые",
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openDeleted
            )
        }
    }
}

func fullGramPrivacyCategoryController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let store = context.account.network.fullGramGhostMode
    let extrasTick = ValuePromise<Int>(0, ignoreRepeated: false)
    let tickCounter = Atomic<Int>(value: 0)
    let extrasObserver = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        extrasTick.set(tickCounter.modify { $0 + 1 })
    }

    let arguments = FullGramPrivacyCategoryArguments(
        openGhostMode: {
            pushControllerImpl?(fullGramGhostModeController(context: context))
        },
        openPrivateMode: {
            pushControllerImpl?(fullGramPrivateModeController(context: context))
        },
        openActivityAndTraces: {
            pushControllerImpl?(fullGramActivityAndTracesController(context: context))
        },
        openDeleted: {
            pushControllerImpl?(fullGramMessageHistoryController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, store.signal, extrasTick.get())
    |> deliverOnMainQueue
    |> map { presentationData, settings, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramPrivacyCategoryEntry] = [
            .ghostModeLink(presentationData.theme, settings.isActive),
            .privateModeLink(presentationData.theme, FullGramExtras.shared.privateMode),
            .activityAndTracesLink(presentationData.theme),
            .deletedLink(presentationData.theme)
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Приватность"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(extrasObserver)
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

private enum FullGramActivityExtraToggle: Int32 {
    case alwaysOnline = 1
    case confirmCalls = 2
    case removePhotoMetadata = 3
    case randomFileNames = 4
    case cleanLinks = 5
}

private struct FullGramActivityAndTracesArguments {
    let openActivityFilter: () -> Void
    let toggleExtra: (FullGramActivityExtraToggle, Bool) -> Void
    let selectUndoSend: () -> Void
}

private enum FullGramActivityAndTracesEntry: ItemListNodeEntry {
    case statusesHeader(String)
    case activityFilterLink(String, String)
    case statusesInfo(String)
    case otherHeader(String)
    case extraToggle(FullGramActivityExtraToggle, String, Bool)
    case extraInfo(Int32, String)
    case undoSend(String, String)

    var section: ItemListSectionId {
        switch self {
        case .statusesHeader, .activityFilterLink, .statusesInfo:
            return 0
        case .otherHeader, .extraToggle, .extraInfo, .undoSend:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .statusesHeader: return 0
        case .activityFilterLink: return 1
        case .statusesInfo: return 2
        case .otherHeader: return 50
        case .extraToggle(.alwaysOnline, _, _): return 51
        case .extraToggle(.confirmCalls, _, _): return 52
        case .undoSend: return 53
        case .extraToggle(.removePhotoMetadata, _, _): return 54
        case let .extraInfo(id, _): return id
        case .extraToggle(.randomFileNames, _, _): return 56
        case .extraToggle(.cleanLinks, _, _): return 57
        }
    }

    static func ==(lhs: FullGramActivityAndTracesEntry, rhs: FullGramActivityAndTracesEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.statusesHeader(a), .statusesHeader(b)): return a == b
        case let (.activityFilterLink(at, al), .activityFilterLink(bt, bl)): return at == bt && al == bl
        case let (.statusesInfo(a), .statusesInfo(b)): return a == b
        case let (.otherHeader(a), .otherHeader(b)): return a == b
        case let (.extraToggle(ao, at, av), .extraToggle(bo, bt, bv)): return ao == bo && at == bt && av == bv
        case let (.extraInfo(ai, at), .extraInfo(bi, bt)): return ai == bi && at == bt
        case let (.undoSend(at, al), .undoSend(bt, bl)): return at == bt && al == bl
        default: return false
        }
    }

    static func <(lhs: FullGramActivityAndTracesEntry, rhs: FullGramActivityAndTracesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramActivityAndTracesArguments
        switch self {
        case let .statusesHeader(text), let .otherHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .activityFilterLink(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.openActivityFilter
            )
        case let .statusesInfo(text), let .extraInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .extraToggle(opt, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { args.toggleExtra(opt, $0) }
            )
        case let .undoSend(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: args.selectUndoSend
            )
        }
    }
}

private struct FullGramActivityFilterArguments {
    let toggleAll: (Bool) -> Void
    let toggleStatus: (FullGramActivityFilter.Kind, Bool) -> Void
}

private enum FullGramActivityFilterEntry: ItemListNodeEntry {
    case allHeader(String)
    case toggleAll(String, Bool)
    case statusesHeader(String)
    case statusToggle(Int32, FullGramActivityFilter.Kind, Bool)
    case statusesInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .allHeader, .toggleAll:
            return 0
        case .statusesHeader, .statusToggle, .statusesInfo:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .allHeader: return 0
        case .toggleAll: return 1
        case .statusesHeader: return 10
        case let .statusToggle(idx, _, _): return 11 + idx
        case .statusesInfo: return 100
        }
    }

    static func ==(lhs: FullGramActivityFilterEntry, rhs: FullGramActivityFilterEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.allHeader(a), .allHeader(b)): return a == b
        case let (.toggleAll(at, av), .toggleAll(bt, bv)): return at == bt && av == bv
        case let (.statusesHeader(a), .statusesHeader(b)): return a == b
        case let (.statusToggle(ai, ak, av), .statusToggle(bi, bk, bv)): return ai == bi && ak == bk && av == bv
        case let (.statusesInfo(a), .statusesInfo(b)): return a == b
        default: return false
        }
    }

    static func <(lhs: FullGramActivityFilterEntry, rhs: FullGramActivityFilterEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramActivityFilterArguments
        switch self {
        case let .allHeader(text), let .statusesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggleAll(title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: args.toggleAll
            )
        case let .statusToggle(_, kind, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: kind.titleRu,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { args.toggleStatus(kind, $0) }
            )
        case let .statusesInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramActivityFilterController(context: AccountContext) -> ViewController {
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramActivityFilterArguments(
        toggleAll: { value in
            for kind in FullGramActivityFilter.Kind.allCases {
                FullGramActivityFilter.setHidden(kind, value)
            }
        },
        toggleStatus: { kind, value in
            FullGramActivityFilter.setHidden(kind, value)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let allKinds = FullGramActivityFilter.Kind.allCases
        let allHidden = allKinds.allSatisfy { FullGramActivityFilter.isHidden($0) }
        var entries: [FullGramActivityFilterEntry] = [
            .allHeader("ОБЩЕЕ"),
            .toggleAll("Скрывать все статусы", allHidden),
            .statusesHeader("ВЫБРАТЬ СТАТУСЫ")
        ]
        for (index, kind) in allKinds.enumerated() {
            entries.append(.statusToggle(Int32(index), kind, FullGramActivityFilter.isHidden(kind)))
        }
        entries.append(.statusesInfo("Выбранные статусы активности («печатает», запись голосовых и др.) не будут отправляться собеседникам."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Скрытие статусов"),
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

func fullGramActivityAndTracesController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramActivityAndTracesArguments(
        openActivityFilter: {
            pushControllerImpl?(fullGramActivityFilterController(context: context))
        },
        toggleExtra: { opt, value in
            switch opt {
            case .alwaysOnline:
                FullGramExtras.shared.alwaysOnline = value
            case .confirmCalls:
                FullGramExtras.shared.confirmCalls = value
            case .removePhotoMetadata:
                FullGramExtras.shared.removePhotoMetadata = value
            case .randomFileNames:
                FullGramExtras.shared.randomFileNames = value
            case .cleanLinks:
                FullGramExtras.shared.cleanLinks = value
            }
        },
        selectUndoSend: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let sheet = ActionSheetController(presentationData: presentationData)
            let options: [(Int, String)] = [
                (0, "Выкл."),
                (3, "3 сек."),
                (5, "5 сек."),
                (10, "10 сек."),
                (15, "15 сек.")
            ]
            var items: [ActionSheetItem] = options.map { seconds, label in
                ActionSheetButtonItem(title: label, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    FullGramExtras.shared.undoSendSeconds = seconds
                })
            }
            items.append(ActionSheetButtonItem(title: "Своё время…", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let alert = UIAlertController(title: "Отложенная отправка", message: "Введите задержку в секундах (от 0 до 3600):", preferredStyle: .alert)
                alert.addTextField { tf in
                    tf.keyboardType = .numberPad
                    tf.placeholder = "Например: 30"
                    let current = FullGramExtras.shared.undoSendSeconds
                    tf.text = current > 0 ? "\(current)" : ""
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert] _ in
                    let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if let seconds = Int(raw) {
                        FullGramExtras.shared.undoSendSeconds = seconds
                    }
                }))
                presentNativeImpl?(alert)
            }))
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
        let extras = FullGramExtras.shared
        let undoLabel = extras.undoSendSeconds == 0 ? "Выкл." : "\(extras.undoSendSeconds) сек."
        let allKinds = FullGramActivityFilter.Kind.allCases
        let hiddenCount = allKinds.filter { FullGramActivityFilter.isHidden($0) }.count
        let statusesLabel = hiddenCount == 0 ? "Выкл." : "\(hiddenCount) из \(allKinds.count)"
        var entries: [FullGramActivityAndTracesEntry] = [
            .statusesHeader("СКРЫТИЕ СТАТУСОВ"),
            .activityFilterLink("Скрытие статусов", statusesLabel),
            .statusesInfo("Печатает, запись голосовых, кружки, стикеры и др.")
        ]
        entries.append(.otherHeader("ДОПОЛНИТЕЛЬНО"))
        entries.append(.extraToggle(.alwaysOnline, "Всегда онлайн", extras.alwaysOnline))
        entries.append(.extraToggle(.confirmCalls, "Подтверждать звонки", extras.confirmCalls))
        entries.append(.undoSend("Отложенная отправка", undoLabel))
        entries.append(.extraToggle(.removePhotoMetadata, "Удаление метаданных", extras.removePhotoMetadata))
        entries.append(.extraInfo(55, "Удаляет метаданные с фото"))
        entries.append(.extraToggle(.randomFileNames, "Случайные имена файлов", extras.randomFileNames))
        entries.append(.extraToggle(.cleanLinks, "Чистые ссылки", extras.cleanLinks))
        entries.append(.extraInfo(58, "Убирает метки слежки из ссылки"))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Деятельность и следы"),
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
    pushControllerImpl = { [weak controller] c in
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

private enum FullGramGhostModeOption: Int32 {
    case all = 1
    case readReceipts = 2
    case online = 3
    case typing = 4
    case uploadProgress = 5
    case markReadAfterSend = 6
    case silentSendInGhostMode = 7
}

private struct FullGramGhostModeArguments {
    let update: (FullGramGhostModeOption, Bool) -> Void
    let addException: () -> Void
    let removeException: (Int64) -> Void
    let clearExceptions: () -> Void
}

private enum FullGramGhostModeEntry: ItemListNodeEntry {
    case header(String)
    case toggle(FullGramGhostModeOption, String, Bool)
    case info(String)
    case exceptionsHeader(String)
    case addException(String)
    case exceptionPeer(Int, Int64, String, String)
    case clearExceptions(String)
    case exceptionsInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .toggle(.all, _, _), .toggle(.readReceipts, _, _), .toggle(.online, _, _), .toggle(.typing, _, _), .toggle(.uploadProgress, _, _), .info:
            return 0
        case .toggle(.markReadAfterSend, _, _), .toggle(.silentSendInGhostMode, _, _):
            return 1
        case .exceptionsHeader, .addException, .exceptionPeer, .clearExceptions, .exceptionsInfo:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .toggle(option, _, _):
            return option.rawValue
        case .info:
            return 100
        case .exceptionsHeader:
            return 200
        case .addException:
            return 201
        case let .exceptionPeer(index, _, _, _):
            return 300 + Int32(index)
        case .clearExceptions:
            return 900
        case .exceptionsInfo:
            return 901
        }
    }

    static func <(lhs: FullGramGhostModeEntry, rhs: FullGramGhostModeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramGhostModeArguments
        switch self {
        case let .header(text), let .exceptionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(option, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { value in
                    arguments.update(option, value)
                }
            )
        case let .info(text), let .exceptionsInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .addException(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.addException()
                }
            )
        case let .exceptionPeer(_, peerId, title, removeLabel):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: removeLabel,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.removeException(peerId)
                }
            )
        case let .clearExceptions(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    arguments.clearExceptions()
                }
            )
        }
    }
}

public func fullGramGhostModeController(context: AccountContext) -> ViewController {
    let store = context.account.network.fullGramGhostMode
    var presentError: (() -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = FullGramGhostModeArguments(
        update: { option, value in
            do {
                try store.update { settings in
                    switch option {
                    case .all:
                        settings.setAllEnabled(value)
                    case .readReceipts:
                        settings.hideReadReceipts = value
                    case .online:
                        settings.hideOnline = value
                    case .typing:
                        settings.hideTyping = value
                    case .uploadProgress:
                        settings.hideUploadProgress = value
                    case .markReadAfterSend:
                        settings.markReadAfterSend = value
                    case .silentSendInGhostMode:
                        settings.silentSendMode = value ? .inGhostMode : .never
                    }
                }
            } catch {
                presentError?()
            }
        },
        addException: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.excludeRecent],
                hasChatListSelector: true,
                hasContactSelector: true,
                hasGlobalSearch: true,
                title: isRussian ? "Добавить в исключения" : "Add Exception"
            ))
            selector.peerSelected = { [weak selector] peer, _ in
                try? store.update { settings in
                    settings.setException(true, peerId: peer.id.toInt64())
                }
                selector?.dismiss()
            }
            presentControllerImpl?(selector)
        },
        removeException: { peerId in
            try? store.update { settings in
                settings.setException(false, peerId: peerId)
            }
        },
        clearExceptions: {
            try? store.update { settings in
                settings.exceptionPeerIds.removeAll()
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, store.signal)
    |> mapToSignal { presentationData, settings -> Signal<(PresentationData, FullGramGhostModeSettings, [(Int64, String)]), NoError> in
        let peerIds = settings.exceptionPeerIds
        if peerIds.isEmpty {
            return .single((presentationData, settings, []))
        }
        return context.account.postbox.transaction { transaction -> [(Int64, String)] in
            return peerIds.map { rawId in
                let peerId = PeerId(rawId)
                let title = transaction.getPeer(peerId).map { EnginePeer($0).compactDisplayTitle } ?? "ID \(peerId.id._internalGetInt64Value())"
                return (rawId, title)
            }
        }
        |> map { peers in
            return (presentationData, settings, peers)
        }
    }
    |> deliverOnMainQueue
    |> map { presentationData, settings, exceptionPeers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func title(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let infoText = title(
            "В режиме призрака собеседники не видят, что вы прочитали сообщение, находитесь в сети, печатаете или загружаете файл.",
            "In Ghost Mode, others won't see that you read messages, are online, typing, or uploading files."
        )

        var entries: [FullGramGhostModeEntry] = [
            .header(title("ЧТО СКРЫВАТЬ", "WHAT TO HIDE")),
            .toggle(.all, title("Включить всё", "Turn everything on"), settings.allEnabled),
            .toggle(.readReceipts, title("Не отмечать прочитанным", "Don't mark as read"), settings.hideReadReceipts),
            .toggle(.online, title("Не показывать «в сети»", "Don't show online"), settings.hideOnline),
            .toggle(.typing, title("Не показывать «печатает»", "Don't show typing"), settings.hideTyping),
            .toggle(.uploadProgress, title("Не показывать загрузку файлов", "Don't show uploads"), settings.hideUploadProgress),
            .info(infoText),
            .toggle(.markReadAfterSend, title("Читать чат после отправки ответа", "Mark read after sending"), settings.markReadAfterSend),
            .toggle(.silentSendInGhostMode, title("Отправлять без звука в режиме призрака", "Send silently in Ghost Mode"), settings.silentSendMode == .inGhostMode),
            .exceptionsHeader(title("ИСКЛЮЧЕНИЯ (ГДЕ ПРИЗРАК НЕ РАБОТАЕТ)", "EXCEPTIONS (NEVER USE GHOST MODE)")),
            .addException(title("Добавить чат в исключения…", "Add chat to exceptions…"))
        ]

        let removeLabel = title("Убрать", "Remove")
        for (index, item) in exceptionPeers.enumerated() {
            entries.append(.exceptionPeer(index, item.0, item.1, removeLabel))
        }

        if !exceptionPeers.isEmpty {
            entries.append(.clearExceptions(title("Очистить список исключений", "Clear exceptions")))
        }

        entries.append(.exceptionsInfo(title(
            "В выбранных чатах режим призрака никогда не будет работать (сообщения будут сразу отмечаться прочитанными, а статус «печатает» будет виден). Нажмите на чат в списке, чтобы убрать его из исключений.",
            "Ghost Mode will never apply in the selected chats. Tap a chat in the list to remove it from exceptions."
        )))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text(title("Режим призрака", "Ghost Mode")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let list = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (state, (list, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentError = { [weak controller] in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        controller?.present(
            textAlertController(
                context: context,
                title: "FullGram",
                text: isRussian ? "Не удалось сохранить настройки." : "Could not save settings.",
                actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
            ),
            in: .window(.root)
        )
    }
    return controller
}

private enum FullGramChatsToggle: Int32 {
    case hideStickerTime = 1
    case unlimitedRecentStickers = 2
    case disableJumpToNextChannel = 3
    case hideKeyboardOnScroll = 4
    case addCommaAfterMention = 5
    case hideFastShare = 6
    case horizonLockVideoMessages = 7
    case autoRevealSpoilers = 8
    case deletePaperAnimation = 9
}

private struct FullGramChatsCategoryArguments {
    let openHistory: () -> Void
    let openRestrictionBypass: () -> Void
    let openSending: () -> Void
    let openTranslation: () -> Void
    let openMessageMenu: () -> Void
    let openReactions: () -> Void
    let openAutoResponder: () -> Void
    let toggle: (FullGramChatsToggle, Bool) -> Void
}

private enum FullGramChatsCategoryEntry: ItemListNodeEntry {
    case sectionsHeader(String)
    case messageHistoryLink(PresentationTheme, Int)
    case restrictionBypassLink(PresentationTheme, Bool)
    case sendingLink(PresentationTheme)
    case translationLink(PresentationTheme, String)
    case messageMenuLink(PresentationTheme)
    case reactionsLink(PresentationTheme, String)
    case autoResponderLink(PresentationTheme, String)
    case optionsHeader(String)
    case toggle(FullGramChatsToggle, String, Bool)
    case optionsInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .sectionsHeader, .messageHistoryLink, .restrictionBypassLink, .sendingLink, .translationLink, .messageMenuLink, .reactionsLink, .autoResponderLink:
            return 0
        case .optionsHeader, .toggle, .optionsInfo:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .sectionsHeader:
            return 0
        case .messageHistoryLink:
            return 1
        case .restrictionBypassLink:
            return 2
        case .sendingLink:
            return 3
        case .translationLink:
            return 4
        case .messageMenuLink:
            return 5
        case .reactionsLink:
            return 6
        case .autoResponderLink:
            return 7
        case .optionsHeader:
            return 100
        case let .toggle(option, _, _):
            return 100 + option.rawValue
        case .optionsInfo:
            return 200
        }
    }

    static func <(lhs: FullGramChatsCategoryEntry, rhs: FullGramChatsCategoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramChatsCategoryArguments
        switch self {
        case let .sectionsHeader(text), let .optionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .messageHistoryLink(_, count):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.privateChats,
                title: "Удалённые и изменённые",
                label: count > 0 ? "\(count)" : "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openHistory
            )
        case let .restrictionBypassLink(_, enabled):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.security,
                title: "Обход ограничений",
                label: enabled ? "Вкл." : "Выкл.",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openRestrictionBypass
            )
        case .sendingLink:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.privateChats,
                title: "Сообщение",
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openSending
            )
        case let .translationLink(_, providerTitle):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.language,
                title: "Перевод",
                label: providerTitle,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openTranslation
            )
        case .messageMenuLink:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.appearance,
                title: "Меню сообщения",
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openMessageMenu
            )
        case let .reactionsLink(_, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.stickers,
                title: "Реакции в чатах",
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openReactions
            )
        case let .autoResponderLink(_, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.privateChats,
                title: "Авто-ответчик",
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openAutoResponder
            )
        case let .toggle(option, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.toggle(option, newValue)
                }
            )
        case let .optionsInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func fullGramTranslationProviderTitle(_ provider: FullGramTranslationSettings.Provider) -> String {
    switch provider {
    case .telegram:
        return "Telegram"
    case .libreTranslate:
        return "LibreTranslate"
    case .deepLFree:
        return "DeepL API Free"
    }
}

private func fullGramLanguageDisplayName(code: String, isRussian: Bool) -> String {
    let locale = Locale(identifier: isRussian ? "ru" : "en")
    if let localized = locale.localizedString(forLanguageCode: code), !localized.isEmpty {
        return localized.prefix(1).uppercased() + localized.dropFirst()
    }
    return code.uppercased()
}

func fullGramChatsCategoryController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let store = context.account.network.fullGramGhostMode
    let extrasChanged = ValuePromise<Int>(0, ignoreRepeated: false)
    var extrasVersion = 0
    let observer = NotificationCenter.default.addObserver(
        forName: FullGramExtras.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        extrasVersion += 1
        extrasChanged.set(extrasVersion)
    }
    let autoResponderObserver = NotificationCenter.default.addObserver(
        forName: FullGramAutoResponderSettings.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        extrasVersion += 1
        extrasChanged.set(extrasVersion)
    }

    let arguments = FullGramChatsCategoryArguments(
        openHistory: {
            pushControllerImpl?(fullGramMessageHistoryController(context: context))
        },
        openRestrictionBypass: {
            pushControllerImpl?(fullGramRestrictionBypassController(context: context))
        },
        openSending: {
            pushControllerImpl?(fullGramSendingController(context: context))
        },
        openTranslation: {
            pushControllerImpl?(fullGramTranslationSettingsController(context: context))
        },
        openMessageMenu: {
            pushControllerImpl?(fullGramMessageMenuController(context: context))
        },
        openReactions: {
            pushControllerImpl?(fullGramReactionSettingsController(context: context))
        },
        openAutoResponder: {
            pushControllerImpl?(fullGramAutoResponderController(context: context))
        },
        toggle: { option, value in
            switch option {
            case .autoRevealSpoilers:
                FullGramExtras.shared.autoRevealSpoilers = value
                return
            case .deletePaperAnimation:
                FullGramExtras.shared.deletePaperAnimation = value
                return
            default:
                break
            }
            try? store.update { settings in
                switch option {
                case .hideStickerTime:
                    settings.interface.hideStickerTime = value
                case .unlimitedRecentStickers:
                    settings.interface.unlimitedRecentStickers = value
                case .disableJumpToNextChannel:
                    settings.interface.disableJumpToNextChannel = value
                case .hideKeyboardOnScroll:
                    settings.interface.hideKeyboardOnScroll = value
                case .addCommaAfterMention:
                    settings.interface.addCommaAfterMention = value
                case .hideFastShare:
                    settings.interface.hideFastShare = value
                case .horizonLockVideoMessages:
                    settings.interface.horizonLockVideoMessages = value
                case .autoRevealSpoilers, .deletePaperAnimation:
                    break
                }
            }
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.engine.messages.fullGramMessageHistory(),
        store.signal,
        extrasChanged.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, historyState, ghostSettings, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let ui = ghostSettings.interface
        let reactionsLabel = ghostSettings.reactionDisplay.enabled
            ? "\(ghostSettings.reactionDisplay.maxVisibleCount)"
            : t("Выкл.", "Off")

        let entries: [FullGramChatsCategoryEntry] = [
            .sectionsHeader(t("РАЗДЕЛЫ ЧАТОВ", "CHAT SECTIONS")),
            .messageHistoryLink(presentationData.theme, historyState.records.count),
            .restrictionBypassLink(presentationData.theme, FullGramExtras.shared.saveViewOnce),
            .sendingLink(presentationData.theme),
            .translationLink(presentationData.theme, fullGramTranslationProviderTitle(ghostSettings.translation.provider)),
            .messageMenuLink(presentationData.theme),
            .reactionsLink(presentationData.theme, reactionsLabel),
            .autoResponderLink(presentationData.theme, FullGramAutoResponderSettings.shared.mode.title(isRussian)),
            .optionsHeader(t("ПОВЕДЕНИЕ В ЧАТЕ", "CHAT BEHAVIOR")),
            .toggle(.hideStickerTime, t("Скрывать время на стикерах", "Hide time on stickers"), ui.hideStickerTime),
            .toggle(.unlimitedRecentStickers, t("Увеличить недавние стикеры (до 200)", "Unlimited recent stickers (up to 200)"), ui.unlimitedRecentStickers),
            .toggle(.disableJumpToNextChannel, t("Не переходить к следующему каналу", "Disable jump to next channel"), ui.disableJumpToNextChannel),
            .toggle(.hideKeyboardOnScroll, t("Скрывать клавиатуру при прокрутке", "Hide keyboard on scroll"), ui.hideKeyboardOnScroll),
            .toggle(.addCommaAfterMention, t("Запятая после упоминания (@nick, )", "Add comma after mention"), ui.addCommaAfterMention),
            .toggle(.hideFastShare, t("Скрыть кнопку быстрого репоста", "Hide fast share button"), ui.hideFastShare),
            .toggle(.horizonLockVideoMessages, t("Фиксация горизонта в видеокружках", "Horizon lock in video messages"), ui.horizonLockVideoMessages),
            .toggle(.autoRevealSpoilers, t("Автораскрытие спойлеров", "Auto-reveal spoilers"), FullGramExtras.shared.autoRevealSpoilers),
            .toggle(.deletePaperAnimation, t("Анимация удаления (бумага в мусорку)", "Paper trash delete animation"), FullGramExtras.shared.deletePaperAnimation),
            .optionsInfo(t(
                "Настройки мгновенно применяются ко всем открытым чатам.",
                "Settings take effect immediately in chats."
            ))
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(t("Чаты", "Chats")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
        NotificationCenter.default.removeObserver(autoResponderObserver)
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

private enum FullGramMediaToggle: Int32 {
    case saveMedia = 1
    case privateChats = 2
    case privateGroups = 3
    case publicGroups = 4
    case privateChannels = 5
    case publicChannels = 6
}

private struct FullGramMessageHistoryArguments {
    let toggleEdits: (Bool) -> Void
    let toggleDeleted: (Bool) -> Void
    let toggleDimDeleted: (Bool) -> Void
    let toggleBots: (Bool) -> Void
    let openRestrictionBypass: () -> Void
    let toggleMedia: (FullGramMediaToggle, Bool) -> Void
    let selectFileLimit: () -> Void
    let selectQuota: () -> Void
    let openMediaArchive: () -> Void
    let clear: () -> Void
    let showRecord: (FullGramMessageHistoryRecord, String, String) -> Void
}

private enum FullGramMessageHistoryEntry: ItemListNodeEntry {
    case header(String)
    case saveDeleted(String, Bool)
    case dimDeleted(String, Bool)
    case saveEdits(String, Bool)
    case saveForBots(String, Bool)
    case restrictionBypassLink(String, String)
    case info(String)
    case recordsHeader(String)
    case record(Int, FullGramMessageHistoryRecord, String, String, String)
    case empty(String)
    case clear(String)
    case mediaHeader(String)
    case mediaToggle(FullGramMediaToggle, String, Bool)
    case mediaFileLimit(String, String)
    case mediaQuota(String, String)
    case mediaArchiveScreen(String, String)
    case mediaInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .saveDeleted, .dimDeleted, .saveEdits, .saveForBots, .restrictionBypassLink, .info:
            return 0
        case .recordsHeader, .record, .empty:
            return 1
        case .clear:
            return 2
        case .mediaHeader, .mediaToggle, .mediaFileLimit, .mediaQuota, .mediaArchiveScreen, .mediaInfo:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case .saveDeleted:
            return 1
        case .dimDeleted:
            return 2
        case .saveEdits:
            return 3
        case .saveForBots:
            return 4
        case .restrictionBypassLink:
            return 5
        case .info:
            return 6
        case .recordsHeader:
            return 10
        case let .record(index, _, _, _, _):
            return 100 + Int32(index)
        case .empty:
            return 900
        case .clear:
            return 1000
        case .mediaHeader:
            return 2000
        case let .mediaToggle(option, _, _):
            return 2000 + option.rawValue
        case .mediaFileLimit:
            return 2020
        case .mediaQuota:
            return 2021
        case .mediaArchiveScreen:
            return 2022
        case .mediaInfo:
            return 2023
        }
    }

    static func <(lhs: FullGramMessageHistoryEntry, rhs: FullGramMessageHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramMessageHistoryArguments
        switch self {
        case let .header(text), let .recordsHeader(text), let .mediaHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .saveDeleted(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleDeleted)
        case let .dimDeleted(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleDimDeleted)
        case let .saveEdits(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleEdits)
        case let .saveForBots(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleBots)
        case let .restrictionBypassLink(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openRestrictionBypass
            )
        case let .info(text), let .empty(text), let .mediaInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .record(_, record, title, label, detail):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.showRecord(record, title, detail)
                }
            )
        case let .clear(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.clear
            )
        case let .mediaToggle(option, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.toggleMedia(option, newValue)
                }
            )
        case let .mediaFileLimit(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.selectFileLimit
            )
        case let .mediaQuota(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.selectQuota
            )
        case let .mediaArchiveScreen(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openMediaArchive
            )
        }
    }
}

public func fullGramMessageHistoryController(context: AccountContext) -> ViewController {
    var presentRecordImpl: ((FullGramMessageHistoryRecord, String, String) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let extrasChanged = ValuePromise<Int>(0, ignoreRepeated: false)
    var extrasVersion = 0
    let observer = NotificationCenter.default.addObserver(
        forName: FullGramExtras.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        extrasVersion += 1
        extrasChanged.set(extrasVersion)
    }

    let arguments = FullGramMessageHistoryArguments(
        toggleEdits: { value in
            let _ = context.engine.messages.updateFullGramMessageHistory(saveEdits: value).start()
        },
        toggleDeleted: { value in
            let _ = context.engine.messages.updateFullGramMessageHistory(saveDeleted: value).start()
        },
        toggleDimDeleted: { value in
            FullGramExtras.shared.dimDeletedMessages = value
        },
        toggleBots: { value in
            let _ = context.engine.messages.updateFullGramMessageHistory(saveForBots: value).start()
        },
        openRestrictionBypass: {
            pushControllerImpl?(fullGramRestrictionBypassController(context: context))
        },
        toggleMedia: { option, value in
            switch option {
            case .saveMedia:
                let _ = context.engine.messages.updateFullGramMessageHistory(saveMedia: value).start()
            case .privateChats:
                let _ = context.engine.messages.updateFullGramMessageHistory(mediaPrivateChats: value).start()
            case .publicChannels:
                let _ = context.engine.messages.updateFullGramMessageHistory(mediaPublicChannels: value).start()
            case .privateChannels:
                let _ = context.engine.messages.updateFullGramMessageHistory(mediaPrivateChannels: value).start()
            case .publicGroups:
                let _ = context.engine.messages.updateFullGramMessageHistory(mediaPublicGroups: value).start()
            case .privateGroups:
                let _ = context.engine.messages.updateFullGramMessageHistory(mediaPrivateGroups: value).start()
            }
        },
        selectFileLimit: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let sheet = ActionSheetController(presentationData: presentationData)
            let options: [Int32] = [5, 15, 30, 50, 100]
            let items: [ActionSheetItem] = options.map { limit in
                ActionSheetButtonItem(title: "\(limit) МБ", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    let _ = context.engine.messages.fullGramSetMediaArchiveLimits(fileLimitMB: limit).start()
                })
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: isRussian ? "Отмена" : "Cancel", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        selectQuota: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let sheet = ActionSheetController(presentationData: presentationData)
            let options: [Int32] = [100, 250, 500, 1000, 2000]
            let items: [ActionSheetItem] = options.map { quota in
                ActionSheetButtonItem(title: "\(quota) МБ", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    let _ = context.engine.messages.fullGramSetMediaArchiveLimits(quotaMB: quota).start()
                })
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: isRussian ? "Отмена" : "Cancel", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        openMediaArchive: {
            pushControllerImpl?(FullGramMediaArchiveScreen(context: context))
        },
        clear: {
            let _ = context.engine.messages.updateFullGramMessageHistory(clear: true).start()
        },
        showRecord: { record, title, detail in
            presentRecordImpl?(record, title, detail)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.engine.messages.fullGramMessageHistory(),
        extrasChanged.get()
    )
    |> mapToSignal { presentationData, state, _ -> Signal<(PresentationData, FullGramMessageHistoryState, [Int64: String]), NoError> in
        let peerIds = Set(state.records.map { $0.peerId })
        if peerIds.isEmpty {
            return .single((presentationData, state, [:]))
        }
        return context.account.postbox.transaction { transaction -> [Int64: String] in
            var names: [Int64: String] = [:]
            for rawId in peerIds {
                let peerId = PeerId(rawId)
                if let peer = transaction.getPeer(peerId) {
                    names[rawId] = EnginePeer(peer).compactDisplayTitle
                }
            }
            return names
        }
        |> map { names in
            return (presentationData, state, names)
        }
    }
    |> deliverOnMainQueue
    |> map { presentationData, state, peerNames -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        let bypassActive = FullGramExtras.shared.saveViewOnce
        var entries: [FullGramMessageHistoryEntry] = [
            .header(t("СОХРАНЕНИЕ СООБЩЕНИЙ", "MESSAGE RETENTION")),
            .saveDeleted(t("Сохранять удалённые сообщения", "Save deleted messages"), state.saveDeleted),
            .dimDeleted(t("Делать удалённые полупрозрачными", "Make deleted messages translucent"), FullGramExtras.shared.dimDeletedMessages),
            .saveEdits(t("Сохранять историю изменений", "Save message edits"), state.saveEdits),
            .saveForBots(t("Сохранять сообщения ботов", "Save bot messages"), state.saveForBots),
            .restrictionBypassLink(
                t("Обход ограничений (одноразовые)", "Restriction bypass (view-once)"),
                bypassActive ? t("Вкл.", "On") : t("Выкл.", "Off")
            ),
            .info(t(
                "Удалённые сообщения остаются в чате с пометкой «Удалено» (при желании — полупрозрачными), а предыдущие версии изменённых и удалённых сообщений сохраняются в списке ниже прямо на устройстве.",
                "Deleted messages stay in chats with a 'Deleted' label (translucent when enabled), and previous versions of edited and deleted messages are stored locally below."
            )),
            .recordsHeader(t("ЖУРНАЛ (\(state.records.count))", "ARCHIVE (\(state.records.count))"))
        ]

        if state.records.isEmpty {
            entries.append(.empty(t("Пока нет сохранённых изменений или удалённых сообщений.", "No archived edits or deleted messages yet.")))
        } else {
            for (index, record) in state.records.reversed().prefix(80).enumerated() {
                let kindLabel = record.kind == .deleted ? t("Удалено", "Deleted") : t("Изменено", "Edited")
                let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(record.capturedAt)))
                let peerTitle = peerNames[record.peerId] ?? "ID \(PeerId(record.peerId).id._internalGetInt64Value())"
                let preview = record.text.isEmpty ? t("Медиа", "Media") : record.text.replacingOccurrences(of: "\n", with: " ")
                let clipped = preview.count > 44 ? String(preview.prefix(44)) + "…" : preview
                let attachmentsCount = record.attachments?.count ?? 0
                let mediaSuffix = attachmentsCount > 0 ? " [📎\(attachmentsCount)]" : ""
                let detail = "\(peerTitle)\n\(kindLabel): \(date)\n\n\(record.text)"
                entries.append(.record(index, record, "[\(kindLabel)] \(peerTitle): \(clipped)\(mediaSuffix)", date, detail))
            }
            entries.append(.clear(t("Очистить архив", "Clear archive")))
        }

        let files = context.engine.messages.fullGramArchivedMediaFiles()
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        let archiveSummary = files.isEmpty
            ? t("Пусто", "Empty")
            : "\(files.count) • \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))"

        entries.append(.mediaHeader(t("АРХИВ МЕДИА", "MEDIA ARCHIVE")))
        entries.append(.mediaToggle(.saveMedia, t("Сохранять медиа из удалённых и изменённых", "Save media from deleted & edited"), state.saveMedia))
        if state.saveMedia {
            entries.append(.mediaToggle(.privateChats, t("Личные чаты", "Private chats"), state.mediaPrivateChats))
            entries.append(.mediaToggle(.privateGroups, t("Частные группы", "Private groups"), state.mediaPrivateGroups))
            entries.append(.mediaToggle(.publicGroups, t("Публичные группы", "Public groups"), state.mediaPublicGroups))
            entries.append(.mediaToggle(.privateChannels, t("Частные каналы", "Private channels"), state.mediaPrivateChannels))
            entries.append(.mediaToggle(.publicChannels, t("Публичные каналы", "Public channels"), state.mediaPublicChannels))
        }
        entries.append(.mediaFileLimit(t("Макс. размер одного файла", "Max single file size"), "\(state.mediaFileLimitMB) МБ"))
        entries.append(.mediaQuota(t("Лимит хранилища архива", "Archive storage quota"), "\(state.mediaQuotaMB) МБ"))
        entries.append(.mediaArchiveScreen(t("Открыть архив медиа", "Open media archive"), archiveSummary))
        entries.append(.mediaInfo(t(
            "Фото, видео, кружки, голосовые сообщения и файлы, загруженные на устройство до удаления или редактирования, сохраняются в локальный архив медиа.",
            "Photos, videos, video messages, voice messages, and files downloaded before deletion or editing are saved to the local media archive."
        )))

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Удалённые и изменённые", "Deleted & Edited")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentRecordImpl = { [weak controller] record, title, detail in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        var actions: [TextAlertAction] = []
        if let firstAttachment = record.attachments?.first,
           let url = context.engine.messages.fullGramArchivedAttachmentUrl(storedName: firstAttachment.storedName) {
            actions.append(TextAlertAction(
                type: .genericAction,
                title: isRussian ? "Открыть медиа" : "Open Media",
                action: { [weak controller] in
                    let preview = FullGramSingleFilePreviewController(url: url, title: firstAttachment.displayName)
                    controller?.present(preview, in: .window(.root))
                }
            ))
        }
        actions.append(TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {}))
        controller?.present(
            textAlertController(
                context: context,
                title: title,
                text: detail,
                actions: actions
            ),
            in: .window(.root)
        )
    }
    return controller
}

// MARK: - Экран просмотра Архива Медиа

private final class FullGramQuickLookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(url: URL, title: String) {
        self.previewItemURL = url
        self.previewItemTitle = title
        super.init()
    }
}

private final class FullGramSingleFilePreviewController: ViewController, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private let item: FullGramQuickLookItem
    private var didPresentPreview: Bool = false

    init(url: URL, title: String) {
        self.item = FullGramQuickLookItem(url: url, title: title)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !self.didPresentPreview else { return }
        self.didPresentPreview = true
        let ql = QLPreviewController()
        ql.dataSource = self
        ql.delegate = self
        var presenter = self.view.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        if let presenter {
            presenter.present(ql, animated: true)
        } else {
            self.dismiss()
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return self.item
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        self.dismiss()
    }
}

private struct FullGramMediaArchiveArguments {
    let openFile: (URL, String) -> Void
    let deleteFile: (String) -> Void
    let clearAll: () -> Void
}

private enum FullGramMediaArchiveEntry: ItemListNodeEntry {
    case summaryHeader(String)
    case summaryInfo(String)
    case filesHeader(String)
    case fileItem(Int, String, String, String, URL)
    case empty(String)
    case clearAll(String)

    var section: ItemListSectionId {
        switch self {
        case .summaryHeader, .summaryInfo:
            return 0
        case .filesHeader, .fileItem, .empty:
            return 1
        case .clearAll:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .summaryHeader:
            return 0
        case .summaryInfo:
            return 1
        case .filesHeader:
            return 10
        case let .fileItem(index, _, _, _, _):
            return 100 + Int32(index)
        case .empty:
            return 9000
        case .clearAll:
            return 9001
        }
    }

    static func <(lhs: FullGramMediaArchiveEntry, rhs: FullGramMediaArchiveEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramMediaArchiveArguments
        switch self {
        case let .summaryHeader(text), let .filesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .summaryInfo(text), let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .fileItem(_, _, title, label, url):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openFile(url, title)
                }
            )
        case let .clearAll(title):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: .destructive,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: arguments.clearAll
            )
        }
    }
}

public func FullGramMediaArchiveScreen(context: AccountContext) -> ViewController {
    let reloadTrigger = ValuePromise<Int>(0, ignoreRepeated: false)
    var reloadCounter = 0
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = FullGramMediaArchiveArguments(
        openFile: { url, _ in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let sheet = ActionSheetController(presentationData: presentationData)
            let storedName = url.lastPathComponent
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: isRussian ? "Просмотреть / Поделиться" : "Preview / Share", color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
                           let root = window.rootViewController {
                            root.present(activity, animated: true)
                        }
                    }),
                    ActionSheetButtonItem(title: isRussian ? "Удалить из архива" : "Delete from archive", color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let _ = (context.engine.messages.fullGramRemoveArchivedMedia(storedNames: [storedName])
                        |> deliverOnMainQueue).start(completed: {
                            reloadCounter += 1
                            reloadTrigger.set(reloadCounter)
                        })
                    })
                ]),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: isRussian ? "Отмена" : "Cancel", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        deleteFile: { storedName in
            let _ = (context.engine.messages.fullGramRemoveArchivedMedia(storedNames: [storedName])
            |> deliverOnMainQueue).start(completed: {
                reloadCounter += 1
                reloadTrigger.set(reloadCounter)
            })
        },
        clearAll: {
            let files = context.engine.messages.fullGramArchivedMediaFiles()
            let allNames = Set(files.map { $0.storedName })
            guard !allNames.isEmpty else { return }
            let _ = (context.engine.messages.fullGramRemoveArchivedMedia(storedNames: allNames)
            |> deliverOnMainQueue).start(completed: {
                reloadCounter += 1
                reloadTrigger.set(reloadCounter)
            })
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.engine.messages.fullGramMessageHistory(),
        reloadTrigger.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, state, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let files = context.engine.messages.fullGramArchivedMediaFiles()
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.byteCount }
        let formattedSize = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        let displayByStoredName: [String: String] = Dictionary(
            state.records.flatMap { $0.attachments ?? [] }.map { ($0.storedName, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )

        var entries: [FullGramMediaArchiveEntry] = [
            .summaryHeader(t("СТАТИСТИКА ХРАНИЛИЩА", "STORAGE SUMMARY")),
            .summaryInfo(t(
                "Файлов в архиве: \(files.count) • Занято: \(formattedSize) из \(state.mediaQuotaMB) МБ.",
                "Archived files: \(files.count) • Used: \(formattedSize) of \(state.mediaQuotaMB) MB."
            )),
            .filesHeader(t("СОХРАНЁННЫЕ ФАЙЛЫ", "SAVED FILES"))
        ]

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if files.isEmpty {
            entries.append(.empty(t("В архиве медиа пока нет сохранённых файлов.", "No media files in the archive yet.")))
        } else {
            for (index, file) in files.prefix(200).enumerated() {
                let displayName = displayByStoredName[file.storedName] ?? file.storedName
                let sizeStr = ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file)
                let dateStr = formatter.string(from: file.createdAt)
                entries.append(.fileItem(index, file.storedName, displayName, "\(sizeStr) • \(dateStr)", file.url))
            }
            entries.append(.clearAll(t("Очистить весь архив медиа", "Clear entire media archive")))
        }

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Архив медиа", "Media Archive")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - 2. Вкладка «Обход ограничений»

private enum FullGramRestrictionBypassToggle: Int32 {
    case saveViewOnce = 1
    case viewOnceMenuSave = 2
    case viewOnceKeepInChat = 3
    case viewOnceReview = 4
}

private enum FullGramRestrictionBypassEntry: ItemListNodeEntry {
    case header(String)
    case toggle(FullGramRestrictionBypassToggle, String, Bool)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .toggle(option, _, _):
            return option.rawValue
        case .info:
            return 100
        }
    }

    static func <(lhs: FullGramRestrictionBypassEntry, rhs: FullGramRestrictionBypassEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let update = arguments as! (FullGramRestrictionBypassToggle, Bool) -> Void
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(option, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    update(option, newValue)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramRestrictionBypassController(context: AccountContext) -> ViewController {
    let extrasChanged = ValuePromise<Int>(0, ignoreRepeated: false)
    var extrasVersion = 0
    let observer = NotificationCenter.default.addObserver(
        forName: FullGramExtras.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        extrasVersion += 1
        extrasChanged.set(extrasVersion)
    }

    let update: (FullGramRestrictionBypassToggle, Bool) -> Void = { option, value in
        switch option {
        case .saveViewOnce:
            FullGramExtras.shared.saveViewOnce = value
        case .viewOnceMenuSave:
            FullGramExtras.shared.viewOnceMenuSave = value
        case .viewOnceKeepInChat:
            FullGramExtras.shared.viewOnceKeepInChat = value
        case .viewOnceReview:
            FullGramExtras.shared.viewOnceReview = value
        }
    }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        extrasChanged.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let extras = FullGramExtras.shared
        var entries: [FullGramRestrictionBypassEntry] = [
            .header(t("ОДНОРАЗОВЫЕ МЕДИА (ФОТО, ВИДЕО, КРУЖКИ)", "VIEW-ONCE MEDIA (PHOTOS, VIDEOS, VIDEO NOTES)")),
            .toggle(.saveViewOnce, t("Сохранять одноразовые", "Save view-once media"), extras.saveViewOnce)
        ]

        if extras.saveViewOnce {
            entries.append(.toggle(.viewOnceMenuSave, t("Кнопка «Сохранить» в меню", "Save button in context menu"), extras.viewOnceMenuSave))
            entries.append(.toggle(.viewOnceKeepInChat, t("Сохранить в чате после просмотра", "Keep in chat after viewing"), extras.viewOnceKeepInChat))
            entries.append(.toggle(.viewOnceReview, t("Возможность повторного просмотра", "Allow repeated viewing"), extras.viewOnceReview))
        }

        entries.append(.info(t(
            "При включении «Сохранять одноразовые» одноразовые фотографии, видео и видеокружки можно сохранять через меню сообщения, оставлять в чате после истечения таймера и открывать повторно без сжигания.",
            "When enabled, view-once photos, videos, and video messages can be saved from the message menu, kept in chat after expiration, and viewed repeatedly without burning."
        )))

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Обход ограничений", "Restriction Bypass")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, update))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - 3. Вкладка «Сообщение» (бывшее «Отправка»)

private enum FullGramSendingToggle: Int32 {
    case quickFormattingBar = 1
    case antiCaps = 2
    case translateBeforeSend = 3
    case audioTrimSpliceBeforeSend = 4
    case renameFileBeforeSend = 5
    case confirmSendBeforePosting = 6
    case confirmSendForAllChats = 7
    case autoCropScreenshots = 8
    case chooseVideoNoteCoverBeforeSend = 9
    case editForwardedBeforeSend = 10
    case smartTransferQueue = 11
    case autoResumeDownloadsOnReconnect = 12
}

private struct FullGramSendingArguments {
    let toggle: (FullGramSendingToggle, Bool) -> Void
    let selectTranslateLanguage: () -> Void
    let openAudioStudio: () -> Void
    let openTransferQueue: () -> Void
}

private enum FullGramSendingEntry: ItemListNodeEntry {
    case textHeader(String)
    case toggle(FullGramSendingToggle, String, Bool)
    case translateLanguage(String, String)
    case mediaHeader(String)
    case queueHeader(String)
    case openAudioStudio(String)
    case openTransferQueue(String, String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .textHeader, .toggle(.quickFormattingBar, _, _), .toggle(.antiCaps, _, _), .toggle(.translateBeforeSend, _, _), .translateLanguage:
            return 0
        case .mediaHeader, .toggle:
            return 1
        case .queueHeader, .openAudioStudio, .openTransferQueue, .info:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .textHeader:
            return 0
        case let .toggle(option, _, _):
            return option.rawValue
        case .translateLanguage:
            return 15
        case .mediaHeader:
            return 20
        case .queueHeader:
            return 40
        case .openAudioStudio:
            return 45
        case .openTransferQueue:
            return 46
        case .info:
            return 60
        }
    }

    static func <(lhs: FullGramSendingEntry, rhs: FullGramSendingEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramSendingArguments
        switch self {
        case let .textHeader(text), let .mediaHeader(text), let .queueHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(option, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    arguments.toggle(option, newValue)
                }
            )
        case let .translateLanguage(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.selectTranslateLanguage
            )
        case let .openAudioStudio(title):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openAudioStudio
            )
        case let .openTransferQueue(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openTransferQueue
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramSendingController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    let extrasChanged = ValuePromise<Int>(0, ignoreRepeated: false)
    var extrasVersion = 0
    let observer = NotificationCenter.default.addObserver(
        forName: FullGramExtras.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        extrasVersion += 1
        extrasChanged.set(extrasVersion)
    }
    let queueObserver = NotificationCenter.default.addObserver(
        forName: FullGramTransferQueue.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        extrasVersion += 1
        extrasChanged.set(extrasVersion)
    }

    let arguments = FullGramSendingArguments(
        toggle: { option, value in
            switch option {
            case .antiCaps:
                FullGramExtras.shared.antiCaps = value
            case .translateBeforeSend:
                FullGramExtras.shared.translateBeforeSend = value
            case .quickFormattingBar:
                FullGramExtras.shared.quickFormattingBar = value
            case .audioTrimSpliceBeforeSend:
                FullGramExtras.shared.audioTrimSpliceBeforeSend = value
            case .renameFileBeforeSend:
                FullGramExtras.shared.renameFileBeforeSend = value
            case .confirmSendBeforePosting:
                FullGramExtras.shared.confirmSendBeforePosting = value
            case .confirmSendForAllChats:
                FullGramExtras.shared.confirmSendForAllChats = value
            case .autoCropScreenshots:
                FullGramExtras.shared.autoCropScreenshots = value
            case .chooseVideoNoteCoverBeforeSend:
                FullGramExtras.shared.chooseVideoNoteCoverBeforeSend = value
            case .editForwardedBeforeSend:
                FullGramExtras.shared.editForwardedBeforeSend = value
            case .smartTransferQueue:
                FullGramExtras.shared.smartTransferQueue = value
            case .autoResumeDownloadsOnReconnect:
                FullGramExtras.shared.autoResumeDownloadsOnReconnect = value
            }
        },
        selectTranslateLanguage: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let sheet = ActionSheetController(presentationData: presentationData)
            let items: [ActionSheetItem] = FullGramTranslationSettings.supportedLanguageCodes.map { code in
                ActionSheetButtonItem(
                    title: "\(fullGramLanguageDisplayName(code: code, isRussian: isRussian)) (\(code.uppercased()))",
                    color: .accent,
                    action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        FullGramExtras.shared.translateTo = code
                    }
                )
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: isRussian ? "Отмена" : "Cancel", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        openAudioStudio: {
            let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            pushControllerImpl?(FullGramAudioTrimSpliceController(initialURL: nil, title: isRussian ? "Студия аудио" : "Audio Studio"))
        },
        openTransferQueue: {
            pushControllerImpl?(fullGramTransferQueueController(context: context))
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        extrasChanged.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let extras = FullGramExtras.shared

        var entries: [FullGramSendingEntry] = [
            .textHeader(t("ОБРАБОТКА ТЕКСТА", "TEXT PROCESSING")),
            .toggle(.quickFormattingBar, t("Панель быстрого форматирования", "Quick formatting bar"), extras.quickFormattingBar),
            .toggle(.antiCaps, t("Анти-капс", "Anti-caps"), extras.antiCaps),
            .toggle(.translateBeforeSend, t("Перевод перед отправкой", "Translate before send"), extras.translateBeforeSend)
        ]

        if extras.translateBeforeSend {
            entries.append(.translateLanguage(
                t("Язык перевода перед отправкой", "Target language"),
                fullGramLanguageDisplayName(code: extras.translateTo, isRussian: isRussian)
            ))
        }

        entries.append(.mediaHeader(t("МЕДИА И ПОДТВЕРЖДЕНИЕ", "MEDIA & CONFIRMATION")))
        entries.append(.toggle(.audioTrimSpliceBeforeSend, t("Нарезка и склейка аудио перед отправкой", "Audio trim & splice before sending"), extras.audioTrimSpliceBeforeSend))
        entries.append(.toggle(.renameFileBeforeSend, t("Переименовывать файл перед отправкой", "Rename file before sending"), extras.renameFileBeforeSend))
        entries.append(.toggle(.autoCropScreenshots, t("Автообрезка скриншотов (убрать статус-бар)", "Auto-crop screenshots (remove status bar)"), extras.autoCropScreenshots))
        entries.append(.toggle(.chooseVideoNoteCoverBeforeSend, t("Выбор кадра-обложки кружка", "Choose cover frame for video notes"), extras.chooseVideoNoteCoverBeforeSend))
        entries.append(.toggle(.editForwardedBeforeSend, t("Правка текста перед пересылкой", "Edit forwarded text before sending"), extras.editForwardedBeforeSend))
        entries.append(.toggle(.confirmSendBeforePosting, t("Запрос перед отправкой («Вы точно хотите…»)", "Confirm before sending prompt"), extras.confirmSendBeforePosting))
        if extras.confirmSendBeforePosting {
            entries.append(.toggle(.confirmSendForAllChats, t("Спрашивать во всех чатах (не только выбранных)", "Confirm in all chats (not only selected)"), extras.confirmSendForAllChats))
        }

        let pendingCount = FullGramTransferQueue.shared.currentItems().filter { $0.status != .completed }.count
        let queueBadge = pendingCount > 0 ? "\(pendingCount)" : FullGramTransferQueue.shared.connectionKind
        entries.append(.queueHeader(t("ОЧЕРЕДЬ И ИНСТРУМЕНТЫ", "QUEUE & TOOLS")))
        entries.append(.toggle(.smartTransferQueue, t("Умная очередь отправки и загрузки", "Smart transfer queue"), extras.smartTransferQueue))
        entries.append(.toggle(.autoResumeDownloadsOnReconnect, t("Автодокачка при появлении сети", "Auto-resume on reconnect"), extras.autoResumeDownloadsOnReconnect))
        entries.append(.openAudioStudio(t("Студия нарезки и склейки аудио…", "Audio trim & splice studio…")))
        entries.append(.openTransferQueue(t("Очередь отправки и докачки файлов", "Transfer & resume queue"), queueBadge))

        entries.append(.info(t(
            "• В профиле нужного чата можно включить пункт «Запрос перед отправкой».\n• При пересылке сообщений нажмите на панель пересылки над полем ввода → «✂️ Править текст пересылки…».\n• Нарезка и автообрезка скриншотов работают полностью локально на устройстве.",
            "• Enable \"Confirm before sending\" per-chat from any Peer Info screen.\n• Tap the forward bar above the input field to trim or remove parts before sending.\n• Audio trimming and screenshot cropping run locally on-device."
        )))

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Сообщение и отправка", "Message & Sending")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
        NotificationCenter.default.removeObserver(queueObserver)
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

private enum FullGramTransferQueueSection: Int32 {
    case status = 0
    case actions = 1
    case items = 2
}

private final class FullGramTransferQueueArguments {
    let resumeAll: () -> Void
    let clearCompleted: () -> Void
    init(resumeAll: @escaping () -> Void, clearCompleted: @escaping () -> Void) {
        self.resumeAll = resumeAll
        self.clearCompleted = clearCompleted
    }
}

private enum FullGramTransferQueueEntry: ItemListNodeEntry {
    case statusHeader(String)
    case networkStatus(String, String)
    case resumeAll(String)
    case clearCompleted(String)
    case itemsHeader(String)
    case transferRow(Int32, String, String)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .statusHeader, .networkStatus:
            return FullGramTransferQueueSection.status.rawValue
        case .resumeAll, .clearCompleted:
            return FullGramTransferQueueSection.actions.rawValue
        case .itemsHeader, .transferRow, .empty:
            return FullGramTransferQueueSection.items.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .statusHeader: return 0
        case .networkStatus: return 1
        case .resumeAll: return 10
        case .clearCompleted: return 11
        case .itemsHeader: return 20
        case let .transferRow(idx, _, _): return 100 + idx
        case .empty: return 999
        }
    }

    static func <(lhs: FullGramTransferQueueEntry, rhs: FullGramTransferQueueEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramTransferQueueArguments
        switch self {
        case let .statusHeader(text), let .itemsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .networkStatus(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, enabled: false, action: {})
        case let .resumeAll(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.resumeAll)
        case let .clearCompleted(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.clearCompleted)
        case let .transferRow(_, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, enabled: false, action: {})
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramTransferQueueController(context: AccountContext) -> ViewController {
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let observer = NotificationCenter.default.addObserver(
        forName: FullGramTransferQueue.didChangeNotification,
        object: nil,
        queue: .main
    ) { _ in
        version += 1
        changed.set(version)
    }

    let args = FullGramTransferQueueArguments(
        resumeAll: {
            FullGramTransferQueue.shared.resumeAllNow()
        },
        clearCompleted: {
            FullGramTransferQueue.shared.clearCompleted()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let queue = FullGramTransferQueue.shared
        let items = queue.currentItems()
        var entries: [FullGramTransferQueueEntry] = [
            .statusHeader(t("СЕТЕВОЙ СТАТУС", "NETWORK STATUS")),
            .networkStatus(
                t("Соединение", "Connection"),
                queue.isConnected ? queue.connectionKind : t("Офлайн — пауза", "Offline — paused")
            ),
            .resumeAll(t("Докачать / возобновить все", "Resume all transfers")),
            .clearCompleted(t("Очистить завершённые", "Clear completed")),
            .itemsHeader(t("ПЕРЕДАЧИ (\(items.count))", "TRANSFERS (\(items.count))"))
        ]

        if items.isEmpty {
            entries.append(.empty(t(
                "Очередь пуста. Отправленные или загруженные файлы с включённой опцией «Умная очередь» будут отслеживаться здесь и автоматически возобновляться при восстановлении сети.",
                "Queue is empty. Files sent or downloaded with Smart Transfer Queue enabled will appear here and auto-resume when network returns."
            )))
        } else {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            for (index, item) in items.prefix(40).enumerated() {
                let dir = item.direction == .upload ? "↑" : "↓"
                let statusText: String
                switch item.status {
                case .queued: statusText = t("В очереди", "Queued")
                case .active: statusText = t("Активно", "Active")
                case .pausedByNetwork: statusText = t("Ждёт сеть", "Waiting network")
                case .completed: statusText = t("Готово", "Done")
                case .failed: statusText = t("Ошибка", "Failed")
                }
                let sizeLabel = item.byteCount > 0 ? "\(formatter.string(fromByteCount: item.byteCount)) · \(statusText)" : statusText
                entries.append(.transferRow(Int32(index), "\(dir) \(item.title)", sizeLabel))
            }
        }

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Очередь и докачка", "Transfer Queue")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - 4. Вкладка «Перевод» (без DeepL API Pro)

private struct FullGramTranslationArguments {
    let selectProvider: (FullGramTranslationSettings.Provider) -> Void
    let selectLanguage: () -> Void
    let editLibreEndpoint: () -> Void
    let editApiKey: (FullGramTranslationSettings.Provider) -> Void
}

private enum FullGramTranslationEntry: ItemListNodeEntry {
    case providerHeader(String)
    case providerItem(Int32, FullGramTranslationSettings.Provider, String, Bool)
    case languageHeader(String)
    case targetLanguage(String, String)
    case configHeader(String)
    case libreEndpoint(String, String)
    case apiKey(FullGramTranslationSettings.Provider, String, String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .providerHeader, .providerItem:
            return 0
        case .languageHeader, .targetLanguage:
            return 1
        case .configHeader, .libreEndpoint, .apiKey, .info:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .providerHeader:
            return 0
        case let .providerItem(index, _, _, _):
            return 1 + index
        case .languageHeader:
            return 10
        case .targetLanguage:
            return 11
        case .configHeader:
            return 20
        case .libreEndpoint:
            return 21
        case .apiKey:
            return 22
        case .info:
            return 30
        }
    }

    static func <(lhs: FullGramTranslationEntry, rhs: FullGramTranslationEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramTranslationArguments
        switch self {
        case let .providerHeader(text), let .languageHeader(text), let .configHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .providerItem(_, provider, title, selected):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                style: .left,
                checked: selected,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    arguments.selectProvider(provider)
                }
            )
        case let .targetLanguage(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.selectLanguage
            )
        case let .libreEndpoint(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.editLibreEndpoint
            )
        case let .apiKey(provider, title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.editApiKey(provider)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramTranslationSettingsController(context: AccountContext) -> ViewController {
    let store = context.account.network.fullGramGhostMode
    let accountId = context.account.peerId.toInt64()
    let keyVersion = ValuePromise<Int>(0, ignoreRepeated: false)
    var keyVersionCount = 0
    var presentControllerImpl: ((ViewController) -> Void)?

    let promptInput: (String, String, String, Bool, @escaping (String) -> Void) -> Void = { title, message, current, isSecure, completion in
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else {
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = current
            textField.isSecureTextEntry = isSecure
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            completion(text)
        })
        var presenter: UIViewController = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(alert, animated: true)
    }

    let arguments = FullGramTranslationArguments(
        selectProvider: { provider in
            try? store.update { settings in
                settings.translation.provider = provider
            }
        },
        selectLanguage: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let sheet = ActionSheetController(presentationData: presentationData)
            let items: [ActionSheetItem] = FullGramTranslationSettings.supportedLanguageCodes.map { code in
                ActionSheetButtonItem(
                    title: "\(fullGramLanguageDisplayName(code: code, isRussian: isRussian)) (\(code.uppercased()))",
                    color: .accent,
                    action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        try? store.update { settings in
                            settings.translation.targetLanguage = code
                        }
                    }
                )
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: isRussian ? "Отмена" : "Cancel", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        },
        editLibreEndpoint: {
            let current = store.current.translation.libreTranslateURL
            promptInput(
                "LibreTranslate URL",
                "Введите HTTPS-адрес сервера LibreTranslate (например, https://libretranslate.com):",
                current,
                false,
                { value in
                    try? store.update { settings in
                        settings.translation.libreTranslateURL = FullGramTranslationSettings.normalizeEndpoint(value)
                    }
                }
            )
        },
        editApiKey: { provider in
            let current = FullGramTranslationKeys.apiKey(for: provider, accountId: accountId)
            let title = provider == .deepLFree ? "Ключ DeepL API Free" : "Ключ LibreTranslate API"
            promptInput(
                title,
                "Ключ хранится локально в защищённой связке ключей устройства (Keychain):",
                current,
                true,
                { value in
                    FullGramTranslationKeys.setApiKey(value, for: provider, accountId: accountId)
                    keyVersionCount += 1
                    keyVersion.set(keyVersionCount)
                }
            )
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        store.signal,
        keyVersion.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, ghostSettings, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let translation = ghostSettings.translation
        var entries: [FullGramTranslationEntry] = [
            .providerHeader(t("ПРОВАЙДЕР ПЕРЕВОДА", "TRANSLATION PROVIDER")),
            .providerItem(0, .telegram, "Telegram", translation.provider == .telegram),
            .providerItem(1, .libreTranslate, "LibreTranslate", translation.provider == .libreTranslate),
            .providerItem(2, .deepLFree, "DeepL API Free", translation.provider == .deepLFree),
            .languageHeader(t("ЯЗЫК ПЕРЕВОДА", "TARGET LANGUAGE")),
            .targetLanguage(
                t("Переводить сообщения на", "Translate messages to"),
                fullGramLanguageDisplayName(code: translation.targetLanguage, isRussian: isRussian)
            )
        ]

        switch translation.provider {
        case .telegram:
            entries.append(.info(t(
                "Используется встроенный переводчик Telegram без дополнительных ключей.",
                "Uses built-in Telegram translation without extra API keys."
            )))
        case .libreTranslate:
            let endpointLabel = translation.libreTranslateURL.isEmpty ? t("Не задан", "Not set") : translation.libreTranslateURL
            let hasKey = !FullGramTranslationKeys.apiKey(for: .libreTranslate, accountId: accountId).isEmpty
            entries.append(.configHeader("LIBRETRANSLATE"))
            entries.append(.libreEndpoint(t("Сервер (HTTPS)", "Server URL (HTTPS)"), endpointLabel))
            entries.append(.apiKey(.libreTranslate, t("API-ключ (необязательно)", "API Key (optional)"), hasKey ? t("Задан", "Set") : t("Нет", "None")))
            entries.append(.info(t(
                "Укажите HTTPS-адрес вашего или публичного сервера LibreTranslate.",
                "Specify the HTTPS URL of a LibreTranslate server."
            )))
        case .deepLFree:
            let hasKey = !FullGramTranslationKeys.apiKey(for: .deepLFree, accountId: accountId).isEmpty
            entries.append(.configHeader("DEEPL API FREE"))
            entries.append(.apiKey(.deepLFree, t("Ключ DeepL API Free", "DeepL API Free Key"), hasKey ? t("Задан", "Set") : t("Не задан", "Not set")))
            entries.append(.info(t(
                "Используется официальный бесплатный шлюз api-free.deepl.com.",
                "Uses the official free endpoint api-free.deepl.com."
            )))
        }

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Перевод", "Translation")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - 5. Вкладка «Меню сообщения» (бывшее «Меню и жесты») и «Реакции в чатах»

private enum FullGramMessageMenuOption: Int32 {
    case showReactionPicker = 1
    case showReadSummary = 2
    case showEditedInfo = 3
    case showAuthorSearch = 4
    case showCopyMessageIds = 5
}

private enum FullGramMessageMenuEntry: ItemListNodeEntry {
    case header(String)
    case toggle(FullGramMessageMenuOption, String, Bool)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .toggle(option, _, _):
            return option.rawValue
        case .info:
            return 100
        }
    }

    static func <(lhs: FullGramMessageMenuEntry, rhs: FullGramMessageMenuEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let update = arguments as! (FullGramMessageMenuOption, Bool) -> Void
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(option, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in
                    update(option, newValue)
                }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramMessageMenuController(context: AccountContext) -> ViewController {
    let store = context.account.network.fullGramGhostMode

    let update: (FullGramMessageMenuOption, Bool) -> Void = { option, value in
        try? store.update { settings in
            switch option {
            case .showReactionPicker:
                settings.interface.showReactionPicker = value
            case .showReadSummary:
                settings.interface.showReadSummary = value
            case .showEditedInfo:
                settings.interface.showEditedInfo = value
            case .showAuthorSearch:
                settings.interface.showAuthorSearch = value
            case .showCopyMessageIds:
                settings.interface.showCopyMessageIds = value
            }
        }
    }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        store.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, ghostSettings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let ui = ghostSettings.interface
        let entries: [FullGramMessageMenuEntry] = [
            .header(t("ЭЛЕМЕНТЫ КОНТЕКСТНОГО МЕНЮ", "CONTEXT MENU ITEMS")),
            .toggle(.showReactionPicker, t("Полоса быстрых реакций", "Quick reaction bar"), ui.showReactionPicker),
            .toggle(.showReadSummary, t("Сводка прочтений и реакций", "Read & reaction summary"), ui.showReadSummary),
            .toggle(.showEditedInfo, t("Дата и время изменения", "Edited date & time"), ui.showEditedInfo),
            .toggle(.showAuthorSearch, t("Кнопка «Сообщения автора» в группах", "'Author's messages' search in groups"), ui.showAuthorSearch),
            .toggle(.showCopyMessageIds, t("Пункты копирования ID сообщения и автора", "Copy message ID & author ID items"), ui.showCopyMessageIds),
            .info(t(
                "Выберите, какие дополнительные пункты должны отображаться при долгом нажатии на сообщение в чате.",
                "Choose which items appear when long-pressing a message in a chat."
            ))
        ]

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Меню сообщения", "Message Menu")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, update))
    }

    return ItemListController(context: context, state: signal)
}

private struct FullGramReactionsArguments {
    let toggleEnabled: (Bool) -> Void
    let toggleCounts: (Bool) -> Void
    let selectMaxCount: () -> Void
}

private enum FullGramReactionsEntry: ItemListNodeEntry {
    case header(String)
    case enabled(String, Bool)
    case showCounts(String, Bool)
    case maxVisible(String, String)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case .enabled:
            return 1
        case .showCounts:
            return 2
        case .maxVisible:
            return 3
        case .info:
            return 4
        }
    }

    static func <(lhs: FullGramReactionsEntry, rhs: FullGramReactionsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramReactionsArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .enabled(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleEnabled)
        case let .showCounts(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: arguments.toggleCounts)
        case let .maxVisible(title, label):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.selectMaxCount
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramReactionSettingsController(context: AccountContext) -> ViewController {
    let store = context.account.network.fullGramGhostMode
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = FullGramReactionsArguments(
        toggleEnabled: { value in
            try? store.update { settings in
                settings.reactionDisplay.enabled = value
            }
        },
        toggleCounts: { value in
            try? store.update { settings in
                settings.reactionDisplay.showCounts = value
            }
        },
        selectMaxCount: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            let sheet = ActionSheetController(presentationData: presentationData)
            let counts: [Int32] = [1, 2, 3, 4, 5, 6, 8, 11]
            let items: [ActionSheetItem] = counts.map { count in
                ActionSheetButtonItem(title: "\(count)", color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    try? store.update { settings in
                        settings.reactionDisplay.maxVisibleCount = count
                    }
                })
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: isRussian ? "Отмена" : "Cancel", color: .accent, font: .bold, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                    })
                ])
            ])
            presentControllerImpl?(sheet)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        store.signal
    )
    |> deliverOnMainQueue
    |> map { presentationData, ghostSettings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }

        let r = ghostSettings.reactionDisplay
        var entries: [FullGramReactionsEntry] = [
            .header(t("ОТОБРАЖЕНИЕ РЕАКЦИЙ ПОД СООБЩЕНИЯМИ", "MESSAGE REACTIONS DISPLAY")),
            .enabled(t("Показывать реакции под сообщениями", "Show reactions under messages"), r.enabled)
        ]

        if r.enabled {
            entries.append(.showCounts(t("Показывать счётчики реакций", "Show reaction counters"), r.showCounts))
            entries.append(.maxVisible(t("Макс. число видов реакций", "Max visible reaction types"), "\(r.maxVisibleCount)"))
        }

        entries.append(.info(t(
            "Настройте, сколько различных реакций отображается под пузырём сообщения и нужно ли показывать их количество.",
            "Configure how many reaction types are displayed under message bubbles and whether counters are shown."
        )))

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Реакции в чатах", "Reactions in Chats")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: data,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Раздел «Оформление» (2.1 Шрифты, 2.2 Темы, 2.3 Дизайн, 2.4 Иконки приложения)

private struct FullGramAppearanceCategoryArguments {
    let openFonts: () -> Void
    let openThemes: () -> Void
    let openDesign: () -> Void
    let openIcons: () -> Void
    let openFrames: () -> Void
    let openNicknames: () -> Void
}

private enum FullGramAppearanceCategoryEntry: ItemListNodeEntry {
    case fonts(String)
    case themes(String)
    case design(String)
    case icons(String)
    case frames(String, String)
    case nicknames(String, String)

    var section: ItemListSectionId {
        switch self {
        case .fonts, .themes, .design, .icons: return 0
        case .frames, .nicknames: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .fonts: return 0
        case .themes: return 1
        case .design: return 2
        case .icons: return 3
        case .frames: return 10
        case .nicknames: return 11
        }
    }

    static func <(lhs: FullGramAppearanceCategoryEntry, rhs: FullGramAppearanceCategoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramAppearanceCategoryArguments
        switch self {
        case let .fonts(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: FullGramSettingsIcons.symbol("textformat", color: UIColor(rgb: 0x007AFF)), title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openFonts)
        case let .themes(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: FullGramSettingsIcons.symbol("paintpalette.fill", color: UIColor(rgb: 0xFF2D55)), title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openThemes)
        case let .design(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: FullGramSettingsIcons.symbol("sparkles.rectangle.stack.fill", color: UIColor(rgb: 0x5856D6)), title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openDesign)
        case let .icons(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: FullGramSettingsIcons.symbol("app.badge.fill", color: UIColor(rgb: 0xFF9500)), title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openIcons)
        case let .frames(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: FullGramSettingsIcons.symbol("person.crop.circle.dashed", color: UIColor(rgb: 0x34C759)), title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openFrames)
        case let .nicknames(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: FullGramSettingsIcons.symbol("signature", color: UIColor(rgb: 0xAF52DE)), title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openNicknames)
        }
    }
}

public func fullGramAppearanceCategoryController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let cosmeticsTick = ValuePromise<Int>(0, ignoreRepeated: false)
    let tickCounter = Atomic<Int>(value: 0)
    let bump: @Sendable () -> Void = {
        cosmeticsTick.set(tickCounter.modify { $0 + 1 })
    }
    let cloudObs = NotificationCenter.default.addObserver(forName: FullGramCloudCosmetics.didChangeNotification, object: nil, queue: .main) { _ in bump() }
    let framesObs = NotificationCenter.default.addObserver(forName: FullGramAvatarFrames.didChangeNotification, object: nil, queue: .main) { _ in bump() }
    let nickObs = NotificationCenter.default.addObserver(forName: FullGramNicknameStyle.didChangeNotification, object: nil, queue: .main) { _ in bump() }

    let args = FullGramAppearanceCategoryArguments(
        openFonts: { pushImpl?(fullGramFontsController(context: context)) },
        openThemes: { pushImpl?(fullGramThemesController(context: context)) },
        openDesign: { pushImpl?(fullGramDesignController(context: context)) },
        openIcons: { pushImpl?(fullGramAppIconsController(context: context)) },
        openFrames: { pushImpl?(fullGramAvatarFramesController(context: context)) },
        openNicknames: { pushImpl?(fullGramNicknameStyleController(context: context)) }
    )
    let selfPeerId = context.account.peerId.toInt64()
    let signal = combineLatest(context.sharedContext.presentationData, cosmeticsTick.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let frameLabel = FullGramAvatarFrames.selectedFrameId(forPeerId: selfPeerId, selfPeerId: selfPeerId) != nil ? "Вкл." : "Выкл."
        let nickLabel = FullGramNicknameStyle.statusSummary(forPeerId: selfPeerId, selfPeerId: selfPeerId)
        let entries: [FullGramAppearanceCategoryEntry] = [
            .fonts("Шрифты"),
            .themes("Темы"),
            .design("Дизайн"),
            .icons("Иконки приложения"),
            .frames("Анимированные рамки", frameLabel),
            .nicknames("Стили ников", nickLabel)
        ]
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Оформление"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(cloudObs)
        NotificationCenter.default.removeObserver(framesObs)
        NotificationCenter.default.removeObserver(nickObs)
    }
    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in controller?.push(c) }
    return controller
}

// MARK: - Раздел «Безопасность» (3.1 Face ID, 3.2 Скрыть мой номер, 3.3 Размытие в трее, 3.4 Анти-скам)

private enum FullGramSecurityToggle: Int32 {
    case faceIdChats = 1
    case hidePhone = 2
    case blurInTray = 3
}

private struct FullGramSecurityArguments {
    let toggle: (FullGramSecurityToggle, Bool) -> Void
    let openAntiScam: () -> Void
}

private enum FullGramSecurityEntry: ItemListNodeEntry {
    case toggle(FullGramSecurityToggle, String, Bool)
    case info(Int32, String)
    case antiScam(String, String)

    var section: ItemListSectionId {
        switch self {
        case .toggle(.faceIdChats, _, _), .info(10, _): return 0
        case .toggle(.hidePhone, _, _), .info(20, _): return 1
        case .toggle(.blurInTray, _, _), .info(30, _): return 2
        case .antiScam, .info(40, _): return 3
        default: return 0
        }
    }

    var stableId: Int32 {
        switch self {
        case .toggle(.faceIdChats, _, _): return 1
        case .info(10, _): return 10
        case .toggle(.hidePhone, _, _): return 11
        case .info(20, _): return 20
        case .toggle(.blurInTray, _, _): return 21
        case .info(30, _): return 30
        case .antiScam: return 31
        case .info(40, _): return 40
        case let .info(id, _): return id
        }
    }

    static func <(lhs: FullGramSecurityEntry, rhs: FullGramSecurityEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramSecurityArguments
        switch self {
        case let .toggle(opt, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(opt, $0) })
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .antiScam(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.security, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openAntiScam)
        }
    }
}

func fullGramSecurityCategoryController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let extrasObserver = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let antiScamObserver = NotificationCenter.default.addObserver(forName: FullGramAntiScam.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let args = FullGramSecurityArguments(toggle: { opt, value in
        switch opt {
        case .faceIdChats:
            FullGramChatPrivacy.isEnabled = value
        case .hidePhone:
            FullGramExtras.shared.hidePhoneNumber = value
        case .blurInTray:
            FullGramExtras.shared.blurInAppSwitcher = value
        }
    }, openAntiScam: {
        pushImpl?(fullGramAntiScamController(context: context))
    })
    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let antiScamStatus = FullGramAntiScam.shared.isEnabled ? "Вкл" : "Выкл"
        let entries: [FullGramSecurityEntry] = [
            .toggle(.faceIdChats, "Защита чатов по Face ID", FullGramChatPrivacy.isEnabled),
            .info(10, "Долгое нажатие на чат в списке → «Заблокировать Face ID»."),
            .toggle(.hidePhone, "Скрыть мой номер", FullGramExtras.shared.hidePhoneNumber),
            .info(20, "Скрывает номер в настройках для скриншотов, видео и демонстрации экрана"),
            .toggle(.blurInTray, "Размытие в трее", FullGramExtras.shared.blurInAppSwitcher),
            .info(30, "Приложение не видно в списке открытых"),
            .antiScam("Анти-скам", antiScamStatus),
            .info(40, "Проверка фишинговых ссылок, скам-сообщений и опасных файлов")
        ]
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Безопасность"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(extrasObserver)
        NotificationCenter.default.removeObserver(antiScamObserver)
    }
    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in controller?.push(c) }
    return controller
}

// MARK: - Раздел «Прочее» (4.1 Локальный Premium, 4.2 Основное, 4.3 Датчик приближения)

private struct FullGramOtherCategoryArguments {
    let toggleLocalPremium: (Bool) -> Void
    let openGeneral: () -> Void
    let openPowerSaving: () -> Void
    let openAIAssistant: () -> Void
    let openBadges: () -> Void
    let exportBackup: () -> Void
    let importBackup: () -> Void
}

private enum FullGramOtherCategoryEntry: ItemListNodeEntry {
    case localPremium(Bool)
    case localPremiumInfo(String)
    case generalLink(String)
    case powerSavingLink(String, String)
    case aiAssistantLink(String, String)
    case badgesLink(String, String)
    case backupHeader(String)
    case exportBackup(String)
    case importBackup(String)
    case backupInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .localPremium, .localPremiumInfo: return 0
        case .generalLink, .powerSavingLink, .aiAssistantLink, .badgesLink: return 1
        case .backupHeader, .exportBackup, .importBackup, .backupInfo: return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .localPremium: return 0
        case .localPremiumInfo: return 1
        case .generalLink: return 10
        case .powerSavingLink: return 11
        case .aiAssistantLink: return 12
        case .badgesLink: return 13
        case .backupHeader: return 20
        case .exportBackup: return 21
        case .importBackup: return 22
        case .backupInfo: return 23
        }
    }

    static func <(lhs: FullGramOtherCategoryEntry, rhs: FullGramOtherCategoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramOtherCategoryArguments
        switch self {
        case let .localPremium(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Локальный Premium", value: value, sectionId: self.section, style: .blocks, updated: args.toggleLocalPremium)
        case let .localPremiumInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .generalLink(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.dataAndStorage, title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openGeneral)
        case let .powerSavingLink(title, value):
            let icon = FullGramSettingsIcons.symbol("bolt.batteryblock.fill", color: UIColor(rgb: 0x34c759)) ?? PresentationResourcesSettings.powerSaving
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openPowerSaving)
        case let .aiAssistantLink(title, value):
            let icon = FullGramSettingsIcons.symbol("sparkles", color: UIColor(rgb: 0x5856d6)) ?? PresentationResourcesSettings.stickers
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openAIAssistant)
        case let .badgesLink(title, value):
            let icon = FullGramSettingsIcons.symbol("checkmark.seal.fill", color: UIColor(rgb: 0x007aff)) ?? PresentationResourcesSettings.stickers
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openBadges)
        case let .backupHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .exportBackup(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.exportBackup)
        case let .importBackup(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.importBackup)
        case let .backupInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class FullGramBackupPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let first = urls.first { self.onPick(first) }
    }
}

private var activeBackupPickerDelegate: FullGramBackupPickerDelegate?

func fullGramOtherCategoryController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let backupObserver = NotificationCenter.default.addObserver(forName: FullGramBackup.didRestoreNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let aiObserver = NotificationCenter.default.addObserver(forName: FullGramAINotifications.settingsChanged, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let badgesObserver = NotificationCenter.default.addObserver(forName: FullGramBadges.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let args = FullGramOtherCategoryArguments(
        toggleLocalPremium: { value in
            FullGramExtras.shared.localPremium = value
        },
        openGeneral: {
            pushImpl?(fullGramOtherGeneralController(context: context))
        },
        openPowerSaving: {
            pushImpl?(fullGramPowerSavingController(context: context))
        },
        openAIAssistant: {
            pushImpl?(fullGramAIAssistantController(context: context))
        },
        openBadges: {
            pushImpl?(fullGramBadgesController(context: context))
        },
        exportBackup: {
            guard let url = FullGramBackup.exportToTemporaryFile() else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: url)
            }
            presentNativeImpl?(activity)
        },
        importBackup: {
            var types: [UTType] = [.json, .data, .item]
            if let fg = UTType(filenameExtension: "fullgram") { types.insert(fg, at: 0) }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            let delegate = FullGramBackupPickerDelegate { url in
                activeBackupPickerDelegate = nil
                let finishImport: (Bool) -> Void = { allowWhitelist in
                    do {
                        let res = try FullGramBackup.importFromFile(url: url, allowAntiScamWhitelist: allowWhitelist)
                        let alert = UIAlertController(title: "Бэкап восстановлен", message: "Загружено настроек: \(res.settingsCount), плагинов: \(res.pluginsCount).", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        presentNativeImpl?(alert)
                    } catch {
                        let alert = UIAlertController(title: "Ошибка импорта", message: error.localizedDescription, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        presentNativeImpl?(alert)
                    }
                }
                do {
                    let info = try FullGramBackup.inspectFile(url: url)
                    if info.hasAntiScamWhitelist {
                        let domainsPreview = info.whitelistDomains.prefix(4).joined(separator: ", ")
                        let alert = UIAlertController(
                            title: "Белый список Анти-скама",
                            message: "Бэкап содержит доверенные домены (\(info.whitelistDomains.count): \(domainsPreview)). Если файл от другого человека, злоумышленник может скрыть фишинговые сайты. Заменить белый список?",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "Пропустить домены (безопасно)", style: .default, handler: { _ in
                            finishImport(false)
                        }))
                        alert.addAction(UIAlertAction(title: "Заменить белый список", style: .destructive, handler: { _ in
                            finishImport(true)
                        }))
                        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                        presentNativeImpl?(alert)
                    } else {
                        finishImport(false)
                    }
                } catch {
                    let alert = UIAlertController(title: "Ошибка импорта", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(alert)
                }
            }
            activeBackupPickerDelegate = delegate
            picker.delegate = delegate
            presentNativeImpl?(picker)
        }
    )
    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let aiStatus = FullGramAIStore.shared.hasConfiguredKey ? FullGramAIStore.shared.provider.title : "Не настроен"
        let badgesStatus = FullGramBadges.shared.isEnabled ? "\(FullGramBadges.shared.totalCount)" : "Выкл."
        let powerStatus = FullGramPowerSaving.profile().mode.title
        var entries: [FullGramOtherCategoryEntry] = [
            .localPremium(FullGramExtras.shared.localPremium),
            .localPremiumInfo("Открывает клиентские возможности Telegram Premium только на этом устройстве (без серверного эмодзи-статуса)."),
            .generalLink("Основное"),
            .powerSavingLink("Энергосбережение", powerStatus),
            .aiAssistantLink("ИИ Ассистент и свой агент", aiStatus)
        ]
        if fullGramCanOpenAdmin(context: context) {
            entries.append(.badgesLink("Бейджи FullGram (badges.json)", badgesStatus))
        }
        entries.append(contentsOf: [
            .backupHeader("БЭКАП FULLGRAM (.FULLGRAM)"),
            .exportBackup("Экспорт настроек, тем и плагинов"),
            .importBackup("Импорт из файла .fullgram"),
            .backupInfo("Сохраняет в один файл .fullgram все переключатели, белый список Анти-скама, пресеты Микшера, шрифты, темы и установленные плагины.")
        ])
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Прочее"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
        NotificationCenter.default.removeObserver(backupObserver)
        NotificationCenter.default.removeObserver(aiObserver)
        NotificationCenter.default.removeObserver(badgesObserver)
    }
    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}

private enum FullGramOtherGeneralToggle: Int32, CaseIterable {
    case disableNumberRounding = 1
    case showMessageSeconds = 2
    case showPeerIds = 3
    case hidePaidAds = 4
    case dimRepliesToMe = 5
    case trackOnLockScreen = 6
    case noAutoplayNextVoice = 7
    case keepScreenOnInPlayer = 8
    case keepScreenOnInVoice = 9
    case downloadBoost = 10
    case localFreeTranscription = 11
    case videoSubtitles = 12
    case autoCleanTempCaches = 13

    var title: String {
        switch self {
        case .disableNumberRounding: return "не округлять числа"
        case .showMessageSeconds: return "время с секундами"
        case .showPeerIds: return "показывать ID"
        case .hidePaidAds: return "скрывать платную рекламу"
        case .dimRepliesToMe: return "полупрозрачные ответы"
        case .trackOnLockScreen: return "трек на экране блокировки"
        case .noAutoplayNextVoice: return "не включать следующее голосовое/кружок"
        case .keepScreenOnInPlayer: return "экран не гаснет в плеере"
        case .keepScreenOnInVoice: return "не гасить экран в голосовых и кружках"
        case .downloadBoost: return "Улучшение загрузки"
        case .localFreeTranscription: return "Бесплатная расшифровка голосовых и кружков"
        case .videoSubtitles: return "Субтитры для кружков и видео"
        case .autoCleanTempCaches: return "Автоочистка временных кэшей (оптимизация)"
        }
    }
}

private struct FullGramOtherGeneralArguments {
    let toggle: (FullGramOtherGeneralToggle, Bool) -> Void
    let pickDownloadBoostMultiplier: () -> Void
}

private enum FullGramOtherGeneralEntry: ItemListNodeEntry {
    case header(String)
    case toggle(FullGramOtherGeneralToggle, Bool)
    case boostHeader(String)
    case boostToggle(Bool)
    case boostMultiplier(String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .boostHeader, .boostToggle, .boostMultiplier, .info:
            return 1
        default:
            return 0
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .toggle(opt, _): return opt.rawValue
        case .boostHeader: return 20
        case .boostToggle: return 21
        case .boostMultiplier: return 22
        case .info: return 50
        }
    }

    static func <(lhs: FullGramOtherGeneralEntry, rhs: FullGramOtherGeneralEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramOtherGeneralArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(opt, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: opt.title, value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(opt, $0) })
        case let .boostHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .boostToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Улучшение загрузки", value: value, sectionId: self.section, style: .blocks, updated: { args.toggle(.downloadBoost, $0) })
        case let .boostMultiplier(value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Множитель ускорения", label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickDownloadBoostMultiplier)
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramOtherGeneralController(context: AccountContext) -> ViewController {
    var presentImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }
    let args = FullGramOtherGeneralArguments(
        toggle: { opt, value in
            switch opt {
            case .disableNumberRounding: FullGramExtras.shared.disableNumberRounding = value
            case .showMessageSeconds: FullGramExtras.shared.showMessageSeconds = value
            case .showPeerIds: FullGramExtras.shared.showPeerIds = value
            case .hidePaidAds: FullGramExtras.shared.hidePaidAds = value
            case .dimRepliesToMe: FullGramExtras.shared.dimRepliesToMe = value
            case .trackOnLockScreen: FullGramExtras.shared.trackOnLockScreen = value
            case .noAutoplayNextVoice: FullGramExtras.shared.noAutoplayNextVoice = value
            case .keepScreenOnInPlayer: FullGramExtras.shared.keepScreenOnInPlayer = value
            case .keepScreenOnInVoice: FullGramExtras.shared.keepScreenOnInVoice = value
            case .downloadBoost: FullGramExtras.shared.downloadBoost = value
            case .localFreeTranscription: FullGramExtras.shared.localFreeTranscription = value
            case .videoSubtitles: FullGramExtras.shared.videoSubtitlesEnabled = value
            case .autoCleanTempCaches:
                FullGramExtras.shared.autoCleanTempCaches = value
                if value {
                    let _ = FullGramTransferQueue.shared.purgeStaleTemporaryFiles()
                }
            }
        },
        pickDownloadBoostMultiplier: {
            let sheet = UIAlertController(
                title: "Множитель ускорения загрузки",
                message: "Выберите кратность параллельных потоков к DC и CDN",
                preferredStyle: .actionSheet
            )
            let current = FullGramExtras.shared.downloadBoostMultiplier
            for option in FullGramExtras.downloadBoostMultiplierOptions {
                let prefix = (FullGramExtras.shared.downloadBoost && current == option) ? "✓ " : ""
                sheet.addAction(UIAlertAction(title: "\(prefix)x\(option)", style: .default) { _ in
                    FullGramExtras.shared.downloadBoost = true
                    FullGramExtras.shared.downloadBoostMultiplier = option
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentImpl?(sheet)
        }
    )
    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let extras = FullGramExtras.shared
        let values: [(FullGramOtherGeneralToggle, Bool)] = [
            (.disableNumberRounding, extras.disableNumberRounding),
            (.showMessageSeconds, extras.showMessageSeconds),
            (.showPeerIds, extras.showPeerIds),
            (.hidePaidAds, extras.hidePaidAds),
            (.dimRepliesToMe, extras.dimRepliesToMe),
            (.trackOnLockScreen, extras.trackOnLockScreen),
            (.noAutoplayNextVoice, extras.noAutoplayNextVoice),
            (.keepScreenOnInPlayer, extras.keepScreenOnInPlayer),
            (.keepScreenOnInVoice, extras.keepScreenOnInVoice),
            (.localFreeTranscription, extras.localFreeTranscription),
            (.videoSubtitles, extras.videoSubtitlesEnabled),
            (.autoCleanTempCaches, extras.autoCleanTempCaches)
        ]
        var entries: [FullGramOtherGeneralEntry] = [.header("ОСНОВНОЕ")]
        for (opt, val) in values {
            entries.append(.toggle(opt, val))
        }
        entries.append(.boostHeader("УЛУЧШЕНИЕ ЗАГРУЗКИ"))
        entries.append(.boostToggle(extras.downloadBoost))
        let multLabel = extras.downloadBoost ? "x\(extras.downloadBoostMultiplier)" : "Выкл (x\(extras.downloadBoostMultiplier))"
        entries.append(.boostMultiplier(multLabel))
        entries.append(.info("Переключатель «не гасить экран в голосовых и кружках» отключает датчик приближения при прослушивании.\n\n«Улучшение загрузки» увеличивает пул параллельных соединений до DC и CDN с выбранным множителем (x2–x8), распределяет части равномерно по сокетам и ускоряет загрузку крупных файлов."))
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Основное"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }
    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}

// MARK: - Бейджи FullGram (badges.json)

private final class FullGramBadgesArguments {
    let toggleEnabled: (Bool) -> Void
    let editCustomText: () -> Void
    let editURL: () -> Void
    let refreshNow: () -> Void
    init(toggleEnabled: @escaping (Bool) -> Void, editCustomText: @escaping () -> Void, editURL: @escaping () -> Void, refreshNow: @escaping () -> Void) {
        self.toggleEnabled = toggleEnabled
        self.editCustomText = editCustomText
        self.editURL = editURL
        self.refreshNow = refreshNow
    }
}

private enum FullGramBadgesSection: Int32 {
    case main
    case roles
}

private enum FullGramBadgesEntry: ItemListNodeEntry {
    case header(String)
    case enabled(Bool)
    case customText(String, String)
    case url(String, String)
    case refresh(String, ItemListActionKind)
    case footer(String)
    case rolesHeader(String)
    case roleItem(Int32, String, String)

    var section: ItemListSectionId {
        switch self {
        case .header, .enabled, .customText, .url, .refresh, .footer: return FullGramBadgesSection.main.rawValue
        case .rolesHeader, .roleItem: return FullGramBadgesSection.roles.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .enabled: return 1
        case .customText: return 2
        case .url: return 3
        case .refresh: return 4
        case .footer: return 5
        case .rolesHeader: return 100
        case let .roleItem(idx, _, _): return 101 + idx
        }
    }

    static func <(lhs: FullGramBadgesEntry, rhs: FullGramBadgesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramBadgesArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .enabled(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Показывать бейджи FullGram", value: val, sectionId: self.section, style: .blocks, updated: args.toggleEnabled)
        case let .customText(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editCustomText)
        case let .url(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editURL)
        case let .refresh(title, kind):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: kind, alignment: .center, sectionId: self.section, style: .blocks, action: args.refreshNow)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .rolesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .roleItem(_, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {})
        }
    }
}

public func fullGramBadgesController(context: AccountContext) -> ViewController {
    guard fullGramCanOpenAdmin(context: context) else {
        return fullGramOtherCategoryController(context: context)
    }
    var presentNativeImpl: ((UIViewController) -> Void)?
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    var isRefreshing = false

    let bump: () -> Void = {
        version += 1
        refresh.set(version)
    }

    let observer = NotificationCenter.default.addObserver(forName: FullGramBadges.didChangeNotification, object: nil, queue: .main) { _ in
        bump()
    }

    let args = FullGramBadgesArguments(
        toggleEnabled: { val in
            FullGramBadges.shared.isEnabled = val
        },
        editCustomText: {
            let alert = UIAlertController(
                title: "Текст бейджа",
                message: "Этот текст показывается во всплывающем окне сверху при нажатии на эмодзи бейджа в профиле. Оставьте пустым, чтобы использовать текст роли по умолчанию.",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.text = FullGramBadges.shared.customPopupText
                tf.placeholder = "Например: Официальный создатель плагинов…"
            }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
                FullGramBadges.shared.customPopupText = alert.textFields?.first?.text ?? ""
            }))
            alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive, handler: { _ in
                FullGramBadges.shared.customPopupText = ""
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        editURL: {
            let alert = UIAlertController(
                title: "URL файла badges.json",
                message: "Укажите https:// ссылку на badges.json (Cloudflare Pages / GitHub Pages). Можно указать резервное зеркало через запятую.",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.text = FullGramBadges.shared.badgesURL
                tf.placeholder = "https://fullgram.pages.dev/badges.json"
                tf.keyboardType = .URL
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "Сохранить и обновить", style: .default, handler: { _ in
                FullGramBadges.shared.badgesURL = alert.textFields?.first?.text ?? ""
                isRefreshing = true
                bump()
                FullGramBadges.shared.refreshNow { _ in
                    isRefreshing = false
                    bump()
                }
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(alert)
        },
        refreshNow: {
            guard !isRefreshing else { return }
            isRefreshing = true
            bump()
            FullGramBadges.shared.refreshNow { result in
                isRefreshing = false
                bump()
                let title: String
                let msg: String
                switch result {
                case let .success(count):
                    title = "Бейджи обновлены"
                    msg = "Загружено записей: \(count)"
                case let .failure(err):
                    title = "Ошибка обновления"
                    msg = err.localizedDescription
                }
                let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                presentNativeImpl?(alert)
            }
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let badges = FullGramBadges.shared
        let customTextLabel = badges.customPopupText.isEmpty ? "По умолчанию" : String(badges.customPopupText.prefix(24))
        let urlLabel = badges.badgesURL.isEmpty ? "По умолчанию" : String(badges.badgesURL.suffix(24))

        var entries: [FullGramBadgesEntry] = [
            .header("БЕЙДЖИ FULLGRAM (CLOUDFLARE / GITHUB)"),
            .enabled(badges.isEnabled),
            .customText("Текст бейджа", customTextLabel),
            .url("Ссылка на badges.json", urlLabel),
            .refresh(isRefreshing ? "⏳ Загрузка…" : "🔄 Обновить бейджи с сервера", isRefreshing ? .neutral : .generic),
            .footer("Бейджи отображаются в профиле, шапке чата и у сообщений в группах. @shermanko (Создатель), @fullgram_mod и @fullgramgroup уже встроены по умолчанию; новых Premium-пользователей можно добавлять в badges.json без обновления приложения.")
        ]

        let roleList = badges.roleSummaries
        entries.append(.rolesHeader("ДОСТУПНЫЕ РОЛИ (\(badges.totalCount) ЗАПИСЕЙ)"))
        for (idx, item) in roleList.enumerated() {
            let short = item.role.shortLabel ?? item.role.label
            entries.append(.roleItem(Int32(idx), "\(item.role.emoji) \(item.role.label)", short))
        }

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Бейджи FullGram"),
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
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}

// MARK: - Авто-ответчик без Telegram Premium (AFK Mode)

private final class FullGramAutoResponderArguments {
    let selectMode: (FullGramAutoResponderSettings.Mode) -> Void
    let editCustomText: () -> Void
    let selectCooldown: () -> Void
    let toggleGroupsMention: (Bool) -> Void
    let resetCooldowns: () -> Void

    init(
        selectMode: @escaping (FullGramAutoResponderSettings.Mode) -> Void,
        editCustomText: @escaping () -> Void,
        selectCooldown: @escaping () -> Void,
        toggleGroupsMention: @escaping (Bool) -> Void,
        resetCooldowns: @escaping () -> Void
    ) {
        self.selectMode = selectMode
        self.editCustomText = editCustomText
        self.selectCooldown = selectCooldown
        self.toggleGroupsMention = toggleGroupsMention
        self.resetCooldowns = resetCooldowns
    }
}

private enum FullGramAutoResponderSection: Int32 {
    case mode
    case template
    case rules
}

private enum FullGramAutoResponderEntry: ItemListNodeEntry {
    case modeHeader(String)
    case modeOption(Int32, FullGramAutoResponderSettings.Mode, String, Bool)
    case modeFooter(String)
    case templateHeader(String)
    case editCustomText(String, String)
    case previewText(String)
    case rulesHeader(String)
    case cooldown(String, String)
    case groupsMention(String, Bool)
    case resetCooldowns(String)
    case statsFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .modeHeader, .modeOption, .modeFooter: return FullGramAutoResponderSection.mode.rawValue
        case .templateHeader, .editCustomText, .previewText: return FullGramAutoResponderSection.template.rawValue
        case .rulesHeader, .cooldown, .groupsMention, .resetCooldowns, .statsFooter: return FullGramAutoResponderSection.rules.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .modeHeader: return 0
        case let .modeOption(idx, _, _, _): return 1 + idx
        case .modeFooter: return 20
        case .templateHeader: return 30
        case .editCustomText: return 31
        case .previewText: return 32
        case .rulesHeader: return 50
        case .cooldown: return 51
        case .groupsMention: return 52
        case .resetCooldowns: return 53
        case .statsFooter: return 60
        }
    }

    static func < (lhs: FullGramAutoResponderEntry, rhs: FullGramAutoResponderEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramAutoResponderArguments
        switch self {
        case let .modeHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .modeOption(_, mode, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectMode(mode)
            })
        case let .modeFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .templateHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .editCustomText(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.editCustomText)
        case let .previewText(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .rulesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .cooldown(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: args.selectCooldown)
        case let .groupsMention(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: args.toggleGroupsMention)
        case let .resetCooldowns(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.resetCooldowns)
        case let .statsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramAutoResponderController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
    }

    var presentUIKitImpl: ((UIViewController) -> Void)?

    let args = FullGramAutoResponderArguments(
        selectMode: { mode in
            FullGramAutoResponderSettings.shared.mode = mode
            bump()
        },
        editCustomText: {
            let alert = UIAlertController(
                title: "Свой текст авто-ответа",
                message: "Введите сообщение, которое будет автоматически отправляться собеседникам:",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "Например: Сейчас занят, напишу позже!"
                tf.text = FullGramAutoResponderSettings.shared.customText
            }
            alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { _ in
                if let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    FullGramAutoResponderSettings.shared.customText = text
                    FullGramAutoResponderSettings.shared.mode = .custom
                    bump()
                }
            })
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentUIKitImpl?(alert)
        },
        selectCooldown: {
            let sheet = UIAlertController(title: "Интервал авто-ответа", message: "Как часто отвечать одному и тому же собеседнику:", preferredStyle: .actionSheet)
            let options: [(String, Int)] = [
                ("Раз в 5 минут", 300),
                ("Раз в 15 минут", 900),
                ("Раз в 30 минут", 1800),
                ("Раз в 1 час", 3600),
                ("Раз в 24 часа", 86400)
            ]
            for (title, sec) in options {
                sheet.addAction(UIAlertAction(title: title, style: .default) { _ in
                    FullGramAutoResponderSettings.shared.cooldownSeconds = sec
                    bump()
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentUIKitImpl?(sheet)
        },
        toggleGroupsMention: { val in
            FullGramAutoResponderSettings.shared.replyInGroupsOnMention = val
            bump()
        },
        resetCooldowns: {
            FullGramAutoResponderSettings.shared.resetCooldowns()
            bump()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let s = FullGramAutoResponderSettings.shared
        let currentMode = s.mode

        let cooldownLabel: String
        switch s.cooldownSeconds {
        case ..<600: cooldownLabel = "5 мин"
        case ..<1500: cooldownLabel = "15 мин"
        case ..<2700: cooldownLabel = "30 мин"
        case ..<7200: cooldownLabel = "1 час"
        default: cooldownLabel = "24 часа"
        }

        var entries: [FullGramAutoResponderEntry] = []
        entries.append(.modeHeader("РЕЖИМ АВТО-ОТВЕТЧИКА"))
        for (idx, m) in FullGramAutoResponderSettings.Mode.allCases.enumerated() {
            entries.append(.modeOption(Int32(idx), m, m.title(ru), m == currentMode))
        }
        entries.append(.modeFooter("При получении нового сообщения автоматически отправляет выбранный ответ (боты и каналы игнорируются)."))

        entries.append(.templateHeader("ТЕКСТ АВТО-ОТВЕТА"))
        entries.append(.editCustomText("Изменить свой текст", "Настроить"))
        let preview = currentMode == .off ? "Авто-ответчик сейчас выключен." : "Текущий ответ: «\(s.effectiveReplyText)»"
        entries.append(.previewText(preview))

        entries.append(.rulesHeader("ПРАВИЛА И ЗАЩИТА ОТ СПАМА"))
        entries.append(.cooldown("Пауза для одного собеседника", cooldownLabel))
        entries.append(.groupsMention("Отвечать в группах при упоминании (@тег / реплай)", s.replyInGroupsOnMention))
        entries.append(.resetCooldowns("Сбросить таймеры ответов сейчас"))
        entries.append(.statsFooter("Всего отправлено авто-ответов за всё время: \(s.totalRepliesSent)."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Авто-ответчик"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, args))
    }

    let controller = ItemListController(context: context, state: signal)
    presentUIKitImpl = { [weak controller] vc in
        guard let controller else { return }
        if let pop = vc.popoverPresentationController {
            pop.sourceView = controller.view
            pop.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller.view.window?.rootViewController?.present(vc, animated: true)
    }
    return controller
}
