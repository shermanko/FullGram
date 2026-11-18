import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import SwiftSignalKit
import AccountContext
import ChatInterfaceState

// MARK: - Local Telegram Context Builder for AI Agent

private enum FullGramAITelegramContextBuilder {
    struct ParsedDateQuery {
        let label: String
        let startTimestamp: Int32
        let endTimestamp: Int32
    }

    static func parseDate(from prompt: String) -> ParsedDateQuery? {
        let lower = prompt.lowercased()
        let cal = Calendar.current
        let now = Date()

        let makeRange: (Date, String) -> ParsedDateQuery? = { date, label in
            let start = cal.startOfDay(for: date)
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            return ParsedDateQuery(
                label: label,
                startTimestamp: Int32(start.timeIntervalSince1970),
                endTimestamp: Int32(end.timeIntervalSince1970) - 1
            )
        }

        if lower.contains("позавчера"), let d = cal.date(byAdding: .day, value: -2, to: now) {
            return makeRange(d, "позавчера")
        }
        if lower.contains("вчера"), let d = cal.date(byAdding: .day, value: -1, to: now) {
            return makeRange(d, "вчера")
        }
        if lower.contains("сегодня") {
            return makeRange(now, "сегодня")
        }

        // dd.MM.yyyy or dd/MM/yyyy
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})[./](\d{1,2})[./](\d{2,4})\b"#),
           let match = regex.firstMatch(in: prompt, range: NSRange(location: 0, length: (prompt as NSString).length)) {
            let ns = prompt as NSString
            if let day = Int(ns.substring(with: match.range(at: 1))),
               let month = Int(ns.substring(with: match.range(at: 2))),
               var year = Int(ns.substring(with: match.range(at: 3))) {
                if year < 100 { year += 2000 }
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = day
                if let date = cal.date(from: comps) {
                    let df = DateFormatter()
                    df.dateFormat = "dd.MM.yyyy"
                    return makeRange(date, df.string(from: date))
                }
            }
        }

        // yyyy-MM-dd
        if let regex = try? NSRegularExpression(pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#),
           let match = regex.firstMatch(in: prompt, range: NSRange(location: 0, length: (prompt as NSString).length)) {
            let ns = prompt as NSString
            if let year = Int(ns.substring(with: match.range(at: 1))),
               let month = Int(ns.substring(with: match.range(at: 2))),
               let day = Int(ns.substring(with: match.range(at: 3))) {
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = day
                if let date = cal.date(from: comps) {
                    let df = DateFormatter()
                    df.dateFormat = "dd.MM.yyyy"
                    return makeRange(date, df.string(from: date))
                }
            }
        }
        return nil
    }

    static func gatherContext(
        prompt: String,
        targetPeerId: PeerId?,
        context: AccountContext,
        completion: @escaping (String) -> Void
    ) {
        let store = FullGramAIStore.shared
        var signals: [Signal<String, NoError>] = []

        if let peerId = targetPeerId, store.allowReadCurrentChat {
            let peerSignal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            let recentSignal = context.account.postbox.aroundMessageHistoryViewForLocation(
                .peer(peerId: peerId, threadId: nil),
                anchor: .upperBound,
                ignoreMessagesInTimestampRange: nil,
                ignoreMessageIds: Set(),
                count: 45,
                fixedCombinedReadStates: nil,
                topTaggedMessageIdNamespaces: [Namespaces.Message.Cloud],
                tag: nil,
                appendMessagesFromTheSameGroup: false,
                namespaces: .not(Namespaces.Message.allNonRegular),
                orderStatistics: []
            )
            |> take(1)

            let dateQuery = Self.parseDate(from: prompt)
            let dateSearchSignal: Signal<SearchMessagesResult?, NoError>
            if let dq = dateQuery {
                dateSearchSignal = context.engine.messages.searchMessages(
                    location: .peer(
                        peerId: peerId,
                        fromId: nil,
                        tags: nil,
                        reactions: nil,
                        threadId: nil,
                        minDate: dq.startTimestamp,
                        maxDate: dq.endTimestamp
                    ),
                    query: "",
                    state: nil,
                    centerId: nil,
                    limit: 100
                )
                |> take(1)
                |> map { Optional($0.0) }
            } else {
                dateSearchSignal = .single(nil)
            }

            let currentChatBlock = combineLatest(peerSignal, recentSignal, dateSearchSignal)
            |> map { peer, historyTuple, dateSearch -> String in
                let peerTitle = peer?.debugDisplayTitle ?? "Текущий чат"
                let df = DateFormatter()
                df.dateFormat = "dd.MM.yyyy HH:mm"

                var lines: [String] = []
                lines.append("[ТЕКУЩИЙ ЧАТ: peer_id=\(peerId.toInt64()), title=\"\(Self.sanitize(peerTitle, maxLen: 60))\"]")

                if let dq = dateQuery, let dateSearch {
                    let countInDay = dateSearch.totalCount > 0 ? Int(dateSearch.totalCount) : dateSearch.messages.count
                    var authorCounts: [String: Int] = [:]
                    for msg in dateSearch.messages {
                        let author = msg.author.map { EnginePeer($0).debugDisplayTitle } ?? "Система"
                        authorCounts[Self.sanitize(author, maxLen: 32), default: 0] += 1
                    }
                    let authorBreakdown = authorCounts
                        .sorted { $0.value > $1.value }
                        .prefix(6)
                        .map { "\($0.key): \($0.value)" }
                        .joined(separator: ", ")

                    lines.append("[VERIFIED_LOCAL_STATS]")
                    lines.append("Дата запроса: \(dq.label)")
                    lines.append("Точное количество сообщений за \(dq.label) в Telegram: \(countInDay) (загружено примеров: \(dateSearch.messages.count))")
                    if !authorBreakdown.isEmpty {
                        lines.append("Активность участников (среди загруженных): \(authorBreakdown)")
                    }
                    if !dateSearch.messages.isEmpty {
                        lines.append("[UNTRUSTED_CHAT_DATA — сообщения за \(dq.label)]")
                        for msg in dateSearch.messages.prefix(25).reversed() {
                            let author = Self.sanitize(msg.author.map { EnginePeer($0).debugDisplayTitle } ?? "Пользователь", maxLen: 28)
                            let body = Self.formatMessageBody(msg)
                            let ts = df.string(from: Date(timeIntervalSince1970: TimeInterval(msg.timestamp)))
                            lines.append("[\(ts)] \(author): \(body)")
                        }
                    }
                }

                let recentMessages = historyTuple.0.entries.map { $0.message }
                if !recentMessages.isEmpty {
                    lines.append("[UNTRUSTED_CHAT_DATA — последние \(min(30, recentMessages.count)) сообщений]")
                    for msg in recentMessages.suffix(30) {
                        let author = Self.sanitize(msg.author.map { EnginePeer($0).debugDisplayTitle } ?? "Пользователь", maxLen: 28)
                        let body = Self.formatMessageBody(msg)
                        let ts = df.string(from: Date(timeIntervalSince1970: TimeInterval(msg.timestamp)))
                        lines.append("[\(ts)] \(author): \(body)")
                    }
                }
                return lines.joined(separator: "\n")
            }
            signals.append(currentChatBlock)
        }

        if store.allowReadChatList {
            let chatListSignal = context.account.viewTracker.tailChatListView(
                groupId: .root,
                filterPredicate: nil,
                count: 14,
                shouldLoadCanMessagePeer: false
            )
            |> take(1)
            |> map { view, _ -> String in
                var listLines: [String] = ["[UNTRUSTED_CHAT_DATA — последние диалоги (для поиска/открытия)]"]
                for entry in view.entries.reversed() {
                    if case let .MessageEntry(data) = entry, let mainPeer = data.renderedPeer.chatMainPeer {
                        let title = Self.sanitize(EnginePeer(mainPeer).debugDisplayTitle, maxLen: 42)
                        let unread = data.readState?.state.count ?? 0
                        listLines.append("peer_id=\(mainPeer.id.toInt64()) | \(title) | непрочит: \(unread)")
                    }
                }
                return listLines.joined(separator: "\n")
            }
            signals.append(chatListSignal)
        }

        guard !signals.isEmpty else {
            completion("")
            return
        }

        let _ = (combineLatest(signals) |> deliverOnMainQueue).start(next: { blocks in
            completion(blocks.filter { !$0.isEmpty }.joined(separator: "\n\n"))
        })
    }

    private static func formatMessageBody(_ msg: Message) -> String {
        let raw = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return Self.sanitize(raw, maxLen: 160)
        }
        if !msg.media.isEmpty {
            return "<медиафайл>"
        }
        return "<событие>"
    }

    private static func sanitize(_ text: String, maxLen: Int) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        if singleLine.count <= maxLen {
            return singleLine
        }
        return String(singleLine.prefix(maxLen)) + "…"
    }
}

// MARK: - Floating Draggable Mascot Pet View

private final class FullGramMascotPetView: UIView {
    private let imageView = UIImageView()
    private let badgeView = UIView()
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    private let posXKey = "fullgram.ai.petPosX"
    private let posYKey = "fullgram.ai.petPosY"
    private var initialCenter = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.28
        self.layer.shadowRadius = 8.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)

        self.imageView.image = UIImage(named: "FullGramMascotPet") ?? UIImage(named: "FullGramMascotPortrait")
        self.imageView.contentMode = .scaleAspectFit
        self.imageView.isUserInteractionEnabled = false
        self.addSubview(self.imageView)

        self.badgeView.backgroundColor = UIColor.systemGreen
        self.badgeView.layer.cornerRadius = 6.0
        self.badgeView.layer.borderWidth = 1.5
        self.badgeView.layer.borderColor = UIColor.white.cgColor
        self.badgeView.isHidden = true
        self.addSubview(self.badgeView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        self.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        self.addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        self.addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.imageView.frame = self.bounds
        self.badgeView.frame = CGRect(x: self.bounds.width - 14.0, y: 4.0, width: 12.0, height: 12.0)
    }

    func updateBusy(_ busy: Bool, accentColor: UIColor) {
        self.badgeView.backgroundColor = busy ? UIColor.systemOrange : accentColor
        self.badgeView.isHidden = !busy && !FullGramAIStore.shared.hasConfiguredKey
    }

    func restorePosition(in bounds: CGRect, safeInsets: UIEdgeInsets) {
        let size = CGFloat(FullGramAIStore.shared.petSizePt)
        let savedX = UserDefaults.standard.object(forKey: self.posXKey) as? Double
        let savedY = UserDefaults.standard.object(forKey: self.posYKey) as? Double

        let minX = safeInsets.left + 8.0
        let maxX = max(minX, bounds.width - safeInsets.right - size - 8.0)
        let minY = safeInsets.top + 56.0
        let maxY = max(minY, bounds.height - safeInsets.bottom - size - 80.0)

        let originX = savedX.map { CGFloat($0) * maxX } ?? maxX
        let originY = savedY.map { CGFloat($0) * maxY } ?? maxY - 24.0
        self.frame = CGRect(
            x: min(maxX, max(minX, originX)),
            y: min(maxY, max(minY, originY)),
            width: size,
            height: size
        )
    }

    @objc private func handleTap() {
        UIView.animate(withDuration: 0.12, animations: {
            self.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        }, completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 0.0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, animations: {
                self.transform = .identity
            })
        })
        self.onTap?()
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        if gr.state == .began {
            self.onLongPress?()
        }
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let host = self.superview else { return }
        let safeInsets = host.safeAreaInsets
        let size = self.bounds.width
        let minX = safeInsets.left + 8.0
        let maxX = max(minX, host.bounds.width - safeInsets.right - size - 8.0)
        let minY = safeInsets.top + 56.0
        let maxY = max(minY, host.bounds.height - safeInsets.bottom - size - 70.0)

        switch gr.state {
        case .began:
            self.initialCenter = self.center
        case .changed:
            let trans = gr.translation(in: host)
            let half = size * 0.5
            let nextX = min(maxX + half, max(minX + half, self.initialCenter.x + trans.x))
            let nextY = min(maxY + half, max(minY + half, self.initialCenter.y + trans.y))
            self.center = CGPoint(x: nextX, y: nextY)
        case .ended, .cancelled:
            let snapLeft = self.center.x < host.bounds.midX
            let targetOriginX = snapLeft ? minX : maxX
            let targetOriginY = min(maxY, max(minY, self.frame.minY))
            if maxX > 0 { UserDefaults.standard.set(Double(targetOriginX / maxX), forKey: self.posXKey) }
            if maxY > 0 { UserDefaults.standard.set(Double(targetOriginY / maxY), forKey: self.posYKey) }
            UIView.animate(withDuration: 0.28, delay: 0.0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.5, options: [.allowUserInteraction], animations: {
                self.frame.origin = CGPoint(x: targetOriginX, y: targetOriginY)
            })
        default:
            break
        }
    }
}

