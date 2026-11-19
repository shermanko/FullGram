import Foundation
import UIKit
import WebKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import SwiftSignalKit
import AccountContext
import ChatInterfaceState
import UndoUI

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
                count: 200,
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

                let recentMessages = historyTuple.0.entries.map { $0.message }
                let cal = Calendar.current
                let startOfToday = Int32(cal.startOfDay(for: Date()).timeIntervalSince1970)
                let startOfWeek = Int32((cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()).timeIntervalSince1970)

                var todayCount = 0
                var weekCount = 0
                var voiceCount = 0
                var roundCount = 0
                var mediaCount = 0
                var authorTotals: [String: Int] = [:]
                for msg in recentMessages {
                    if msg.timestamp >= startOfToday { todayCount += 1 }
                    if msg.timestamp >= startOfWeek { weekCount += 1 }
                    let author = Self.sanitize(msg.author.map { EnginePeer($0).debugDisplayTitle } ?? "Участник", maxLen: 28)
                    authorTotals[author, default: 0] += 1
                    for media in msg.media {
                        mediaCount += 1
                        if let file = media as? TelegramMediaFile {
                            if file.isVoice { voiceCount += 1 }
                            else if file.isInstantVideo { roundCount += 1 }
                        }
                    }
                }
                let topAuthors = authorTotals
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: ", ")

                lines.append("[VERIFIED_LOCAL_STATS — ТЕКУЩИЙ ЧАТ]")
                lines.append("Проанализировано последних сообщений в локальной истории: \(recentMessages.count)")
                lines.append("Сообщений сегодня (в загруженной истории): \(todayCount); за последние 7 дней: \(weekCount)")
                lines.append("Медиафайлов: \(mediaCount) (голосовых: \(voiceCount), кружков: \(roundCount))")
                if !topAuthors.isEmpty {
                    lines.append("Активность участников: \(topAuthors)")
                }
                if let firstTs = recentMessages.first?.timestamp, let lastTs = recentMessages.last?.timestamp {
                    lines.append("Диапазон загруженных сообщений: с \(df.string(from: Date(timeIntervalSince1970: TimeInterval(firstTs)))) по \(df.string(from: Date(timeIntervalSince1970: TimeInterval(lastTs))))")
                }

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

                    lines.append("[VERIFIED_LOCAL_STATS — ПОИСК ЗА ДАТУ]")
                    lines.append("Дата запроса: \(dq.label)")
                    lines.append("Точное количество сообщений за \(dq.label) в Telegram: \(countInDay) (загружено примеров: \(dateSearch.messages.count))")
                    if !authorBreakdown.isEmpty {
                        lines.append("Активность участников за \(dq.label): \(authorBreakdown)")
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
                count: 45,
                shouldLoadCanMessagePeer: false
            )
            |> take(1)
            |> map { view, _ -> String in
                let startOfToday = Int32(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
                var totalChats = 0
                var privateChats = 0
                var groupChats = 0
                var channelChats = 0
                var totalUnreadMessages = 0
                var unreadDialogsCount = 0
                var activeTodayDialogs = 0
                var unreadTop: [(title: String, unread: Int32)] = []
                var recentLines: [String] = []

                for entry in view.entries.reversed() {
                    if case let .MessageEntry(data) = entry, let mainPeer = data.renderedPeer.chatMainPeer {
                        totalChats += 1
                        if mainPeer is TelegramUser {
                            privateChats += 1
                        } else if let ch = mainPeer as? TelegramChannel {
                            if case .broadcast = ch.info { channelChats += 1 } else { groupChats += 1 }
                        } else {
                            groupChats += 1
                        }
                        let unread = data.readState?.state.count ?? 0
                        if unread > 0 {
                            unreadDialogsCount += 1
                            totalUnreadMessages += Int(unread)
                            let title = Self.sanitize(EnginePeer(mainPeer).debugDisplayTitle, maxLen: 36)
                            unreadTop.append((title, unread))
                        }
                        if let lastMsg = data.messages.last, lastMsg.timestamp >= startOfToday {
                            activeTodayDialogs += 1
                        }
                        if recentLines.count < 16 {
                            let title = Self.sanitize(EnginePeer(mainPeer).debugDisplayTitle, maxLen: 42)
                            recentLines.append("peer_id=\(mainPeer.id.toInt64()) | \(title) | непрочит: \(unread)")
                        }
                    }
                }

                var out: [String] = [
                    "[VERIFIED_LOCAL_STATS — ОБЩАЯ СТАТИСТИКА АККАУНТА]",
                    "Проанализировано последних диалогов: \(totalChats) (личных: \(privateChats), групп: \(groupChats), каналов: \(channelChats))",
                    "Активных диалогов сегодня: \(activeTodayDialogs)",
                    "Непрочитанных диалогов: \(unreadDialogsCount), всего непрочитанных сообщений в них: \(totalUnreadMessages)"
                ]
                let topUnreadStr = unreadTop
                    .sorted { $0.unread > $1.unread }
                    .prefix(5)
                    .map { "\($0.title) (\($0.unread))" }
                    .joined(separator: ", ")
                if !topUnreadStr.isEmpty {
                    out.append("Топ чатов с непрочитанными: \(topUnreadStr)")
                }
                if !recentLines.isEmpty {
                    out.append("")
                    out.append("[UNTRUSTED_CHAT_DATA — последние диалоги (для поиска/открытия)]")
                    out.append(contentsOf: recentLines)
                }
                return out.joined(separator: "\n")
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
    private let senderLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let textLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let secondaryButton = UIButton(type: .system)
    private var messageId: String = ""
    private var messageText: String = ""
    private var action: FullGramAIProposedAction?

    var onConfirmAction: ((String, FullGramAIProposedAction) -> Void)?
    var onInsertDraftInstead: ((String, FullGramAIProposedAction) -> Void)?

    func configure(
        message: FullGramAIChatMessage,
        theme: PresentationTheme,
        maxWidth: CGFloat
    ) -> CGFloat {
        self.messageId = message.id
        self.messageText = message.text
        self.action = message.action

        self.subviews.forEach { $0.removeFromSuperview() }
        self.cardView.subviews.forEach { $0.removeFromSuperview() }
        self.addSubview(self.cardView)

        let accent = theme.chat.inputPanel.actionControlFillColor
        let isUser = message.isUser
        let isDark = theme.overallDarkAppearance

        self.cardView.layer.cornerRadius = 17.0
        self.cardView.layer.cornerCurve = .continuous
        self.cardView.layer.maskedCorners = isUser
            ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        if isUser {
            self.cardView.backgroundColor = accent
            self.cardView.layer.borderWidth = 0.0
            self.cardView.layer.borderColor = nil
        } else {
            self.cardView.backgroundColor = isDark
                ? UIColor.white.withAlphaComponent(0.09)
                : UIColor.black.withAlphaComponent(0.05)
            self.cardView.layer.borderWidth = 0.5
            self.cardView.layer.borderColor = (isDark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.07)).cgColor
        }

        let bubbleMaxW = max(180.0, maxWidth * 0.86)
        let padH: CGFloat = 13.0
        let padV: CGFloat = 10.0

        var textTopY: CGFloat = padV
        var minCardW: CGFloat = 84.0
        if !isUser {
            self.senderLabel.text = "✨ FullGram AI"
            self.senderLabel.font = .systemFont(ofSize: 10.5, weight: .bold)
            self.senderLabel.textColor = accent
            self.cardView.addSubview(self.senderLabel)

            self.copyButton.removeTarget(nil, action: nil, for: .allEvents)
            let copyCfg = UIImage.SymbolConfiguration(pointSize: 11.0, weight: .medium)
            self.copyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: copyCfg), for: .normal)
            self.copyButton.tintColor = theme.list.itemSecondaryTextColor
            self.copyButton.addTarget(self, action: #selector(self.copyTapped), for: .touchUpInside)
            self.cardView.addSubview(self.copyButton)

            textTopY = padV + 18.0
            minCardW = 148.0
        }

        self.textLabel.numberOfLines = 0
        self.textLabel.font = .systemFont(ofSize: 14.0, weight: .regular)
        self.textLabel.textColor = isUser ? .white : theme.list.itemPrimaryTextColor
        self.textLabel.text = message.text
        self.cardView.addSubview(self.textLabel)

        let textFit = self.textLabel.sizeThatFits(CGSize(width: bubbleMaxW - padH * 2.0, height: .greatestFiniteMagnitude))
        var contentW = min(bubbleMaxW, max(minCardW, ceil(textFit.width) + padH * 2.0))
        if message.action != nil && !isUser {
            contentW = bubbleMaxW
        }

        if !isUser {
            self.senderLabel.frame = CGRect(x: padH, y: padV - 1.0, width: max(60.0, contentW - padH * 2.0 - 26.0), height: 14.0)
            self.copyButton.frame = CGRect(x: contentW - padH - 22.0, y: padV - 5.0, width: 24.0, height: 22.0)
        }

        self.textLabel.frame = CGRect(x: padH, y: textTopY, width: contentW - padH * 2.0, height: ceil(textFit.height))
        var contentH = self.textLabel.frame.maxY + padV

        if let action = message.action, !isUser {
            let buttonW = contentW - padH * 2.0
            let statusY = self.textLabel.frame.maxY + 10.0

            self.actionButton.removeTarget(nil, action: nil, for: .allEvents)
            self.secondaryButton.removeTarget(nil, action: nil, for: .allEvents)

            var btnCfg = UIButton.Configuration.filled()
            btnCfg.cornerStyle = .capsule
            btnCfg.titleAlignment = .center
            btnCfg.baseBackgroundColor = action.status == .applied
                ? UIColor.systemGreen.withAlphaComponent(0.20)
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
            self.actionButton.frame = CGRect(x: padH, y: statusY, width: buttonW, height: 34.0)
            self.cardView.addSubview(self.actionButton)
            contentH = self.actionButton.frame.maxY + padV

            if action.kind == .sendMessage && action.status == .pending {
                var secCfg = UIButton.Configuration.tinted()
                var secTitle = AttributedString("Вставить как черновик")
                secTitle.font = .systemFont(ofSize: 12.0, weight: .medium)
                secCfg.attributedTitle = secTitle
                secCfg.cornerStyle = .capsule
                secCfg.baseBackgroundColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.14)
                secCfg.baseForegroundColor = theme.list.itemPrimaryTextColor
                self.secondaryButton.configuration = secCfg
                self.secondaryButton.addTarget(self, action: #selector(self.draftActionTapped), for: .touchUpInside)
                self.secondaryButton.frame = CGRect(x: padH, y: self.actionButton.frame.maxY + 6.0, width: buttonW, height: 30.0)
                self.cardView.addSubview(self.secondaryButton)
                contentH = self.secondaryButton.frame.maxY + padV
            }
        }

        let originX = isUser ? (maxWidth - contentW) : 0.0
        self.cardView.frame = CGRect(x: originX, y: 0.0, width: contentW, height: contentH)
        return contentH
    }

    @objc private func copyTapped() {
        guard !self.messageText.isEmpty else { return }
        UIPasteboard.general.string = self.messageText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let checkCfg = UIImage.SymbolConfiguration(pointSize: 11.0, weight: .bold)
        self.copyButton.setImage(UIImage(systemName: "checkmark", withConfiguration: checkCfg), for: .normal)
        self.copyButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self else { return }
            let docCfg = UIImage.SymbolConfiguration(pointSize: 11.0, weight: .medium)
            self.copyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: docCfg), for: .normal)
        }
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

    private let clipView = UIView()
    private let backdropBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let headerView = UIView()
    private let avatarView = UIImageView()
    private let onlineDot = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let petButton = UIButton(type: .system)
    private let resizeButton = UIButton(type: .system)
    private let minimizeButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private let headerSeparator = UIView()
    private let bodyContainer = UIView()
    private let scrollView = UIScrollView()
    private let emptyCardView = UIView()
    private let emptyIconView = UIImageView()
    private let emptyTitleLabel = UILabel()
    private let emptyHintLabel = UILabel()
    private let typingCardView = UIView()
    private let typingSpinner = UIActivityIndicatorView(style: .medium)
    private let typingLabel = UILabel()
    private let chipsScroll = UIScrollView()
    private let composerPillView = UIView()
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

        self.layer.cornerRadius = 26.0
        self.layer.cornerCurve = .continuous
        self.layer.borderWidth = 0.65
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.28
        self.layer.shadowRadius = 24.0
        self.layer.shadowOffset = CGSize(width: 0.0, height: 12.0)

        self.clipView.layer.cornerRadius = 26.0
        self.clipView.layer.cornerCurve = .continuous
        self.clipView.clipsToBounds = true
        self.addSubview(self.clipView)

        self.clipView.addSubview(self.backdropBlur)
        self.clipView.addSubview(self.headerView)

        self.avatarView.image = UIImage(named: "FullGramMascotPortrait") ?? UIImage(named: "FullGramMascotPet")
        self.avatarView.contentMode = .scaleAspectFill
        self.avatarView.layer.cornerRadius = 17.0
        self.avatarView.layer.borderWidth = 1.5
        self.avatarView.clipsToBounds = true
        self.headerView.addSubview(self.avatarView)

        self.onlineDot.backgroundColor = UIColor(rgb: 0x30D158)
        self.onlineDot.layer.cornerRadius = 4.5
        self.onlineDot.layer.borderWidth = 1.5
        self.headerView.addSubview(self.onlineDot)

        self.titleLabel.text = "FullGram AI"
        self.titleLabel.font = .systemFont(ofSize: 15.0, weight: .bold)
        self.headerView.addSubview(self.titleLabel)

        self.subtitleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        self.headerView.addSubview(self.subtitleLabel)

        self.setupHeaderButton(self.petButton, systemName: "pawprint.fill", action: #selector(self.petTapped))
        self.setupHeaderButton(self.resizeButton, systemName: "arrow.down.right.and.arrow.up.left", action: #selector(self.resizeTapped))
        self.setupHeaderButton(self.minimizeButton, systemName: "minus", action: #selector(self.minimizeTapped))
        self.setupHeaderButton(self.closeButton, systemName: "xmark", action: #selector(self.closeTapped))

        let drag = UIPanGestureRecognizer(target: self, action: #selector(self.handleHeaderDrag(_:)))
        self.headerView.addGestureRecognizer(drag)

        self.clipView.addSubview(self.headerSeparator)
        self.clipView.addSubview(self.bodyContainer)

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .interactive
        self.bodyContainer.addSubview(self.scrollView)

        self.emptyCardView.layer.cornerRadius = 18.0
        self.emptyCardView.layer.cornerCurve = .continuous
        self.emptyCardView.layer.borderWidth = 0.5
        self.scrollView.addSubview(self.emptyCardView)

        let iconCfg = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .semibold)
        self.emptyIconView.image = UIImage(systemName: "sparkles", withConfiguration: iconCfg)
        self.emptyIconView.contentMode = .scaleAspectFit
        self.emptyCardView.addSubview(self.emptyIconView)

        self.emptyTitleLabel.text = "ИИ-помощник FullGram"
        self.emptyTitleLabel.textAlignment = .center
        self.emptyTitleLabel.font = .systemFont(ofSize: 15.0, weight: .bold)
        self.emptyCardView.addSubview(self.emptyTitleLabel)

        self.emptyHintLabel.numberOfLines = 0
        self.emptyHintLabel.textAlignment = .center
        self.emptyHintLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        self.emptyHintLabel.text = "Спросите о текущем чате, попросите сводку или черновик ответа.\n\nКоманда прямо в строке ввода:\n.ai сколько сообщений сегодня"
        self.emptyCardView.addSubview(self.emptyHintLabel)

        self.typingCardView.layer.cornerRadius = 15.0
        self.typingCardView.layer.cornerCurve = .continuous
        self.typingCardView.isHidden = true
        self.typingSpinner.transform = CGAffineTransform(scaleX: 0.78, y: 0.78)
        self.typingCardView.addSubview(self.typingSpinner)
        self.typingLabel.text = "Думаю…"
        self.typingLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        self.typingCardView.addSubview(self.typingLabel)

        self.chipsScroll.showsHorizontalScrollIndicator = false
        self.bodyContainer.addSubview(self.chipsScroll)
        self.buildQuickChips()

        self.composerPillView.layer.cornerRadius = 20.0
        self.composerPillView.layer.cornerCurve = .continuous
        self.composerPillView.layer.borderWidth = 0.65
        self.bodyContainer.addSubview(self.composerPillView)

        let trashCfg = UIImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        self.clearButton.setImage(UIImage(systemName: "trash", withConfiguration: trashCfg), for: .normal)
        self.clearButton.addTarget(self, action: #selector(self.clearTapped), for: .touchUpInside)
        self.composerPillView.addSubview(self.clearButton)

        self.inputField.placeholder = "Задать вопрос или команду…"
        self.inputField.font = .systemFont(ofSize: 14.0)
        self.inputField.returnKeyType = .send
        self.inputField.delegate = self
        self.composerPillView.addSubview(self.inputField)

        let sendCfg = UIImage.SymbolConfiguration(pointSize: 14.0, weight: .bold)
        self.sendButton.setImage(UIImage(systemName: "arrow.up", withConfiguration: sendCfg), for: .normal)
        self.sendButton.layer.cornerRadius = 15.0
        self.sendButton.clipsToBounds = true
        self.sendButton.addTarget(self, action: #selector(self.sendTapped), for: .touchUpInside)
        self.composerPillView.addSubview(self.sendButton)

        self.activityIndicator.hidesWhenStopped = true
        self.composerPillView.addSubview(self.activityIndicator)

        self.applyTheme(theme)
    }

    required init?(coder: NSCoder) { return nil }

    private func setupHeaderButton(_ btn: UIButton, systemName: String, action: Selector) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        btn.setImage(UIImage(systemName: systemName, withConfiguration: cfg), for: .normal)
        btn.layer.cornerRadius = 14.0
        btn.clipsToBounds = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        self.headerView.addSubview(btn)
    }

    private func buildQuickChips() {
        self.chipsScroll.subviews.forEach { $0.removeFromSuperview() }
        let items: [(title: String, prompt: String)] = [
            ("✨ Сводка чата", "Сделай краткую сводку этого чата"),
            ("📊 Статистика", "Дай общую статистику по аккаунту и чату"),
            ("📅 Сегодня", "Сколько сообщений было сегодня?"),
            ("✍️ Черновик", "Подготовь вежливый черновик ответа"),
            ("💬 Чаты", "Покажи последние чаты")
        ]
        var x: CGFloat = 12.0
        for item in items {
            var cfg = UIButton.Configuration.filled()
            var titleAttr = AttributedString(item.title)
            titleAttr.font = .systemFont(ofSize: 12.0, weight: .semibold)
            cfg.attributedTitle = titleAttr
            cfg.cornerStyle = .capsule
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 5.0, leading: 11.0, bottom: 5.0, trailing: 11.0)
            let btn = UIButton(configuration: cfg)
            btn.accessibilityLabel = item.prompt
            btn.addTarget(self, action: #selector(self.chipTapped(_:)), for: .touchUpInside)
            btn.sizeToFit()
            btn.frame = CGRect(x: x, y: 2.0, width: btn.bounds.width, height: 28.0)
            self.chipsScroll.addSubview(btn)
            x += btn.bounds.width + 7.0
        }
        self.chipsScroll.contentSize = CGSize(width: x + 6.0, height: 32.0)
    }

    func applyTheme(_ theme: PresentationTheme) {
        self.theme = theme
        let accent = theme.chat.inputPanel.actionControlFillColor
        let isDark = theme.overallDarkAppearance
        let bgColor = theme.list.itemBlocksBackgroundColor.withAlphaComponent(isDark ? 0.86 : 0.90)
        let secondaryBg = theme.list.blocksBackgroundColor.withAlphaComponent(isDark ? 0.55 : 0.65)

        self.backdropBlur.effect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
        self.backgroundColor = .clear
        self.clipView.backgroundColor = bgColor
        self.headerView.backgroundColor = secondaryBg
        self.layer.borderColor = (isDark ? UIColor.white.withAlphaComponent(0.16) : UIColor.black.withAlphaComponent(0.08)).cgColor
        self.avatarView.layer.borderColor = accent.withAlphaComponent(0.65).cgColor
        self.onlineDot.layer.borderColor = theme.list.itemBlocksBackgroundColor.cgColor

        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.subtitleLabel.textColor = theme.list.itemSecondaryTextColor
        self.headerSeparator.backgroundColor = theme.list.itemPlainSeparatorColor.withAlphaComponent(0.55)

        self.emptyCardView.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.06) : UIColor.black.withAlphaComponent(0.04)
        self.emptyCardView.layer.borderColor = (isDark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.06)).cgColor
        self.emptyIconView.tintColor = accent
        self.emptyTitleLabel.textColor = theme.list.itemPrimaryTextColor
        self.emptyHintLabel.textColor = theme.list.itemSecondaryTextColor

        self.typingCardView.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.09) : UIColor.black.withAlphaComponent(0.05)
        self.typingSpinner.color = accent
        self.typingLabel.textColor = theme.list.itemSecondaryTextColor

        let pillBg = isDark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.06)
        self.resizeButton.backgroundColor = pillBg
        self.minimizeButton.backgroundColor = pillBg
        self.closeButton.backgroundColor = pillBg
        self.petButton.backgroundColor = FullGramAIStore.shared.showFloatingPet ? accent.withAlphaComponent(0.20) : pillBg

        self.resizeButton.tintColor = theme.list.itemPrimaryTextColor
        self.minimizeButton.tintColor = theme.list.itemPrimaryTextColor
        self.closeButton.tintColor = theme.list.itemSecondaryTextColor
        self.petButton.tintColor = FullGramAIStore.shared.showFloatingPet ? accent : theme.list.itemSecondaryTextColor

        self.composerPillView.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.045)
        self.composerPillView.layer.borderColor = (isDark ? UIColor.white.withAlphaComponent(0.14) : UIColor.black.withAlphaComponent(0.08)).cgColor
        self.inputField.textColor = theme.list.itemPrimaryTextColor
        self.inputField.tintColor = accent
        self.inputField.attributedPlaceholder = NSAttributedString(
            string: "Задать вопрос или команду…",
            attributes: [.foregroundColor: theme.list.itemSecondaryTextColor]
        )
        self.clearButton.tintColor = theme.list.itemSecondaryTextColor
        self.sendButton.backgroundColor = accent
        self.sendButton.tintColor = .white
        self.activityIndicator.color = accent

        for case let btn as UIButton in self.chipsScroll.subviews {
            var cfg = btn.configuration
            cfg?.baseBackgroundColor = accent.withAlphaComponent(isDark ? 0.16 : 0.11)
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
            self.typingSpinner.startAnimating()
        } else {
            self.activityIndicator.stopAnimating()
            self.typingSpinner.stopAnimating()
        }
        self.reloadConversation()
    }

    func setMode(_ newMode: WindowMode, in hostBounds: CGRect, safeInsets: UIEdgeInsets, animated: Bool = true) {
        self.mode = newMode
        self.customOrigin = nil
        let cfg = UIImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold)
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
        let usableW = max(290.0, bounds.width - safeInsets.left - safeInsets.right - 20.0)
        let targetSize: CGSize
        switch self.mode {
        case .standard:
            targetSize = CGSize(width: min(440.0, usableW), height: min(500.0, max(300.0, bounds.height * 0.58)))
        case .compact:
            targetSize = CGSize(width: min(330.0, usableW), height: 280.0)
        case .minimized:
            targetSize = CGSize(width: min(305.0, usableW), height: 54.0)
        }

        let bottomReserve = max(safeInsets.bottom + 14.0, self.keyboardHeight + 10.0)
        let maxY = max(safeInsets.top + 50.0, bounds.height - bottomReserve - targetSize.height)
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
        self.clipView.frame = self.bounds
        self.backdropBlur.frame = self.clipView.bounds

        let headerH: CGFloat = 54.0
        self.headerView.frame = CGRect(x: 0.0, y: 0.0, width: targetSize.width, height: headerH)
        self.avatarView.frame = CGRect(x: 12.0, y: 10.0, width: 34.0, height: 34.0)
        self.onlineDot.frame = CGRect(x: self.avatarView.frame.maxX - 9.0, y: self.avatarView.frame.maxY - 9.0, width: 9.0, height: 9.0)

        let btnSize: CGFloat = 28.0
        self.closeButton.frame = CGRect(x: targetSize.width - 38.0, y: 13.0, width: btnSize, height: btnSize)
        self.minimizeButton.frame = CGRect(x: self.closeButton.frame.minX - 32.0, y: 13.0, width: btnSize, height: btnSize)
        if self.mode == .minimized {
            self.resizeButton.isHidden = true
            self.petButton.isHidden = true
            let textRight = self.minimizeButton.frame.minX - 8.0
            self.titleLabel.frame = CGRect(x: 54.0, y: 10.0, width: max(60.0, textRight - 54.0), height: 18.0)
            self.subtitleLabel.frame = CGRect(x: 54.0, y: 28.0, width: max(60.0, textRight - 54.0), height: 14.0)
            self.headerSeparator.isHidden = true
            self.bodyContainer.isHidden = true
        } else {
            self.resizeButton.isHidden = false
            self.petButton.isHidden = false
            self.resizeButton.frame = CGRect(x: self.minimizeButton.frame.minX - 32.0, y: 13.0, width: btnSize, height: btnSize)
            self.petButton.frame = CGRect(x: self.resizeButton.frame.minX - 32.0, y: 13.0, width: btnSize, height: btnSize)
            let textRight = self.petButton.frame.minX - 8.0
            self.titleLabel.frame = CGRect(x: 54.0, y: 10.0, width: max(60.0, textRight - 54.0), height: 18.0)
            self.subtitleLabel.frame = CGRect(x: 54.0, y: 28.0, width: max(60.0, textRight - 54.0), height: 14.0)
            self.headerSeparator.isHidden = false
            self.bodyContainer.isHidden = false
            self.headerSeparator.frame = CGRect(x: 0.0, y: headerH, width: targetSize.width, height: 0.5)
            self.bodyContainer.frame = CGRect(x: 0.0, y: headerH + 0.5, width: targetSize.width, height: max(0.0, targetSize.height - headerH - 0.5))

            let bodyW = self.bodyContainer.bounds.width
            let bodyH = self.bodyContainer.bounds.height
            let footerH: CGFloat = 54.0
            let chipsH: CGFloat = self.mode == .compact ? 0.0 : 34.0
            self.chipsScroll.isHidden = self.mode == .compact

            self.scrollView.frame = CGRect(x: 0.0, y: 0.0, width: bodyW, height: max(40.0, bodyH - footerH - chipsH))
            if !self.chipsScroll.isHidden {
                self.chipsScroll.frame = CGRect(x: 0.0, y: self.scrollView.frame.maxY, width: bodyW, height: chipsH)
            }
            let pillW = max(120.0, bodyW - 20.0)
            self.composerPillView.frame = CGRect(x: 10.0, y: bodyH - 46.0, width: pillW, height: 38.0)
            self.clearButton.frame = CGRect(x: 6.0, y: 4.0, width: 30.0, height: 30.0)
            self.sendButton.frame = CGRect(x: pillW - 34.0, y: 4.0, width: 30.0, height: 30.0)
            self.activityIndicator.center = self.sendButton.center
            self.inputField.frame = CGRect(x: 40.0, y: 3.0, width: max(60.0, pillW - 78.0), height: 32.0)

            self.reloadConversation()
        }
    }

    func reloadConversation() {
        let msgs = FullGramAIStore.shared.messagesSnapshot()
        for view in self.scrollView.subviews where view !== self.emptyCardView {
            view.removeFromSuperview()
        }
        self.emptyCardView.isHidden = !msgs.isEmpty || self.isLoading

        let width = max(200.0, self.scrollView.bounds.width - 24.0)
        if msgs.isEmpty && !self.isLoading {
            let cardW = min(width, 320.0)
            let innerW = cardW - 32.0
            let hintFit = self.emptyHintLabel.sizeThatFits(CGSize(width: innerW, height: .greatestFiniteMagnitude))
            self.emptyIconView.frame = CGRect(x: (cardW - 30.0) * 0.5, y: 18.0, width: 30.0, height: 30.0)
            self.emptyTitleLabel.frame = CGRect(x: 16.0, y: self.emptyIconView.frame.maxY + 8.0, width: innerW, height: 20.0)
            self.emptyHintLabel.frame = CGRect(x: 16.0, y: self.emptyTitleLabel.frame.maxY + 8.0, width: innerW, height: ceil(hintFit.height))
            let cardH = self.emptyHintLabel.frame.maxY + 18.0
            let cardY = max(16.0, floor((self.scrollView.bounds.height - cardH) * 0.42))
            self.emptyCardView.frame = CGRect(x: floor((self.scrollView.bounds.width - cardW) * 0.5), y: cardY, width: cardW, height: cardH)
            self.scrollView.contentSize = CGSize(width: self.scrollView.bounds.width, height: self.emptyCardView.frame.maxY + 16.0)
            return
        }

        var y: CGFloat = 12.0
        for msg in msgs {
            let row = FullGramAIChatBubbleRow()
            row.onConfirmAction = { [weak self] id, action in
                self?.onConfirmAction?(id, action)
            }
            row.onInsertDraftInstead = { [weak self] id, action in
                self?.onInsertDraftInstead?(id, action)
            }
            let h = row.configure(message: msg, theme: self.theme, maxWidth: width)
            row.frame = CGRect(x: 12.0, y: y, width: width, height: h)
            self.scrollView.addSubview(row)
            y += h + 10.0
        }

        if self.isLoading {
            self.typingCardView.isHidden = false
            self.typingCardView.frame = CGRect(x: 12.0, y: y, width: 126.0, height: 32.0)
            self.typingSpinner.center = CGPoint(x: 18.0, y: 16.0)
            self.typingLabel.frame = CGRect(x: 34.0, y: 0.0, width: 84.0, height: 32.0)
            self.scrollView.addSubview(self.typingCardView)
            y += 40.0
        } else {
            self.typingCardView.isHidden = true
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

        self.observers.append(nc.addObserver(forName: FullGramPluginNotifications.toastRequested, object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let text = (note.userInfo as? [String: Any])?["text"] as? String,
                  !text.isEmpty else { return }
            let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
            let overlay = UndoOverlayController(
                presentationData: presentationData,
                content: .succeed(text: text, timeout: nil, customUndoText: nil),
                elevatedLayout: false,
                action: { _ in return false }
            )
            if let chatController = self.activeChatController() {
                chatController.present(overlay, in: .current)
            } else if let topController = self.rootController?.viewControllers.last as? ViewController {
                topController.present(overlay, in: .window(.root))
            } else {
                self.context.sharedContext.presentGlobalController(overlay, nil)
            }
        })
    }

    private func presentNativeUIKitController(_ vc: UIViewController, retryCount: Int = 0) {
        if let rootWindowVC = self.rootController?.view.window?.rootViewController, !(rootWindowVC is NavigationController) {
            var presenter = rootWindowVC
            while let next = presenter.presentedViewController, !next.isBeingDismissed {
                presenter = next
            }
            if presenter.isBeingDismissed || presenter.isBeingPresented {
                if retryCount < 4 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                        self?.presentNativeUIKitController(vc, retryCount: retryCount + 1)
                    }
                }
                return
            }
            presenter.present(vc, animated: true)
            return
        }
        if let mainWindow = self.context.sharedContext.mainWindow {
            mainWindow.presentNative(vc)
        } else {
            self.context.sharedContext.applicationBindings.presentNativeController(vc)
        }
    }

    private func presentPluginGUI(spec: [String: Any], retryCount: Int = 0) {
        let kind = (spec["kind"] as? String)?.lowercased() ?? (spec["pluginId"] as? String)?.lowercased() ?? ""
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
        if kind == "webview", let rawUrl = spec["url"] as? String, let url = URL(string: rawUrl), url.scheme?.lowercased() == "https" {
            let webVC = FullGramPluginWebViewController(url: url, onSendToChat: sendToChat)
            webVC.modalPresentationStyle = .fullScreen
            self.presentNativeUIKitController(webVC, retryCount: retryCount)
            return
        } else if kind.contains("deadline") || kind.contains("dl") {
            vc = FullGramDeadlinesGUIViewController(onSendToChat: sendToChat)
        } else {
            vc = FullGramCustomPluginGUIViewController(spec: spec, onSendToChat: sendToChat)
        }

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        self.presentNativeUIKitController(nav, retryCount: retryCount)
    }

    private func presentPluginActionsPicker(peerId: PeerId?, chatTitle: String) {
        guard let rootView = self.rootController?.view else { return }
        let sheet = UIAlertController(title: "Плагины и ИИ FullGram", message: chatTitle, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "✨ Сводка чата (ИИ)", style: .default) { [weak self] _ in
            self?.openWindow(
                initialPrompt: "Сделай подробную краткую сводку этого чата по последним сообщениям",
                explicitPeerId: peerId,
                autoSend: true
            )
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
            pop.sourceView = rootView
            pop.sourceRect = CGRect(x: rootView.bounds.midX, y: rootView.bounds.midY, width: 1.0, height: 1.0)
        }
        self.presentNativeUIKitController(sheet)
    }

    private func executePluginCommand(_ rawCommand: String, peerId: PeerId?, chatTitle: String) {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let commandText = trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
        let lower = commandText.lowercased()
        let needsStats = lower.hasPrefix(".plug") || lower.hasPrefix(".info-chat") || lower.hasPrefix(".export") || lower.hasPrefix(".chatstats")

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
                    guard let self else { return }
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
                    self.presentNativeUIKitController(alert)
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
        if let pop = controller.popoverPresentationController, let host = self.hostContainerView() {
            pop.sourceView = host
            pop.sourceRect = self.petView?.frame ?? CGRect(x: host.bounds.midX, y: host.bounds.midY, width: 1.0, height: 1.0)
        }
        self.presentNativeUIKitController(controller)
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
            self.presentNativeUIKitController(alert)

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

        let exportedMessages: [FullGramPluginValue] = sortedByTime.suffix(50).map { msg in
            let authorName = msg.author.map { EnginePeer($0).compactDisplayTitle } ?? (msg.flags.contains(.Incoming) ? "Собеседник" : "Вы")
            let dateStr = df.string(from: Date(timeIntervalSince1970: TimeInterval(msg.timestamp)))
            let textStr = msg.text.isEmpty ? "[Медиа]" : msg.text
            return .table(FullGramPluginTableBox(dict: [
                "date": .string(dateStr),
                "author": .string(authorName),
                "text": .string(textStr)
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
            "round_count": .int(Int64(roundCount)),
            "messages": .table(FullGramPluginTableBox(array: exportedMessages))
        ]
    }
}

// MARK: - Graphical UI Engine for Lua & Python Plugins (`fullgram.open_ui`)

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
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.closeTapped))
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
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeadlineCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "DeadlineCell")
        let item = self.items[indexPath.row]
        let icon = item.done ? "✅" : "⏳"
        var config = cell.defaultContentConfiguration()
        config.text = "\(icon) \(item.task)"
        config.textProperties.font = .systemFont(ofSize: 16.0, weight: .semibold)
        config.secondaryText = "Срок: \(item.due)"
        config.secondaryTextProperties.color = item.done ? .systemGreen : .systemOrange
        cell.contentConfiguration = config
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
    private let scrollView = UIScrollView()
    private let outputCard = UIView()
    private let outputLabel = UILabel()
    private let inputField = UITextField()
    private var lastChatText: String = ""

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
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Закрыть", style: .plain, target: self, action: #selector(self.closeTapped))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "В чат", style: .plain, target: self, action: #selector(self.sendToChatTapped))

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.keyboardDismissMode = .onDrag
        self.view.addSubview(self.scrollView)
        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 14.0),
            stack.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -20.0),
            stack.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor, constant: 16.0),
            stack.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor, constant: -16.0),
            stack.widthAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.widthAnchor, constant: -32.0)
        ])

        self.outputCard.backgroundColor = .secondarySystemGroupedBackground
        self.outputCard.layer.cornerRadius = 14.0
        self.outputLabel.font = .monospacedSystemFont(ofSize: 14.0, weight: .medium)
        self.outputLabel.numberOfLines = 0
        self.outputLabel.text = (self.spec["subtitle"] as? String) ?? "Графический интерфейс плагина активен."
        self.outputLabel.translatesAutoresizingMaskIntoConstraints = false
        self.outputCard.addSubview(self.outputLabel)
        NSLayoutConstraint.activate([
            self.outputLabel.topAnchor.constraint(equalTo: self.outputCard.topAnchor, constant: 14.0),
            self.outputLabel.bottomAnchor.constraint(equalTo: self.outputCard.bottomAnchor, constant: -14.0),
            self.outputLabel.leadingAnchor.constraint(equalTo: self.outputCard.leadingAnchor, constant: 14.0),
            self.outputLabel.trailingAnchor.constraint(equalTo: self.outputCard.trailingAnchor, constant: -14.0)
        ])
        stack.addArrangedSubview(self.outputCard)

        self.inputField.borderStyle = .roundedRect
        self.inputField.clearButtonMode = .whileEditing
        self.inputField.placeholder = (self.spec["placeholder"] as? String) ?? "Введите аргумент…"
        if let initialInput = self.spec["default_input"] as? String, !initialInput.isEmpty {
            self.inputField.text = initialInput
        }
        self.inputField.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        stack.addArrangedSubview(self.inputField)

        if let buttons = self.spec["buttons"] as? [[String: Any]] {
            for b in buttons {
                if let rowItems = b["items"] as? [[String: Any]], !rowItems.isEmpty {
                    let row = UIStackView()
                    row.axis = .horizontal
                    row.distribution = .fillEqually
                    row.spacing = 8.0
                    for item in rowItems {
                        row.addArrangedSubview(self.makePluginButton(spec: item))
                    }
                    stack.addArrangedSubview(row)
                } else {
                    stack.addArrangedSubview(self.makePluginButton(spec: b))
                }
            }
        }
    }

    private func makePluginButton(spec b: [String: Any]) -> UIButton {
        let btnTitle = (b["title"] as? String) ?? "Действие"
        let actionId = (b["id"] as? String) ?? btnTitle
        let colorName = (b["color"] as? String)?.lowercased() ?? "blue"
        let bgColor: UIColor
        switch colorName {
        case "green": bgColor = .systemGreen
        case "orange": bgColor = .systemOrange
        case "red": bgColor = .systemRed
        case "purple": bgColor = .systemPurple
        case "indigo": bgColor = .systemIndigo
        case "teal": bgColor = .systemTeal
        case "gray": bgColor = .systemGray
        default: bgColor = .systemBlue
        }
        let btn = UIButton(type: .system)
        btn.setTitle(btnTitle, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13.5, weight: .semibold)
        btn.titleLabel?.numberOfLines = 2
        btn.titleLabel?.textAlignment = .center
        btn.backgroundColor = bgColor
        btn.layer.cornerRadius = 11.0
        btn.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        btn.accessibilityIdentifier = actionId
        btn.addTarget(self, action: #selector(self.customButtonTapped(_:)), for: .touchUpInside)
        return btn
    }

    @objc private func closeTapped() {
        self.dismiss(animated: true)
    }

    @objc private func sendToChatTapped() {
        let candidate = self.lastChatText.isEmpty ? (self.outputLabel.text ?? "") : self.lastChatText
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.onSendToChat(trimmed)
        self.dismiss(animated: true)
    }

    @objc private func customButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        let pluginId = (self.spec["pluginId"] as? String) ?? ""
        let actionId = sender.accessibilityIdentifier ?? "click"
        let inputText = self.inputField.text ?? ""
        let res = FullGramPluginManager.shared.dispatchUIEvent(
            pluginId: pluginId,
            action: actionId,
            payload: ["input": .string(inputText)]
        )
        switch res {
        case let .table(box):
            let display = box.get(key: .string("text")).asString
            if !display.isEmpty {
                self.outputLabel.text = display
            }
            let chat = box.get(key: .string("chat")).asString
            if !chat.isEmpty {
                self.lastChatText = chat
            } else if !display.isEmpty {
                self.lastChatText = display
            }
            if box.get(key: .string("send_to_chat")).isTruthy && !self.lastChatText.isEmpty {
                self.onSendToChat(self.lastChatText)
                self.dismiss(animated: true)
            }
        default:
            let str = res.asString
            if !str.isEmpty {
                self.outputLabel.text = str
                self.lastChatText = str
            }
        }
    }
}

