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

    override func viewDidLoad() {
        super.viewDidLoad()
        self.attachHostedIfNeeded()
    }

    private func attachHostedIfNeeded() {
        guard !self.didAttachHosted else { return }
        self.didAttachHosted = true
        self.addChild(self.hosted)
        self.hosted.view.frame = self.view.bounds
        self.hosted.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let navView = self.navigationBar?.view, navView.superview === self.view {
            self.view.insertSubview(self.hosted.view, belowSubview: navView)
        } else {
            self.view.insertSubview(self.hosted.view, at: 0)
        }
        self.hosted.didMove(toParent: self)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.attachHostedIfNeeded()
        self.hosted.view.frame = CGRect(origin: .zero, size: layout.size)
        let topInset = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.hosted.additionalSafeAreaInsets = UIEdgeInsets(
            top: topInset,
            left: layout.safeInsets.left,
            bottom: layout.intrinsicInsets.bottom,
            right: layout.safeInsets.right
        )
    }
}

public enum FullGramCategory: Int32, CaseIterable {
    case privacy = 0
    case chats = 1
    case mediaAndAudio = 2
    case appearance = 3
    case security = 4
    case antiScam = 5
    case other = 6
    case plugins = 7
    case aiAssistant = 8

    var title: String {
        switch self {
        case .privacy:
            return "Приватность"
        case .chats:
            return "Чаты"
        case .mediaAndAudio:
            return "Медиа и Аудио"
        case .appearance:
            return "Оформление"
        case .security:
            return "Безопасность"
        case .antiScam:
            return "Анти-скам"
        case .other:
            return "Прочее"
        case .plugins:
            return "Плагины"
        case .aiAssistant:
            return "ИИ Ассистент"
        }
    }

    var icon: UIImage? {
        switch self {
        case .privacy:
            return PresentationResourcesSettings.security
        case .chats:
            return PresentationResourcesSettings.privateChats
        case .mediaAndAudio:
            return PresentationResourcesSettings.photos
        case .appearance:
            return PresentationResourcesSettings.appearance
        case .security:
            return PresentationResourcesSettings.devices
        case .antiScam:
            return UIImage(systemName: "shield.lefthalf.filled")?.withTintColor(UIColor(rgb: 0xFF9500), renderingMode: .alwaysOriginal) ?? PresentationResourcesSettings.security
        case .other:
            return PresentationResourcesSettings.dataAndStorage
        case .plugins:
            return PresentationResourcesSettings.stickers
        case .aiAssistant:
            return UIImage(systemName: "sparkles")?.withTintColor(UIColor(rgb: 0x5856d6), renderingMode: .alwaysOriginal) ?? PresentationResourcesSettings.stickers
        }
    }
}

private final class FullGramSettingsControllerArguments {
    let context: AccountContext
    let openSearch: () -> Void
    let openCategory: (FullGramCategory) -> Void
    let openAdmin: () -> Void
    let openLink: (String) -> Void