// MARK: - AI Message Cell View

private final class FullGramAIChatBubbleRow: UIView {
    private let cardView = UIView()
    private let textLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private var messageId: String = ""
    private var action: FullGramAIProposedAction?

    var onConfirmAction: ((String, FullGramAIProposedAction) -> Void)?
    var onInsertDraftInstead: ((String, FullGramAIProposedAction) -> Void)?

    func configure(
        message: FullGramAIChatMessage,
        theme: PresentationTheme,
        maxWidth: CGFloat
    ) -> CGFloat {
        self.messageId = message.id
        self.action = message.action

        self.subviews.forEach { $0.removeFromSuperview() }
        self.addSubview(self.cardView)
        self.cardView.addSubview(self.textLabel)

        let accent = theme.chat.inputPanel.actionControlFillColor
        let isUser = message.isUser

        self.cardView.layer.cornerRadius = 14.0
        self.cardView.backgroundColor = isUser
            ? accent
            : (theme.overallDarkAppearance ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.06))

        self.textLabel.numberOfLines = 0
        self.textLabel.font = .systemFont(ofSize: 13.5)
        self.textLabel.textColor = isUser ? .white : theme.list.itemPrimaryTextColor
        self.textLabel.text = message.text

        let bubbleMaxW = max(160.0, maxWidth * 0.84)
        let padH: CGFloat = 11.0
        let padV: CGFloat = 8.0
        let textFit = self.textLabel.sizeThatFits(CGSize(width: bubbleMaxW - padH * 2.0, height: .greatestFiniteMagnitude))

        var contentW = min(bubbleMaxW, max(72.0, ceil(textFit.width) + padH * 2.0))
        var contentH = ceil(textFit.height) + padV * 2.0
        self.textLabel.frame = CGRect(x: padH, y: padV, width: contentW - padH * 2.0, height: ceil(textFit.height))

        if let action = message.action, !isUser {
            contentW = bubbleMaxW
            let buttonW = contentW - padH * 2.0
            let statusY = self.textLabel.frame.maxY + 8.0

            self.actionButton.removeTarget(nil, action: nil, for: .allEvents)
            self.secondaryButton.removeTarget(nil, action: nil, for: .allEvents)

            var btnCfg = UIButton.Configuration.filled()
            btnCfg.cornerStyle = .medium
            btnCfg.titleAlignment = .center
            btnCfg.baseBackgroundColor = action.status == .applied
                ? UIColor.systemGreen.withAlphaComponent(0.18)
                : accent.withAlphaComponent(0.18)
            btnCfg.baseForegroundColor = action.status == .applied ? UIColor.systemGreen : accent

            var titleAttr: AttributedString
            switch action.status {
            case .pending:
                titleAttr = AttributedString(action.kind == .sendMessage ? "Отправить: \(action.summaryTitle)" : action.summaryTitle)
                self.actionButton.isEnabled = true
            case .applied:
                titleAttr = AttributedString("✓ Выполнено")
                self.actionButton.isEnabled = false
            case .cancelled:
                titleAttr = AttributedString("Отменено")
                self.actionButton.isEnabled = false
            }
            titleAttr.font = .systemFont(ofSize: 12.5, weight: .semibold)
            btnCfg.attributedTitle = titleAttr
            self.actionButton.configuration = btnCfg
            self.actionButton.addTarget(self, action: #selector(self.primaryActionTapped), for: .touchUpInside)
            self.actionButton.frame = CGRect(x: padH, y: statusY, width: buttonW, height: 32.0)
            self.cardView.addSubview(self.actionButton)
            contentH = self.actionButton.frame.maxY + padV

            if action.kind == .sendMessage && action.status == .pending {
                var secCfg = UIButton.Configuration.tinted()
                var secTitle = AttributedString("Вставить как черновик")
                secTitle.font = .systemFont(ofSize: 12.0, weight: .medium)
                secCfg.attributedTitle = secTitle
                secCfg.cornerStyle = .medium
                secCfg.baseBackgroundColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.14)
                secCfg.baseForegroundColor = theme.list.itemPrimaryTextColor
                self.secondaryButton.configuration = secCfg
                self.secondaryButton.addTarget(self, action: #selector(self.draftActionTapped), for: .touchUpInside)
                self.secondaryButton.frame = CGRect(x: padH, y: self.actionButton.frame.maxY + 6.0, width: buttonW, height: 28.0)
                self.cardView.addSubview(self.secondaryButton)
                contentH = self.secondaryButton.frame.maxY + padV
            }
        }

        let originX = isUser ? (maxWidth - contentW) : 0.0
        self.cardView.frame = CGRect(x: originX, y: 0.0, width: contentW, height: contentH)
        return contentH
    }

    @objc private func primaryActionTapped() {
        guard let action = self.action else { return }
        self.onConfirmAction?(self.messageId, action)
    }

    @objc private func draftActionTapped() {
        guard let action = self.action else { return }
        self.onInsertDraftInstead?(self.messageId, action)
    }
}

// MARK: - Minimizable & Resizable Theme-Matched AI Window

private final class FullGramAIChatWindowView: UIView, UITextFieldDelegate {
    enum WindowMode {
        case standard
        case compact
        case minimized
    }

    private var mode: WindowMode = .standard
    private var theme: PresentationTheme
    private var isLoading = false

    private let headerView = UIView()
    private let avatarView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let petButton = UIButton(type: .system)
    private let resizeButton = UIButton(type: .system)
    private let minimizeButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private let headerSeparator = UIView()
    private let bodyContainer = UIView()
    private let scrollView = UIScrollView()
    private let emptyHintLabel = UILabel()
    private let chipsScroll = UIScrollView()
    private let footerSeparator = UIView()
    private let inputField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    var onSendPrompt: ((String) -> Void)?
    var onConfirmAction: ((String, FullGramAIProposedAction) -> Void)?
    var onInsertDraftInstead: ((String, FullGramAIProposedAction) -> Void)?
    var onTogglePet: (() -> Void)?
    var onClose: (() -> Void)?

    private var panStartOrigin = CGPoint.zero
    private var customOrigin: CGPoint?
    private var keyboardHeight: CGFloat = 0.0

    init(theme: PresentationTheme) {
        self.theme = theme
        super.init(frame: .zero)

        self.layer.cornerRadius = 18.0
        self.layer.borderWidth = 0.5
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.25
        self.layer.shadowRadius = 16.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 8.0)

        self.headerView.clipsToBounds = true
        self.headerView.layer.cornerRadius = 18.0
        self.headerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        self.addSubview(self.headerView)

        self.avatarView.image = UIImage(named: "FullGramMascotPortrait") ?? UIImage(named: "FullGramMascotPet")
        self.avatarView.contentMode = .scaleAspectFill
        self.avatarView.layer.cornerRadius = 15.0
        self.avatarView.clipsToBounds = true
        self.headerView.addSubview(self.avatarView)

        self.titleLabel.text = "ИИ Ассистент"
        self.titleLabel.font = .systemFont(ofSize: 14.5, weight: .semibold)
        self.headerView.addSubview(self.titleLabel)

        self.subtitleLabel.font = .systemFont(ofSize: 11.0)
        self.headerView.addSubview(self.subtitleLabel)

