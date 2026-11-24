import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import TextFormat
import UrlEscaping
import TelegramUniversalVideoContent
import TextSelectionNode
import Emoji
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import SwiftSignalKit
import AccountContext
import YuvConversion
import AnimationCache
import LottieAnimationCache
import MultiAnimationRenderer
import EmojiTextAttachmentView
import TextNodeWithEntities
import ChatMessageDateAndStatusNode
import ChatMessageBubbleContentNode
import ShimmeringLinkNode
import ChatMessageItemCommon
import TextLoadingEffect
import ChatControllerInteraction
import InteractiveTextComponent
import ShimmeringMask
import StreamingTextReveal
import WalletContext
import ComponentFlow
import GiftItemComponent
import PeerInfoCoverComponent
import AppBundle

private final class CachedChatMessageText {
    let text: String
    let inputEntities: [MessageTextEntity]?
    let entities: [MessageTextEntity]?
    
    init(text: String, inputEntities: [MessageTextEntity]?, entities: [MessageTextEntity]?) {
        self.text = text
        self.inputEntities = inputEntities
        self.entities = entities
    }
    
    func matches(text: String, inputEntities: [MessageTextEntity]?) -> Bool {
        if self.text != text {
            return false
        }
        if let current = self.inputEntities, let inputEntities = inputEntities {
            if current != inputEntities {
                return false
            }
        } else if (self.inputEntities != nil) != (inputEntities != nil) {
            return false
        }
        return true
    }
}

public class ChatMessageTextBubbleContentNode: ChatMessageBubbleContentNode {
    public final class ContainerNode: ASDisplayNode {
    }
    
    private let containerNode: ContainerNode
    private let textNode: InteractiveTextNodeWithEntities

    private let textAccessibilityOverlayNode: TextAccessibilityOverlayNode
    public var statusNode: ChatMessageDateAndStatusNode?
    private var linkHighlightingNode: LinkHighlightingNode?
    private var shimmeringNode: ShimmeringLinkNode?
    private var textSelectionNode: TextSelectionNode?
    private var fullGramScamBannerView: UIView?
    private var fullGramScamBannerLabel: UILabel?
    private var fullGramGiftCardView: FullGramChatGiftCardView?
    
    private var textHighlightingNodes: [LinkHighlightingNode] = []
    
    private var cachedChatMessageText: CachedChatMessageText?
    
    private var textSelectionState: Promise<ChatControllerSubject.MessageOptionsInfo.SelectionState>?
    
    private var linkPreviewHighlightText: String?
    private var linkPreviewOptionsDisposable: Disposable?
    private var linkPreviewHighlightingNodes: [LinkHighlightingNode] = []
    
    private var quoteHighlightingNode: LinkHighlightingNode?
    
    private var linkProgressRange: NSRange?
    private var linkProgressView: TextLoadingEffectView?
    private var linkProgressDisposable: Disposable?
    
    private var codeHighlightState: (id: EngineMessage.Id, specs: [CachedMessageSyntaxHighlight.Spec], disposable: Disposable)?
    
    private var expandedBlockIds: Set<Int> = Set()
    private var appliedExpandedBlockIds: Set<Int>?
    private var displayContentsUnderSpoilers: (value: Bool, location: CGPoint?) = (false, nil)
    
    private var isSummaryApplied = false

    private var textRevealLink: SharedDisplayLinkDriver.Link?
    private var textRevealController: TextRevealController?
    
    private var relativeDateTimer: (timer: SwiftSignalKit.Timer, period: Int32)?
    
    override public var visibility: ListViewItemNodeVisibility {
        didSet {
            if oldValue != self.visibility {
                switch self.visibility {
                case .none:
                    self.textNode.visibilityRect = nil
                case let .visible(_, subRect):
                    var subRect = subRect
                    subRect.origin.x = 0.0
                    subRect.size.width = 10000.0
                    self.textNode.visibilityRect = subRect
                }
            }
        }
    }
    
    required public init() {
        self.containerNode = ContainerNode()
        self.containerNode.clipsToBounds = true
        
        self.textNode = InteractiveTextNodeWithEntities()
        
        self.textAccessibilityOverlayNode = TextAccessibilityOverlayNode()
        
        super.init()
        
        self.addSubnode(self.containerNode)
        
        self.textNode.textNode.isUserInteractionEnabled = true
        self.textNode.textNode.contentMode = .topLeft
        self.textNode.textNode.contentsScale = UIScreenScale
        self.textNode.textNode.displaysAsynchronously = true
        //self.containerNode.addSubnode(self.textAccessibilityOverlayNode)
        self.containerNode.addSubnode(self.textNode.textNode)
        
        self.textAccessibilityOverlayNode.openUrl = { [weak self] url in
            self?.item?.controllerInteraction.openUrl(ChatControllerInteraction.OpenUrl(url: url, concealed: false, external: false))
        }
        
        self.textNode.textNode.requestToggleBlockCollapsed = { [weak self] blockId in
            guard let self, let item = self.item else {
                return
            }
            if self.expandedBlockIds.contains(blockId) {
                self.expandedBlockIds.remove(blockId)
            } else {
                self.expandedBlockIds.insert(blockId)
            }
            item.controllerInteraction.requestMessageUpdate(item.message.id, false, nil)
        }
        self.textNode.textNode.requestDisplayContentsUnderSpoilers = { [weak self] location in
            guard let self else {
                return
            }
            
            cancelParentGestures(view: self.view)
            
            var mappedLocation: CGPoint?
            if let location {
                mappedLocation = self.textNode.textNode.layer.convert(location, to: self.layer)
            }
            self.updateDisplayContentsUnderSpoilers(value: true, at: mappedLocation)
        }
        self.textNode.textNode.canHandleTapAtPoint = { [weak self] point in
            guard let self else {
                return false
            }
            let localPoint = self.textNode.textNode.view.convert(point, to: self.view)
            let action = self.tapActionAtPoint(localPoint, gesture: .tap, isEstimating: true)
            if case .none = action.content {
                return true
            } else {
                return false
            }
        }
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.linkPreviewOptionsDisposable?.dispose()
        self.linkProgressDisposable?.dispose()
        self.codeHighlightState?.disposable.dispose()
        self.relativeDateTimer?.timer.invalidate()
    }
    