    init(
        context: AccountContext,
        openSearch: @escaping () -> Void,
        openCategory: @escaping (FullGramCategory) -> Void,
        openAdmin: @escaping () -> Void,
        openLink: @escaping (String) -> Void
    ) {
        self.context = context
        self.openSearch = openSearch
        self.openCategory = openCategory
        self.openAdmin = openAdmin
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
        case .adminPanel:
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
        case .categoriesHeader:
            return 3
        case let .category(index, _, _):
            return 4 + index
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
        case let .search(theme):
            let icon = UIImage(systemName: "magnifyingglass")?.withTintColor(theme.list.itemAccentColor, renderingMode: .alwaysOriginal)
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
                    string: "0.0.1",
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

func fullGramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?

    let arguments = FullGramSettingsControllerArguments(
        context: context,
        openSearch: {
            pushControllerImpl?(fullGramSettingsSearchController(context: context))
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
        openAdmin: {
            pushControllerImpl?(fullGramAdminController(context: context))
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

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramSettingsEntry] = [
            .header(presentationData.theme),
            .search(presentationData.theme)
        ]
        if fullGramCanOpenAdmin(context: context) {
            let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
            entries.append(.adminPanel(presentationData.theme, ru ? "Админ-панель FullGram" : "FullGram Admin"))
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
    let openActivityAndTraces: () -> Void
    let openDeleted: () -> Void
}

private enum FullGramPrivacyCategoryEntry: ItemListNodeEntry {
    case ghostModeLink(PresentationTheme, Bool)
    case activityAndTracesLink(PresentationTheme)
    case deletedLink(PresentationTheme)

    var section: ItemListSectionId {
        switch self {
        case .ghostModeLink, .activityAndTracesLink:
            return 0
        case .deletedLink:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostModeLink: return 0
        case .activityAndTracesLink: return 1
        case .deletedLink: return 2
        }
    }

    static func ==(lhs: FullGramPrivacyCategoryEntry, rhs: FullGramPrivacyCategoryEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.ghostModeLink(lhsTheme, lhsActive), .ghostModeLink(rhsTheme, rhsActive)):
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
                icon: PresentationResourcesSettings.security,
                title: "Режим призрака (Ghost Mode)",
                label: isActive ? "Вкл." : "Выкл.",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: arguments.openGhostMode
            )
        case .activityAndTracesLink:
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: PresentationResourcesSettings.lockOrange,
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
                icon: PresentationResourcesSettings.dataAndStorage,
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

    let arguments = FullGramPrivacyCategoryArguments(
        openGhostMode: {
            pushControllerImpl?(fullGramGhostModeController(context: context))
        },
        openActivityAndTraces: {
            pushControllerImpl?(fullGramActivityAndTracesController(context: context))
        },
        openDeleted: {
            pushControllerImpl?(fullGramMessageHistoryController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, store.signal)
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramPrivacyCategoryEntry] = [
            .ghostModeLink(presentationData.theme, settings.isActive),
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
    let toggleStatus: (FullGramActivityFilter.Kind, Bool) -> Void
    let toggleExtra: (FullGramActivityExtraToggle, Bool) -> Void
    let selectUndoSend: () -> Void
}

private enum FullGramActivityAndTracesEntry: ItemListNodeEntry {
    case statusesHeader(String)
    case statusToggle(Int32, FullGramActivityFilter.Kind, Bool)
    case otherHeader(String)
    case extraToggle(FullGramActivityExtraToggle, String, Bool)
    case extraInfo(Int32, String)
    case undoSend(String, String)

    var section: ItemListSectionId {
        switch self {
        case .statusesHeader, .statusToggle:
            return 0
        case .otherHeader, .extraToggle, .extraInfo, .undoSend:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .statusesHeader: return 0
        case let .statusToggle(idx, _, _): return 1 + idx
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
        case let (.statusToggle(ai, ak, av), .statusToggle(bi, bk, bv)): return ai == bi && ak == bk && av == bv
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
        case let .extraInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
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

func fullGramActivityAndTracesController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    var version = 0
    let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: .main) { _ in
        version += 1
        changed.set(version)
    }

    let args = FullGramActivityAndTracesArguments(
        toggleStatus: { kind, value in
            FullGramActivityFilter.setHidden(kind, value)
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
        var entries: [FullGramActivityAndTracesEntry] = [
            .statusesHeader("СКРЫТИЕ СТАТУСОВ")
        ]
        for (index, kind) in FullGramActivityFilter.Kind.allCases.enumerated() {
            entries.append(.statusToggle(Int32(index), kind, FullGramActivityFilter.isHidden(kind)))
        }
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
}

private struct FullGramChatsCategoryArguments {
    let openHistory: () -> Void
    let openRestrictionBypass: () -> Void
    let openSending: () -> Void
    let openTranslation: () -> Void
    let openMessageMenu: () -> Void
    let openReactions: () -> Void
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
    case optionsHeader(String)
    case toggle(FullGramChatsToggle, String, Bool)
    case optionsInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .sectionsHeader, .messageHistoryLink, .restrictionBypassLink, .sendingLink, .translationLink, .messageMenuLink, .reactionsLink:
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
        toggle: { option, value in
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
            .optionsHeader(t("ПОВЕДЕНИЕ В ЧАТЕ", "CHAT BEHAVIOR")),
            .toggle(.hideStickerTime, t("Скрывать время на стикерах", "Hide time on stickers"), ui.hideStickerTime),
            .toggle(.unlimitedRecentStickers, t("Увеличить недавние стикеры (до 200)", "Unlimited recent stickers (up to 200)"), ui.unlimitedRecentStickers),
            .toggle(.disableJumpToNextChannel, t("Не переходить к следующему каналу", "Disable jump to next channel"), ui.disableJumpToNextChannel),
            .toggle(.hideKeyboardOnScroll, t("Скрывать клавиатуру при прокрутке", "Hide keyboard on scroll"), ui.hideKeyboardOnScroll),
            .toggle(.addCommaAfterMention, t("Запятая после упоминания (@nick, )", "Add comma after mention"), ui.addCommaAfterMention),
            .toggle(.hideFastShare, t("Скрыть кнопку быстрого репоста", "Hide fast share button"), ui.hideFastShare),
            .toggle(.horizonLockVideoMessages, t("Фиксация горизонта в видеокружках", "Horizon lock in video messages"), ui.horizonLockVideoMessages),
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
    case publicChannels = 3
    case privateChannels = 4
    case publicGroups = 5
    case privateGroups = 6
}

private struct FullGramMessageHistoryArguments {
    let toggleEdits: (Bool) -> Void
    let toggleDeleted: (Bool) -> Void
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
        case .header, .saveDeleted, .saveEdits, .saveForBots, .restrictionBypassLink, .info:
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
        case .saveEdits:
            return 2
        case .saveForBots:
            return 3
        case .restrictionBypassLink:
            return 4
        case .info:
            return 5
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
            .saveEdits(t("Сохранять историю изменений", "Save message edits"), state.saveEdits),
            .saveForBots(t("Сохранять сообщения ботов", "Save bot messages"), state.saveForBots),
            .restrictionBypassLink(
                t("Обход ограничений (одноразовые)", "Restriction bypass (view-once)"),
                bypassActive ? t("Вкл.", "On") : t("Выкл.", "Off")
            ),
            .info(t(
                "Удалённые сообщения остаются в чате с пометкой «Удалено», а предыдущие версии изменённых и удалённых сообщений сохраняются в списке ниже прямо на устройстве.",
                "Deleted messages stay in chats with a 'Deleted' label, and previous versions of edited and deleted messages are stored locally below."
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

    init(url: URL, title: String) {
        self.item = FullGramQuickLookItem(url: url, title: title)
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let ql = QLPreviewController()
        ql.dataSource = self
        ql.delegate = self
        self.view.window?.rootViewController?.present(ql, animated: true)
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
    case antiCaps = 1
    case translateBeforeSend = 2
    case quickFormattingBar = 3
}

private struct FullGramSendingArguments {
    let toggle: (FullGramSendingToggle, Bool) -> Void
    let selectTranslateLanguage: () -> Void
}

private enum FullGramSendingEntry: ItemListNodeEntry {
    case textHeader(String)
    case toggle(FullGramSendingToggle, String, Bool)
    case translateLanguage(String, String)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .textHeader:
            return 0
        case let .toggle(option, _, _):
            return option.rawValue
        case .translateLanguage:
            return 10
        case .info:
            return 30
        }
    }

    static func <(lhs: FullGramSendingEntry, rhs: FullGramSendingEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! FullGramSendingArguments
        switch self {
        case let .textHeader(text):
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
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramSendingController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
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

    let arguments = FullGramSendingArguments(
        toggle: { option, value in
            switch option {
            case .antiCaps:
                FullGramExtras.shared.antiCaps = value
            case .translateBeforeSend:
                FullGramExtras.shared.translateBeforeSend = value
            case .quickFormattingBar:
                FullGramExtras.shared.quickFormattingBar = value
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

        entries.append(.info(t(
            "• Анти-капс автоматически исправляет случайный CAPS LOCK при наборе.\n• Перевод перед отправкой добавляет панель быстрого перевода над полем ввода.",
            "• Anti-caps fixes accidental CAPS LOCK.\n• Translate before send adds a quick translation bar above the input field."
        )))

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(t("Сообщение", "Message")),
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
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
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
}

private enum FullGramAppearanceCategoryEntry: ItemListNodeEntry {
    case fonts(String)
    case themes(String)
    case design(String)
    case icons(String)

    var section: ItemListSectionId { return 0 }

    var stableId: Int32 {
        switch self {
        case .fonts: return 0
        case .themes: return 1
        case .design: return 2
        case .icons: return 3
        }
    }

    static func <(lhs: FullGramAppearanceCategoryEntry, rhs: FullGramAppearanceCategoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramAppearanceCategoryArguments
        switch self {
        case let .fonts(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openFonts)
        case let .themes(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openThemes)
        case let .design(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openDesign)
        case let .icons(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.appearance, title: title, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openIcons)
        }
    }
}

func fullGramAppearanceCategoryController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let args = FullGramAppearanceCategoryArguments(
        openFonts: { pushImpl?(fullGramFontsController(context: context)) },
        openThemes: { pushImpl?(fullGramThemesController(context: context)) },
        openDesign: { pushImpl?(fullGramDesignController(context: context)) },
        openIcons: { pushImpl?(fullGramAppIconsController(context: context)) }
    )
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramAppearanceCategoryEntry] = [
            .fonts("Шрифты"),
            .themes("Темы"),
            .design("Дизайн"),
            .icons("Иконки приложения")
        ]
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("Оформление"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, args))
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
    let openAIAssistant: () -> Void
    let openBadges: () -> Void
    let exportBackup: () -> Void
    let importBackup: () -> Void
}

private enum FullGramOtherCategoryEntry: ItemListNodeEntry {
    case localPremium(Bool)
    case localPremiumInfo(String)
    case generalLink(String)
    case aiAssistantLink(String, String)
    case badgesLink(String, String)
    case backupHeader(String)
    case exportBackup(String)
    case importBackup(String)
    case backupInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .localPremium, .localPremiumInfo: return 0
        case .generalLink, .aiAssistantLink, .badgesLink: return 1
        case .backupHeader, .exportBackup, .importBackup, .backupInfo: return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .localPremium: return 0
        case .localPremiumInfo: return 1
        case .generalLink: return 10
        case .aiAssistantLink: return 11
        case .badgesLink: return 12
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
        case let .aiAssistantLink(title, value):
            let icon = UIImage(systemName: "sparkles")?.withTintColor(UIColor(rgb: 0x5856d6), renderingMode: .alwaysOriginal) ?? PresentationResourcesSettings.stickers
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openAIAssistant)
        case let .badgesLink(title, value):
            let icon = UIImage(systemName: "checkmark.seal.fill")?.withTintColor(UIColor(rgb: 0x007aff), renderingMode: .alwaysOriginal) ?? PresentationResourcesSettings.stickers
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
        let entries: [FullGramOtherCategoryEntry] = [
            .localPremium(FullGramExtras.shared.localPremium),
            .localPremiumInfo("Открывает клиентские возможности Telegram Premium только на этом устройстве."),
            .generalLink("Основное"),
            .aiAssistantLink("ИИ Ассистент и свой агент", aiStatus),
            .badgesLink("Бейджи FullGram (badges.json)", badgesStatus),
            .backupHeader("БЭКАП FULLGRAM (.FULLGRAM)"),
            .exportBackup("Экспорт настроек, тем и плагинов"),
            .importBackup("Импорт из файла .fullgram"),
            .backupInfo("Сохраняет в один файл .fullgram все переключатели, белый список Анти-скама, пресеты Микшера, шрифты, темы и установленные плагины.")
        ]
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
            (.localFreeTranscription, extras.localFreeTranscription)
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

private func fullGramCategoryController(context: AccountContext, category: FullGramCategory) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramSettingsEntry] = []

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(category.title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks
        )
        return (controllerState, (listState, ()))
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - Бейджи FullGram (badges.json)

private final class FullGramBadgesArguments {
    let toggleEnabled: (Bool) -> Void
    let editURL: () -> Void
    let refreshNow: () -> Void
    init(toggleEnabled: @escaping (Bool) -> Void, editURL: @escaping () -> Void, refreshNow: @escaping () -> Void) {
        self.toggleEnabled = toggleEnabled
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
    case url(String, String)
    case refresh(String, ItemListActionKind)
    case footer(String)
    case rolesHeader(String)
    case roleItem(Int32, String, String)

    var section: ItemListSectionId {
        switch self {
        case .header, .enabled, .url, .refresh, .footer: return FullGramBadgesSection.main.rawValue
        case .rolesHeader, .roleItem: return FullGramBadgesSection.roles.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .enabled: return 1
        case .url: return 2
        case .refresh: return 3
        case .footer: return 4
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
        let urlLabel = badges.badgesURL.isEmpty ? "По умолчанию" : String(badges.badgesURL.suffix(24))

        var entries: [FullGramBadgesEntry] = [
            .header("БЕЙДЖИ FULLGRAM (CLOUDFLARE / GITHUB)"),
            .enabled(badges.isEnabled),
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