        self.setupHeaderButton(self.petButton, systemName: "pawprint.fill", action: #selector(self.petTapped))
        self.setupHeaderButton(self.resizeButton, systemName: "arrow.down.right.and.arrow.up.left", action: #selector(self.resizeTapped))
        self.setupHeaderButton(self.minimizeButton, systemName: "minus", action: #selector(self.minimizeTapped))
        self.setupHeaderButton(self.closeButton, systemName: "xmark", action: #selector(self.closeTapped))

        let drag = UIPanGestureRecognizer(target: self, action: #selector(self.handleHeaderDrag(_:)))
        self.headerView.addGestureRecognizer(drag)

        self.addSubview(self.headerSeparator)
        self.addSubview(self.bodyContainer)

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .interactive
        self.bodyContainer.addSubview(self.scrollView)

        self.emptyHintLabel.numberOfLines = 0
        self.emptyHintLabel.textAlignment = .center
        self.emptyHintLabel.font = .systemFont(ofSize: 13.0)
        self.emptyHintLabel.text = "Спросите про текущий чат, статистику сообщений по дате, подготовьте ответ или управляйте диалогами.\n\nМожно также писать прямо в чате:\n.ai сколько сообщений было 15.05.2026"
        self.scrollView.addSubview(self.emptyHintLabel)

        self.chipsScroll.showsHorizontalScrollIndicator = false
        self.bodyContainer.addSubview(self.chipsScroll)
        self.buildQuickChips()

        self.bodyContainer.addSubview(self.footerSeparator)

        self.inputField.placeholder = "Задать вопрос или команду…"
        self.inputField.font = .systemFont(ofSize: 14.0)
        self.inputField.layer.cornerRadius = 16.0
        self.inputField.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 12.0, height: 34.0))
        self.inputField.leftViewMode = .always
        self.inputField.rightView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 10.0, height: 34.0))
        self.inputField.rightViewMode = .always
        self.inputField.returnKeyType = .send
        self.inputField.delegate = self
        self.bodyContainer.addSubview(self.inputField)

        self.clearButton.setImage(UIImage(systemName: "trash"), for: .normal)
        self.clearButton.addTarget(self, action: #selector(self.clearTapped), for: .touchUpInside)
        self.bodyContainer.addSubview(self.clearButton)

        self.sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        self.sendButton.addTarget(self, action: #selector(self.sendTapped), for: .touchUpInside)
        self.bodyContainer.addSubview(self.sendButton)

        self.activityIndicator.hidesWhenStopped = true
        self.bodyContainer.addSubview(self.activityIndicator)

        self.applyTheme(theme)
    }

    required init?(coder: NSCoder) { return nil }

    private func setupHeaderButton(_ btn: UIButton, systemName: String, action: Selector) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
        btn.setImage(UIImage(systemName: systemName, withConfiguration: cfg), for: .normal)
        btn.addTarget(self, action: action, for: .touchUpInside)
        self.headerView.addSubview(btn)
    }

    private func buildQuickChips() {
        self.chipsScroll.subviews.forEach { $0.removeFromSuperview() }
        let prompts = [
            "Сводка чата",
            "Сколько сообщений сегодня?",
            "Черновик ответа",
            "Покажи последние чаты"
        ]
        var x: CGFloat = 10.0
        for p in prompts {
            var cfg = UIButton.Configuration.filled()
            var titleAttr = AttributedString(p)
            titleAttr.font = .systemFont(ofSize: 12.0, weight: .medium)
            cfg.attributedTitle = titleAttr
            cfg.cornerStyle = .capsule
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 5.0, leading: 10.0, bottom: 5.0, trailing: 10.0)
            let btn = UIButton(configuration: cfg)
            btn.accessibilityLabel = p
            btn.addTarget(self, action: #selector(self.chipTapped(_:)), for: .touchUpInside)
            btn.sizeToFit()
            btn.frame = CGRect(x: x, y: 2.0, width: btn.bounds.width, height: 28.0)
            self.chipsScroll.addSubview(btn)
            x += btn.bounds.width + 6.0
        }
        self.chipsScroll.contentSize = CGSize(width: x + 6.0, height: 32.0)
    }

    func applyTheme(_ theme: PresentationTheme) {
        self.theme = theme
        let accent = theme.chat.inputPanel.actionControlFillColor
        let bgColor = theme.list.itemBlocksBackgroundColor
        let secondaryBg = theme.list.blocksBackgroundColor

        self.backgroundColor = bgColor
        self.headerView.backgroundColor = secondaryBg
        self.layer.borderColor = theme.list.itemPlainSeparatorColor.cgColor

        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.subtitleLabel.textColor = theme.list.itemSecondaryTextColor
        self.headerSeparator.backgroundColor = theme.list.itemPlainSeparatorColor
        self.footerSeparator.backgroundColor = theme.list.itemPlainSeparatorColor
        self.emptyHintLabel.textColor = theme.list.itemSecondaryTextColor

        self.resizeButton.tintColor = theme.list.itemPrimaryTextColor
        self.minimizeButton.tintColor = theme.list.itemPrimaryTextColor
        self.closeButton.tintColor = theme.list.itemSecondaryTextColor
        self.petButton.tintColor = FullGramAIStore.shared.showFloatingPet ? accent : theme.list.itemSecondaryTextColor

        self.inputField.backgroundColor = secondaryBg
        self.inputField.textColor = theme.list.itemPrimaryTextColor
        self.inputField.attributedPlaceholder = NSAttributedString(
            string: "Задать вопрос или команду…",
            attributes: [.foregroundColor: theme.list.itemSecondaryTextColor]
        )
        self.clearButton.tintColor = theme.list.itemSecondaryTextColor
        self.sendButton.tintColor = accent
        self.activityIndicator.color = accent

        for case let btn as UIButton in self.chipsScroll.subviews {
            var cfg = btn.configuration
            cfg?.baseBackgroundColor = accent.withAlphaComponent(0.14)
            cfg?.baseForegroundColor = accent
            btn.configuration = cfg
        }
        self.reloadConversation()
    }

    func setSubtitle(_ text: String) {
        self.subtitleLabel.text = text
    }

    func setLoading(_ loading: Bool) {
        self.isLoading = loading
        self.sendButton.isHidden = loading
        if loading {
            self.activityIndicator.startAnimating()
        } else {
            self.activityIndicator.stopAnimating()
        }
    }

    func setMode(_ newMode: WindowMode, in hostBounds: CGRect, safeInsets: UIEdgeInsets, animated: Bool = true) {
        self.mode = newMode
        self.customOrigin = nil
        let cfg = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
        switch newMode {
        case .standard:
            self.resizeButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left", withConfiguration: cfg), for: .normal)
            self.minimizeButton.setImage(UIImage(systemName: "minus", withConfiguration: cfg), for: .normal)
        case .compact:
            self.resizeButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: cfg), for: .normal)
            self.minimizeButton.setImage(UIImage(systemName: "minus", withConfiguration: cfg), for: .normal)
        case .minimized:
            self.minimizeButton.setImage(UIImage(systemName: "chevron.up", withConfiguration: cfg), for: .normal)
            self.endEditing(true)
        }
        let applyBlock = {
            self.layoutInHost(bounds: hostBounds, safeInsets: safeInsets)
        }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0.0, usingSpringWithDamping: 0.84, initialSpringVelocity: 0.4, animations: applyBlock)
        } else {
            applyBlock()
        }
    }

    func updateKeyboardHeight(_ height: CGFloat, in hostBounds: CGRect, safeInsets: UIEdgeInsets) {
        self.keyboardHeight = max(0.0, height)
        UIView.animate(withDuration: 0.24) {
            self.layoutInHost(bounds: hostBounds, safeInsets: safeInsets)
        }
    }

    func layoutInHost(bounds: CGRect, safeInsets: UIEdgeInsets) {
        let usableW = max(280.0, bounds.width - safeInsets.left - safeInsets.right - 24.0)
        let targetSize: CGSize
        switch self.mode {
        case .standard:
            targetSize = CGSize(width: min(440.0, usableW), height: min(470.0, max(280.0, bounds.height * 0.56)))
        case .compact:
            targetSize = CGSize(width: min(320.0, usableW), height: 265.0)
        case .minimized:
            targetSize = CGSize(width: min(295.0, usableW), height: 48.0)
        }

        let bottomReserve = max(safeInsets.bottom + 14.0, self.keyboardHeight + 10.0)
        let maxY = max(safeInsets.top + 52.0, bounds.height - bottomReserve - targetSize.height)
        let defaultOrigin: CGPoint
        if self.mode == .minimized {
            defaultOrigin = CGPoint(x: bounds.width - safeInsets.right - targetSize.width - 12.0, y: safeInsets.top + 56.0)
        } else {
            defaultOrigin = CGPoint(x: floor((bounds.width - targetSize.width) * 0.5), y: maxY)
        }

        let chosen = self.customOrigin ?? defaultOrigin
        let clampedX = min(bounds.width - safeInsets.right - targetSize.width - 8.0, max(safeInsets.left + 8.0, chosen.x))
        let clampedY = min(maxY, max(safeInsets.top + 48.0, chosen.y))
        self.frame = CGRect(x: clampedX, y: clampedY, width: targetSize.width, height: targetSize.height)

        let headerH: CGFloat = 48.0
        self.headerView.frame = CGRect(x: 0.0, y: 0.0, width: targetSize.width, height: headerH)
        self.headerView.layer.maskedCorners = self.mode == .minimized
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        self.avatarView.frame = CGRect(x: 10.0, y: 9.0, width: 30.0, height: 30.0)

        let btnSize: CGFloat = 28.0
        self.closeButton.frame = CGRect(x: targetSize.width - 36.0, y: 10.0, width: btnSize, height: btnSize)
        self.minimizeButton.frame = CGRect(x: self.closeButton.frame.minX - 30.0, y: 10.0, width: btnSize, height: btnSize)
        if self.mode == .minimized {
            self.resizeButton.isHidden = true
            self.petButton.isHidden = true
            let textRight = self.minimizeButton.frame.minX - 6.0
            self.titleLabel.frame = CGRect(x: 48.0, y: 8.0, width: max(60.0, textRight - 48.0), height: 17.0)
            self.subtitleLabel.frame = CGRect(x: 48.0, y: 25.0, width: max(60.0, textRight - 48.0), height: 14.0)
            self.headerSeparator.isHidden = true
            self.bodyContainer.isHidden = true
        } else {
            self.resizeButton.isHidden = false
            self.petButton.isHidden = false
            self.resizeButton.frame = CGRect(x: self.minimizeButton.frame.minX - 30.0, y: 10.0, width: btnSize, height: btnSize)
            self.petButton.frame = CGRect(x: self.resizeButton.frame.minX - 30.0, y: 10.0, width: btnSize, height: btnSize)
            let textRight = self.petButton.frame.minX - 6.0
            self.titleLabel.frame = CGRect(x: 48.0, y: 8.0, width: max(60.0, textRight - 48.0), height: 17.0)
            self.subtitleLabel.frame = CGRect(x: 48.0, y: 25.0, width: max(60.0, textRight - 48.0), height: 14.0)
            self.headerSeparator.isHidden = false
            self.bodyContainer.isHidden = false
            self.headerSeparator.frame = CGRect(x: 0.0, y: headerH, width: targetSize.width, height: 0.5)
            self.bodyContainer.frame = CGRect(x: 0.0, y: headerH + 0.5, width: targetSize.width, height: max(0.0, targetSize.height - headerH - 0.5))

            let bodyW = self.bodyContainer.bounds.width
            let bodyH = self.bodyContainer.bounds.height
            let footerH: CGFloat = 46.0
            let chipsH: CGFloat = self.mode == .compact ? 0.0 : 34.0
            self.chipsScroll.isHidden = self.mode == .compact

            self.scrollView.frame = CGRect(x: 0.0, y: 0.0, width: bodyW, height: max(40.0, bodyH - footerH - chipsH))
            if !self.chipsScroll.isHidden {
                self.chipsScroll.frame = CGRect(x: 0.0, y: self.scrollView.frame.maxY, width: bodyW, height: chipsH)
            }
            self.footerSeparator.frame = CGRect(x: 0.0, y: bodyH - footerH, width: bodyW, height: 0.5)
            self.clearButton.frame = CGRect(x: 6.0, y: bodyH - 39.0, width: 32.0, height: 32.0)
            self.sendButton.frame = CGRect(x: bodyW - 38.0, y: bodyH - 39.0, width: 32.0, height: 32.0)
            self.activityIndicator.center = self.sendButton.center
            self.inputField.frame = CGRect(x: 42.0, y: bodyH - 39.0, width: max(80.0, bodyW - 86.0), height: 32.0)

            self.reloadConversation()
        }
    }

    func reloadConversation() {
        let msgs = FullGramAIStore.shared.messagesSnapshot()
        for view in self.scrollView.subviews where view !== self.emptyHintLabel {
            view.removeFromSuperview()
        }
        self.emptyHintLabel.isHidden = !msgs.isEmpty

        let width = max(200.0, self.scrollView.bounds.width - 20.0)
        if msgs.isEmpty {
            let hintFit = self.emptyHintLabel.sizeThatFits(CGSize(width: width - 16.0, height: .greatestFiniteMagnitude))
            self.emptyHintLabel.frame = CGRect(x: 18.0, y: 18.0, width: width - 16.0, height: ceil(hintFit.height))
            self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: self.emptyHintLabel.frame.maxY + 16.0)
            return
        }

        var y: CGFloat = 10.0
        for msg in msgs {
            let row = FullGramAIChatBubbleRow()
            row.onConfirmAction = { [weak self] id, action in
                self?.onConfirmAction?(id, action)
            }
            row.onInsertDraftInstead = { [weak self] id, action in
                self?.onInsertDraftInstead?(id, action)
            }
            let h = row.configure(message: msg, theme: self.theme, maxWidth: width)
            row.frame = CGRect(x: 10.0, y: y, width: width, height: h)
            self.scrollView.addSubview(row)
            y += h + 8.0
        }
        self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: y + 8.0)
        let offsetY = max(0.0, self.scrollView.contentSize.height - self.scrollView.bounds.height)
        if self.scrollView.bounds.height > 20.0 {
            self.scrollView.setContentOffset(CGPoint(x: 0.0, y: offsetY), animated: true)
        }
    }

    @objc private func handleHeaderDrag(_ gr: UIPanGestureRecognizer) {
        guard let host = self.superview else { return }
        switch gr.state {
        case .began:
            self.panStartOrigin = self.frame.origin
        case .changed:
            let trans = gr.translation(in: host)
            self.customOrigin = CGPoint(x: self.panStartOrigin.x + trans.x, y: self.panStartOrigin.y + trans.y)
            self.layoutInHost(bounds: host.bounds, safeInsets: host.safeAreaInsets)
        default:
            break
        }
    }

    @objc private func petTapped() {
        self.onTogglePet?()
        self.petButton.tintColor = FullGramAIStore.shared.showFloatingPet
            ? self.theme.chat.inputPanel.actionControlFillColor
            : self.theme.list.itemSecondaryTextColor
    }

    @objc private func resizeTapped() {
        guard let host = self.superview else { return }
        let next: WindowMode = self.mode == .compact ? .standard : .compact
        self.setMode(next, in: host.bounds, safeInsets: host.safeAreaInsets)
    }

    @objc private func minimizeTapped() {
        guard let host = self.superview else { return }
        let next: WindowMode = self.mode == .minimized ? .standard : .minimized
        self.setMode(next, in: host.bounds, safeInsets: host.safeAreaInsets)
    }

    @objc private func closeTapped() {
        self.endEditing(true)
        self.onClose?()
    }

    @objc private func clearTapped() {
        FullGramAIStore.shared.clearConversation()
        self.reloadConversation()
    }

    @objc private func chipTapped(_ sender: UIButton) {
        if let title = sender.accessibilityLabel, !title.isEmpty {
            self.onSendPrompt?(title)
        }
    }

    @objc private func sendTapped() {
        let txt = (self.inputField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !txt.isEmpty, !self.isLoading else { return }
        self.inputField.text = ""
        self.onSendPrompt?(txt)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.sendTapped()
        return true
    }
}