    override public func asyncLayoutContent() -> (_ item: ChatMessageBubbleContentItem, _ layoutConstants: ChatMessageItemLayoutConstants, _ preparePosition: ChatMessageBubblePreparePosition, _ messageSelection: Bool?, _ constrainedSize: CGSize, _ avatarInset: CGFloat) -> (ChatMessageBubbleContentProperties, CGSize?, CGFloat, (CGSize, ChatMessageBubbleContentPosition) -> (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation, Bool, ListViewItemApply?) -> Void))) {
        let previousItem = self.item
        
        let textLayout = InteractiveTextNodeWithEntities.asyncLayout(self.textNode)
        let statusLayout = ChatMessageDateAndStatusNode.asyncLayout(self.statusNode)
        
        let currentCachedChatMessageText = self.cachedChatMessageText
        let expandedBlockIds = self.expandedBlockIds
        let displayContentsUnderSpoilers: (value: Bool, location: CGPoint?) = FullGramExtras.shared.autoRevealSpoilers ? (true, nil) : self.displayContentsUnderSpoilers
        let currentMaxGlyphCount: Int? = self.textRevealController?.currentGlyphCount
        let previousGlyphCount = self.textNode.textNode.cachedLayout?.attributedString?.length ?? 0
        
        return { [weak self] item, layoutConstants, _, _, _, _ in
            let earlyRawText: String
            var earlyEntities: [MessageTextEntity]?
            if let updatingMedia = item.attributes.updatingMedia {
                earlyRawText = updatingMedia.text
                earlyEntities = updatingMedia.entities?.entities
            } else {
                earlyRawText = item.message.text
                for attribute in item.message.attributes {
                    if let attribute = attribute as? TextEntitiesMessageAttribute {
                        earlyEntities = attribute.entities
                        break
                    }
                }
            }
            let earlyGiftPayload = FullGramChatGiftPayload.parse(from: earlyRawText, entities: earlyEntities)
            let isGiftPlaque = earlyGiftPayload != nil

            let contentProperties: ChatMessageBubbleContentProperties
            if isGiftPlaque {
                contentProperties = ChatMessageBubbleContentProperties(
                    hidesSimpleAuthorHeader: true,
                    headerSpacing: 0.0,
                    hidesBackground: .always,
                    forceFullCorners: false,
                    forceAlignment: .center
                )
            } else {
                contentProperties = ChatMessageBubbleContentProperties(
                    hidesSimpleAuthorHeader: false,
                    headerSpacing: 0.0,
                    hidesBackground: .never,
                    forceFullCorners: false,
                    forceAlignment: .none
                )
            }
            
            return (contentProperties, nil, CGFloat.greatestFiniteMagnitude, { [weak self] constrainedSize, position in
                var topInset: CGFloat = 0.0
                var bottomInset: CGFloat = 0.0
                if isGiftPlaque {
                    topInset = 3.0
                    bottomInset = 3.0
                } else if case let .linear(top, bottom) = position {
                    switch top {
                    case .None:
                        topInset = layoutConstants.text.bubbleInsets.top
                    case let .Neighbour(_, topType, _):
                        switch topType {
                        case .text:
                            topInset = layoutConstants.text.bubbleInsets.top - 2.0
                        case .header, .footer, .media, .reactions:
                            topInset = layoutConstants.text.bubbleInsets.top
                        }
                    default:
                        topInset = layoutConstants.text.bubbleInsets.top
                    }
                    
                    switch bottom {
                    case .None:
                        bottomInset = layoutConstants.text.bubbleInsets.bottom
                    default:
                        bottomInset = layoutConstants.text.bubbleInsets.bottom - 3.0
                    }
                    
                    if item.bubbleStyle == .bubbleless {
                        // Without bubbles a caption belongs to the media above it: its capitals stand a block gap under
                        // the media, closer than the next message does. Text above media keeps half the block gap.
                        if case .Neighbour(_, .media, _) = top {
                            let messageFont = item.presentationData.bubblelessIncomingBodyFont
                            topInset = chatMessageBubblelessCaptionTopInset(ascender: messageFont.ascender, capHeight: messageFont.capHeight)
                        }
                        if case .Neighbour(_, .media, _) = bottom {
                            bottomInset = layoutConstants.text.bubbleInsets.bottom + chatMessageBubblelessBlockGap * 0.5
                        }
                    }
                }
                
                let message = item.message
                
                var incoming = item.message.effectivelyIncoming(item.context.account.peerId)
                if let subject = item.associatedData.subject, case let .messageOptions(_, _, info) = subject {
                    if case .forward = info {
                        incoming = false
                    } else if case let .link(link) = info, link.isCentered {
                        incoming = true
                    }
                }
                
                var maxTextWidth = CGFloat.greatestFiniteMagnitude
                for media in item.message.media {
                    if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content, content.type == "telegram_background" || content.type == "telegram_theme" {
                        maxTextWidth = layoutConstants.wallpapers.maxTextWidth
                        break
                    }
                }
                
                let horizontalInset = layoutConstants.text.bubbleInsets.left + layoutConstants.text.bubbleInsets.right
                let textConstrainedSize = CGSize(width: min(maxTextWidth, constrainedSize.width - horizontalInset), height: constrainedSize.height)
                
                var edited = false
                if item.attributes.updatingMedia != nil {
                    edited = true
                }
                var viewCount: Int?
                var dateReplies = 0
                var starsCount: Int64?
                var dateReactionsAndPeers = mergedMessageReactionsAndPeers(accountPeerId: item.context.account.peerId, accountPeer: item.associatedData.accountPeer, message: item.topMessage)
                if item.message.isRestricted(platform: "ios", contentSettings: item.context.currentContentSettings.with { $0 }) {
                    dateReactionsAndPeers = ([], [])
                }
                
                for attribute in item.message.attributes {
                    if let attribute = attribute as? EditedMessageAttribute {
                        edited = !attribute.isHidden
                    } else if let attribute = attribute as? ViewCountMessageAttribute {
                        viewCount = attribute.count
                    } else if let attribute = attribute as? ReplyThreadMessageAttribute, case .peer = item.chatLocation {
                        if let channel = item.message.peers[item.message.id.peerId] as? TelegramChannel, case .group = channel.info {
                            dateReplies = Int(attribute.count)
                        }
                    } else if let attribute = attribute as? PaidStarsMessageAttribute, item.message.id.peerId.namespace == Namespaces.Peer.CloudChannel {
                        starsCount = attribute.stars.value
                    }
                }
                
                let dateFormat: MessageTimestampStatusFormat
                if item.presentationData.isPreview {
                    dateFormat = .full
                } else if let subject = item.associatedData.subject, case .messageOptions = subject {
                    dateFormat = .minimal
                } else {
                    dateFormat = .regular
                }
                let dateText = stringForMessageTimestampStatus(context: item.context, message: EngineMessage(item.message), dateTimeFormat: item.presentationData.dateTimeFormat, nameDisplayOrder: item.presentationData.nameDisplayOrder, strings: item.presentationData.strings, format: dateFormat, associatedData: item.associatedData)
                
                let statusType: ChatMessageDateAndStatusType?
                var displayStatus = false
                switch position {
                case let .linear(_, neighbor):
                    if case .None = neighbor {
                        displayStatus = true
                    } else if case .Neighbour(true, _, _) = neighbor {
                        displayStatus = true
                    }
                default:
                    break
                }
                if case let .customChatContents(contents) = item.associatedData.subject {
                    if case .hashTagSearch = contents.kind {
                        displayStatus = true
                    } else {
                        displayStatus = false
                    }
                } else if !item.presentationData.chatBubbleCorners.hasTails {
                    displayStatus = false
                } else if case let .messageOptions(_, _, info) = item.associatedData.subject, case let .link(link) = info, link.isCentered {
                    displayStatus = false
                }
                if item.bubbleStyle.hidesIncomingStatus {
                    // Without bubbles the time is in the author header.
                    displayStatus = false
                }
                if isGiftPlaque {
                    displayStatus = false
                }
                if displayStatus {
                    if incoming {
                        statusType = .BubbleIncoming
                    } else {
                        if message.flags.contains(.Failed) {
                            statusType = .BubbleOutgoing(.Failed)
                        } else if (message.flags.isSending && !message.isSentOrAcknowledged) || item.attributes.updatingMedia != nil {
                            statusType = .BubbleOutgoing(.Sending)
                        } else {
                            statusType = .BubbleOutgoing(.Sent(read: item.read))
                        }
                    }
                } else {
                    statusType = nil
                }
                
                var rawText: String
                var fullGramScamWarningText: String?
                let attributedText: NSAttributedString
                var messageEntities: [MessageTextEntity]?
                
                var mediaDuration: Double? = nil
                var isSeekableWebMedia = false
                var story: Stories.Item?
                var invoice: TelegramMediaInvoice?
                for media in item.message.media {
                    if let file = media as? TelegramMediaFile, let duration = file.duration {
                        mediaDuration = Double(duration)
                    }
                    if let media = media as? TelegramMediaInvoice, media.currency == "XTR" {
                        invoice = media
                    } else if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content, webEmbedType(content: content).supportsSeeking {
                        isSeekableWebMedia = true
                    } else if let storyMedia = media as? TelegramMediaStory {
                        if let value = item.message.associatedStories[storyMedia.storyId]?.get(Stories.StoredItem.self) {
                            if case let .item(storyValue) = value {
                                story = storyValue
                            }
                        }
                    }
                }
                
                var fullGramGiftPayload: FullGramChatGiftPayload?
                var isSummaryApplied = false
                var isTranslating = false
                if let invoice {
                    rawText = invoice.description
                } else if let story {
                    rawText = story.text
                    messageEntities = story.entities
                } else {
                    if let updatingMedia = item.attributes.updatingMedia {
                        rawText = updatingMedia.text
                    } else {
                        rawText = item.message.text
                    }
                    if let parsedGift = earlyGiftPayload ?? FullGramChatGiftPayload.parse(from: rawText, entities: earlyEntities) {
                        fullGramGiftPayload = parsedGift
                        rawText = " "
                        messageEntities = nil
                    } else {
                        rawText = FullGramPluginManager.shared.processRenderMessage(
                            text: rawText,
                            peerId: item.message.id.peerId.toInt64(),
                            isIncoming: incoming,
                            messageId: item.message.id.id
                        )
                    }
                    if incoming && fullGramGiftPayload == nil {
                        let sourceText = rawText
                        var warnings: [String] = []
                        let isForwarded = item.message.forwardInfo != nil
                        let isChannelPost = (item.message.id.peerId.namespace == Namespaces.Peer.CloudChannel) && (item.message.author == nil || item.message.author?.id == item.message.id.peerId)
                        let fromUnknown = item.message.forwardInfo?.author == nil || item.message.forwardInfo?.author?.id != item.message.author?.id
                        let viaBot = item.message.attributes.contains(where: { $0 is InlineBotMessageAttribute }) || (item.message.author as? TelegramUser)?.botInfo != nil
                        if let offerVerdict = FullGramAntiScam.shared.inspectOffer(
                            text: sourceText,
                            isForwarded: isForwarded,
                            fromUnknownAuthor: fromUnknown,
                            viaBot: viaBot,
                            isChannelPost: isChannelPost
                        ) {
                            warnings.append("⚠️ Анти-офер: \(offerVerdict.summary) (\(offerVerdict.reasons.joined(separator: ", ")))")
                        }
                        if !isChannelPost, let otcWarning = FullGramAntiScam.shared.inspectOTC(text: sourceText) {
                            warnings.append("⚠️ \(otcWarning)")
                        }
                        if let scamVerdict = FullGramAntiScam.shared.inspectIncomingMessage(sourceText) {
                            warnings.append("⚠️ Возможный скам: \(scamVerdict.reasons.first ?? scamVerdict.summary)")
                        }
                        let authorUser = item.message.author as? TelegramUser
                        if let ruleVerdict = FullGramAntiScam.shared.inspectModerationRules(
                            text: sourceText,
                            authorRawId: item.message.author?.id.id._internalGetInt64Value() ?? 0,
                            hasUsername: (authorUser?.addressName?.isEmpty == false),
                            hasAvatar: !(authorUser?.photo.isEmpty ?? true),
                            chatPeerId: item.message.id.peerId.toInt64()
                        ) {
                            warnings.append("🛡 \(ruleVerdict.rule): \(ruleVerdict.reason)")
                        }
                        if !warnings.isEmpty {
                            fullGramScamWarningText = warnings.joined(separator: "\n")
                        }
                    }
                    
                    for attribute in item.message.attributes {
                        if let attribute = attribute as? TextEntitiesMessageAttribute {
                            messageEntities = attribute.entities
                        } else if mediaDuration == nil, let attribute = attribute as? ReplyMessageAttribute {
                            if let replyMessage = item.message.associatedMessages[attribute.messageId] {
                                for media in replyMessage.media {
                                    if let file = media as? TelegramMediaFile, let duration = file.duration {
                                        mediaDuration = Double(duration)
                                    }
                                    if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content, webEmbedType(content: content).supportsSeeking {
                                        isSeekableWebMedia = true
                                    }
                                }
                            }
                        }
                    }
                    
                    if let updatingMedia = item.attributes.updatingMedia {
                        messageEntities = updatingMedia.entities?.entities ?? []
                    }
                    
                    let translateToLanguage = item.associatedData.translateToLanguage
                    var isSummarized = false
                    if item.controllerInteraction.summarizedMessageIds.contains(item.message.id) {
                        isSummarized = true
                    }
                    
                    if let subject = item.associatedData.subject, case .messageOptions = subject {
                    } else if !item.message.text.isEmpty && incoming {
                        if translateToLanguage != nil || isSummarized {
                            isTranslating = true
                        }
                        if isTranslating {
                            if isSummarized, let attribute = item.message.attributes.first(where: { $0 is SummarizationMessageAttribute }) as? SummarizationMessageAttribute, let summary = attribute.summaryForLang(translateToLanguage) {
                                rawText = summary.text
                                messageEntities = summary.entities
                                isTranslating = false
                                isSummaryApplied = true
                            } else if let attribute = item.message.attributes.first(where: { $0 is TranslationMessageAttribute }) as? TranslationMessageAttribute, !attribute.text.isEmpty, attribute.toLang == translateToLanguage {
                                rawText = attribute.text
                                messageEntities = attribute.entities
                                if !isSummarized {
                                    isTranslating = false
                                }
                            }
                        }
                    }
                }
                
                
                if incoming && item.associatedData.isSuspiciousPeer, let entities = messageEntities {
                    messageEntities = entities.filter(\.isShownFromSuspiciousPeer)
                }
                
                var formattedDateUpdatePeriod: Int32?
                if let messageEntities {
                    for entity in messageEntities {
                        if case let .FormattedDate(format, timestamp) = entity.type, case .relative = format {
                            let currentTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
                            let value = abs(currentTimestamp - timestamp)
                            if value < 120 {
                                formattedDateUpdatePeriod = 1
                            } else if value <= 60 * 60 {
                                formattedDateUpdatePeriod = 60
                            } else {
                                formattedDateUpdatePeriod = 30 * 60
                            }
                        }
                    }
                }
                
                var entities: [MessageTextEntity]?
                var updatedCachedChatMessageText: CachedChatMessageText?
                if let cached = currentCachedChatMessageText, cached.matches(text: rawText, inputEntities: messageEntities) {
                    entities = cached.entities
                } else {
                    entities = messageEntities
                    
                    if entities == nil && (mediaDuration != nil || isSeekableWebMedia) {
                        entities = []
                    }
                    
                    if let entitiesValue = entities {
                        var enabledTypes: EnabledEntityTypes = .all
                        if mediaDuration != nil || isSeekableWebMedia {
                            enabledTypes.insert(.timecode)
                            if mediaDuration == nil {
                                mediaDuration = 60.0 * 60.0 * 24.0
                            }
                        }
                        if let result = addLocallyGeneratedEntities(rawText, enabledTypes: enabledTypes, entities: entitiesValue, mediaDuration: mediaDuration) {
                            entities = result
                        }
                    } else {
                        var generateEntities = false
                        for media in message.media {
                            if media is TelegramMediaImage || media is TelegramMediaFile {
                                generateEntities = true
                                break
                            }
                        }
                        if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                           generateEntities = true
                        }
                        if generateEntities {
                            let parsedEntities = generateTextEntities(rawText, enabledTypes: .all)
                            if !parsedEntities.isEmpty {
                                entities = parsedEntities
                            }
                        }
                    }
                    
                    if !item.associatedData.hasBots {
                        messageEntities = messageEntities?.filter { $0.type != .BotCommand }
                        entities = entities?.filter { $0.type != .BotCommand }
                    }
                    
                    updatedCachedChatMessageText = CachedChatMessageText(text: rawText, inputEntities: messageEntities, entities: entities)
                }
                
                
                let messageTheme = incoming ? item.presentationData.theme.theme.chat.message.incoming : item.presentationData.theme.theme.chat.message.outgoing
                
                // Message text in New York when it is picked in Text Size; its quotes and code-block titles keep the system
                // family.
                let messageBodyFonts = item.presentationData.messageBodyFonts
                let textFont = messageBodyFonts.body.regular
                
                var codeHighlightSpecs: [CachedMessageSyntaxHighlight.Spec] = []
                var cachedMessageSyntaxHighlight: CachedMessageSyntaxHighlight?
                
                if let entities {
                    var underlineLinks = true
                    if !messageTheme.primaryTextColor.isEqual(messageTheme.linkTextColor) {
                        underlineLinks = false
                    }
                    
                    let author = item.message.author
                    let mainColor: UIColor
                    var secondaryColor: UIColor? = nil
                    var tertiaryColor: UIColor? = nil
                    
                    let nameColors: PeerNameColors.Colors?
                    switch author?.nameColor {
                    case let .preset(nameColor):
                        nameColors = item.context.peerNameColors.get(nameColor, dark: item.presentationData.theme.theme.overallDarkAppearance)
                    case let .collectible(collectibleColor):
                        nameColors = collectibleColor.peerNameColors(dark: item.presentationData.theme.theme.overallDarkAppearance)
                    default:
                        nameColors = nil
                    }
                    
                    let codeBlockTitleColor: UIColor
                    let codeBlockAccentColor: UIColor
                    let codeBlockBackgroundColor: UIColor
                    var codeBlockFillColor: UIColor?
                    if !incoming {
                        mainColor = messageTheme.accentTextColor
                        if let _ = nameColors?.secondary {
                            secondaryColor = .clear
                        }
                        if let _ = nameColors?.tertiary {
                            tertiaryColor = .clear
                        }
                        
                        if item.presentationData.theme.theme.overallDarkAppearance {
                            codeBlockTitleColor = .white
                            codeBlockAccentColor = UIColor(white: 1.0, alpha: 0.5)
                            codeBlockBackgroundColor = UIColor(white: 0.0, alpha: 0.25)
                            // Dark themes' outgoing bubbles are coloured (the default's a light blue gradient): the
                            // white-tinted block made the code hard to read on them.
                            codeBlockFillColor = UIColor(white: 0.0, alpha: 0.1)
                        } else {
                            codeBlockTitleColor = mainColor
                            codeBlockAccentColor = mainColor
                            codeBlockBackgroundColor = mainColor.withMultipliedAlpha(0.1)
                        }
                    } else {
                        let authorNameColor = nameColors?.main
                        secondaryColor = nameColors?.secondary
                        tertiaryColor = nameColors?.tertiary
                        
                        if let authorNameColor {
                            mainColor = authorNameColor
                        } else {
                            mainColor = messageTheme.accentTextColor
                        }
                        
                        codeBlockTitleColor = mainColor
                        codeBlockAccentColor = mainColor
                        
                        if item.presentationData.theme.theme.overallDarkAppearance {
                            codeBlockBackgroundColor = UIColor(white: 0.0, alpha: 0.65)
                        } else {
                            codeBlockBackgroundColor = UIColor(white: 0.0, alpha: 0.05)
                        }
                    }
                    
                    codeHighlightSpecs = extractMessageSyntaxHighlightSpecs(text: rawText, entities: entities)
                    
                    if !codeHighlightSpecs.isEmpty {
                        for attribute in message.attributes {
                            if let attribute = attribute as? DerivedDataMessageAttribute {
                                if let value = attribute.data["code"]?.get(CachedMessageSyntaxHighlight.self) {
                                    cachedMessageSyntaxHighlight = value
                                }
                            }
                        }
                    }
                    
                    attributedText = stringWithAppliedEntities(rawText, entities: entities, strings: item.presentationData.strings, dateTimeFormat: item.presentationData.dateTimeFormat, baseColor: messageTheme.primaryTextColor, linkColor: messageTheme.linkTextColor, baseQuoteTintColor: mainColor, baseQuoteSecondaryTintColor: secondaryColor, baseQuoteTertiaryTintColor: tertiaryColor, codeBlockTitleColor: codeBlockTitleColor, codeBlockAccentColor: codeBlockAccentColor, codeBlockBackgroundColor: codeBlockBackgroundColor, codeBlockFillColor: codeBlockFillColor, baseFont: textFont, linkFont: textFont, boldFont: messageBodyFonts.body.bold, italicFont: messageBodyFonts.body.italic, boldItalicFont: messageBodyFonts.body.boldItalic, fixedFont: item.presentationData.messageFixedFont, blockQuoteFont: item.presentationData.messageBlockQuoteFont, blockFonts: messageBodyFonts.blockFonts, underlineLinks: underlineLinks, message: item.message, adjustQuoteFontSize: true, cachedMessageSyntaxHighlight: cachedMessageSyntaxHighlight)
                } else if !rawText.isEmpty {
                    attributedText = NSAttributedString(string: rawText, font: textFont, textColor: messageTheme.primaryTextColor)
                } else {
                    attributedText = NSAttributedString(string: " ", font: textFont, textColor: messageTheme.primaryTextColor)
                }
                
                // The custom-emoji attribute is not re-applied here: `stringWithAppliedEntities`
                // already attached it, using ranges adjusted for the substitutions it performs
                // (`.FormattedDate` renders to text of a different length). An entity's own offsets
                // index `rawText`, not the string above, so indexing with them lands on the wrong
                // characters — or out of bounds.

                var customTruncationToken: ((UIFont, Bool) -> NSAttributedString?)?
                var maximumNumberOfLines: Int = 0
                if item.presentationData.isPreview {
                    if item.message.groupingKey != nil {
                        maximumNumberOfLines = 6
                    } else if let image = item.message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage, let dimensions = image.representations.first?.dimensions {
                        if dimensions.width > dimensions.height {
                            maximumNumberOfLines = 9
                        } else {
                            maximumNumberOfLines = 6
                        }
                    } else if let file = item.message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, file.isVideo || file.isAnimated, let dimensions = file.dimensions {
                        if dimensions.width > dimensions.height {
                            maximumNumberOfLines = 9
                        } else {
                            maximumNumberOfLines = 6
                        }
                    } else if let _ = item.message.media.first(where: { $0 is TelegramMediaWebpage }) as? TelegramMediaWebpage {
                        maximumNumberOfLines = 9
                    } else {
                        maximumNumberOfLines = 12
                    }
                    
                    let truncationTokenText = item.presentationData.strings.Conversation_ReadMore
                    customTruncationToken = { baseFont, isQuote in
                        let truncationToken = NSMutableAttributedString()
                        if isQuote {
                            truncationToken.append(NSAttributedString(string: "\u{2026}", font: Font.regular(baseFont.pointSize), textColor: messageTheme.primaryTextColor))
                        } else {
                            truncationToken.append(NSAttributedString(string: "\u{2026} ", font: Font.regular(baseFont.pointSize), textColor: messageTheme.primaryTextColor))
                            truncationToken.append(NSAttributedString(string: truncationTokenText, font: Font.regular(baseFont.pointSize), textColor: messageTheme.accentTextColor))
                        }
                        return truncationToken
                    }
                }
                
                var hasDraft = false
                if item.message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
                    hasDraft = true
                }
                var hadDraft = false
                if let previousItem, previousItem.message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
                    hadDraft = true
                }
                
                let textInsets = UIEdgeInsets(top: 2.0, left: 2.0, bottom: 5.0, right: 2.0)
                let (textLayout, textApply) = textLayout(InteractiveTextNodeLayoutArguments(
                    attributedString: attributedText,
                    backgroundColor: nil,
                    maximumNumberOfLines: maximumNumberOfLines,
                    truncationType: .end,
                    constrainedSize: textConstrainedSize,
                    alignment: .natural,
                    cutout: nil,
                    insets: textInsets,
                    lineColor: messageTheme.accentControlColor,
                    displayContentsUnderSpoilers: displayContentsUnderSpoilers.value,
                    customTruncationToken: customTruncationToken,
                    expandedBlocks: expandedBlockIds,
                    computeCharacterRects: true
                ))
                
                var maxGlyphCount = currentMaxGlyphCount
                if maxGlyphCount == nil && (hasDraft || hadDraft) {
                    maxGlyphCount = previousGlyphCount
                }
                var clippedGlyphCountLayout: TextNodeLayout.LayoutInfo?
                if let maxGlyphCount {
                    clippedGlyphCountLayout = textLayout.layoutForCharacterCount(characterCount: maxGlyphCount)
                }
            
                var statusSuggestedWidthAndContinue: (CGFloat, (CGFloat) -> (CGSize, (ListViewItemUpdateAnimation) -> ChatMessageDateAndStatusNode))?
                if let statusType = statusType {
                    var isReplyThread = false
                    if case .replyThread = item.chatLocation {
                        isReplyThread = true
                    }
                    
                    let trailingWidthToMeasure: CGFloat
                    if let lastSegment = textLayout.segments.last, lastSegment.hasRTL {
                        trailingWidthToMeasure = 10000.0
                    } else if let lastSegment = textLayout.segments.last, lastSegment.hasBlockQuote {
                        trailingWidthToMeasure = textLayout.size.width
                    } else {
                        if let clippedGlyphCountLayout {
                            trailingWidthToMeasure = clippedGlyphCountLayout.trailingLineWidth
                        } else {
                            trailingWidthToMeasure = textLayout.trailingLineWidth
                        }
                    }
                    
                    let dateLayoutInput: ChatMessageDateAndStatusNode.LayoutInput
                    dateLayoutInput = .trailingContent(contentWidth: trailingWidthToMeasure, reactionSettings: ChatMessageDateAndStatusNode.TrailingReactionSettings(displayInline: shouldDisplayInlineDateReactions(message: EngineMessage(item.message), isPremium: item.associatedData.isPremium, forceInline: item.associatedData.forceInlineReactions), preferAdditionalInset: false))
                    
                    statusSuggestedWidthAndContinue = statusLayout(ChatMessageDateAndStatusNode.Arguments(
                        context: item.context,
                        presentationData: item.presentationData,
                        edited: edited && !item.presentationData.isPreview,
                        impressionCount: !item.presentationData.isPreview ? viewCount : nil,
                        dateText: dateText,
                        type: statusType,
                        layoutInput: dateLayoutInput,
                        constrainedSize: textConstrainedSize,
                        availableReactions: item.associatedData.availableReactions,
                        savedMessageTags: item.associatedData.savedMessageTags,
                        reactions: item.presentationData.isPreview ? [] : dateReactionsAndPeers.reactions,
                        reactionPeers: dateReactionsAndPeers.peers,
                        displayAllReactionPeers: item.message.id.peerId.namespace == Namespaces.Peer.CloudUser,
                        areReactionsTags: item.topMessage.areReactionsTags(accountPeerId: item.context.account.peerId),
                        areStarReactionsEnabled: item.associatedData.areStarReactionsEnabled,
                        messageEffect: item.topMessage.messageEffect(availableMessageEffects: item.associatedData.availableMessageEffects),
                        replyCount: dateReplies,
                        starsCount: starsCount,
                        isPinned: item.message.tags.contains(.pinned) && (!item.associatedData.isInPinnedListMode || isReplyThread),
                        hasAutoremove: item.message.isSelfExpiring,
                        canViewReactionList: canViewMessageReactionList(message: EngineMessage(item.topMessage)),
                        animationCache: item.controllerInteraction.presentationContext.animationCache,
                        animationRenderer: item.controllerInteraction.presentationContext.animationRenderer
                    ))
                }
                
                var textFrame = CGRect(origin: CGPoint(x: -textInsets.left, y: -textInsets.top), size: textLayout.size)

                var textFrameWithoutInsets = CGRect(origin: CGPoint(x: textFrame.origin.x + textInsets.left, y: textFrame.origin.y + textInsets.top), size: CGSize(width: textFrame.width - textInsets.left - textInsets.right, height: textFrame.height - textInsets.top - textInsets.bottom))
                
                textFrame = textFrame.offsetBy(dx: layoutConstants.text.bubbleInsets.left, dy: topInset)
                let realTextFrame = textFrame
                
                if let clippedGlyphCountLayout {
                    textFrame.size = clippedGlyphCountLayout.size
                    textFrameWithoutInsets.size = CGSize(width: textFrame.width - textInsets.left - textInsets.right, height: textFrame.height - textInsets.top - textInsets.bottom)
                }
                
                textFrameWithoutInsets = textFrameWithoutInsets.offsetBy(dx: layoutConstants.text.bubbleInsets.left, dy: topInset)
                
                var scamBannerAttributed: NSAttributedString?
                var scamBannerSize = CGSize.zero
                let scamBannerTopSpacing: CGFloat = 6.0
                let scamBannerPadding = UIEdgeInsets(top: 5.0, left: 8.0, bottom: 5.0, right: 8.0)
                if let fullGramScamWarningText {
                    let bannerColor = incoming ? UIColor(rgb: 0xd9383a) : messageTheme.primaryTextColor
                    let attr = NSAttributedString(
                        string: fullGramScamWarningText,
                        attributes: [
                            .font: Font.medium(11.5),
                            .foregroundColor: bannerColor
                        ]
                    )
                    let maxBannerTextWidth = max(140.0, textConstrainedSize.width - scamBannerPadding.left - scamBannerPadding.right)
                    let measured = attr.boundingRect(
                        with: CGSize(width: maxBannerTextWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    ).integral
                    scamBannerAttributed = attr
                    scamBannerSize = CGSize(
                        width: ceil(measured.width) + scamBannerPadding.left + scamBannerPadding.right,
                        height: ceil(measured.height) + scamBannerPadding.top + scamBannerPadding.bottom
                    )
                }

                let giftCardSize: CGSize
                if let giftPayload = fullGramGiftPayload {
                    giftCardSize = FullGramChatGiftCardView.preferredSize(for: giftPayload, maxWidth: max(220.0, constrainedSize.width - 24.0))
                } else {
                    giftCardSize = .zero
                }

                let horizontalBubbleInsets: CGFloat = isGiftPlaque ? 0.0 : (layoutConstants.text.bubbleInsets.left + layoutConstants.text.bubbleInsets.right)
                var suggestedBoundingWidth: CGFloat = isGiftPlaque
                    ? giftCardSize.width
                    : max(textFrameWithoutInsets.width, max(scamBannerSize.width, giftCardSize.width))
                if !isGiftPlaque, let statusSuggestedWidthAndContinue = statusSuggestedWidthAndContinue, !hasDraft {
                    suggestedBoundingWidth = max(suggestedBoundingWidth, statusSuggestedWidthAndContinue.0)
                }
                let sideInsets = horizontalBubbleInsets
                suggestedBoundingWidth += sideInsets
                
                return (suggestedBoundingWidth, { [weak self] boundingWidth in
                    var boundingSize: CGSize
                    
                    let statusSizeAndApply = isGiftPlaque ? nil : statusSuggestedWidthAndContinue?.1(boundingWidth - sideInsets)
                    
                    if giftCardSize.height > 0.0 {
                        boundingSize = giftCardSize
                    } else {
                        boundingSize = textFrameWithoutInsets.size
                    }
                    if scamBannerSize.height > 0.0 && !isGiftPlaque {
                        boundingSize.width = max(boundingSize.width, scamBannerSize.width)
                        boundingSize.height += scamBannerTopSpacing + scamBannerSize.height
                    }
                    if let statusSizeAndApply = statusSizeAndApply, !hasDraft {
                        boundingSize.height += statusSizeAndApply.0.height + (giftCardSize.height > 0.0 ? 4.0 : 0.0)
                    }

                    boundingSize.width += sideInsets
                    
                    boundingSize.height += topInset + bottomInset
                    
                    return (boundingSize, { [weak self] animation, synchronousLoads, itemApply in
                        if let strongSelf = self {
                            strongSelf.item = item
                            if let updatedCachedChatMessageText = updatedCachedChatMessageText {
                                strongSelf.cachedChatMessageText = updatedCachedChatMessageText
                            }
                            
                            var previousAnimateGlyphCount: Int?
                            if hasDraft || hadDraft {
                                previousAnimateGlyphCount = strongSelf.textNode.textNode.cachedLayout?.attributedString?.length ?? 0
                            }
                            
                            strongSelf.textNode.textNode.displaysAsynchronously = !item.presentationData.isPreview
                            animation.animator.updatePosition(layer: strongSelf.containerNode.layer, position: CGRect(origin: CGPoint(), size: boundingSize).center, completion: nil)
                            animation.animator.updateBounds(layer: strongSelf.containerNode.layer, bounds: CGRect(origin: CGPoint(), size: boundingSize), completion: nil)
                            
                            if let formattedDateUpdatePeriod {
                                if strongSelf.relativeDateTimer?.period != formattedDateUpdatePeriod {
                                    strongSelf.relativeDateTimer?.timer.invalidate()
                                    strongSelf.relativeDateTimer = nil
                                }
                                strongSelf.relativeDateTimer = (SwiftSignalKit.Timer(timeout: Double(formattedDateUpdatePeriod), repeat: true, completion: { [weak self] in
                                    self?.requestFullUpdate?(ControlledTransition(duration: 0.15, curve: .easeInOut, interactive: false))
                                }, queue: Queue.mainQueue()), formattedDateUpdatePeriod)
                                strongSelf.relativeDateTimer?.timer.start()
                            } else if let (timer, _) = strongSelf.relativeDateTimer {
                                strongSelf.relativeDateTimer = nil
                                timer.invalidate()
                            }
                            
                            if strongSelf.isSummaryApplied != isSummaryApplied {
                                strongSelf.isSummaryApplied = isSummaryApplied
                                itemApply?.setInvertOffsetDirection()
                                
                                if let snapshotView = strongSelf.textNode.textNode.view.snapshotContentTree() {
                                    strongSelf.view.addSubview(snapshotView)
                                    
                                    snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { _ in
                                        snapshotView.removeFromSuperview()
                                    })
                                    strongSelf.textNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                                }
                            }
                            if strongSelf.appliedExpandedBlockIds != nil && strongSelf.appliedExpandedBlockIds != strongSelf.expandedBlockIds {
                                itemApply?.setInvertOffsetDirection()
                            }
                            strongSelf.appliedExpandedBlockIds = strongSelf.expandedBlockIds
                            
                            var spoilerExpandRect: CGRect?
                            if let location = strongSelf.displayContentsUnderSpoilers.location {
                                strongSelf.displayContentsUnderSpoilers.location = nil
                                
                                let mappedLocation = CGPoint(x: location.x - textFrame.minX, y: location.y - textFrame.minY)
                                
                                let getDistance: (CGPoint, CGPoint) -> CGFloat = { a, b in
                                    let v = CGPoint(x: a.x - b.x, y: a.y - b.y)
                                    return sqrt(v.x * v.x + v.y * v.y)
                                }
                                
                                var maxDistance: CGFloat = getDistance(mappedLocation, CGPoint(x: 0.0, y: 0.0))
                                maxDistance = max(maxDistance, getDistance(mappedLocation, CGPoint(x: textFrame.width, y: 0.0)))
                                maxDistance = max(maxDistance, getDistance(mappedLocation, CGPoint(x: textFrame.width, y: textFrame.height)))
                                maxDistance = max(maxDistance, getDistance(mappedLocation, CGPoint(x: 0.0, y: textFrame.height)))
                                
                                let mappedSize = CGSize(width: maxDistance * 2.0, height: maxDistance * 2.0)
                                spoilerExpandRect = mappedSize.centered(around: mappedLocation)
                            }
                            
                            let _ = textApply(InteractiveTextNodeWithEntities.Arguments(
                                context: item.context,
                                cache: item.controllerInteraction.presentationContext.animationCache,
                                renderer: item.controllerInteraction.presentationContext.animationRenderer,
                                placeholderColor: messageTheme.mediaPlaceholderColor,
                                attemptSynchronous: synchronousLoads,
                                textColor: messageTheme.primaryTextColor,
                                spoilerEffectColor: messageTheme.secondaryTextColor,
                                applyArguments: InteractiveTextNode.ApplyArguments(
                                    animation: animation,
                                    spoilerTextColor: messageTheme.primaryTextColor,
                                    spoilerEffectColor: messageTheme.secondaryTextColor,
                                    areContentAnimationsEnabled: item.context.sharedContext.energyUsageSettings.loopEmoji,
                                    spoilerExpandRect: spoilerExpandRect,
                                    crossfadeContents: { [weak strongSelf] sourceView in
                                        guard let strongSelf else {
                                            return
                                        }
                                        if let textNodeContainer = strongSelf.textNode.textNode.view.superview {
                                            sourceView.frame = CGRect(origin: strongSelf.textNode.textNode.frame.origin, size: sourceView.bounds.size)
                                            textNodeContainer.addSubview(sourceView)
                                            
                                            sourceView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.12, removeOnCompletion: false, completion: { [weak sourceView] _ in
                                                sourceView?.removeFromSuperview()
                                            })
                                            strongSelf.textNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1)
                                        }
                                    },
                                    blockCornerRadius: item.bubbleStyle.isBubbleless ? chatMessageBubblelessInlineBlockCornerRadius : nil
                                )
                            ))
                            animation.animator.updatePosition(layer: strongSelf.textNode.textNode.layer, position: realTextFrame.center, completion: nil)
                            animation.animator.updateBounds(layer: strongSelf.textNode.textNode.layer, bounds: CGRect(origin: CGPoint(), size: realTextFrame.size), completion: nil)
                            
                            
                            switch strongSelf.visibility {
                            case .none:
                                strongSelf.textNode.visibilityRect = nil
                            case let .visible(_, subRect):
                                var subRect = subRect
                                subRect.origin.x = 0.0
                                subRect.size.width = 10000.0
                                strongSelf.textNode.visibilityRect = subRect
                            }
                            
                            if let textSelectionNode = strongSelf.textSelectionNode {
                                let shouldUpdateLayout = textSelectionNode.frame.size != textFrame.size
                                textSelectionNode.frame = textFrame
                                textSelectionNode.highlightAreaNode.frame = textFrame
                                if shouldUpdateLayout {
                                    textSelectionNode.updateLayout()
                                }
                            }
                            strongSelf.textAccessibilityOverlayNode.frame = textFrame
                    
                            let showTextAsPlaceholder = item.associatedData.showTextAsPlaceholder
                            if showTextAsPlaceholder {
                                isTranslating = true
                            }
                            strongSelf.updateIsTranslating(isTranslating, showTextAsPlaceholder: showTextAsPlaceholder)

                            if let giftPayload = fullGramGiftPayload, giftCardSize.height > 0.0 {
                                strongSelf.textNode.textNode.isHidden = true
                                let cardView: FullGramChatGiftCardView
                                if let existing = strongSelf.fullGramGiftCardView {
                                    cardView = existing
                                } else {
                                    let created = FullGramChatGiftCardView(frame: .zero)
                                    strongSelf.fullGramGiftCardView = created
                                    strongSelf.containerNode.view.addSubview(created)
                                    cardView = created
                                }
                                let availableWidth = max(giftCardSize.width, boundingWidth - sideInsets)
                                let originX = isGiftPlaque
                                    ? floorToScreenPixels((availableWidth - giftCardSize.width) * 0.5)
                                    : layoutConstants.text.bubbleInsets.left
                                cardView.frame = CGRect(
                                    x: originX,
                                    y: topInset,
                                    width: giftCardSize.width,
                                    height: giftCardSize.height
                                )
                                let authorDisplayName: String = {
                                    if !giftPayload.senderName.isEmpty {
                                        return giftPayload.senderName
                                    }
                                    if let author = item.message.author {
                                        return EnginePeer(author).compactDisplayTitle
                                    }
                                    if let peer = item.message.peers[item.message.id.peerId] {
                                        return EnginePeer(peer).compactDisplayTitle
                                    }
                                    return "FullGram"
                                }()
                                let isSelfChat = (item.message.id.peerId == item.context.account.peerId && item.message.forwardInfo == nil)
                                cardView.configure(
                                    context: item.context,
                                    presentationData: item.presentationData,
                                    payload: giftPayload,
                                    incoming: incoming || isSelfChat,
                                    isSelfChat: isSelfChat,
                                    peerId: item.message.id.peerId.toInt64(),
                                    authorName: authorDisplayName
                                )
                            } else {
                                strongSelf.textNode.textNode.isHidden = showTextAsPlaceholder
                                strongSelf.fullGramGiftCardView?.removeFromSuperview()
                                strongSelf.fullGramGiftCardView = nil
                            }
                            
                            if let scamBannerAttributed, scamBannerSize.height > 0.0 {
                                let bannerView: UIView
                                if let existing = strongSelf.fullGramScamBannerView {
                                    bannerView = existing
                                } else {
                                    let created = UIView()
                                    created.layer.cornerRadius = 8.0
                                    created.clipsToBounds = true
                                    created.isUserInteractionEnabled = false
                                    strongSelf.fullGramScamBannerView = created
                                    strongSelf.containerNode.view.addSubview(created)
                                    bannerView = created
                                }
                                let bannerLabel: UILabel
                                if let existing = strongSelf.fullGramScamBannerLabel {
                                    bannerLabel = existing
                                } else {
                                    let created = UILabel()
                                    created.numberOfLines = 0
                                    created.isUserInteractionEnabled = false
                                    strongSelf.fullGramScamBannerLabel = created
                                    bannerView.addSubview(created)
                                    bannerLabel = created
                                }
                                bannerView.backgroundColor = UIColor(rgb: 0xd9383a).withAlphaComponent(0.12)
                                let bannerWidth = max(scamBannerSize.width, boundingWidth - sideInsets)
                                let bannerFrame = CGRect(
                                    x: textFrameWithoutInsets.minX,
                                    y: textFrameWithoutInsets.maxY + scamBannerTopSpacing,
                                    width: bannerWidth,
                                    height: scamBannerSize.height
                                )
                                bannerView.frame = bannerFrame
                                bannerLabel.attributedText = scamBannerAttributed
                                bannerLabel.frame = CGRect(
                                    x: scamBannerPadding.left,
                                    y: scamBannerPadding.top,
                                    width: bannerWidth - scamBannerPadding.left - scamBannerPadding.right,
                                    height: scamBannerSize.height - scamBannerPadding.top - scamBannerPadding.bottom
                                )
                            } else {
                                strongSelf.fullGramScamBannerView?.removeFromSuperview()
                                strongSelf.fullGramScamBannerView = nil
                                strongSelf.fullGramScamBannerLabel = nil
                            }

                            let scamBannerOffsetY = scamBannerSize.height > 0.0 ? (scamBannerTopSpacing + scamBannerSize.height) : 0.0
                            let contentBottomY = giftCardSize.height > 0.0 ? (topInset + giftCardSize.height + 4.0) : textFrameWithoutInsets.maxY
                            if let statusSizeAndApply {
                                let statusNode = statusSizeAndApply.1(strongSelf.statusNode == nil ? .None : animation)
                                let statusFrame = CGRect(origin: CGPoint(x: textFrameWithoutInsets.minX, y: contentBottomY + scamBannerOffsetY), size: statusSizeAndApply.0)
                                
                                if strongSelf.statusNode !== statusNode {
                                    strongSelf.statusNode?.removeFromSupernode()
                                    strongSelf.statusNode = statusNode
                                    
                                    strongSelf.addSubnode(statusNode)
                                    
                                    statusNode.reactionSelected = { [weak strongSelf] _, value, sourceView in
                                        guard let strongSelf, let item = strongSelf.item else {
                                            return
                                        }
                                        item.controllerInteraction.updateMessageReaction(item.topMessage, .reaction(value), false, sourceView)
                                    }
                                    statusNode.openReactionPreview = { [weak strongSelf] gesture, sourceNode, value in
                                        guard let strongSelf, let item = strongSelf.item else {
                                            gesture?.cancel()
                                            return
                                        }
                                        
                                        item.controllerInteraction.openMessageReactionContextMenu(item.topMessage, sourceNode, gesture, value)
                                    }
                                    statusNode.frame = statusFrame
                                } else {
                                    animation.animator.updatePosition(layer: statusNode.layer, position: statusFrame.center, completion: nil)
                                    animation.animator.updateBounds(layer: statusNode.layer, bounds: CGRect(origin: CGPoint(), size: statusFrame.size), completion: nil)
                                }
                            } else if let statusNode = strongSelf.statusNode {
                                strongSelf.statusNode = nil
                                statusNode.removeFromSupernode()
                            }
                            
                            if let forwardInfo = item.message.forwardInfo, forwardInfo.flags.contains(.isImported), let statusNode = strongSelf.statusNode {
                                statusNode.pressed = {
                                    guard let strongSelf = self, let statusNode = strongSelf.statusNode else {
                                        return
                                    }
                                    item.controllerInteraction.displayImportedMessageTooltip(statusNode)
                                }
                            } else {
                                strongSelf.statusNode?.pressed = nil
                            }
                            
                            if let subject = item.associatedData.subject, case let .messageOptions(_, _, info) = subject {
                                if case let .reply(info) = info {
                                    if strongSelf.textSelectionNode == nil {
                                        strongSelf.updateIsExtractedToContextPreview(true)
                                        if let initialQuote = info.quote, item.message.id == initialQuote.messageId {
                                            let nsString = item.message.text as NSString
                                            let subRange = nsString.range(of: initialQuote.text)
                                            if subRange.location != NSNotFound {
                                                strongSelf.beginTextSelection(range: subRange, displayMenu: true)
                                            }
                                        }
                                        
                                        if strongSelf.textSelectionState == nil {
                                            if let textSelectionNode = strongSelf.textSelectionNode {
                                                let range = textSelectionNode.getSelection()
                                                strongSelf.textSelectionState = Promise(strongSelf.getSelectionState(range: range))
                                            } else {
                                                strongSelf.textSelectionState = Promise(strongSelf.getSelectionState(range: nil))
                                            }
                                        }
                                        if let textSelectionState = strongSelf.textSelectionState {
                                            info.selectionState.set(textSelectionState.get())
                                        }
                                    }
                                } else if case let .link(link) = info {
                                    if strongSelf.linkPreviewOptionsDisposable == nil {
                                        strongSelf.linkPreviewOptionsDisposable = (link.options
                                        |> deliverOnMainQueue).startStrict(next: { [weak strongSelf] options in
                                            guard let strongSelf else {
                                                return
                                            }
                                            
                                            if options.hasAlternativeLinks {
                                                strongSelf.linkPreviewHighlightText = options.url
                                                strongSelf.updateLinkPreviewTextHighlightState(text: strongSelf.linkPreviewHighlightText)
                                            }
                                        })
                                    }
                                }
                            }
                            
                            strongSelf.updateLinkProgressState()
                            if let linkPreviewHighlightText = strongSelf.linkPreviewHighlightText {
                                strongSelf.updateLinkPreviewTextHighlightState(text: linkPreviewHighlightText)
                            }
                            
                            if !codeHighlightSpecs.isEmpty {
                                if let current = strongSelf.codeHighlightState, current.id == message.id, current.specs == codeHighlightSpecs {
                                } else {
                                    if let codeHighlightState = strongSelf.codeHighlightState {
                                        strongSelf.codeHighlightState = nil
                                        codeHighlightState.disposable.dispose()
                                    }
                                    
                                    let disposable = MetaDisposable()
                                    strongSelf.codeHighlightState = (message.id, codeHighlightSpecs, disposable)
                                    disposable.set(asyncUpdateMessageSyntaxHighlight(engine: item.context.engine, messageId: message.id, current: cachedMessageSyntaxHighlight, specs: codeHighlightSpecs).startStrict(completed: {
                                    }))
                                }
                            } else if let codeHighlightState = strongSelf.codeHighlightState {
                                strongSelf.codeHighlightState = nil
                                codeHighlightState.disposable.dispose()
                            }
                            
                            if previousAnimateGlyphCount != nil || strongSelf.textRevealController != nil || hasDraft || hadDraft {
                                if strongSelf.textNode.textNode.revealCharacterCount == nil {
                                    if hasDraft {
                                        strongSelf.statusNode?.alpha = 0.0
                                    }
                                    strongSelf.textNode.textNode.updateRevealCharacterCount(count: previousAnimateGlyphCount ?? 0, animated: false)
                                }
                                strongSelf.updateTextRevealAnimation(previousGlyphCount: previousAnimateGlyphCount ?? 0, hasDraft: hasDraft, hadDraft: hadDraft)
                            }
                        }
                    })
                })
            })
        }
    }
    
    private func updateTextRevealAnimation(previousGlyphCount: Int, hasDraft: Bool, hadDraft: Bool) {
        let toCount = self.textNode.textNode.cachedLayout?.attributedString?.length ?? 0
        let now = CACurrentMediaTime()

        if hasDraft, let controller = self.textRevealController, controller.isFinalizing {
            self.textRevealController = nil
            self.textRevealLink = nil
        }

        if self.textRevealController == nil && (hasDraft || hadDraft) {
            self.textRevealController = TextRevealController(initialRevealedCount: previousGlyphCount, initialLength: toCount)
        }

        guard let controller = self.textRevealController else {
            return
        }

        if hasDraft {
            controller.observeUpdate(latestLength: toCount, at: now)
        } else if hadDraft {
            controller.finalize(finalLength: toCount)
        }

        if controller.isFinalizing && controller.revealedCount >= Double(controller.latestLength) {
            self.textRevealController = nil
            self.textRevealLink = nil
            self.textNode.textNode.updateRevealCharacterCount(count: nil, animated: false)
            return
        }

        if self.textRevealLink == nil {
            self.textRevealLink = SharedDisplayLinkDriver.shared.add { [weak self] _ in
                guard let self else {
                    return
                }
                guard let item = self.item else {
                    self.textRevealController = nil
                    self.textRevealLink = nil
                    return
                }
                guard let controller = self.textRevealController else {
                    self.textRevealLink = nil
                    return
                }
                let now = CACurrentMediaTime()
                let (revealedGlyphCount, isComplete) = controller.tick(now: now)
                if isComplete {
                    self.textRevealController = nil
                    self.textRevealLink = nil

                    self.textNode.textNode.updateRevealCharacterCount(count: nil, animated: false)

                    if let statusNode = self.statusNode, !item.message.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) {
                        ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateAlpha(node: statusNode, alpha: 1.0)
                    }

                    self.requestFullUpdate?(ControlledTransition(duration: 0.15, curve: .easeInOut, interactive: false))
                } else {
                    var requestUpdate = false
                    if let previousRevealGlyphCount = self.textNode.textNode.revealCharacterCount, previousRevealGlyphCount != revealedGlyphCount {
                        if let cachedLayout = self.textNode.textNode.cachedLayout {
                            if cachedLayout.sizeForCharacterCount(characterCount: previousRevealGlyphCount) != cachedLayout.sizeForCharacterCount(characterCount: revealedGlyphCount) {
                                requestUpdate = true
                            }
                        } else {
                            requestUpdate = true
                        }
                        self.textNode.textNode.updateRevealCharacterCount(count: revealedGlyphCount, animated: true)
                    }
                    if requestUpdate {
                        self.requestFullUpdate?(ControlledTransition(duration: 0.15, curve: .easeInOut, interactive: false))
                    }
                }
            }
        }
    }
    
    override public func animateInsertion(_ currentTimestamp: Double, duration: Double) {
        self.textNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: 0.0, to: statusNode.alpha, duration: 0.2)
        }
    }
    
    override public func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.textNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: 0.0, to: statusNode.alpha, duration: 0.2)
        }
    }
    
    override public func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.textNode.textNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
        if let statusNode = self.statusNode, statusNode.alpha != 0.0 {
            statusNode.layer.animateAlpha(from: statusNode.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false)
        }
    }
    
    override public func tapActionAtPoint(_ point: CGPoint, gesture: TapLongTapOrDoubleTapGesture, isEstimating: Bool) -> ChatMessageBubbleContentTapAction {
        if case .tap = gesture {
        } else {
            if let item = self.item, let subject = item.associatedData.subject, case .messageOptions = subject {
                return ChatMessageBubbleContentTapAction(content: .none)
            }
        }
        
        func makeActivate(_ urlRange: NSRange?) -> (() -> Promise<Bool>?)? {
            return { [weak self] in
                guard let self else {
                    return nil
                }
                
                let promise = Promise<Bool>()
                
                self.linkProgressDisposable?.dispose()
                
                if self.linkProgressRange != nil {
                    self.linkProgressRange = nil
                    self.updateLinkProgressState()
                }
                
                self.linkProgressDisposable = (promise.get() |> deliverOnMainQueue).startStrict(next: { [weak self] value in
                    guard let self else {
                        return
                    }
                    let updatedRange: NSRange? = value ? urlRange : nil
                    if self.linkProgressRange != updatedRange {
                        self.linkProgressRange = updatedRange
                        self.updateLinkProgressState()
                    }
                })
                
                return promise
            }
        }
        
        let textNodeFrame = self.textNode.textNode.frame
        let textLocalPoint = CGPoint(x: point.x - textNodeFrame.minX, y: point.y - textNodeFrame.minY)
        if let (index, attributes) = self.textNode.textNode.attributesAtPoint(textLocalPoint) {
            var rects: [CGRect]?
            let possibleNames: [String] = [
                TelegramTextAttributes.URL,
                TelegramTextAttributes.PeerMention,
                TelegramTextAttributes.PeerTextMention,
                TelegramTextAttributes.BotCommand,
                TelegramTextAttributes.Hashtag,
                TelegramTextAttributes.Timecode,
                TelegramTextAttributes.BankCard,
                TelegramTextAttributes.TonAddress,
                TelegramTextAttributes.Date
            ]
            for name in possibleNames {
                if let _ = attributes[NSAttributedString.Key(rawValue: name)] {
                    rects = self.textNode.textNode.attributeRects(name: name, at: index)
                    break
                }
            }
            
            
            if let _ = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler)], !self.displayContentsUnderSpoilers.value {
                return ChatMessageBubbleContentTapAction(content: .none)
            } else if let tonAddress = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.TonAddress)] as? TelegramTonAddress {
                guard tonAddress.range.length == 48, tonAddress.address.utf8.count == 48,
                      WalletContext.transferAddress(from: tonAddress.address) != nil else {
                    return ChatMessageBubbleContentTapAction(content: .none)
                }
                return ChatMessageBubbleContentTapAction(content: .tonAddress(tonAddress.address), rects: self.textNode.textNode.rangeRects(in: tonAddress.range)?.rects, activate: makeActivate(tonAddress.range))
            } else if let url = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.URL)] as? String {
                var concealed = true
                var urlRange: NSRange?
                if let (attributeText, fullText, urlRangeValue) = self.textNode.textNode.attributeSubstringWithRange(name: TelegramTextAttributes.URL, index: index) {
                    urlRange = urlRangeValue
                    concealed = !doesUrlMatchText(url: url, text: attributeText, fullText: fullText)
                }
                
                var content: ChatMessageBubbleContentTapAction.Content
                if url.hasPrefix("tel:") {
                    content = .phone(url.replacingOccurrences(of: "tel:", with: ""))
                } else {
                    content = .url(ChatMessageBubbleContentTapAction.Url(url: url, concealed: concealed))
                }
                
                return ChatMessageBubbleContentTapAction(content: content, rects: rects, activate: makeActivate(urlRange))
            } else if let peerMention = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerMention)] as? TelegramPeerMention {
                return ChatMessageBubbleContentTapAction(content: .peerMention(peerId: peerMention.peerId, mention: peerMention.mention, openProfile: false), rects: rects)
            } else if let peerName = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.PeerTextMention)] as? String {
                var urlRange: NSRange?
                if let (_, _, urlRangeValue) = self.textNode.textNode.attributeSubstringWithRange(name: TelegramTextAttributes.PeerTextMention, index: index) {
                    urlRange = urlRangeValue
                }
                
                return ChatMessageBubbleContentTapAction(content: .textMention(peerName), rects: rects, activate: makeActivate(urlRange))
            } else if let botCommand = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.BotCommand)] as? String {
                return ChatMessageBubbleContentTapAction(content: .botCommand(botCommand), rects: rects)
            } else if let hashtag = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Hashtag)] as? TelegramHashtag {
                return ChatMessageBubbleContentTapAction(content: .hashtag(hashtag.peerName, hashtag.hashtag), rects: rects)
            } else if let timecode = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Timecode)] as? TelegramTimecode {
                return ChatMessageBubbleContentTapAction(content: .timecode(timecode.time, timecode.text), rects: rects)
            } else if let bankCard = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.BankCard)] as? String {
                var urlRange: NSRange?
                if let (_, _, urlRangeValue) = self.textNode.textNode.attributeSubstringWithRange(name: TelegramTextAttributes.BankCard, index: index) {
                    urlRange = urlRangeValue
                }
                return ChatMessageBubbleContentTapAction(content: .bankCard(bankCard), rects: rects, activate: makeActivate(urlRange))
            } else if let pre = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Pre)] as? String {
                return ChatMessageBubbleContentTapAction(content: .copy(pre))
            } else if let code = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Code)] as? String {
                return ChatMessageBubbleContentTapAction(content: .copy(code))
            } else if let date = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Date)] as? Int32 {
                var string = ""
                if let (_, text, _) = self.textNode.textNode.attributeSubstringWithRange(name: TelegramTextAttributes.Date, index: index) {
                    string = text
                }
                return ChatMessageBubbleContentTapAction(content: .date(date, string), rects: rects)
            } else if let _ = attributes[NSAttributedString.Key(rawValue: "Attribute__Blockquote")] {
                if let _ = self.textNode.textNode.collapsibleBlockAtPoint(textLocalPoint) {
                    return ChatMessageBubbleContentTapAction(content: .none)
                } else {
                    if let text = self.textNode.textNode.attributeSubstring(name: "Attribute__Blockquote", index: index) {
                        return ChatMessageBubbleContentTapAction(content: .copy(text.0))
                    } else {
                        return ChatMessageBubbleContentTapAction(content: .none)
                    }
                }
            } else if let emoji = attributes[NSAttributedString.Key(rawValue: ChatTextInputAttributes.customEmoji.rawValue)] as? ChatTextInputTextCustomEmojiAttribute, let file = emoji.file {
                return ChatMessageBubbleContentTapAction(content: .customEmoji(file))
            } else {
                if let item = self.item, item.message.text.count == 1, !item.presentationData.largeEmoji {
                    let (emoji, fitz) = item.message.text.basicEmoji
                    var emojiFile: TelegramMediaFile?
                    
                    emojiFile = item.associatedData.animatedEmojiStickers[emoji]?.first?.file._parse()
                    if emojiFile == nil {
                        emojiFile = item.associatedData.animatedEmojiStickers[emoji.strippedEmoji]?.first?.file._parse()
                    }
                    
                    if let emojiFile = emojiFile {
                        return ChatMessageBubbleContentTapAction(content: .largeEmoji(emoji, fitz, emojiFile))
                    } else {
                        return ChatMessageBubbleContentTapAction(content: .none)
                    }
                } else {
                    return ChatMessageBubbleContentTapAction(content: .none)
                }
            }
        } else {
            if let statusNode = self.statusNode, let _ = statusNode.hitTest(self.view.convert(point, to: statusNode.view), with: nil) {
                return ChatMessageBubbleContentTapAction(content: .ignore)
            }
            return ChatMessageBubbleContentTapAction(content: .none)
        }
    }
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let cardView = self.fullGramGiftCardView, !cardView.isHidden {
            let cardPoint = self.view.convert(point, to: cardView)
            if cardView.bounds.contains(cardPoint) {
                return cardView.hitTest(cardPoint, with: event) ?? cardView
            }
        }
        if let statusNode = self.statusNode, statusNode.supernode != nil, let result = statusNode.hitTest(self.view.convert(point, to: statusNode.view), with: event) {
            return result
        }
        return super.hitTest(point, with: event)
    }
    
    private func updateIsTranslating(_ isTranslating: Bool, showTextAsPlaceholder: Bool) {
        guard let item = self.item else {
            return
        }
        var rects = self.textNode.textNode.rangeRects(in: NSRange(location: 0, length: self.textNode.textNode.cachedLayout?.attributedString?.length ?? 0))?.rects ?? []
        if isTranslating, !rects.isEmpty {
            if showTextAsPlaceholder {
                self.textNode.textNode.isHidden = true
            }
            let shimmeringNode: ShimmeringLinkNode
            if let current = self.shimmeringNode {
                shimmeringNode = current
            } else {
                let color: UIColor
                let isIncoming = item.message.effectivelyIncoming(item.context.account.peerId)
                let messageTheme = item.presentationData.theme.theme.chat.message
                if showTextAsPlaceholder {
                    rects = rects.map { $0.insetBy(dx: 0.0, dy: 6.0 + UIScreenPixel) }
                    if rects.count == 2 {
                        rects[0].origin.y += 1.0
                        rects[1].origin.y -= 1.0
                    }
                    color = isIncoming ? messageTheme.incoming.secondaryTextColor.withMultipliedAlpha(0.25) : messageTheme.outgoing.secondaryTextColor.withMultipliedAlpha(0.25)
                } else {
                    if item.presentationData.theme.theme.overallDarkAppearance {
                        color = isIncoming ? messageTheme.incoming.primaryTextColor.withAlphaComponent(0.1) : messageTheme.outgoing.primaryTextColor.withAlphaComponent(0.1)
                    } else {
                        color = isIncoming ? messageTheme.incoming.accentTextColor.withAlphaComponent(0.1) : messageTheme.outgoing.secondaryTextColor.withAlphaComponent(0.1)
                    }
                }
                shimmeringNode = ShimmeringLinkNode(color: color, isSkeleton: showTextAsPlaceholder)
                shimmeringNode.updateRects(rects)
                shimmeringNode.frame = self.textNode.textNode.frame
                shimmeringNode.updateLayout(self.textNode.textNode.frame.size)
                shimmeringNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                self.shimmeringNode = shimmeringNode
                self.containerNode.insertSubnode(shimmeringNode, belowSubnode: self.textNode.textNode)
            }
        } else if let shimmeringNode = self.shimmeringNode {
            self.shimmeringNode = nil
            shimmeringNode.alpha = 0.0
            shimmeringNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, completion: { [weak shimmeringNode] _ in
                shimmeringNode?.removeFromSupernode()
            })
        }
    }
    
    override public func updateTouchesAtPoint(_ point: CGPoint?) {
        if let item = self.item {
            var rects: [CGRect]?
            var spoilerRects: [CGRect]?
            if let point = point {
                let textNodeFrame = self.textNode.textNode.frame
                if let (index, attributes) = self.textNode.textNode.attributesAtPoint(CGPoint(x: point.x - textNodeFrame.minX, y: point.y - textNodeFrame.minY)) {
                    let possibleNames: [String] = [
                        TelegramTextAttributes.URL,
                        TelegramTextAttributes.PeerMention,
                        TelegramTextAttributes.PeerTextMention,
                        TelegramTextAttributes.BotCommand,
                        TelegramTextAttributes.Hashtag,
                        TelegramTextAttributes.Timecode,
                        TelegramTextAttributes.BankCard,
                        TelegramTextAttributes.TonAddress,
                        TelegramTextAttributes.Date
                    ]
                    for name in possibleNames {
                        if let _ = attributes[NSAttributedString.Key(rawValue: name)] {
                            rects = self.textNode.textNode.attributeRects(name: name, at: index)
                            break
                        }
                    }
                    if let tonAddress = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.TonAddress)] as? TelegramTonAddress {
                        rects = self.textNode.textNode.rangeRects(in: tonAddress.range)?.rects
                    }
                    if let _ = attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.Spoiler)] {
                        spoilerRects = self.textNode.textNode.attributeRects(name: TelegramTextAttributes.Spoiler, at: index)
                    }
                }
            }
            
            if let spoilerRects = spoilerRects, !spoilerRects.isEmpty, !self.displayContentsUnderSpoilers.value {
            } else if let rects = rects {
                let linkHighlightingNode: LinkHighlightingNode
                if let current = self.linkHighlightingNode {
                    linkHighlightingNode = current
                } else {
                    linkHighlightingNode = LinkHighlightingNode(color: item.message.effectivelyIncoming(item.context.account.peerId) ? item.presentationData.theme.theme.chat.message.incoming.linkHighlightColor : item.presentationData.theme.theme.chat.message.outgoing.linkHighlightColor)
                    self.linkHighlightingNode = linkHighlightingNode
                    self.containerNode.insertSubnode(linkHighlightingNode, belowSubnode: self.textNode.textNode)
                }
                linkHighlightingNode.frame = self.textNode.textNode.frame
                linkHighlightingNode.updateRects(rects)
            } else if let linkHighlightingNode = self.linkHighlightingNode {
                self.linkHighlightingNode = nil
                linkHighlightingNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18, removeOnCompletion: false, completion: { [weak linkHighlightingNode] _ in
                    linkHighlightingNode?.removeFromSupernode()
                })
            }
        }
    }
    
    override public func updateSearchTextHighlightState(text: String?, messages: [EngineMessage.Index]?) {
        guard let item = self.item else {
            return
        }
        let rectsSet: [[CGRect]]
        if let text = text, let messages = messages, !text.isEmpty, messages.contains(item.message.index) {
            rectsSet = self.textNode.textNode.textRangesRects(text: text)
        } else {
            rectsSet = []
        }
        for i in 0 ..< rectsSet.count {
            var rects = rectsSet[i]
            if rects.count > 1 {
                for i in 0 ..< rects.count - 1 {
                    let deltaY = rects[i + 1].minY - rects[i].maxY
                    if deltaY > 0.0 && deltaY <= 2.0 {
                        rects[i].size.height += deltaY * 0.5
                        rects[i + 1].size.height += deltaY * 0.5
                        rects[i + 1].origin.y -= deltaY * 0.5
                    }
                }
            }
            let textHighlightNode: LinkHighlightingNode
            if i < self.textHighlightingNodes.count {
                textHighlightNode = self.textHighlightingNodes[i]
            } else {
                textHighlightNode = LinkHighlightingNode(color: item.message.effectivelyIncoming(item.context.account.peerId) ? item.presentationData.theme.theme.chat.message.incoming.textHighlightColor : item.presentationData.theme.theme.chat.message.outgoing.textHighlightColor)
                self.textHighlightingNodes.append(textHighlightNode)
                self.containerNode.insertSubnode(textHighlightNode, belowSubnode: self.textNode.textNode)
            }
            textHighlightNode.frame = self.textNode.textNode.frame
            textHighlightNode.updateRects(rects)
        }
        for i in (rectsSet.count ..< self.textHighlightingNodes.count).reversed() {
            self.textHighlightingNodes[i].removeFromSupernode()
            self.textHighlightingNodes.remove(at: i)
        }
    }
    
    private func updateLinkPreviewTextHighlightState(text: String?) {
        guard let item = self.item else {
            return
        }
        
        var rectsSet: [[CGRect]] = []
        if let text = text, !text.isEmpty, let cachedLayout = self.textNode.textNode.cachedLayout, let string = cachedLayout.attributedString?.string {
            let nsString = string as NSString
            let range = nsString.range(of: text)
            if range.location != NSNotFound {
                if let rects = cachedLayout.rangeRects(in: range)?.rects, !rects.isEmpty {
                    rectsSet = [rects]
                }
            }
        }
        for i in 0 ..< rectsSet.count {
            let rects = rectsSet[i]
            let textHighlightNode: LinkHighlightingNode
            if i < self.linkPreviewHighlightingNodes.count {
                textHighlightNode = self.linkPreviewHighlightingNodes[i]
            } else {
                textHighlightNode = LinkHighlightingNode(color: item.message.effectivelyIncoming(item.context.account.peerId) ? item.presentationData.theme.theme.chat.message.incoming.linkHighlightColor.withMultipliedAlpha(0.5) : item.presentationData.theme.theme.chat.message.outgoing.linkHighlightColor.withMultipliedAlpha(0.5))
                self.linkPreviewHighlightingNodes.append(textHighlightNode)
                self.containerNode.insertSubnode(textHighlightNode, belowSubnode: self.textNode.textNode)
            }
            textHighlightNode.frame = self.textNode.textNode.frame
            textHighlightNode.updateRects(rects)
        }
        for i in (rectsSet.count ..< self.linkPreviewHighlightingNodes.count).reversed() {
            self.linkPreviewHighlightingNodes[i].removeFromSupernode()
            self.linkPreviewHighlightingNodes.remove(at: i)
        }
    }
    
    private func updateLinkProgressState() {
        guard let item = self.item else {
            return
        }
        
        let range: NSRange = self.linkProgressRange ?? NSRange(location: NSNotFound, length: 0)
        if range.location != NSNotFound {
            let linkProgressView: TextLoadingEffectView
            if let current = self.linkProgressView {
                linkProgressView = current
            } else {
                linkProgressView = TextLoadingEffectView(frame: CGRect())
                self.linkProgressView = linkProgressView
                self.containerNode.view.addSubview(linkProgressView)
            }
            linkProgressView.frame = self.textNode.textNode.frame
            
            let progressColor: UIColor = item.message.effectivelyIncoming(item.context.account.peerId) ? item.presentationData.theme.theme.chat.message.incoming.linkHighlightColor : item.presentationData.theme.theme.chat.message.outgoing.linkHighlightColor
            
            linkProgressView.update(color: progressColor, textNode: self.textNode.textNode, range: range)
        } else {
            if let linkProgressView = self.linkProgressView {
                self.linkProgressView = nil
                linkProgressView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak linkProgressView] _ in
                    linkProgressView?.removeFromSuperview()
                })
            }
        }
    }
    
    public func animateQuoteTextHighlightIn(sourceFrame: CGRect, transition: ContainedViewLayoutTransition) -> CGRect? {
        if let quoteHighlightingNode = self.quoteHighlightingNode {
            var currentRect = CGRect()
            for rect in quoteHighlightingNode.rects {
                if currentRect.isEmpty {
                    currentRect = rect
                } else {
                    currentRect = currentRect.union(rect)
                }
            }
            if !currentRect.isEmpty {
                currentRect = currentRect.insetBy(dx: -quoteHighlightingNode.inset, dy: -quoteHighlightingNode.inset)
                let innerRect = currentRect.offsetBy(dx: quoteHighlightingNode.frame.minX, dy: quoteHighlightingNode.frame.minY)
                
                quoteHighlightingNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1, delay: 0.04)
                
                let fromScale = CGPoint(x: sourceFrame.width / innerRect.width, y: sourceFrame.height / innerRect.height)
                
                var fromTransform = CATransform3DIdentity
                let fromOffset = CGPoint(x: sourceFrame.midX - innerRect.midX, y: sourceFrame.midY - innerRect.midY)
                
                fromTransform = CATransform3DTranslate(fromTransform, fromOffset.x, fromOffset.y, 0.0)
                
                fromTransform = CATransform3DTranslate(fromTransform, -quoteHighlightingNode.bounds.width * 0.5 + currentRect.midX, -quoteHighlightingNode.bounds.height * 0.5 + currentRect.midY, 0.0)
                fromTransform = CATransform3DScale(fromTransform, fromScale.x, fromScale.y, 1.0)
                fromTransform = CATransform3DTranslate(fromTransform, quoteHighlightingNode.bounds.width * 0.5 - currentRect.midX, quoteHighlightingNode.bounds.height * 0.5 - currentRect.midY, 0.0)
                
                quoteHighlightingNode.transform = fromTransform
                transition.updateTransform(node: quoteHighlightingNode, transform: CGAffineTransformIdentity)
                
                return currentRect.offsetBy(dx: quoteHighlightingNode.frame.minX, dy: quoteHighlightingNode.frame.minY)
            }
        }
        return nil
    }
    
    public func getQuoteRect(quote: String, offset: Int?) -> CGRect? {
        var rectsSet: [CGRect] = []
        if !quote.isEmpty, let cachedLayout = self.textNode.textNode.cachedLayout, let layoutString = cachedLayout.attributedString {
            let range = findQuoteRange(layoutString: layoutString, quoteText: quote, offset: offset)
            if let range, let rects = cachedLayout.rangeRects(in: range)?.rects, !rects.isEmpty {
                rectsSet = rects
            }
        }
        if !rectsSet.isEmpty {
            var currentRect = CGRect()
            for rect in rectsSet {
                if currentRect.isEmpty {
                    currentRect = rect
                } else {
                    currentRect = currentRect.union(rect)
                }
            }
            
            return currentRect.offsetBy(dx: self.textNode.textNode.frame.minX, dy: self.textNode.textNode.frame.minY)
        }
        
        return nil
    }
    
    public func updateQuoteTextHighlightState(text: String?, offset: Int?, color: UIColor, animated: Bool) {
        var rectsSet: [CGRect] = []
        if let text = text, !text.isEmpty, let cachedLayout = self.textNode.textNode.cachedLayout, let layoutString = cachedLayout.attributedString {
            let quoteRange = findQuoteRange(layoutString: layoutString, quoteText: text, offset: offset)
            if let quoteRange, let rects = cachedLayout.rangeRects(in: quoteRange)?.rects, !rects.isEmpty {
                rectsSet = rects
            }
        }
        if !rectsSet.isEmpty {
            let rects = rectsSet
            let textHighlightNode: LinkHighlightingNode
            if let current = self.quoteHighlightingNode {
                textHighlightNode = current
            } else {
                textHighlightNode = LinkHighlightingNode(color: color)
                self.quoteHighlightingNode = textHighlightNode
                self.containerNode.insertSubnode(textHighlightNode, belowSubnode: self.textNode.textNode)
            }
            textHighlightNode.frame = self.textNode.textNode.frame
            textHighlightNode.updateRects(rects)
        } else {
            if let quoteHighlightingNode = self.quoteHighlightingNode {
                self.quoteHighlightingNode = nil
                if animated {
                    quoteHighlightingNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak quoteHighlightingNode] _ in
                        quoteHighlightingNode?.removeFromSupernode()
                    })
                } else {
                    quoteHighlightingNode.removeFromSupernode()
                }
            }
        }
    }
    
    override public func bubblelessLiftParts() -> [ChatMessageBubblelessLiftPart] {
        let textNode = self.textNode.textNode
        guard let layout = textNode.cachedLayout else {
            return super.bubblelessLiftParts()
        }
        // The line boxes, and each quote or code background as a block.
        let linesFrame = textNode.frame.inset(by: layout.insets)
        var parts: [ChatMessageBubblelessLiftPart] = [.textLines(chatMessageBubblelessTextLinesFrame(nodeFrame: textNode.frame, insets: layout.insets, lineRects: layout.linesRects()))]
        for segment in layout.segments {
            if let blockQuoteFrame = segment.blockQuoteFrame {
                parts.append(.block(blockQuoteFrame.offsetBy(dx: linesFrame.minX, dy: linesFrame.minY)))
            }
        }
        return parts
    }
    
    override public func willUpdateIsExtractedToContextPreview(_ value: Bool) {
        if !value {
            if let textSelectionNode = self.textSelectionNode {
                self.textSelectionNode = nil
                textSelectionNode.highlightAreaNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
                textSelectionNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak textSelectionNode] _ in
                    textSelectionNode?.highlightAreaNode.removeFromSupernode()
                    textSelectionNode?.removeFromSupernode()
                })
            }
        }
    }
    
    override public func resignTextSelection() {
        self.cancelTextSelection()
    }

    override public func updateIsExtractedToContextPreview(_ value: Bool) {
        if value {
            if self.textSelectionNode == nil, let item = self.item, let rootNode = item.controllerInteraction.chatControllerNode() {
                let selectionColor: UIColor
                let knobColor: UIColor
                if item.message.effectivelyIncoming(item.context.account.peerId) {
                    selectionColor = item.presentationData.theme.theme.chat.message.incoming.textSelectionColor
                    knobColor = item.presentationData.theme.theme.chat.message.incoming.textSelectionKnobColor
                } else {
                    selectionColor = item.presentationData.theme.theme.chat.message.outgoing.textSelectionColor
                    knobColor = item.presentationData.theme.theme.chat.message.outgoing.textSelectionKnobColor
                }
                
                let textSelectionNode = TextSelectionNode(theme: TextSelectionTheme(selection: selectionColor, knob: knobColor, isDark: item.presentationData.theme.theme.overallDarkAppearance), strings: item.presentationData.strings, textNodeOrView: .node(self.textNode.textNode), updateIsActive: { [weak self] value in
                    self?.updateIsTextSelectionActive?(value)
                }, present: { [weak self] c, a in
                    guard let self, let item = self.item else {
                        return
                    }
                    
                    if let subject = item.associatedData.subject, case let .messageOptions(_, _, info) = subject, case .reply = info {
                        item.controllerInteraction.presentControllerInCurrent(c, a)
                    } else {
                        item.controllerInteraction.presentGlobalOverlayController(c, a)
                    }
                }, rootView: { [weak rootNode] in
                    return rootNode?.view
                }, performAction: { [weak self] text, action in
                    guard let strongSelf = self, let item = strongSelf.item else {
                        return
                    }
                    item.controllerInteraction.performTextSelectionAction(item.message, true, text, nil, action)
                })
                textSelectionNode.updateRange = { [weak self] selectionRange in
                    guard let strongSelf = self else {
                        return
                    }
                    if !strongSelf.displayContentsUnderSpoilers.value, let textLayout = strongSelf.textNode.textNode.cachedLayout, textLayout.segments.contains(where: { !$0.spoilers.isEmpty }), let selectionRange {
                        for segment in textLayout.segments {
                            for (spoilerRange, _) in segment.spoilers {
                                if let intersection = selectionRange.intersection(spoilerRange), intersection.length > 0 {
                                    strongSelf.updateDisplayContentsUnderSpoilers(value: true, at: nil)
                                    return
                                }
                            }
                        }
                    }
                    if let textSelectionState = strongSelf.textSelectionState {
                        textSelectionState.set(.single(strongSelf.getSelectionState(range: selectionRange)))
                    }
                }
                
                let enableCopy = (!item.associatedData.isCopyProtectionEnabled && !item.message.isCopyProtected()) || item.message.id.peerId.isVerificationCodes
                textSelectionNode.enableCopy = enableCopy
                
                var enableQuote = !item.message.text.isEmpty
                var enableOtherActions = true
                if let subject = item.associatedData.subject, case let .messageOptions(_, _, info) = subject, case .reply = info {
                    enableOtherActions = false
                } else if item.controllerInteraction.canSetupReply(item.message) == .reply {
                    //enableOtherActions = false
                }
                
                if !item.controllerInteraction.canSendMessages() && !enableCopy {
                    enableQuote = false
                }
                if item.message.id.peerId.namespace == Namespaces.Peer.SecretChat || item.message.id.peerId.isVerificationCodes {
                    enableQuote = false
                }
                if item.message.containsSecretMedia {
                    enableQuote = false
                }
                if item.associatedData.translateToLanguage != nil {
                    enableQuote = false
                }
                
                textSelectionNode.enableQuote = enableQuote
                textSelectionNode.enableTranslate = enableOtherActions
                textSelectionNode.enableShare = enableOtherActions && enableCopy
                textSelectionNode.menuSkipCoordnateConversion = !enableOtherActions
                self.textSelectionNode = textSelectionNode
                self.containerNode.addSubnode(textSelectionNode)
                self.containerNode.insertSubnode(textSelectionNode.highlightAreaNode, belowSubnode: self.textNode.textNode)
                textSelectionNode.frame = self.textNode.textNode.frame
                textSelectionNode.highlightAreaNode.frame = self.textNode.textNode.frame
            }
        } else {
            if let textSelectionNode = self.textSelectionNode {
                self.textSelectionNode = nil
                self.updateIsTextSelectionActive?(false)
                textSelectionNode.highlightAreaNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
                textSelectionNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak textSelectionNode] _ in
                    textSelectionNode?.highlightAreaNode.removeFromSupernode()
                    textSelectionNode?.removeFromSupernode()
                })
            }
            
            if self.displayContentsUnderSpoilers.value {
                self.updateDisplayContentsUnderSpoilers(value: false, at: nil)
            }
        }
    }
    
    private func updateDisplayContentsUnderSpoilers(value: Bool, at location: CGPoint?) {
        if self.displayContentsUnderSpoilers.value == value {
            return
        }
        self.displayContentsUnderSpoilers = (value, location)
        if let item = self.item {
            item.controllerInteraction.requestMessageUpdate(item.message.id, false, nil)
        }
    }
    
    override public func reactionTargetView(value: MessageReaction.Reaction) -> UIView? {
        if let statusNode = self.statusNode, !statusNode.isHidden {
            return statusNode.reactionView(value: value)
        }
        return nil
    }
    
    override public func messageEffectTargetView() -> UIView? {
        if let statusNode = self.statusNode, !statusNode.isHidden {
            return statusNode.messageEffectTargetView()
        }
        return nil
    }
    
    override public func getStatusNode() -> ASDisplayNode? {
        return self.statusNode
    }

    public func animateFrom(sourceView: UIView, scrollOffset: CGFloat, widthDifference: CGFloat, transition: CombinedTransition) {
        self.containerNode.clipsToBounds = false
        self.containerNode.view.addSubview(sourceView)

        sourceView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.1, removeOnCompletion: false, completion: { [weak sourceView] _ in
            sourceView?.removeFromSuperview()
        })
        self.textNode.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.08)

        let offset = CGPoint(
            x: sourceView.frame.minX - (self.textNode.textNode.frame.minX - 0.0),
            y: sourceView.frame.minY - (self.textNode.textNode.frame.minY - 3.0) - scrollOffset
        )

        transition.vertical.animatePositionAdditive(layer: self.textNode.textNode.layer, offset: offset, completion: { [weak self] _ in
            guard let self else {
                return
            }
            self.containerNode.clipsToBounds = true
        })
        transition.updatePosition(layer: sourceView.layer, position: CGPoint(x: sourceView.layer.position.x - offset.x, y: sourceView.layer.position.y - offset.y))

        if let statusNode = self.statusNode {
            statusNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
            transition.horizontal.animatePositionAdditive(node: statusNode, offset: CGPoint(x: -widthDifference, y: 0.0))
        }
    }
    
    public func beginTextSelection(range: NSRange?, displayMenu: Bool = true) {
        guard let textSelectionNode = self.textSelectionNode else {
            return
        }
        guard let string = self.textNode.textNode.cachedLayout?.attributedString else {
            return
        }
        let nsString = string.string as NSString
        let range = range ?? NSRange(location: 0, length: nsString.length)
        textSelectionNode.setSelection(range: range, displayMenu: displayMenu)
    }
    
    public func cancelTextSelection() {
        guard let textSelectionNode = self.textSelectionNode else {
            return
        }
        textSelectionNode.cancelSelection()
    }
    
    private func getSelectionState(range: NSRange?) -> ChatControllerSubject.MessageOptionsInfo.SelectionState {
        var quote: ChatControllerSubject.MessageOptionsInfo.Quote?
        if let item = self.item, let range, let selection = self.getCurrentTextSelection(customRange: range) {
            quote = ChatControllerSubject.MessageOptionsInfo.Quote(messageId: item.message.id, text: selection.text, offset: selection.offset)
        }
        return ChatControllerSubject.MessageOptionsInfo.SelectionState(canQuote: true, quote: quote)
    }
    
    public func getCurrentTextSelection(customRange: NSRange? = nil) -> (text: String, entities: [MessageTextEntity], offset: Int)? {
        guard let textSelectionNode = self.textSelectionNode else {
            return nil
        }
        guard let rawRange = customRange ?? textSelectionNode.getSelection() else {
            return nil
        }
        guard let item = self.item else {
            return nil
        }
        guard let string = self.textNode.attributedString else {
            return nil
        }
        
        func normalizedSelectionRange(_ range: NSRange, length: Int) -> NSRange {
            let location = min(max(range.location, 0), length)
            let upperBound = min(max(location, range.location + range.length), length)
            return NSRange(location: location, length: upperBound - location)
        }
        
        let range = normalizedSelectionRange(rawRange, length: string.length)
        guard range.length > 0 else {
            return nil
        }

        let nsString = string.string as NSString
        let substring = nsString.substring(with: range)
        let offset = range.location
        
        var entities: [MessageTextEntity] = []
        if let textEntitiesAttribute = item.message.textEntitiesAttribute {
            entities = messageTextEntitiesInRange(entities: textEntitiesAttribute.entities, range: range, onlyQuoteable: true)
        }
        
        return (substring, entities, offset)
    }
    
    public func animateClippingTransition(offset: CGFloat, animation: ListViewItemUpdateAnimation) {
        self.containerNode.clipsToBounds = true
        self.containerNode.bounds = CGRect(origin: CGPoint(x: 0.0, y: offset), size: self.containerNode.bounds.size)
        self.containerNode.alpha = 0.0
        animation.animator.updateAlpha(layer: self.containerNode.layer, alpha: 1.0, completion: nil)
        animation.animator.updateBounds(layer: self.containerNode.layer, bounds: CGRect(origin: CGPoint(), size: self.containerNode.bounds.size), completion: { [weak self] completed in
            guard let self, completed else {
                return
            }
            self.containerNode.clipsToBounds = true
        })
    }
}

