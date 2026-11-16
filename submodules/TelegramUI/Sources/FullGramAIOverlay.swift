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

    init(context: AccountContext, rootController: TelegramRootController) {
        self.context = context
        self.rootController = rootController
        self.theme = context.sharedContext.currentPresentationData.with { $0 }.theme

        self.observeNotifications()
        DispatchQueue.main.async { [weak self] in
            self?.syncPetVisibility()
        }
    }

    deinit {
        for obs in self.observers {
            NotificationCenter.default.removeObserver(obs)
        }
        self.petView?.removeFromSuperview()
        self.windowView?.removeFromSuperview()
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
                        $0.withUpdatedComposeInputState(ChatTextInputState(inputText: NSAttributedString(string: text), selectionRange: text.count ..< text.count))
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