// MARK: - Root Application Coordinator

final class FullGramAIOverlayCoordinator {
    private let context: AccountContext
    private weak var rootController: TelegramRootController?
    private var theme: PresentationTheme

    private var petView: FullGramMascotPetView?
    private var windowView: FullGramAIChatWindowView?
    private var currentPeerId: PeerId?
    private var observers: [NSObjectProtocol] = []
    private var autoResponderDisposable: Disposable?
    private var seenAutoReplyMessageIds = Set<MessageId>()

    init(context: AccountContext, rootController: TelegramRootController) {
        self.context = context
        self.rootController = rootController
        self.theme = context.sharedContext.currentPresentationData.with { $0 }.theme

        self.observeNotifications()
        self.startAutoResponderMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.syncPetVisibility()
        }
    }

    deinit {
        self.autoResponderDisposable?.dispose()
        for obs in self.observers {
            NotificationCenter.default.removeObserver(obs)
        }
        self.petView?.removeFromSuperview()
        self.windowView?.removeFromSuperview()
    }

    private func startAutoResponderMonitor() {
        let signal = self.context.account.viewTracker.tailChatListView(
            groupId: .root,
            filterPredicate: nil,
            count: 14,
            shouldLoadCanMessagePeer: false
        )
        |> deliverOnMainQueue

        let selfPeerId = self.context.account.peerId
        self.autoResponderDisposable = signal.start(next: { [weak self] view, _ in
            guard let self else { return }
            let settings = FullGramAutoResponderSettings.shared
            guard settings.isEnabled else { return }
            let minTimestamp = settings.enabledSinceTimestamp

            for entry in view.entries {
                guard case let .MessageEntry(data) = entry else { continue }
                guard let unreadCount = data.readState?.state.count, unreadCount > 0 else { continue }
                guard let lastMsg = data.messages.last else { continue }
                guard lastMsg.flags.contains(.Incoming) else { continue }
                guard lastMsg.timestamp >= minTimestamp else { continue }

                let peerId = lastMsg.id.peerId
                guard peerId != selfPeerId, peerId.id._internalGetInt64Value() != 777000 else { continue }

                if peerId.namespace == Namespaces.Peer.CloudUser {
                    guard let user = data.renderedPeer.chatMainPeer as? TelegramUser,
                          !user.isDeleted,
                          user.botInfo == nil,
                          !user.flags.contains(.isSupport) else {
                        continue
                    }
                } else {
                    guard settings.replyInGroupsOnMention, lastMsg.tags.contains(.unseenPersonalMessage) else {
                        continue
                    }
                }

                guard self.seenAutoReplyMessageIds.insert(lastMsg.id).inserted else { continue }
                let peerRaw = peerId.toInt64()
                guard settings.canReply(to: peerRaw) else { continue }
                settings.markReplied(to: peerRaw)

                self.dispatchAutoReply(to: peerId, incomingText: lastMsg.text, mode: settings.mode, fallbackText: settings.effectiveReplyText)
            }
        })
    }

    private func dispatchAutoReply(to peerId: PeerId, incomingText: String, mode: FullGramAutoResponderSettings.Mode, fallbackText: String) {
        let sendNow: (String) -> Void = { [weak self] replyText in
            guard let self, !replyText.isEmpty else { return }
            let _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [
                EnqueueMessage.message(
                    text: replyText,
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
            ]).startStandalone()
        }

        guard mode == .aiSmart else {
            sendNow(fallbackText)
            return
        }

        guard let url = URL(string: "https://text.pollinations.ai/openai") else {
            sendNow(fallbackText)
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 3.5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let cleanIncoming = incomingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "model": "openai",
            "temperature": 0.4,
            "messages": [
                [
                    "role": "system",
                    "content": "Ты — вежливый автоответчик в Telegram. Владелец аккаунта сейчас не у телефона. Напиши короткий (1 предложение) дружелюбный автоответ с префиксом «✨ [Авто-ответ FullGram]: », учитывая тему входящего сообщения."
                ],
                [
                    "role": "user",
                    "content": cleanIncoming.isEmpty ? "Привет!" : String(cleanIncoming.prefix(350))
                ]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let finalReply = trimmed.hasPrefix("✨") || trimmed.hasPrefix("🤖") ? trimmed : "✨ [Авто-ответ FullGram]: \(trimmed)"
                    DispatchQueue.main.async { sendNow(finalReply) }
                    return
                }
            }
            DispatchQueue.main.async { sendNow(fallbackText) }
        }.resume()
    }

    func updateTheme(_ theme: PresentationTheme) {
        self.theme = theme
        self.windowView?.applyTheme(theme)
        self.petView?.updateBusy(false, accentColor: theme.chat.inputPanel.actionControlFillColor)
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        self.observers.append(nc.addObserver(forName: FullGramAINotifications.openWindow, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let prompt = note.userInfo?["prompt"] as? String
            let peerRaw = note.userInfo?["peerId"] as? Int64
            let autoSend = (note.userInfo?["autoSend"] as? Bool) ?? false
            self.openWindow(initialPrompt: prompt, explicitPeerId: peerRaw.map { PeerId($0) }, autoSend: autoSend)
        })

        self.observers.append(nc.addObserver(forName: FullGramAINotifications.minimizeWindow, object: nil, queue: .main) { [weak self] _ in
            guard let self, let win = self.windowView, let host = self.hostContainerView() else { return }
            win.setMode(.minimized, in: host.bounds, safeInsets: host.safeAreaInsets)
        })

        self.observers.append(nc.addObserver(forName: FullGramAINotifications.petVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
            self?.syncPetVisibility()
        })

        self.observers.append(nc.addObserver(forName: FullGramAINotifications.conversationChanged, object: nil, queue: .main) { [weak self] _ in
            self?.windowView?.reloadConversation()
        })

        self.observers.append(nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let win = self.windowView, !win.isHidden,
                  let host = self.hostContainerView(),
                  let kbFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let converted = host.convert(kbFrame, from: nil)
            let overlap = max(0.0, host.bounds.maxY - converted.minY)
            win.updateKeyboardHeight(overlap, in: host.bounds, safeInsets: host.safeAreaInsets)
        })

        self.observers.append(nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let win = self.windowView, !win.isHidden, let host = self.hostContainerView() else { return }
            win.updateKeyboardHeight(0.0, in: host.bounds, safeInsets: host.safeAreaInsets)
        })

        self.observers.append(nc.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let host = self.hostContainerView() else { return }
            self.petView?.restorePosition(in: host.bounds, safeInsets: host.safeAreaInsets)
            if let win = self.windowView, !win.isHidden {
                win.layoutInHost(bounds: host.bounds, safeInsets: host.safeAreaInsets)
            }
        })

        self.observers.append(nc.addObserver(forName: FullGramPluginNotifications.runCommandInChatRequested, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let peerRaw = note.userInfo?["peerId"] as? Int64
            let targetPeerId = peerRaw.map { PeerId($0) } ?? self.activeChatController()?.chatLocation.peerId
            let chatTitle = (note.userInfo?["title"] as? String) ?? "Чат"
            let showPicker = (note.userInfo?["showPicker"] as? Bool) ?? false
            let command = note.userInfo?["command"] as? String
            if showPicker {
                self.presentPluginActionsPicker(peerId: targetPeerId, chatTitle: chatTitle)
            } else if let command, !command.isEmpty {
                self.executePluginCommand(command, peerId: targetPeerId, chatTitle: chatTitle)
            }
        })

        self.observers.append(nc.addObserver(forName: FullGramPluginNotifications.openUIRequested, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            let info = (note.userInfo as? [String: Any]) ?? [:]
            self.presentPluginGUI(spec: info)
        })
    }

    private func presentPluginGUI(spec: [String: Any]) {
        guard let root = self.rootController else { return }
        let kind = (spec["kind"] as? String)?.lowercased() ?? (spec["pluginId"] as? String)?.lowercased() ?? ""
        let initialTab = (spec["tab"] as? String)?.lowercased()
        let targetPeerId = self.activeChatController()?.chatLocation.peerId ?? self.currentPeerId

        let sendToChat: (String) -> Void = { [weak self] text in
            guard let self, !text.isEmpty else { return }
            if let peerId = targetPeerId ?? self.activeChatController()?.chatLocation.peerId {
                let _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [
                    EnqueueMessage.message(
                        text: text,
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
                ]).startStandalone()
            } else {
                UIPasteboard.general.string = text
            }
        }

        let vc: UIViewController
        if kind.contains("casino") || kind.contains("slots") || kind.contains("roulette") {
            vc = FullGramCasinoGUIViewController(initialTab: initialTab, onSendToChat: sendToChat)
        } else if kind.contains("deadline") || kind.contains("dl") {
            vc = FullGramDeadlinesGUIViewController(onSendToChat: sendToChat)
        } else {
            vc = FullGramCustomPluginGUIViewController(spec: spec, onSendToChat: sendToChat)
        }

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let top = root.presentedViewController {
            top.present(nav, animated: true)
        } else {
            root.present(nav, animated: true)
        }
    }

    private func presentPluginActionsPicker(peerId: PeerId?, chatTitle: String) {
        guard let root = self.rootController else { return }
        let sheet = UIAlertController(title: "Плагины и ИИ FullGram", message: chatTitle, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "✨ Сводка чата (ИИ)", style: .default) { [weak self] _ in
            self?.openWindow(
                initialPrompt: "Сделай подробную краткую сводку этого чата по последним сообщениям",
                explicitPeerId: peerId,
                autoSend: true
            )
        })
        sheet.addAction(UIAlertAction(title: "🎰 Открыть Казино (Графический UI)", style: .default) { [weak self] _ in
            self?.presentPluginGUI(spec: ["kind": "casino", "pluginId": "fg_casino"])
        })
        sheet.addAction(UIAlertAction(title: "⏰ Открыть Дедлайны (Графический UI)", style: .default) { [weak self] _ in
            self?.presentPluginGUI(spec: ["kind": "deadlines", "pluginId": "fg_deadlines"])
        })
        if FullGramPluginManager.shared.isSystemEnabled {
            let commands = FullGramPluginManager.shared.availableCommands()
            for item in commands {
                let title = ".\(item.command) — \(item.pluginName)"
                sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                    self?.executePluginCommand(".\(item.command)", peerId: peerId, chatTitle: chatTitle)
                })
            }
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1.0, height: 1.0)
        }
        root.present(sheet, animated: true)
    }

    private func executePluginCommand(_ rawCommand: String, peerId: PeerId?, chatTitle: String) {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let commandText = trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
        let lower = commandText.lowercased()
        let needsStats = lower.hasPrefix(".plug") || lower.hasPrefix(".info-chat")

        let statsSignal: Signal<[String: FullGramPluginValue]?, NoError>
        if needsStats, let peerId {
            statsSignal = fullGramBuildChatStatsSignal(context: self.context, peerId: peerId, chatTitle: chatTitle)
        } else {
            statsSignal = .single(nil)
        }

        let targetPeerRaw = peerId?.toInt64() ?? 0
        let _ = (statsSignal
        |> deliverOnMainQueue).startStandalone(next: { [weak self] chatStats in
            Queue.concurrentDefaultQueue().async {
                let decision = FullGramPluginManager.shared.processOutgoingMessage(
                    text: commandText,
                    peerId: targetPeerRaw,
                    isGroup: false,
                    isChannel: peerId?.namespace == Namespaces.Peer.CloudChannel,
                    chatStats: chatStats
                )
                DispatchQueue.main.async {
                    guard let self, let root = self.rootController else { return }
                    let resultText: String
                    switch decision {
                    case let .replaceText(text):
                        resultText = text
                    case let .cancel(toast):
                        guard let toast, !toast.isEmpty else { return }
                        resultText = toast
                    case .pass:
                        resultText = "Плагин не вернул результат (возможно, команда требует аргументов, например: \(commandText) текст)."
                    }
                    let alert = UIAlertController(title: commandText, message: resultText, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Скопировать", style: .default) { _ in
                        UIPasteboard.general.string = resultText
                    })
                    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                    root.present(alert, animated: true)
                }
            }
        })
    }

    private func hostContainerView() -> UIView? {
        return self.rootController?.view
    }

    private func activeChatController() -> ChatControllerImpl? {
        guard let root = self.rootController else { return nil }
        if let top = root.topViewController as? ChatControllerImpl {
            return top
        }
        for vc in root.viewControllers.reversed() {
            if let chat = vc as? ChatControllerImpl {
                return chat
            }
        }
        return nil
    }

    func syncPetVisibility() {
        guard let host = self.hostContainerView() else { return }
        if FullGramAIStore.shared.showFloatingPet {
            let pet: FullGramMascotPetView
            if let existing = self.petView {
                pet = existing
            } else {
                let created = FullGramMascotPetView(frame: .zero)
                created.onTap = { [weak self] in
                    self?.openWindow(initialPrompt: nil, explicitPeerId: nil, autoSend: false)
                }
                created.onLongPress = { [weak self] in
                    self?.presentPetQuickMenu()
                }
                host.addSubview(created)
                created.restorePosition(in: host.bounds, safeInsets: host.safeAreaInsets)
                self.petView = created
                pet = created
            }
            pet.isHidden = false
            pet.updateBusy(false, accentColor: self.theme.chat.inputPanel.actionControlFillColor)
            host.bringSubviewToFront(pet)
            if let win = self.windowView, !win.isHidden {
                host.bringSubviewToFront(win)
            }
        } else {
            self.petView?.removeFromSuperview()
            self.petView = nil
        }
    }

    private func presentPetQuickMenu() {
        let controller = UIAlertController(title: "Питомец ИИ FullGram", message: nil, preferredStyle: .actionSheet)
        controller.addAction(UIAlertAction(title: "Открыть ИИ-чат", style: .default, handler: { [weak self] _ in
            self?.openWindow(initialPrompt: nil, explicitPeerId: nil, autoSend: false)
        }))
        controller.addAction(UIAlertAction(title: "Скрыть питомца с экрана", style: .destructive, handler: { _ in
            FullGramAIStore.shared.showFloatingPet = false
        }))
        controller.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.rootController?.present(controller, animated: true)
    }

    private func openWindow(initialPrompt: String?, explicitPeerId: PeerId?, autoSend: Bool) {
        guard let host = self.hostContainerView() else { return }
        self.currentPeerId = explicitPeerId ?? self.activeChatController()?.chatLocation.peerId

        let win: FullGramAIChatWindowView
        if let existing = self.windowView {
            win = existing
        } else {
            let created = FullGramAIChatWindowView(theme: self.theme)
            created.onSendPrompt = { [weak self] prompt in
                self?.submitPrompt(prompt)
            }
            created.onConfirmAction = { [weak self] messageId, action in
                self?.executeAction(messageId: messageId, action: action, forceDraft: false)
            }
            created.onInsertDraftInstead = { [weak self] messageId, action in
                self?.executeAction(messageId: messageId, action: action, forceDraft: true)
            }
            created.onTogglePet = { [weak self] in
                FullGramAIStore.shared.showFloatingPet.toggle()
                self?.syncPetVisibility()
            }
            created.onClose = { [weak self] in
                self?.windowView?.isHidden = true
            }
            host.addSubview(created)
            self.windowView = created
            win = created
        }

        win.applyTheme(self.theme)
        let modelLabel = "\(FullGramAIStore.shared.provider.title) • \(FullGramAIStore.shared.effectiveModel)"
        win.setSubtitle(self.currentPeerId != nil ? "Чат + \(modelLabel)" : modelLabel)
        win.isHidden = false
        win.setMode(.standard, in: host.bounds, safeInsets: host.safeAreaInsets)
        host.bringSubviewToFront(win)

        if let initialPrompt, !initialPrompt.isEmpty, autoSend {
            self.submitPrompt(initialPrompt)
        }
    }

    private func submitPrompt(_ prompt: String) {
        let store = FullGramAIStore.shared
        store.appendMessage(FullGramAIChatMessage(isUser: true, text: prompt))
        self.windowView?.setLoading(true)
        self.petView?.updateBusy(true, accentColor: self.theme.chat.inputPanel.actionControlFillColor)

        let peerId = self.currentPeerId ?? self.activeChatController()?.chatLocation.peerId
        FullGramAITelegramContextBuilder.gatherContext(prompt: prompt, targetPeerId: peerId, context: self.context) { [weak self] contextBlock in
            guard let self else { return }
            store.sendPrompt(userPrompt: prompt, contextBlock: contextBlock) { [weak self] result in
                guard let self else { return }
                self.windowView?.setLoading(false)
                self.petView?.updateBusy(false, accentColor: self.theme.chat.inputPanel.actionControlFillColor)
                switch result {
                case let .success(parsed):
                    store.appendMessage(FullGramAIChatMessage(
                        isUser: false,
                        text: parsed.text,
                        action: parsed.action
                    ))
                case let .failure(error):
                    store.appendMessage(FullGramAIChatMessage(
                        isUser: false,
                        text: "⚠️ \(error.localizedDescription)"
                    ))
                }
            }
        }
    }

    private func executeAction(messageId: String, action: FullGramAIProposedAction, forceDraft: Bool) {
        let store = FullGramAIStore.shared
        let effectiveKind: FullGramAIProposedAction.Kind = forceDraft ? .insertDraft : action.kind
        let targetPeer = action.peerId.map { PeerId($0) } ?? self.currentPeerId ?? self.activeChatController()?.chatLocation.peerId

        switch effectiveKind {
        case .insertDraft:
            guard store.allowDraftInsert, let text = action.text, !text.isEmpty else { return }
            if let chat = self.activeChatController() {
                chat.updateChatPresentationInterfaceState(animated: true, interactive: true, {
                    $0.updatedInterfaceState {
                        $0.withUpdatedComposeInputState(ChatTextInputState(inputText: NSAttributedString(string: text), selectionRange: text.utf16.count ..< text.utf16.count))
                    }
                })
                store.updateActionStatus(messageId: messageId, status: .applied)
                if let host = self.hostContainerView() {
                    self.windowView?.setMode(.minimized, in: host.bounds, safeInsets: host.safeAreaInsets)
                }
            }

        case .sendMessage:
            guard let peerId = targetPeer, let text = action.text, !text.isEmpty else { return }
            let alert = UIAlertController(
                title: "Подтвердите отправку",
                message: "ИИ просит отправить сообщение:\n\n«\(text)»",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Отправить", style: .default, handler: { [weak self] _ in
                guard let self else { return }
                let _ = enqueueMessages(account: self.context.account, peerId: peerId, messages: [
                    EnqueueMessage.message(
                        text: text,
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
                ]).startStandalone()
                store.updateActionStatus(messageId: messageId, status: .applied)
            }))
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { _ in
                store.updateActionStatus(messageId: messageId, status: .cancelled)
            }))
            self.rootController?.present(alert, animated: true)

        case .openChat:
            guard let peerId = targetPeer, let nav = self.rootController else { return }
            let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).start(next: { [weak self] peer in
                guard let self, let peer else { return }
                self.context.sharedContext.navigateToChatController(
                    NavigateToChatControllerParams(
                        navigationController: nav,
                        context: self.context,
                        chatLocation: .peer(peer)
                    )
                )
                store.updateActionStatus(messageId: messageId, status: .applied)
                if let host = self.hostContainerView() {
                    self.windowView?.setMode(.minimized, in: host.bounds, safeInsets: host.safeAreaInsets)
                }
            })

        case .toggleSetting:
            guard let key = action.settingKey, let value = action.settingValue else { return }
            switch key {
            case "ghost_mode":
                try? self.context.account.network.fullGramGhostMode.update { settings in
                    settings.setAllEnabled(value)
                }
            case "download_boost":
                FullGramExtras.shared.downloadBoost = value
            case "floating_pet":
                FullGramAIStore.shared.showFloatingPet = value
            case "quick_formatting":
                FullGramExtras.shared.quickFormattingBar = value
            default:
                return
            }
            store.updateActionStatus(messageId: messageId, status: .applied)
        }
    }
}