extension ChatMessageTextBubbleContentNode: ChatMessageQuoteSourceContentNode {
    public var hasTextSelection: Bool {
        return self.getCurrentTextSelection() != nil
    }

    public func currentReplyQuote(maxLength: Int) -> EngineMessageReplyQuote? {
        guard let textSelection = self.getCurrentTextSelection() else {
            return nil
        }
        let trimmedText = trimStringWithEntities(string: textSelection.text, entities: textSelection.entities, maxLength: maxLength)
        if trimmedText.string.isEmpty {
            return nil
        }
        return EngineMessageReplyQuote(text: trimmedText.string, offset: textSelection.offset, entities: trimmedText.entities, media: nil)
    }
}

private final class FullGramChatGiftCardView: UIView {
    private let servicePillBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let servicePillTintView = UIView()
    private let servicePillLabel = UILabel()

    private let plaqueView = UIView()
    private let plaqueBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let radialGradientLayer = CAGradientLayer()
    private let patternHostView = ComponentView<Empty>()
    private let giftIconHostView = ComponentView<Empty>()

    private let fallbackGlowView = UIView()
    private let fallbackEmojiLabel = UILabel()

    private let ribbonImageView = UIImageView()
    private let ribbonLabel = UILabel()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let attributesContainer = UIView()
    private let modelKeyLabel = UILabel()
    private let modelValueLabel = UILabel()
    private let backdropKeyLabel = UILabel()
    private let backdropValueLabel = UILabel()
    private let symbolKeyLabel = UILabel()
    private let symbolValueLabel = UILabel()