@MainActor
private final class FullGramPluginWebMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: FullGramPluginWebViewController?
    init(owner: FullGramPluginWebViewController) {
        self.owner = owner
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        self.owner?.handleScriptMessage(message.body)
    }
}

@MainActor
private final class FullGramPluginWebViewController: UIViewController {
    private let url: URL
    private let titleText: String
    private let onSendToChat: (String) -> Void
    private var webView: WKWebView?
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notifFeedback = UINotificationFeedbackGenerator()

    init(url: URL, title: String, onSendToChat: @escaping (String) -> Void) {
        self.url = url
        self.titleText = title
        self.onSendToChat = onSendToChat
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1.0)

        let contentController = WKUserContentController()
        let proxy = FullGramPluginWebMessageHandler(owner: self)
        contentController.add(proxy, name: "fullgramPlugin")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1.0)
        wv.scrollView.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1.0)
        wv.scrollView.bounces = false
        self.view.addSubview(wv)
        self.webView = wv

        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: self.view.topAnchor),
            wv.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])

        var req = URLRequest(url: self.url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        wv.load(req)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.isBeingDismissed {
            self.webView?.configuration.userContentController.removeScriptMessageHandler(forName: "fullgramPlugin")
        }
    }

    func handleScriptMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let action = dict["action"] as? String else { return }
        switch action {
        case "close":
            self.dismiss(animated: true)
        case "shareChat":
            if let text = dict["text"] as? String, !text.isEmpty {
                self.onSendToChat(text)
            }
        case "haptic":
            let kind = (dict["kind"] as? String) ?? "light"
            switch kind {
            case "heavy": self.impactHeavy.impactOccurred()
            case "medium": self.impactMedium.impactOccurred()
            case "success": self.notifFeedback.notificationOccurred(.success)
            case "error": self.notifFeedback.notificationOccurred(.error)
            default: self.impactLight.impactOccurred()
            }
        default:
            break
        }
    }
}