// MARK: - Chat Statistics Builder for .plug info-chat

func fullGramBuildChatStatsSignal(
    context: AccountContext,
    peerId: PeerId,
    chatTitle: String
) -> Signal<[String: FullGramPluginValue]?, NoError> {
    let firstSignal = context.account.postbox.aroundMessageHistoryViewForLocation(
        .peer(peerId: peerId, threadId: nil),
        anchor: .lowerBound,
        ignoreMessagesInTimestampRange: nil,
        ignoreMessageIds: Set(),
        count: 5,
        fixedCombinedReadStates: nil,
        topTaggedMessageIdNamespaces: [Namespaces.Message.Cloud],
        tag: nil,
        appendMessagesFromTheSameGroup: false,
        namespaces: .not(Namespaces.Message.allNonRegular),
        orderStatistics: []
    )
    |> take(1)

    let recentSignal = context.account.postbox.aroundMessageHistoryViewForLocation(
        .peer(peerId: peerId, threadId: nil),
        anchor: .upperBound,
        ignoreMessagesInTimestampRange: nil,
        ignoreMessageIds: Set(),
        count: 600,
        fixedCombinedReadStates: nil,
        topTaggedMessageIdNamespaces: [Namespaces.Message.Cloud],
        tag: nil,
        appendMessagesFromTheSameGroup: false,
        namespaces: .not(Namespaces.Message.allNonRegular),
        orderStatistics: []
    )
    |> take(1)

    return combineLatest(firstSignal, recentSignal)
    |> map { firstTuple, recentTuple -> [String: FullGramPluginValue]? in
        let earliestMessages = firstTuple.0.entries.map { $0.message }
        let recentMessages = recentTuple.0.entries.map { $0.message }
        var seenIds = Set<MessageId>()
        var allMessages: [Message] = []
        for msg in earliestMessages + recentMessages {
            if seenIds.insert(msg.id).inserted {
                allMessages.append(msg)
            }
        }
        guard !allMessages.isEmpty else {
            return nil
        }

        let sortedByTime = allMessages.sorted { $0.timestamp < $1.timestamp }
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy HH:mm"
        let firstDate = df.string(from: Date(timeIntervalSince1970: TimeInterval(sortedByTime.first?.timestamp ?? 0)))
        let lastDate = df.string(from: Date(timeIntervalSince1970: TimeInterval(sortedByTime.last?.timestamp ?? 0)))

        let stopwords: Set<String> = [
            "и", "в", "во", "не", "на", "я", "ты", "он", "она", "мы", "вы", "они",
            "с", "со", "к", "ко", "по", "за", "из", "у", "от", "до", "о", "об",
            "а", "но", "да", "нет", "то", "что", "это", "как", "так", "же", "ли",
            "бы", "ну", "уже", "еще", "ещё", "для", "при", "или", "вот", "тут",
            "там", "все", "всё", "мне", "меня", "тебя", "тебе", "его", "её", "их",
            "the", "and", "to", "of", "in", "is", "it", "you", "that", "for", "on", "with"
        ]

        var freq: [String: Int] = [:]
        var profanityCount = 0
        var voiceCount = 0
        var roundCount = 0

        for msg in recentMessages {
            for media in msg.media {
                if let file = media as? TelegramMediaFile {
                    if file.isVoice {
                        voiceCount += 1
                    } else if file.isInstantVideo {
                        roundCount += 1
                    }
                }
            }
            if !msg.text.isEmpty {
                let rawTokens = msg.text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                for raw in rawTokens where !raw.isEmpty {
                    let lower = raw.lowercased().replacingOccurrences(of: "ё", with: "е")
                    if FullGramSpeechBleep.isProfanity(lower) {
                        profanityCount += 1
                    }
                    guard lower.count >= 3, !lower.allSatisfy(\.isNumber), !stopwords.contains(lower) else {
                        continue
                    }
                    freq[lower, default: 0] += 1
                }
            }
        }

        let topSorted = freq.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }.prefix(5)

        let rareSorted = freq.filter { $0.key.count >= 4 }.sorted {
            if $0.value != $1.value { return $0.value < $1.value }
            if $0.key.count != $1.key.count { return $0.key.count > $1.key.count }
            return $0.key < $1.key
        }.prefix(5)

        let topValues: [FullGramPluginValue] = topSorted.map { item in
            .table(FullGramPluginTableBox(dict: [
                "word": .string(item.key),
                "count": .int(Int64(item.value))
            ]))
        }
        let rareValues: [FullGramPluginValue] = rareSorted.map { item in
            .table(FullGramPluginTableBox(dict: [
                "word": .string(item.key),
                "count": .int(Int64(item.value))
            ]))
        }

        return [
            "title": .string(chatTitle),
            "first_date": .string(firstDate),
            "last_date": .string(lastDate),
            "analyzed_count": .int(Int64(recentMessages.count)),
            "top_words": .table(FullGramPluginTableBox(array: topValues)),
            "rare_words": .table(FullGramPluginTableBox(array: rareValues)),
            "profanity_count": .int(Int64(profanityCount)),
            "voice_count": .int(Int64(voiceCount)),
            "round_count": .int(Int64(roundCount))
        ]
    }
}