    private let commentPillView = UIView()
    private let commentLabel = UILabel()

    private let actionButton = UIButton(type: .system)

    private var payload: FullGramChatGiftPayload?
    private var targetPeerId: Int64 = 0
    private var resolvedSlugKey: String?
    private var resolvedUniqueGift: StarGift.UniqueGift?
    private var resolvedStarGift: StarGift.Gift?
    private let giftResolveDisposable = MetaDisposable()

    static func preferredSize(for payload: FullGramChatGiftPayload, maxWidth: CGFloat) -> CGSize {
        let plaqueWidth: CGFloat = 224.0
        let servicePillHeight: CGFloat = 22.0
        let serviceGap: CGFloat = 9.0
        let hasComment = !payload.comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttributes: Bool = {
            if hasComment {
                return false
            }
            switch payload.kind {
            case .nft, .upgrade:
                return (payload.modelName?.isEmpty == false)
                    || (payload.backdropName?.isEmpty == false)
                    || (payload.patternName?.isEmpty == false)
            default:
                return false
            }
        }()

        var plaqueHeight: CGFloat = 248.0
        if hasComment {
            plaqueHeight = 294.0
        } else if hasAttributes {
            plaqueHeight = 314.0
        }
        let width = min(max(plaqueWidth, 248.0), maxWidth)
        return CGSize(width: width, height: servicePillHeight + serviceGap + plaqueHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.clipsToBounds = false

        self.servicePillBlurView.layer.cornerRadius = 11.0
        self.servicePillBlurView.clipsToBounds = true
        self.servicePillBlurView.isUserInteractionEnabled = false
        self.addSubview(self.servicePillBlurView)

        self.servicePillTintView.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        self.servicePillTintView.isUserInteractionEnabled = false
        self.servicePillBlurView.contentView.addSubview(self.servicePillTintView)

        self.servicePillLabel.font = Font.regular(13.0)
        self.servicePillLabel.textColor = .white
        self.servicePillLabel.textAlignment = .center
        self.servicePillLabel.lineBreakMode = .byTruncatingMiddle
        self.servicePillBlurView.contentView.addSubview(self.servicePillLabel)

        self.plaqueView.layer.cornerRadius = 24.0
        if #available(iOS 13.0, *) {
            self.plaqueView.layer.cornerCurve = .continuous
        }
        self.plaqueView.clipsToBounds = true
        self.plaqueView.layer.borderWidth = 0.5
        self.plaqueView.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        self.addSubview(self.plaqueView)

        self.plaqueBlurView.isUserInteractionEnabled = false
        self.plaqueView.addSubview(self.plaqueBlurView)

        self.radialGradientLayer.type = .radial
        self.radialGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.34)
        self.radialGradientLayer.endPoint = CGPoint(x: 1.05, y: 1.05)
        self.plaqueView.layer.addSublayer(self.radialGradientLayer)

        self.fallbackGlowView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        self.fallbackGlowView.layer.borderColor = UIColor.white.withAlphaComponent(0.24).cgColor
        self.fallbackGlowView.layer.borderWidth = 1.0
        self.fallbackGlowView.isUserInteractionEnabled = false
        self.plaqueView.addSubview(self.fallbackGlowView)

        self.fallbackEmojiLabel.font = UIFont.systemFont(ofSize: 54.0)
        self.fallbackEmojiLabel.textAlignment = .center
        self.fallbackEmojiLabel.isUserInteractionEnabled = false
        self.plaqueView.addSubview(self.fallbackEmojiLabel)

        self.titleLabel.font = Font.semibold(15.5)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.plaqueView.addSubview(self.titleLabel)

        self.subtitleLabel.font = Font.regular(13.0)
        self.subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.numberOfLines = 2
        self.plaqueView.addSubview(self.subtitleLabel)

        self.attributesContainer.isUserInteractionEnabled = false
        self.plaqueView.addSubview(self.attributesContainer)

        for keyLabel in [self.modelKeyLabel, self.backdropKeyLabel, self.symbolKeyLabel] {
            keyLabel.font = Font.regular(13.0)
            keyLabel.textColor = UIColor.white.withAlphaComponent(0.72)
            keyLabel.textAlignment = .right
            keyLabel.lineBreakMode = .byTruncatingTail
            self.attributesContainer.addSubview(keyLabel)
        }
        for valLabel in [self.modelValueLabel, self.backdropValueLabel, self.symbolValueLabel] {
            valLabel.font = Font.semibold(13.0)
            valLabel.textColor = .white
            valLabel.textAlignment = .left
            valLabel.lineBreakMode = .byTruncatingTail
            self.attributesContainer.addSubview(valLabel)
        }