// MARK: - Graphical UI Engine for Lua & Python Plugins (`fullgram.open_ui`)

private final class FullGramCasinoGUIViewController: UIViewController {
    private enum GameTab: Int {
        case slots = 0
        case roulette = 1
        case coin = 2
    }

    private let onSendToChat: (String) -> Void
    private var currentTab: GameTab = .slots
    private var bet: Int = 100
    private var rouletteChoice: String = "red"
    private var coinChoice: String = "eagle"
    private var isSpinning = false
    private var spinTimer: Foundation.Timer?
    private var lastShareSummary: String = ""

    private let balanceLabel = UILabel()
    private let recordLabel = UILabel()
    private let segmented = UISegmentedControl(items: ["🎰 Слоты 777", "🎡 Рулетка", "🪙 Монетка"])

    private let stageCard = UIView()
    private let slotsStack = UIStackView()
    private var reelLabels: [UILabel] = []

    private let rouletteContainer = UIView()
    private let rouletteBallLabel = UILabel()
    private let rouletteChoiceStack = UIStackView()
    private var rouletteButtons: [String: UIButton] = [:]

    private let coinContainer = UIView()
    private let coinEmojiLabel = UILabel()
    private let coinChoiceStack = UIStackView()
    private var coinButtons: [String: UIButton] = [:]

    private let statusBannerLabel = UILabel()
    private let betLabel = UILabel()
    private let spinButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    private static let balanceKey = "fullgram.plugin.store.fg_casino.balance"
    private static let bestKey = "fullgram.plugin.store.fg_casino.best_balance"
    private static let symbols = ["🍒", "🍋", "🔔", "💎", "7️⃣"]

    init(initialTab: String?, onSendToChat: @escaping (String) -> Void) {
        self.onSendToChat = onSendToChat
        if initialTab == "roulette" {
            self.currentTab = .roulette
        } else if initialTab == "coin" {
            self.currentTab = .coin
        }
        super.init(nibName: nil, bundle: nil)
        self.title = "🎰 Казино FullGram"
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        self.spinTimer?.invalidate()
    }