        self.commentPillView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        self.commentPillView.layer.cornerRadius = 12.0
        if #available(iOS 13.0, *) {
            self.commentPillView.layer.cornerCurve = .continuous
        }
        self.commentPillView.clipsToBounds = true
        self.commentPillView.isUserInteractionEnabled = false
        self.plaqueView.addSubview(self.commentPillView)

        self.commentLabel.font = Font.regular(13.0)
        self.commentLabel.textColor = .white
        self.commentLabel.textAlignment = .center
        self.commentLabel.numberOfLines = 2
        self.commentPillView.addSubview(self.commentLabel)

        self.actionButton.titleLabel?.font = Font.semibold(15.0)
        self.actionButton.setTitleColor(.white, for: .normal)
        self.actionButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        self.actionButton.layer.cornerRadius = 17.0
        if #available(iOS 13.0, *) {
            self.actionButton.layer.cornerCurve = .continuous
        }
        self.actionButton.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)
        self.plaqueView.addSubview(self.actionButton)

        self.ribbonImageView.isUserInteractionEnabled = false
        self.plaqueView.addSubview(self.ribbonImageView)

        self.ribbonLabel.font = Font.semibold(10.5)
        self.ribbonLabel.textColor = .white
        self.ribbonLabel.textAlignment = .center
        self.ribbonLabel.isUserInteractionEnabled = false
        self.plaqueView.addSubview(self.ribbonLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.buttonPressed))
        self.plaqueView.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.giftResolveDisposable.dispose()
    }

    override func removeFromSuperview() {
        super.removeFromSuperview()
        self.giftResolveDisposable.set(nil)
    }

    func configure(
        context: AccountContext,
        presentationData: ChatPresentationData,
        payload: FullGramChatGiftPayload,
        incoming: Bool,
        isSelfChat: Bool,
        peerId: Int64,
        authorName: String
    ) {
        self.payload = payload
        self.targetPeerId = peerId

        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let sender = authorName.isEmpty ? "FullGram" : authorName

        let serviceText: String
        switch payload.kind {
        case .nft, .upgrade:
            if isSelfChat {
                serviceText = ru ? "Коллекционный подарок в Избранном" : "Saved Collectible Gift"
            } else if incoming {
                serviceText = ru ? "\(sender) отправил(а) вам подарок" : "\(sender) sent you a gift"
            } else {
                serviceText = ru ? "Вы отправили коллекционный подарок" : "You sent a collectible gift"
            }
        case .gift:
            if incoming && !isSelfChat {
                serviceText = ru ? "\(sender) отправил(а) вам подарок" : "\(sender) sent you a gift"
            } else {
                serviceText = ru ? "Вы отправили подарок" : "You sent a gift"
            }
        case .stars:
            serviceText = incoming && !isSelfChat
                ? (ru ? "\(sender) подарил(а) вам Звёзды" : "\(sender) gifted you Stars")
                : (ru ? "Вы отправили Звёзды Telegram" : "You gifted Telegram Stars")
        case .ton:
            serviceText = incoming && !isSelfChat
                ? (ru ? "\(sender) перевёл(а) вам TON" : "\(sender) sent you TON")
                : (ru ? "Вы отправили TON" : "You sent TON")
        case .number:
            serviceText = incoming && !isSelfChat
                ? (ru ? "\(sender) передал(а) вам анонимный номер" : "\(sender) transferred an anonymous number")
                : (ru ? "Вы передали анонимный номер" : "You transferred an anonymous number")
        case .username:
            serviceText = incoming && !isSelfChat
                ? (ru ? "\(sender) передал(а) вам юзернейм" : "\(sender) transferred a collectible username")
                : (ru ? "Вы передали коллекционный юзернейм" : "You transferred a collectible username")
        }
        self.servicePillLabel.text = serviceText

        var innerColor: UIColor
        var outerColor: UIColor
        if let unique = self.resolvedUniqueGift {
            var resolvedInner: UIColor?
            var resolvedOuter: UIColor?
            for attr in unique.attributes {
                if case let .backdrop(_, _, innerVal, outerVal, _, _, _) = attr {
                    resolvedInner = UIColor(rgb: UInt32(bitPattern: innerVal))
                    resolvedOuter = UIColor(rgb: UInt32(bitPattern: outerVal))
                    break
                }
            }
            innerColor = resolvedInner ?? payload.backdropInnerHex.map { UIColor(rgb: $0) } ?? UIColor(rgb: 0x4E8CF7)
            outerColor = resolvedOuter ?? payload.backdropOuterHex.map { UIColor(rgb: $0) } ?? UIColor(rgb: 0x223B82)
        } else if let innerHex = payload.backdropInnerHex, let outerHex = payload.backdropOuterHex {
            innerColor = UIColor(rgb: innerHex)
            outerColor = UIColor(rgb: outerHex)
        } else {
            switch payload.kind {
            case .nft, .upgrade:
                innerColor = UIColor(rgb: 0x4E79F5)
                outerColor = UIColor(rgb: 0x1E2F6F)
            case .gift:
                innerColor = UIColor(rgb: 0x2A3550).withAlphaComponent(0.92)
                outerColor = UIColor(rgb: 0x171E30).withAlphaComponent(0.95)
            case .stars:
                innerColor = UIColor(rgb: 0xE59A1A)
                outerColor = UIColor(rgb: 0x7E4208)
            case .ton:
                innerColor = UIColor(rgb: 0x2897FF)
                outerColor = UIColor(rgb: 0x10448A)
            case .number, .username:
                innerColor = UIColor(rgb: 0x3D4C6E)
                outerColor = UIColor(rgb: 0x1A2236)
            }
        }
        self.radialGradientLayer.colors = [innerColor.cgColor, outerColor.cgColor]

        let displayTitle = FullGramGrantedNFT.decoratedTitle(payload.title)
        let trimmedComment = payload.comment.trimmingCharacters(in: .whitespacesAndNewlines)

        var ribbonText = ""
        switch payload.kind {
        case .nft, .upgrade:
            self.titleLabel.text = displayTitle
            if let num = payload.number {
                let nf = NumberFormatter()
                nf.numberStyle = .decimal
                nf.groupingSeparator = " "
                let formatted = nf.string(from: NSNumber(value: num)) ?? "\(num)"
                self.subtitleLabel.text = ru ? "Коллекционный #\(formatted)" : "Collectible #\(formatted)"
                ribbonText = num <= 9999 ? "#\(num)" : (ru ? "Подарок" : "Gift")
            } else {
                self.subtitleLabel.text = ru ? "Коллекционный подарок" : "Collectible Gift"
                ribbonText = ru ? "Подарок" : "Gift"
            }
            self.actionButton.setTitle(ru ? "Просмотреть" : "View", for: .normal)
        case .gift:
            self.titleLabel.text = displayTitle
            self.subtitleLabel.text = payload.canUpgrade
                ? (ru ? "★ \(payload.starsPrice) · Можно улучшить" : "★ \(payload.starsPrice) · Upgradable")
                : "★ \(payload.starsPrice)"
            ribbonText = ru ? "Подарок" : "Gift"
            self.actionButton.setTitle(
                payload.canUpgrade ? (ru ? "Улучшить" : "Upgrade") : (ru ? "Просмотреть" : "View"),
                for: .normal
            )
        case .stars:
            self.titleLabel.text = ru ? "\(payload.starsPrice) Звёзд" : "\(payload.starsPrice) Stars"
            self.subtitleLabel.text = ru ? "Подарочные Звёзды Telegram" : "Telegram Gift Stars"
            ribbonText = "STARS"
            self.actionButton.setTitle(ru ? "Просмотреть" : "View", for: .normal)
        case .ton:
            let amt = String(format: "%.2f", payload.tonAmount ?? 0.0)
            self.titleLabel.text = "\(amt) TON"
            self.subtitleLabel.text = ru ? "Перевод в кошелёк FullGram" : "FullGram Wallet Transfer"
            ribbonText = "TON"
            self.actionButton.setTitle(ru ? "Открыть кошелёк" : "Open Wallet", for: .normal)
        case .number:
            self.titleLabel.text = payload.title
            let tonStr = payload.tonAmount.map { String(format: " · %.0f TON", $0) } ?? ""
            self.subtitleLabel.text = (ru ? "Анонимный номер" : "Anonymous Number") + tonStr
            ribbonText = "+888"
            self.actionButton.setTitle(ru ? "Просмотреть" : "View", for: .normal)
        case .username:
            self.titleLabel.text = payload.title
            let tonStr = payload.tonAmount.map { String(format: " · %.0f TON", $0) } ?? ""
            self.subtitleLabel.text = (ru ? "Коллекционный юзернейм" : "Collectible Username") + tonStr
            ribbonText = "FRAGMENT"
            self.actionButton.setTitle(ru ? "Просмотреть" : "View", for: .normal)
        }

        self.ribbonLabel.text = ribbonText
        if !ribbonText.isEmpty {
            let ribbonBase = UIImage(bundleImageName: "Premium/GiftRibbon") ?? UIImage(bundleImageName: "Chat/Message/GiftRibbon")
            let ribbonColors = [
                outerColor.withMultiplied(hue: 0.98, saturation: 1.35, brightness: 0.92),
                innerColor.withMultiplied(hue: 1.01, saturation: 1.18, brightness: 1.08)
            ]
            self.ribbonImageView.image = generateGradientTintedImage(image: ribbonBase, colors: ribbonColors, direction: .mirroredDiagonal)
            self.ribbonImageView.isHidden = false
            self.ribbonLabel.isHidden = false
        } else {
            self.ribbonImageView.isHidden = true
            self.ribbonLabel.isHidden = true
        }

        if !trimmedComment.isEmpty {
            self.commentPillView.isHidden = false
            self.commentLabel.text = trimmedComment
            self.attributesContainer.isHidden = true
        } else if payload.kind == .nft || payload.kind == .upgrade {
            var resolvedModel = payload.modelName
            var resolvedBackdrop = payload.backdropName
            var resolvedSymbol = payload.patternName
            if let unique = self.resolvedUniqueGift {
                for attr in unique.attributes {
                    switch attr {
                    case let .model(name, _, _, _):
                        if resolvedModel?.isEmpty != false { resolvedModel = name }
                    case let .backdrop(name, _, _, _, _, _, _):
                        if resolvedBackdrop?.isEmpty != false { resolvedBackdrop = name }
                    case let .pattern(name, _, _):
                        if resolvedSymbol?.isEmpty != false { resolvedSymbol = name }
                    default:
                        break
                    }
                }
            }
            let hasAnyAttr = (resolvedModel?.isEmpty == false) || (resolvedBackdrop?.isEmpty == false) || (resolvedSymbol?.isEmpty == false)
            self.commentPillView.isHidden = true
            self.attributesContainer.isHidden = !hasAnyAttr
            if hasAnyAttr {
                self.modelKeyLabel.text = ru ? "Модель" : "Model"
                self.modelValueLabel.text = resolvedModel ?? "Original"
                self.backdropKeyLabel.text = ru ? "Фон" : "Backdrop"
                self.backdropValueLabel.text = resolvedBackdrop ?? "Classic"
                self.symbolKeyLabel.text = ru ? "Узор" : "Symbol"
                self.symbolValueLabel.text = resolvedSymbol ?? "Sparkle"
            }
        } else {
            self.commentPillView.isHidden = true
            self.attributesContainer.isHidden = true
        }

        self.fallbackEmojiLabel.text = payload.emoji.isEmpty ? "🎁" : payload.emoji

        // Resolve real animated 3D GiftItemComponent / pattern cover!
        let candidateSlug: String? = {
            if let s = payload.slug, s.lowercased().hasPrefix("fullgram-") {
                return s
            }
            if let gid = payload.realGiftId {
                return "FullGram-\(gid)-\(payload.number ?? 1)"
            }
            return nil
        }()
        let resolveKey = "\(payload.kind.rawValue)|\(candidateSlug ?? "")|\(payload.realGiftId ?? 0)"
        if self.resolvedSlugKey != resolveKey {
            self.resolvedSlugKey = resolveKey
            self.resolvedUniqueGift = nil
            self.resolvedStarGift = nil
            self.giftResolveDisposable.set(nil)

            if (payload.kind == .nft || payload.kind == .upgrade), let slug = candidateSlug {
                self.giftResolveDisposable.set((context.engine.payments.getUniqueStarGift(slug: slug)
                |> deliverOnMainQueue).start(next: { [weak self] uniqueGift in
                    guard let self, self.resolvedSlugKey == resolveKey else { return }
                    self.resolvedUniqueGift = uniqueGift
                    self.configure(
                        context: context,
                        presentationData: presentationData,
                        payload: payload,
                        incoming: incoming,
                        isSelfChat: isSelfChat,
                        peerId: peerId,
                        authorName: authorName
                    )
                }))
            } else if payload.kind == .gift, let realGiftId = payload.realGiftId {
                self.giftResolveDisposable.set((context.engine.payments.cachedStarGifts()
                |> take(1)
                |> deliverOnMainQueue).start(next: { [weak self] gifts in
                    guard let self, self.resolvedSlugKey == resolveKey else { return }
                    if let items = gifts {
                        for entry in items {
                            if case let .generic(g) = entry, g.id == realGiftId {
                                self.resolvedStarGift = g
                                break
                            }
                        }
                    }
                    if self.resolvedStarGift != nil {
                        self.configure(
                            context: context,
                            presentationData: presentationData,
                            payload: payload,
                            incoming: incoming,
                            isSelfChat: isSelfChat,
                            peerId: peerId,
                            authorName: authorName
                        )
                    }
                }))
            }
        }

        self.updateMediaComponents(context: context, presentationData: presentationData)
        self.setNeedsLayout()
    }

    private func updateMediaComponents(context: AccountContext, presentationData: ChatPresentationData) {
        let plaqueBoundsSize = self.plaqueView.bounds.size.width > 0.0
            ? self.plaqueView.bounds.size
            : CGSize(width: 224.0, height: 280.0)

        if let uniqueGift = self.resolvedUniqueGift {
            self.fallbackGlowView.isHidden = true
            self.fallbackEmojiLabel.isHidden = true

            var bgOuter: UIColor?
            var bgInner: UIColor?
            var patColor: UIColor?
            var patFile: TelegramMediaFile?
            for attr in uniqueGift.attributes {
                switch attr {
                case let .backdrop(_, _, innerVal, outerVal, patVal, _, _):
                    bgInner = UIColor(rgb: UInt32(bitPattern: innerVal))
                    bgOuter = UIColor(rgb: UInt32(bitPattern: outerVal))
                    patColor = UIColor(rgb: UInt32(bitPattern: patVal))
                case let .pattern(_, file, _):
                    patFile = file
                default:
                    break
                }
            }
            if let bgOuter, let bgInner, let patColor, let patFile {
                let files: [Int64: TelegramMediaFile] = [patFile.fileId.id: patFile]
                let _ = self.patternHostView.update(
                    transition: .immediate,
                    component: AnyComponent(PeerInfoCoverComponent(
                        context: context,
                        subject: .custom(bgOuter, bgInner, patColor, patFile.fileId.id),
                        files: files,
                        isDark: false,
                        avatarCenter: CGPoint(x: plaqueBoundsSize.width * 0.5, y: 66.0),
                        avatarScale: 1.0,
                        defaultHeight: plaqueBoundsSize.height,
                        avatarTransitionFraction: 0.0,
                        patternTransitionFraction: 0.0
                    )),
                    environment: {},
                    containerSize: plaqueBoundsSize
                )
                if let patternView = self.patternHostView.view {
                    if patternView.superview == nil {
                        patternView.isUserInteractionEnabled = false
                        self.plaqueView.insertSubview(patternView, belowSubview: self.titleLabel)
                    }
                    patternView.isHidden = false
                    patternView.frame = CGRect(origin: .zero, size: plaqueBoundsSize)
                }
            } else {
                self.patternHostView.view?.isHidden = true
            }

            // Use model-only attributes for the centered 96x96 sticker so it floats cleanly without a nested square box!
            let modelOnlyAttrs = uniqueGift.attributes.filter {
                if case .model = $0 { return true }
                return false
            }
            let iconSize = CGSize(width: 98.0, height: 98.0)
            let subject: GiftItemComponent.Subject = modelOnlyAttrs.isEmpty
                ? .uniqueGift(gift: uniqueGift, price: nil)
                : .preview(attributes: modelOnlyAttrs, rarity: nil)
            let _ = self.giftIconHostView.update(
                transition: .immediate,
                component: AnyComponent(GiftItemComponent(
                    context: context,
                    theme: presentationData.theme.theme,
                    strings: presentationData.strings,
                    peer: nil,
                    subject: subject,
                    mode: .preview,
                    cornerRadius: 0.0,
                    allowAnimations: true
                )),
                environment: {},
                containerSize: iconSize
            )
            if let iconView = self.giftIconHostView.view {
                if iconView.superview == nil {
                    iconView.isUserInteractionEnabled = false
                    iconView.backgroundColor = .clear
                    self.plaqueView.insertSubview(iconView, belowSubview: self.ribbonImageView)
                }
                iconView.isHidden = false
                iconView.frame = CGRect(
                    x: floorToScreenPixels((plaqueBoundsSize.width - iconSize.width) * 0.5),
                    y: 16.0,
                    width: iconSize.width,
                    height: iconSize.height
                )
            }
        } else if let starGift = self.resolvedStarGift {
            self.fallbackGlowView.isHidden = true
            self.fallbackEmojiLabel.isHidden = true
            self.patternHostView.view?.isHidden = true

            let iconSize = CGSize(width: 96.0, height: 96.0)
            let _ = self.giftIconHostView.update(
                transition: .immediate,
                component: AnyComponent(GiftItemComponent(
                    context: context,
                    theme: presentationData.theme.theme,
                    strings: presentationData.strings,
                    peer: nil,
                    subject: .starGift(gift: starGift, price: ""),
                    mode: .preview,
                    cornerRadius: 0.0,
                    allowAnimations: true
                )),
                environment: {},
                containerSize: iconSize
            )
            if let iconView = self.giftIconHostView.view {
                if iconView.superview == nil {
                    iconView.isUserInteractionEnabled = false
                    iconView.backgroundColor = .clear
                    self.plaqueView.insertSubview(iconView, belowSubview: self.ribbonImageView)
                }
                iconView.isHidden = false
                iconView.frame = CGRect(
                    x: floorToScreenPixels((plaqueBoundsSize.width - iconSize.width) * 0.5),
                    y: 18.0,
                    width: iconSize.width,
                    height: iconSize.height
                )
            }
        } else {
            self.patternHostView.view?.isHidden = true
            self.giftIconHostView.view?.isHidden = true
            self.fallbackGlowView.isHidden = false
            self.fallbackEmojiLabel.isHidden = false
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let totalW = self.bounds.width
        let totalH = self.bounds.height
        guard totalW > 0.0, totalH > 0.0 else { return }

        let pillTextSize = self.servicePillLabel.sizeThatFits(CGSize(width: totalW - 16.0, height: 22.0))
        let pillW = min(totalW, max(96.0, ceil(pillTextSize.width) + 22.0))
        let pillH: CGFloat = 22.0
        self.servicePillBlurView.frame = CGRect(
            x: floorToScreenPixels((totalW - pillW) * 0.5),
            y: 0.0,
            width: pillW,
            height: pillH
        )
        self.servicePillTintView.frame = self.servicePillBlurView.bounds
        self.servicePillLabel.frame = self.servicePillBlurView.bounds.insetBy(dx: 10.0, dy: 0.0)

        let plaqueW: CGFloat = min(224.0, totalW)
        let plaqueY: CGFloat = pillH + 9.0
        let plaqueH: CGFloat = max(200.0, totalH - plaqueY)
        self.plaqueView.frame = CGRect(
            x: floorToScreenPixels((totalW - plaqueW) * 0.5),
            y: plaqueY,
            width: plaqueW,
            height: plaqueH
        )
        self.plaqueBlurView.frame = self.plaqueView.bounds
        self.radialGradientLayer.frame = self.plaqueView.bounds

        if let patternView = self.patternHostView.view, !patternView.isHidden {
            patternView.frame = self.plaqueView.bounds
        }
        if let iconView = self.giftIconHostView.view, !iconView.isHidden {
            let iconW = iconView.bounds.width > 0.0 ? iconView.bounds.width : 98.0
            let iconH = iconView.bounds.height > 0.0 ? iconView.bounds.height : 98.0
            iconView.frame = CGRect(
                x: floorToScreenPixels((plaqueW - iconW) * 0.5),
                y: 16.0,
                width: iconW,
                height: iconH
            )
        }

        let circleSide: CGFloat = 84.0
        self.fallbackGlowView.frame = CGRect(
            x: floorToScreenPixels((plaqueW - circleSide) * 0.5),
            y: 22.0,
            width: circleSide,
            height: circleSide
        )
        self.fallbackGlowView.layer.cornerRadius = circleSide * 0.5
        self.fallbackEmojiLabel.frame = self.fallbackGlowView.frame

        if let ribbonImage = self.ribbonImageView.image, !self.ribbonImageView.isHidden {
            let ribbonFrame = CGRect(
                x: plaqueW - ribbonImage.size.width + 1.0,
                y: -1.0,
                width: ribbonImage.size.width,
                height: ribbonImage.size.height
            )
            self.ribbonImageView.frame = ribbonFrame
            let rSize = self.ribbonLabel.sizeThatFits(CGSize(width: 90.0, height: 20.0))
            self.ribbonLabel.transform = .identity
            self.ribbonLabel.bounds = CGRect(origin: .zero, size: CGSize(width: ceil(rSize.width), height: ceil(rSize.height)))
            self.ribbonLabel.center = CGPoint(x: ribbonFrame.midX + 7.0, y: ribbonFrame.midY - 6.0)
            self.ribbonLabel.transform = CGAffineTransform(rotationAngle: .pi / 4.0)
        }

        self.titleLabel.frame = CGRect(x: 14.0, y: 120.0, width: plaqueW - 28.0, height: 21.0)
        let subSize = self.subtitleLabel.sizeThatFits(CGSize(width: plaqueW - 28.0, height: 36.0))
        let subH = min(36.0, max(17.0, ceil(subSize.height)))
        self.subtitleLabel.frame = CGRect(x: 14.0, y: 143.0, width: plaqueW - 28.0, height: subH)

        let contentTopY = self.subtitleLabel.frame.maxY + 10.0
        if !self.commentPillView.isHidden {
            let cTextSize = self.commentLabel.sizeThatFits(CGSize(width: plaqueW - 48.0, height: 40.0))
            let pillBoxW = min(plaqueW - 28.0, max(96.0, ceil(cTextSize.width) + 24.0))
            let pillBoxH = min(46.0, max(28.0, ceil(cTextSize.height) + 10.0))
            self.commentPillView.frame = CGRect(
                x: floorToScreenPixels((plaqueW - pillBoxW) * 0.5),
                y: contentTopY,
                width: pillBoxW,
                height: pillBoxH
            )
            self.commentLabel.frame = self.commentPillView.bounds.insetBy(dx: 10.0, dy: 4.0)
        } else if !self.attributesContainer.isHidden {
            let attrH: CGFloat = 66.0
            self.attributesContainer.frame = CGRect(x: 12.0, y: contentTopY, width: plaqueW - 24.0, height: attrH)
            let rowH: CGFloat = 20.0
            let gap: CGFloat = 7.0
            let containerW = plaqueW - 24.0
            let splitX = floorToScreenPixels(containerW * 0.44)
            let rows: [(UILabel, UILabel, CGFloat)] = [
                (self.modelKeyLabel, self.modelValueLabel, 0.0),
                (self.backdropKeyLabel, self.backdropValueLabel, 22.0),
                (self.symbolKeyLabel, self.symbolValueLabel, 44.0)
            ]
            for (kLabel, vLabel, yOff) in rows {
                kLabel.frame = CGRect(x: 0.0, y: yOff, width: splitX - gap * 0.5, height: rowH)
                vLabel.frame = CGRect(x: splitX + gap * 0.5, y: yOff, width: containerW - splitX - gap * 0.5, height: rowH)
            }
        }

        let btnTitleSize = self.actionButton.titleLabel?.sizeThatFits(CGSize(width: plaqueW - 36.0, height: 34.0)) ?? CGSize(width: 100.0, height: 20.0)
        let btnW = min(plaqueW - 32.0, max(132.0, ceil(btnTitleSize.width) + 38.0))
        let btnH: CGFloat = 34.0
        self.actionButton.frame = CGRect(
            x: floorToScreenPixels((plaqueW - btnW) * 0.5),
            y: plaqueH - btnH - 14.0,
            width: btnW,
            height: btnH
        )
    }

    @objc private func buttonPressed() {
        guard let payload = self.payload,
              let data = try? JSONEncoder().encode(payload) else {
            return
        }
        NotificationCenter.default.post(
            name: FullGramChatGiftPayload.openCardNotification,
            object: nil,
            userInfo: [
                "payload": data,
                "peerId": self.targetPeerId
            ]
        )
    }
}