    private var balance: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.balanceKey) != nil else { return 1000 }
            return UserDefaults.standard.integer(forKey: Self.balanceKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.balanceKey)
            if newValue > self.bestBalance {
                self.bestBalance = newValue
            }
            self.refreshHeader()
        }
    }

    private var bestBalance: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Self.bestKey)
            return max(1000, v)
        }
        set {
            UserDefaults.standard.set(max(1000, newValue), forKey: Self.bestKey)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(rgb: 0x11131A)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .done, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "🎁 +1000", style: .plain, target: self, action: #selector(self.bonusTapped))

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 14.0),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24.0),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16.0)
        ])

        // 1. Balance Header Card
        let headerCard = UIView()
        headerCard.backgroundColor = UIColor(rgb: 0x1C1F2B)
        headerCard.layer.cornerRadius = 16.0
        headerCard.layer.borderWidth = 1.0
        headerCard.layer.borderColor = UIColor(rgb: 0xFFD60A).withAlphaComponent(0.35).cgColor

        self.balanceLabel.font = .monospacedDigitSystemFont(ofSize: 26.0, weight: .bold)
        self.balanceLabel.textColor = UIColor(rgb: 0xFFD60A)
        self.balanceLabel.textAlignment = .center

        self.recordLabel.font = .systemFont(ofSize: 13.0, weight: .medium)
        self.recordLabel.textColor = UIColor(white: 0.72, alpha: 1.0)
        self.recordLabel.textAlignment = .center

        let headerVStack = UIStackView(arrangedSubviews: [self.balanceLabel, self.recordLabel])
        headerVStack.axis = .vertical
        headerVStack.spacing = 4.0
        headerVStack.translatesAutoresizingMaskIntoConstraints = false
        headerCard.addSubview(headerVStack)
        NSLayoutConstraint.activate([
            headerVStack.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 14.0),
            headerVStack.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -14.0),
            headerVStack.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 12.0),
            headerVStack.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -12.0)
        ])
        stack.addArrangedSubview(headerCard)

        // 2. Game Mode Segmented Control
        self.segmented.selectedSegmentIndex = self.currentTab.rawValue
        self.segmented.selectedSegmentTintColor = UIColor(rgb: 0x5856D6)
        self.segmented.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 13.5, weight: .semibold)], for: .normal)
        self.segmented.addTarget(self, action: #selector(self.tabChanged), for: .valueChanged)
        stack.addArrangedSubview(self.segmented)

        // 3. Stage Card (Slots / Roulette / Coin)
        self.stageCard.backgroundColor = UIColor(rgb: 0x1A1D28)
        self.stageCard.layer.cornerRadius = 18.0
        self.stageCard.layer.borderWidth = 1.5
        self.stageCard.layer.borderColor = UIColor(rgb: 0x5856D6).withAlphaComponent(0.45).cgColor
        self.stageCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 185.0).isActive = true

        self.setupSlotsStage()
        self.setupRouletteStage()
        self.setupCoinStage()
        stack.addArrangedSubview(self.stageCard)

        // 4. Status Banner
        self.statusBannerLabel.font = .systemFont(ofSize: 15.0, weight: .semibold)
        self.statusBannerLabel.textColor = .white
        self.statusBannerLabel.textAlignment = .center
        self.statusBannerLabel.numberOfLines = 2
        self.statusBannerLabel.text = "Выберите ставку и нажмите «КРУТИТЬ»!"
        stack.addArrangedSubview(self.statusBannerLabel)

        // 5. Bet Controls Card
        let betCard = UIView()
        betCard.backgroundColor = UIColor(rgb: 0x1C1F2B)
        betCard.layer.cornerRadius = 14.0

        self.betLabel.font = .monospacedDigitSystemFont(ofSize: 17.0, weight: .bold)
        self.betLabel.textColor = .white
        self.betLabel.textAlignment = .center

        let betBtnsRow = UIStackView()
        betBtnsRow.axis = .horizontal
        betBtnsRow.distribution = .fillEqually
        betBtnsRow.spacing = 6.0
        let presets: [(String, Int)] = [("50", 50), ("100", 100), ("250", 250), ("1/2", -1), ("x2", -2), ("MAX", -3)]
        for (title, tagVal) in presets {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(.white, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13.0, weight: .bold)
            b.backgroundColor = UIColor(rgb: 0x2A2E3F)
            b.layer.cornerRadius = 8.0
            b.tag = tagVal
            b.heightAnchor.constraint(equalToConstant: 36.0).isActive = true
            b.addTarget(self, action: #selector(self.betPresetTapped(_:)), for: .touchUpInside)
            betBtnsRow.addArrangedSubview(b)
        }

        let betVStack = UIStackView(arrangedSubviews: [self.betLabel, betBtnsRow])
        betVStack.axis = .vertical
        betVStack.spacing = 10.0
        betVStack.translatesAutoresizingMaskIntoConstraints = false
        betCard.addSubview(betVStack)
        NSLayoutConstraint.activate([
            betVStack.topAnchor.constraint(equalTo: betCard.topAnchor, constant: 12.0),
            betVStack.bottomAnchor.constraint(equalTo: betCard.bottomAnchor, constant: -12.0),
            betVStack.leadingAnchor.constraint(equalTo: betCard.leadingAnchor, constant: 12.0),
            betVStack.trailingAnchor.constraint(equalTo: betCard.trailingAnchor, constant: -12.0)
        ])
        stack.addArrangedSubview(betCard)

        // 6. Spin & Share Buttons
        self.spinButton.setTitle("🎰 КРУТИТЬ", for: .normal)
        self.spinButton.setTitleColor(.black, for: .normal)
        self.spinButton.titleLabel?.font = .systemFont(ofSize: 18.0, weight: .heavy)
        self.spinButton.backgroundColor = UIColor(rgb: 0xFFD60A)
        self.spinButton.layer.cornerRadius = 14.0
        self.spinButton.heightAnchor.constraint(equalToConstant: 52.0).isActive = true
        self.spinButton.addTarget(self, action: #selector(self.spinTapped), for: .touchUpInside)
        stack.addArrangedSubview(self.spinButton)

        self.shareButton.setTitle("📤 Отправить результат в чат", for: .normal)
        self.shareButton.setTitleColor(.white, for: .normal)
        self.shareButton.titleLabel?.font = .systemFont(ofSize: 15.0, weight: .semibold)
        self.shareButton.backgroundColor = UIColor(rgb: 0x2C3042)
        self.shareButton.layer.cornerRadius = 12.0
        self.shareButton.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        self.shareButton.isHidden = true
        self.shareButton.addTarget(self, action: #selector(self.shareTapped), for: .touchUpInside)
        stack.addArrangedSubview(self.shareButton)

        self.refreshHeader()
        self.updateStageVisibility()
    }

    private func setupSlotsStage() {
        self.slotsStack.axis = .horizontal
        self.slotsStack.distribution = .fillEqually
        self.slotsStack.spacing = 12.0
        self.slotsStack.translatesAutoresizingMaskIntoConstraints = false
        self.stageCard.addSubview(self.slotsStack)
        NSLayoutConstraint.activate([
            self.slotsStack.centerYAnchor.constraint(equalTo: self.stageCard.centerYAnchor),
            self.slotsStack.leadingAnchor.constraint(equalTo: self.stageCard.leadingAnchor, constant: 16.0),
            self.slotsStack.trailingAnchor.constraint(equalTo: self.stageCard.trailingAnchor, constant: -16.0),
            self.slotsStack.heightAnchor.constraint(equalToConstant: 120.0)
        ])

        for _ in 0 ..< 3 {
            let box = UIView()
            box.backgroundColor = UIColor(rgb: 0x11131A)
            box.layer.cornerRadius = 14.0
            box.layer.borderWidth = 2.0
            box.layer.borderColor = UIColor(rgb: 0xFFD60A).withAlphaComponent(0.55).cgColor

            let lbl = UILabel()
            lbl.font = .systemFont(ofSize: 54.0)
            lbl.textAlignment = .center
            lbl.text = "7️⃣"
            lbl.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(lbl)
            NSLayoutConstraint.activate([
                lbl.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                lbl.centerYAnchor.constraint(equalTo: box.centerYAnchor)
            ])
            self.reelLabels.append(lbl)
            self.slotsStack.addArrangedSubview(box)
        }
    }

    private func setupRouletteStage() {
        self.rouletteContainer.translatesAutoresizingMaskIntoConstraints = false
        self.stageCard.addSubview(self.rouletteContainer)
        NSLayoutConstraint.activate([
            self.rouletteContainer.topAnchor.constraint(equalTo: self.stageCard.topAnchor, constant: 16.0),
            self.rouletteContainer.bottomAnchor.constraint(equalTo: self.stageCard.bottomAnchor, constant: -16.0),
            self.rouletteContainer.leadingAnchor.constraint(equalTo: self.stageCard.leadingAnchor, constant: 16.0),
            self.rouletteContainer.trailingAnchor.constraint(equalTo: self.stageCard.trailingAnchor, constant: -16.0)
        ])

        self.rouletteBallLabel.font = .monospacedDigitSystemFont(ofSize: 34.0, weight: .heavy)
        self.rouletteBallLabel.textColor = .white
        self.rouletteBallLabel.textAlignment = .center
        self.rouletteBallLabel.text = "🎡 0 🟢"
        self.rouletteBallLabel.backgroundColor = UIColor(rgb: 0x11131A)
        self.rouletteBallLabel.layer.cornerRadius = 14.0
        self.rouletteBallLabel.clipsToBounds = true
        self.rouletteBallLabel.heightAnchor.constraint(equalToConstant: 82.0).isActive = true

        self.rouletteChoiceStack.axis = .horizontal
        self.rouletteChoiceStack.distribution = .fillEqually
        self.rouletteChoiceStack.spacing = 8.0
        let choices: [(String, String, UIColor)] = [
            ("red", "🔴 Красное x2", UIColor(rgb: 0xE53935)),
            ("green", "🟢 Зеро x14", UIColor(rgb: 0x2E7D32)),
            ("black", "⚫️ Чёрное x2", UIColor(rgb: 0x262936))
        ]
        for (id, title, color) in choices {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(.white, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13.0, weight: .bold)
            b.backgroundColor = color
            b.layer.cornerRadius = 10.0
            b.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
            b.accessibilityIdentifier = id
            b.addTarget(self, action: #selector(self.rouletteChoiceTapped(_:)), for: .touchUpInside)
            self.rouletteButtons[id] = b
            self.rouletteChoiceStack.addArrangedSubview(b)
        }

        let v = UIStackView(arrangedSubviews: [self.rouletteBallLabel, self.rouletteChoiceStack])
        v.axis = .vertical
        v.spacing = 14.0
        v.translatesAutoresizingMaskIntoConstraints = false
        self.rouletteContainer.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: self.rouletteContainer.topAnchor),
            v.bottomAnchor.constraint(equalTo: self.rouletteContainer.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: self.rouletteContainer.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: self.rouletteContainer.trailingAnchor)
        ])
        self.highlightRouletteChoice()
    }

    private func setupCoinStage() {
        self.coinContainer.translatesAutoresizingMaskIntoConstraints = false
        self.stageCard.addSubview(self.coinContainer)
        NSLayoutConstraint.activate([
            self.coinContainer.topAnchor.constraint(equalTo: self.stageCard.topAnchor, constant: 16.0),
            self.coinContainer.bottomAnchor.constraint(equalTo: self.stageCard.bottomAnchor, constant: -16.0),
            self.coinContainer.leadingAnchor.constraint(equalTo: self.stageCard.leadingAnchor, constant: 16.0),
            self.coinContainer.trailingAnchor.constraint(equalTo: self.stageCard.trailingAnchor, constant: -16.0)
        ])

        self.coinEmojiLabel.font = .systemFont(ofSize: 32.0, weight: .heavy)
        self.coinEmojiLabel.textColor = UIColor(rgb: 0xFFD60A)
        self.coinEmojiLabel.textAlignment = .center
        self.coinEmojiLabel.text = "🦅 ОРЁЛ"
        self.coinEmojiLabel.backgroundColor = UIColor(rgb: 0x11131A)
        self.coinEmojiLabel.layer.cornerRadius = 14.0
        self.coinEmojiLabel.clipsToBounds = true
        self.coinEmojiLabel.heightAnchor.constraint(equalToConstant: 82.0).isActive = true

        self.coinChoiceStack.axis = .horizontal
        self.coinChoiceStack.distribution = .fillEqually
        self.coinChoiceStack.spacing = 10.0
        let sides: [(String, String)] = [("eagle", "🦅 Орёл (x2)"), ("tails", "🪙 Решка (x2)")]
        for (id, title) in sides {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(.white, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14.0, weight: .bold)
            b.backgroundColor = UIColor(rgb: 0x2A2E3F)
            b.layer.cornerRadius = 10.0
            b.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
            b.accessibilityIdentifier = id
            b.addTarget(self, action: #selector(self.coinChoiceTapped(_:)), for: .touchUpInside)
            self.coinButtons[id] = b
            self.coinChoiceStack.addArrangedSubview(b)
        }

        let v = UIStackView(arrangedSubviews: [self.coinEmojiLabel, self.coinChoiceStack])
        v.axis = .vertical
        v.spacing = 14.0
        v.translatesAutoresizingMaskIntoConstraints = false
        self.coinContainer.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: self.coinContainer.topAnchor),
            v.bottomAnchor.constraint(equalTo: self.coinContainer.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: self.coinContainer.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: self.coinContainer.trailingAnchor)
        ])
        self.highlightCoinChoice()
    }

    private func highlightRouletteChoice() {
        for (id, btn) in self.rouletteButtons {
            btn.layer.borderWidth = (id == self.rouletteChoice) ? 2.5 : 0.0
            btn.layer.borderColor = UIColor(rgb: 0xFFD60A).cgColor
        }
    }

    private func highlightCoinChoice() {
        for (id, btn) in self.coinButtons {
            btn.layer.borderWidth = (id == self.coinChoice) ? 2.5 : 0.0
            btn.layer.borderColor = UIColor(rgb: 0xFFD60A).cgColor
        }
    }

    private func refreshHeader() {
        let bal = self.balance
        let best = self.bestBalance
        self.balanceLabel.text = "💰 \(bal) 🪙"
        self.recordLabel.text = "🏆 Рекорд: \(best) 🪙 • Lua Plugin VM"
        self.bet = max(10, min(max(10, bal), self.bet))
        self.betLabel.text = "Ставка: \(self.bet) 🪙"
    }

    private func updateStageVisibility() {
        self.slotsStack.isHidden = (self.currentTab != .slots)
        self.rouletteContainer.isHidden = (self.currentTab != .roulette)
        self.coinContainer.isHidden = (self.currentTab != .coin)
        switch self.currentTab {
        case .slots:
            self.spinButton.setTitle("🎰 КРУТИТЬ СЛОТЫ", for: .normal)
        case .roulette:
            self.spinButton.setTitle("🎡 ЗАПУСТИТЬ РУЛЕТКУ", for: .normal)
        case .coin:
            self.spinButton.setTitle("🪙 ПОДБРОСИТЬ МОНЕТКУ", for: .normal)
        }
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func bonusTapped() {
        _ = FullGramPluginManager.shared.dispatchUIEvent(pluginId: "fg_casino", action: "bonus")
        self.balance += 1000
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.statusBannerLabel.text = "🎁 Начислен бонус +1000 🪙!"
    }

    @objc private func tabChanged() {
        guard !self.isSpinning else {
            self.segmented.selectedSegmentIndex = self.currentTab.rawValue
            return
        }
        self.currentTab = GameTab(rawValue: self.segmented.selectedSegmentIndex) ?? .slots
        self.updateStageVisibility()
    }

    @objc private func rouletteChoiceTapped(_ sender: UIButton) {
        guard !self.isSpinning, let id = sender.accessibilityIdentifier else { return }
        self.rouletteChoice = id
        self.highlightRouletteChoice()
    }

    @objc private func coinChoiceTapped(_ sender: UIButton) {
        guard !self.isSpinning, let id = sender.accessibilityIdentifier else { return }
        self.coinChoice = id
        self.highlightCoinChoice()
    }

    @objc private func betPresetTapped(_ sender: UIButton) {
        guard !self.isSpinning else { return }
        let bal = max(10, self.balance)
        switch sender.tag {
        case -1: self.bet = max(10, self.bet / 2)
        case -2: self.bet = min(bal, self.bet * 2)
        case -3: self.bet = bal
        default: self.bet = min(bal, max(10, sender.tag))
        }
        self.betLabel.text = "Ставка: \(self.bet) 🪙"
    }

    @objc private func spinTapped() {
        guard !self.isSpinning else { return }
        if self.balance < 10 {
            self.balance = 500
            self.statusBannerLabel.text = "🎁 Баланс пополнен до 500 🪙!"
        }
        let currentBet = min(self.balance, max(10, self.bet))
        self.bet = currentBet
        self.isSpinning = true
        self.spinButton.isEnabled = false
        self.spinButton.alpha = 0.6

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()

        switch self.currentTab {
        case .slots:
            let finalIdx = [Int.random(in: 0 ..< 5), Int.random(in: 0 ..< 5), Int.random(in: 0 ..< 5)]
            var step = 0
            self.spinTimer?.invalidate()
            self.spinTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                step += 1
                if step < 10 {
                    self.reelLabels[0].text = Self.symbols.randomElement()
                } else if step == 10 {
                    self.reelLabels[0].text = Self.symbols[finalIdx[0]]
                    impact.impactOccurred()
                }
                if step < 16 {
                    self.reelLabels[1].text = Self.symbols.randomElement()
                } else if step == 16 {
                    self.reelLabels[1].text = Self.symbols[finalIdx[1]]
                    impact.impactOccurred()
                }
                if step < 22 {
                    self.reelLabels[2].text = Self.symbols.randomElement()
                } else {
                    timer.invalidate()
                    self.reelLabels[2].text = Self.symbols[finalIdx[2]]
                    impact.impactOccurred()
                    self.finishSlotsSpin(finalIdx: finalIdx, bet: currentBet)
                }
            }

        case .roulette:
            let targetNum = Int.random(in: 0 ... 36)
            var step = 0
            self.spinTimer?.invalidate()
            self.spinTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.065, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                step += 1
                if step < 18 {
                    let n = Int.random(in: 0 ... 36)
                    let em = (n == 0) ? "🟢" : (n % 2 == 1 ? "🔴" : "⚫️")
                    self.rouletteBallLabel.text = "🎡 \(n) \(em)"
                    if step % 3 == 0 { impact.impactOccurred() }
                } else {
                    timer.invalidate()
                    self.finishRouletteSpin(num: targetNum, bet: currentBet)
                }
            }

        case .coin:
            let wonEagle = Bool.random()
            var step = 0
            self.spinTimer?.invalidate()
            self.spinTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.11, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                step += 1
                UIView.transition(with: self.coinEmojiLabel, duration: 0.10, options: .transitionFlipFromLeft) {
                    self.coinEmojiLabel.text = (step % 2 == 0) ? "🦅 ОРЁЛ" : "🪙 РЕШКА"
                }
                impact.impactOccurred()
                if step >= 10 {
                    timer.invalidate()
                    self.finishCoinSpin(wonEagle: wonEagle, bet: currentBet)
                }
            }
        }
    }

    private func finishSlotsSpin(finalIdx: [Int], bet: Int) {
        self.isSpinning = false
        self.spinButton.isEnabled = true
        self.spinButton.alpha = 1.0

        let s1 = Self.symbols[finalIdx[0]]
        let s2 = Self.symbols[finalIdx[1]]
        let s3 = Self.symbols[finalIdx[2]]

        var mult = 0
        var status = "❌ Мимо!"
        if finalIdx[0] == 4 && finalIdx[1] == 4 && finalIdx[2] == 4 {
            mult = 15
            status = "🔥 МЕГА ДЖЕКПОТ 777 (x15)!"
        } else if finalIdx[0] == finalIdx[1] && finalIdx[1] == finalIdx[2] {
            mult = 7
            status = "🎉 ДЖЕКПОТ 3 В РЯД (x7)!"
        } else if finalIdx[0] == finalIdx[1] || finalIdx[1] == finalIdx[2] || finalIdx[0] == finalIdx[2] {
            mult = 2
            status = "✨ Совпадение 2 из 3 (x2)!"
        }

        let delta = (mult > 0) ? (bet * (mult - 1)) : (-bet)
        self.balance += delta
        let sign = delta >= 0 ? "+\(delta)" : "\(delta)"
        self.statusBannerLabel.text = "\(status) (\(sign) 🪙)"
        UINotificationFeedbackGenerator().notificationOccurred(mult > 0 ? .success : .warning)

        self.lastShareSummary = "🎰 Слоты FullGram | Ставка: \(bet) 🪙\n┏━━━━━━━━━━━┓\n┃  \(s1) │ \(s2) │ \(s3)  ┃\n┗━━━━━━━━━━━┛\n\(status) (\(sign) 🪙)\n💰 Баланс: \(self.balance) 🪙"
        self.shareButton.isHidden = false
    }

    private func finishRouletteSpin(num: Int, bet: Int) {
        self.isSpinning = false
        self.spinButton.isEnabled = true
        self.spinButton.alpha = 1.0

        let color: String
        let badge: String
        if num == 0 {
            color = "green"
            badge = "🟢 Зеро (0)"
        } else if num % 2 == 1 {
            color = "red"
            badge = "🔴 Красное"
        } else {
            color = "black"
            badge = "⚫️ Чёрное"
        }
        self.rouletteBallLabel.text = "\(badge) [\(num)]"

        let won = (self.rouletteChoice == color)
        let mult = (color == "green") ? 14 : 2
        let delta = won ? (bet * (mult - 1)) : (-bet)
        self.balance += delta
        let sign = delta >= 0 ? "+\(delta)" : "\(delta)"
        self.statusBannerLabel.text = won ? "✅ Выигрыш в рулетке: \(sign) 🪙!" : "❌ Выпало \(badge) (\(sign) 🪙)"
        UINotificationFeedbackGenerator().notificationOccurred(won ? .success : .warning)

        self.lastShareSummary = "🎡 Рулетка FullGram\nВыпало: \(badge) [\(num)]\nРезультат: \(sign) 🪙\n💰 Баланс: \(self.balance) 🪙"
        self.shareButton.isHidden = false
    }

    private func finishCoinSpin(wonEagle: Bool, bet: Int) {
        self.isSpinning = false
        self.spinButton.isEnabled = true
        self.spinButton.alpha = 1.0

        self.coinEmojiLabel.text = wonEagle ? "🦅 ОРЁЛ" : "🪙 РЕШКА"
        let pickedEagle = (self.coinChoice == "eagle")
        let won = (wonEagle == pickedEagle)
        let delta = won ? bet : (-bet)
        self.balance += delta
        let sign = delta >= 0 ? "+\(delta)" : "\(delta)"
        self.statusBannerLabel.text = won ? "✅ Вы угадали сторону! (\(sign) 🪙)" : "❌ Не угадали (\(sign) 🪙)"
        UINotificationFeedbackGenerator().notificationOccurred(won ? .success : .warning)

        self.lastShareSummary = "🪙 Монетка FullGram: выпал \(wonEagle ? "🦅 Орёл" : "🪙 Решка")\nРезультат: \(sign) 🪙 (Баланс: \(self.balance) 🪙)"
        self.shareButton.isHidden = false
    }

    @objc private func shareTapped() {
        guard !self.lastShareSummary.isEmpty else { return }
        self.onSendToChat(self.lastShareSummary)
        self.dismiss(animated: true)
    }
}

// MARK: - Graphical Deadlines Manager (`fg_deadlines`)

private final class FullGramDeadlinesGUIViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private struct DeadlineItem: Codable {
        var due: String
        var task: String
        var done: Bool
    }

    private static let storageKey = "fullgram.plugin.store.fg_deadlines.dl_json"
    private let onSendToChat: (String) -> Void
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var items: [DeadlineItem] = []

    init(onSendToChat: @escaping (String) -> Void) {
        self.onSendToChat = onSendToChat
        super.init(nibName: nil, bundle: nil)
        self.title = "⏰ Дедлайны FullGram"
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .done, target: self, action: #selector(self.closeTapped))
        let addBtn = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addTapped))
        let shareBtn = UIBarButtonItem(title: "В чат", style: .plain, target: self, action: #selector(self.sendToChatTapped))
        self.navigationItem.rightBarButtonItems = [addBtn, shareBtn]

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.tableView)
        NSLayoutConstraint.activate([
            self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        self.loadFromStorage()
    }

    private func loadFromStorage() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? "[]"
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([DeadlineItem].self, from: data) {
            self.items = decoded
        } else {
            self.items = []
        }
        self.tableView.reloadData()
    }

    private func saveToStorage() {
        if let data = try? JSONEncoder().encode(self.items),
           let str = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(str, forKey: Self.storageKey)
        }
        self.tableView.reloadData()
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func addTapped() {
        let alert = UIAlertController(title: "Новый дедлайн", message: "Укажите срок и описание задачи:", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Срок (например: Завтра 18:00)"
        }
        alert.addTextField { tf in
            tf.placeholder = "Задача (например: Сдать проект)"
        }
        alert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak self] _ in
            guard let self else { return }
            let due = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let task = alert.textFields?.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !task.isEmpty else { return }
            self.items.append(DeadlineItem(due: due.isEmpty ? "Срочно" : due, task: task, done: false))
            self.saveToStorage()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.present(alert, animated: true)
    }

    @objc private func sendToChatTapped() {
        guard !self.items.isEmpty else { return }
        var lines = ["⏰ Список дедлайнов FullGram:", "━━━━━━━━━━━━━━━━━━━━"]
        for (idx, it) in self.items.enumerated() {
            let icon = it.done ? "✅" : "⏳"
            lines.append("\(idx + 1). \(icon) [\(it.due)] — \(it.task)")
        }
        self.onSendToChat(lines.joined(separator: "\n"))
        self.dismiss(animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.items.isEmpty ? "ДЕДЛАЙНОВ ПОКА НЕТ (НАЖМИТЕ +)" : "НАЖМИТЕ НА ЗАДАЧУ, ЧТОБЫ ОТМЕТИТЬ ВЫПОЛНЕННОЙ"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let item = self.items[indexPath.row]
        let icon = item.done ? "✅" : "⏳"
        cell.textLabel?.text = "\(icon) \(item.task)"
        cell.textLabel?.font = .systemFont(ofSize: 16.0, weight: .semibold)
        cell.detailTextLabel?.text = "Срок: \(item.due)"
        cell.detailTextLabel?.textColor = item.done ? .systemGreen : .systemOrange
        cell.accessoryType = item.done ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.items[indexPath.row].done.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        self.saveToStorage()
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            self.items.remove(at: indexPath.row)
            self.saveToStorage()
        }
    }
}

// MARK: - Generic Declarative Plugin GUI Controller (`fullgram.open_ui`)

private final class FullGramCustomPluginGUIViewController: UIViewController {
    private let spec: [String: Any]
    private let onSendToChat: (String) -> Void
    private let outputLabel = UILabel()
    private let inputField = UITextField()

    init(spec: [String: Any], onSendToChat: @escaping (String) -> Void) {
        self.spec = spec
        self.onSendToChat = onSendToChat
        super.init(nibName: nil, bundle: nil)
        self.title = (spec["title"] as? String) ?? "Плагин FullGram"
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .done, target: self, action: #selector(self.closeTapped))

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 20.0),
            stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0)
        ])

        self.outputLabel.font = .systemFont(ofSize: 16.0, weight: .medium)
        self.outputLabel.numberOfLines = 0
        self.outputLabel.text = (self.spec["subtitle"] as? String) ?? "Графический интерфейс плагина активен."
        stack.addArrangedSubview(self.outputLabel)

        self.inputField.borderStyle = .roundedRect
        self.inputField.placeholder = (self.spec["placeholder"] as? String) ?? "Введите аргумент…"
        stack.addArrangedSubview(self.inputField)

        if let buttons = self.spec["buttons"] as? [[String: Any]] {
            for b in buttons {
                let btnTitle = (b["title"] as? String) ?? "Действие"
                let actionId = (b["id"] as? String) ?? btnTitle
                let btn = UIButton(type: .system)
                btn.setTitle(btnTitle, for: .normal)
                btn.setTitleColor(.white, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 15.0, weight: .semibold)
                btn.backgroundColor = .systemBlue
                btn.layer.cornerRadius = 10.0
                btn.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
                btn.accessibilityIdentifier = actionId
                btn.addTarget(self, action: #selector(self.customButtonTapped(_:)), for: .touchUpInside)
                stack.addArrangedSubview(btn)
            }
        }
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func customButtonTapped(_ sender: UIButton) {
        let pluginId = (self.spec["pluginId"] as? String) ?? ""
        let actionId = sender.accessibilityIdentifier ?? "click"
        let inputText = self.inputField.text ?? ""
        let res = FullGramPluginManager.shared.dispatchUIEvent(
            pluginId: pluginId,
            action: actionId,
            payload: ["input": .string(inputText)]
        )
        let str = res.asString
        if !str.isEmpty {
            self.outputLabel.text = str
        }
    }
}
