import Foundation
import UIKit
import Display
import AsyncDisplayKit
@preconcurrency import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
@preconcurrency import AccountContext
import UndoUI

// MARK: - Хаб: Кошелёк Gram, Звёзды, Подарки FullGram, Апгрейд NFT, Номера +888 и Юзернеймы

private func fullGramSendGiftPayloadMessage(account: Account, peerId: EnginePeer.Id, payload: FullGramChatGiftPayload) {
    let (msgText, msgEntities) = payload.encodeMessageWithEntities()
    let _ = enqueueMessages(
        account: account,
        peerId: peerId,
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

private final class FullGramEconomyHubArguments {
    let grantGram: () -> Void
    let transferGram: () -> Void
    let grantStars: () -> Void
    let giftStars: () -> Void
    let grantToUser: () -> Void
    let openGiftMarket: () -> Void
    let openMyGifts: () -> Void
    let openNumbers: () -> Void
    let openUsernames: () -> Void
    let openTransactions: () -> Void

    init(
        grantGram: @escaping () -> Void,
        transferGram: @escaping () -> Void,
        grantStars: @escaping () -> Void,
        giftStars: @escaping () -> Void,
        grantToUser: @escaping () -> Void,
        openGiftMarket: @escaping () -> Void,
        openMyGifts: @escaping () -> Void,
        openNumbers: @escaping () -> Void,
        openUsernames: @escaping () -> Void,
        openTransactions: @escaping () -> Void
    ) {
        self.grantGram = grantGram
        self.transferGram = transferGram
        self.grantStars = grantStars
        self.giftStars = giftStars
        self.grantToUser = grantToUser
        self.openGiftMarket = openGiftMarket
        self.openMyGifts = openMyGifts
        self.openNumbers = openNumbers
        self.openUsernames = openUsernames
        self.openTransactions = openTransactions
    }
}

private enum FullGramEconomyHubEntry: ItemListNodeEntry {
    case walletHeader(String)
    case gramBalance(String, String)
    case grantGramAction(String)
    case transferGramAction(String)
    case starsBalance(String, String)
    case grantStarsAction(String)
    case giftStarsAction(String)
    case grantToUserAction(String)
    case transactionsLink(String, String)

    case marketHeader(String)
    case giftMarketLink(String, String)
    case myGiftsLink(String, String)
    case marketInfo(String)

    case fragmentHeader(String)
    case numbersLink(String, String)
    case usernamesLink(String, String)
    case fragmentInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .walletHeader, .gramBalance, .grantGramAction, .transferGramAction, .starsBalance, .grantStarsAction, .giftStarsAction, .grantToUserAction, .transactionsLink:
            return 0
        case .marketHeader, .giftMarketLink, .myGiftsLink, .marketInfo:
            return 1
        case .fragmentHeader, .numbersLink, .usernamesLink, .fragmentInfo:
            return 2
        }
    }

    var stableId: Int32 {
        switch self {
        case .walletHeader: return 0
        case .gramBalance: return 1
        case .grantGramAction: return 2
        case .transferGramAction: return 3
        case .starsBalance: return 4
        case .grantStarsAction: return 5
        case .giftStarsAction: return 6
        case .grantToUserAction: return 7
        case .transactionsLink: return 8
        case .marketHeader: return 100
        case .giftMarketLink: return 101
        case .myGiftsLink: return 102
        case .marketInfo: return 103
        case .fragmentHeader: return 200
        case .numbersLink: return 201
        case .usernamesLink: return 202
        case .fragmentInfo: return 203
        }
    }

    static func < (lhs: FullGramEconomyHubEntry, rhs: FullGramEconomyHubEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramEconomyHubArguments
        switch self {
        case let .walletHeader(text), let .marketHeader(text), let .fragmentHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .gramBalance(title, value), let .starsBalance(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {})
        case let .grantGramAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.grantGram)
        case let .transferGramAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.transferGram)
        case let .grantStarsAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.grantStars)
        case let .giftStarsAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.giftStars)
        case let .grantToUserAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.grantToUser)
        case let .transactionsLink(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openTransactions)
        case let .giftMarketLink(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openGiftMarket)
        case let .myGiftsLink(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openMyGifts)
        case let .numbersLink(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openNumbers)
        case let .usernamesLink(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.openUsernames)
        case let .marketInfo(text), let .fragmentInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramPresentGrantEconomyMenu(
    context: AccountContext,
    targetPeerId: Int64,
    targetDisplayName: String,
    presentNative: (@MainActor @Sendable (UIViewController) -> Void)?
) {
    let isPrivileged = fullGramCanOpenAdmin(context: context) || fullGramIsSelfSponsorPlus(context: context)
    guard isPrivileged else { return }
    let actorPeerId = context.account.peerId.id._internalGetInt64Value()
    let isSelfTarget = (FullGramGrantedNFTStore.normalizedTelegramId(for: targetPeerId) == FullGramGrantedNFTStore.normalizedTelegramId(for: actorPeerId))
    let useAdmin = fullGramCanOpenAdmin(context: context)

    let showAlert: @Sendable (String, String) -> Void = { title, msg in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default))
                presentNative?(a)
            }
        }
    }

    let sendAction: (String, Double?, String?, String?, Double?, Bool, String, (@Sendable () -> Void)?) -> Void = { action, amount, username, number, priceTon, isPrimary, successText, onSuccess in
        FullGramAdmin.shared.grantEconomy(
            actorPeerId: actorPeerId,
            targetPeerId: targetPeerId,
            useAdminEndpoint: useAdmin,
            action: action,
            amount: amount,
            username: username,
            number: number,
            priceTon: priceTon,
            isPrimary: isPrimary
        ) { result in
            switch result {
            case .success:
                onSuccess?()
                FullGramEconomy.shared.refreshCloudNow(selfPeerId: actorPeerId) { _ in }
                showAlert("Готово", successText)
            case let .failure(error):
                showAlert("Ошибка", error.localizedDescription)
            }
        }
    }

    let sheet = UIAlertController(
        title: "Выдача экономики → \(targetDisplayName)",
        message: "Доступно Администратору и Спонсор+",
        preferredStyle: .actionSheet
    )
    sheet.addAction(UIAlertAction(title: "Выдать баланс Gram / TON", style: .default) { _ in
        let a = UIAlertController(title: "Баланс Gram → \(targetDisplayName)", message: "Введите сумму в TON / Gram:", preferredStyle: .alert)
        a.addTextField { tf in
            tf.keyboardType = .decimalPad
            tf.placeholder = "5000"
        }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        a.addAction(UIAlertAction(title: "Выдать", style: .default) { [weak a] _ in
            let raw = (a?.textFields?.first?.text ?? "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let val = Double(raw), val.isFinite, val >= 0, val <= 1e12 else { return }
            sendAction("set_gram", val, nil, nil, nil, true, "Пользователю \(targetDisplayName) установлен баланс \(String(format: "%.2f", val)) TON.") {
                if isSelfTarget {
                    FullGramEconomy.shared.setGramBalance(val)
                }
            }
        })
        presentNative?(a)
    })
    sheet.addAction(UIAlertAction(title: "Выдать Звёзды Telegram (★)", style: .default) { _ in
        let a = UIAlertController(title: "Звёзды → \(targetDisplayName)", message: "Введите количество ★:", preferredStyle: .alert)
        a.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.placeholder = "10000"
        }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        a.addAction(UIAlertAction(title: "Выдать", style: .default) { [weak a] _ in
            let raw = (a?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let val = Int64(raw), val >= 0, val <= 1_000_000_000 else { return }
            sendAction("set_stars", Double(val), nil, nil, nil, true, "Пользователю \(targetDisplayName) установлено \(val) ★.") {
                if isSelfTarget {
                    FullGramEconomy.shared.setStarsBalance(val)
                }
            }
        })
        presentNative?(a)
    })
    sheet.addAction(UIAlertAction(title: "Выдать @юзернейм с любой ценой", style: .default) { _ in
        let a = UIAlertController(title: "Юзернейм → \(targetDisplayName)", message: "Введите @юзернейм и любую цену в TON:", preferredStyle: .alert)
        a.addTextField { tf in
            tf.placeholder = "@username"
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        a.addTextField { tf in
            tf.keyboardType = .decimalPad
            tf.placeholder = "Цена в TON (например: 1500)"
            tf.text = "1500"
        }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        a.addAction(UIAlertAction(title: "Выдать", style: .default) { [weak a] _ in
            let uname = a?.textFields?.first?.text ?? ""
            let rawPrice = (a?.textFields?.dropFirst().first?.text ?? "0").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedPrice = rawPrice.isEmpty ? 0.0 : Double(rawPrice)
            guard let price = parsedPrice, price.isFinite, price >= 0, price <= 1e12 else { return }
            let clean = uname.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "@"))).lowercased()
            guard clean.count >= 4 else { return }
            sendAction("grant_username", nil, clean, nil, price, true, "Пользователю \(targetDisplayName) выдан @\(clean) за \(String(format: "%.0f", price)) TON.") {
                if isSelfTarget {
                    let _ = FullGramEconomy.shared.buyCollectibleUsername(rawUsername: clean, priceTon: price, isPrimary: true, deductFromBalance: false)
                }
            }
        })
        presentNative?(a)
    })
    sheet.addAction(UIAlertAction(title: "Выдать номер +888 с любой ценой", style: .default) { _ in
        let a = UIAlertController(title: "Номер +888 → \(targetDisplayName)", message: "Введите номер +888 и цену в TON:", preferredStyle: .alert)
        a.addTextField { tf in
            tf.keyboardType = .phonePad
            tf.text = "+888 \(Int.random(in: 1000...9999)) \(Int.random(in: 1000...9999))"
        }
        a.addTextField { tf in
            tf.keyboardType = .decimalPad
            tf.placeholder = "Цена в TON (например: 250)"
            tf.text = "250"
        }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        a.addAction(UIAlertAction(title: "Выдать", style: .default) { [weak a] _ in
            let num = a?.textFields?.first?.text ?? ""
            let rawPrice = (a?.textFields?.dropFirst().first?.text ?? "0").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedPrice = rawPrice.isEmpty ? 0.0 : Double(rawPrice)
            guard let price = parsedPrice, price.isFinite, price >= 0, price <= 1e12 else { return }
            sendAction("grant_number", nil, nil, num, price, true, "Пользователю \(targetDisplayName) выдан номер \(num).") {
                if isSelfTarget {
                    let _ = FullGramEconomy.shared.buyAnonymousNumber(rawNumber: num, priceTon: price, deductFromBalance: false)
                }
            }
        })
        presentNative?(a)
    })
    sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    presentNative?(sheet)
}

public func fullGramEconomyHubController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: (@MainActor @Sendable (UIViewController) -> Void)?

    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramEconomy.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let selfRawId = context.account.peerId.id._internalGetInt64Value()
    let args = FullGramEconomyHubArguments(
        grantGram: {
            let alert = UIAlertController(title: "Кошелёк Gram / TON", message: "Введите баланс Gram/TON или обнулите кошелёк:", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.keyboardType = .decimalPad
                tf.placeholder = "Например: 5000"
                tf.text = FullGramEconomy.shared.gramBalance > 0 ? String(format: "%.2f", FullGramEconomy.shared.gramBalance) : ""
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Установить", style: .default) { [weak alert] _ in
                let raw = (alert?.textFields?.first?.text ?? "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Double(raw), val.isFinite, val >= 0, val <= 1e12 {
                    FullGramEconomy.shared.setGramBalance(val)
                }
            })
            if FullGramEconomy.shared.gramBalance > 0 {
                alert.addAction(UIAlertAction(title: "Обнулить баланс TON", style: .destructive) { _ in
                    FullGramEconomy.shared.setGramBalance(0.0, note: "Сброс баланса TON")
                })
            }
            presentNativeImpl?(alert)
        },
        transferGram: {
            let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.onlyWriteable, .excludeDisabled],
                hasChatListSelector: true,
                hasContactSelector: true,
                hasGlobalSearch: true,
                title: "Кому перевести TON / Gram?"
            ))
            selector.peerSelected = { [weak selector] peer, _ in
                selector?.dismiss()
                let peerTitle = peer.compactDisplayTitle
                let alert = UIAlertController(
                    title: "Перевести TON → \(peerTitle)",
                    message: String(format: "Ваш баланс: %.2f TON\nСколько TON перевести?", FullGramEconomy.shared.gramBalance),
                    preferredStyle: .alert
                )
                alert.addTextField { tf in
                    tf.keyboardType = .decimalPad
                    tf.placeholder = "Например: 50"
                }
                alert.addTextField { tf in
                    tf.placeholder = "Комментарий (необязательно)"
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Перевести", style: .default) { [weak alert] _ in
                    let rawAmt = (alert?.textFields?.first?.text ?? "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                    let amt = Double(rawAmt) ?? 0.0
                    let comment = (alert?.textFields?.dropFirst().first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard amt.isFinite, amt > 0, amt <= 1e12 else { return }
                    if FullGramEconomy.shared.transferGram(peerName: peerTitle, amount: amt) {
                        FullGramAdmin.shared.performEconomyAction(
                            actorPeerId: selfRawId,
                            toPeerId: peer.id.id._internalGetInt64Value(),
                            action: "transfer_gram",
                            amount: amt
                        )
                        let payload = FullGramChatGiftPayload(
                            kind: .ton,
                            giftRecordId: UUID().uuidString,
                            title: String(format: "%.2f TON", amt),
                            emoji: "💎",
                            tonAmount: amt,
                            comment: comment,
                            senderName: "FullGram"
                        )
                        fullGramSendGiftPayloadMessage(account: context.account, peerId: peer.id, payload: payload)
                    } else {
                        let err = UIAlertController(title: "Недостаточно TON", message: "Сначала пополните баланс Gram / TON в кошельке.", preferredStyle: .alert)
                        err.addAction(UIAlertAction(title: "OK", style: .default))
                        presentNativeImpl?(err)
                    }
                })
                presentNativeImpl?(alert)
            }
            presentControllerImpl?(selector)
        },
        grantStars: {
            let alert = UIAlertController(title: "Звёзды Telegram (FullGram)", message: "Введите количество звёзд (★) для баланса:", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.keyboardType = .numberPad
                tf.placeholder = "Например: 25000"
                tf.text = FullGramEconomy.shared.starsBalance > 0 ? "\(FullGramEconomy.shared.starsBalance)" : ""
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Выдать ★", style: .default) { [weak alert] _ in
                let raw = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int64(raw), val >= 0 {
                    FullGramEconomy.shared.setStarsBalance(val)
                }
            })
            if FullGramEconomy.shared.starsBalance > 0 {
                alert.addAction(UIAlertAction(title: "Обнулить звёзды ★", style: .destructive) { _ in
                    FullGramEconomy.shared.setStarsBalance(0, note: "Сброс баланса звёзд")
                })
            }
            presentNativeImpl?(alert)
        },
        giftStars: {
            let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.onlyWriteable, .excludeDisabled],
                hasChatListSelector: true,
                hasContactSelector: true,
                hasGlobalSearch: true,
                title: "Кому подарить Звёзды?"
            ))
            selector.peerSelected = { [weak selector] peer, _ in
                selector?.dismiss()
                let peerTitle = peer.compactDisplayTitle
                let alert = UIAlertController(
                    title: "Подарить ★ → \(peerTitle)",
                    message: "Ваш баланс: \(FullGramEconomy.shared.starsBalance) ★\nСколько звёзд подарить?",
                    preferredStyle: .alert
                )
                alert.addTextField { tf in
                    tf.keyboardType = .numberPad
                    tf.placeholder = "Например: 100"
                }
                alert.addTextField { tf in
                    tf.placeholder = "Комментарий (необязательно)"
                }
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
                alert.addAction(UIAlertAction(title: "Подарить", style: .default) { [weak alert] _ in
                    let amt = Int64((alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    let comment = (alert?.textFields?.dropFirst().first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard amt > 0 else { return }
                    if FullGramEconomy.shared.giftStars(peerName: peerTitle, amount: amt) {
                        FullGramAdmin.shared.performEconomyAction(
                            actorPeerId: selfRawId,
                            toPeerId: peer.id.id._internalGetInt64Value(),
                            action: "transfer_stars",
                            amount: Double(amt)
                        )
                        let payload = FullGramChatGiftPayload(
                            kind: .stars,
                            giftRecordId: UUID().uuidString,
                            title: "\(amt) Звёзд Telegram",
                            emoji: "⭐️",
                            number: nil,
                            starsPrice: amt,
                            comment: comment,
                            canUpgrade: false,
                            senderName: "FullGram"
                        )
                        fullGramSendGiftPayloadMessage(account: context.account, peerId: peer.id, payload: payload)
                    } else {
                        let err = UIAlertController(title: "Недостаточно звёзд", message: "Сначала выдайте звёзды на баланс в кошельке.", preferredStyle: .alert)
                        err.addAction(UIAlertAction(title: "OK", style: .default))
                        presentNativeImpl?(err)
                    }
                })
                presentNativeImpl?(alert)
            }
            presentControllerImpl?(selector)
        },
        grantToUser: {
            let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.onlyWriteable, .excludeDisabled],
                hasChatListSelector: true,
                hasContactSelector: true,
                hasGlobalSearch: true,
                title: "Кому выдать (Админ / Спонсор+)?"
            ))
            selector.peerSelected = { [weak selector] peer, _ in
                selector?.dismiss()
                fullGramPresentGrantEconomyMenu(
                    context: context,
                    targetPeerId: peer.id.id._internalGetInt64Value(),
                    targetDisplayName: peer.compactDisplayTitle,
                    presentNative: presentNativeImpl
                )
            }
            presentControllerImpl?(selector)
        },
        openGiftMarket: {
            pushImpl?(fullGramGiftMarketController(context: context, targetPeerId: nil, targetPeerName: nil))
        },
        openMyGifts: {
            pushImpl?(fullGramMyGiftsAndUpgradesController(context: context, peerId: context.account.peerId))
        },
        openNumbers: {
            pushImpl?(fullGramCollectibleNumbersController(context: context))
        },
        openUsernames: {
            pushImpl?(fullGramCollectibleUsernamesController(context: context))
        },
        openTransactions: {
            pushImpl?(fullGramEconomyTransactionsController(context: context))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let eco = FullGramEconomy.shared
        let gramStr = String(format: "%.2f TON", eco.gramBalance)
        let starsStr = "\(eco.starsBalance) ★"
        let activeNumberStr = eco.activeCustomNumber?.number ?? "Нет"
        let activeUsernamesCount = eco.activeCustomUsernames.count
        let upgradesCount = eco.ownedGifts.filter { $0.canUpgradeToNFT && !$0.isUpgraded }.count
        let isPrivileged = fullGramCanOpenAdmin(context: context) || fullGramIsSelfSponsorPlus(context: context)

        var entries: [FullGramEconomyHubEntry] = [
            .walletHeader("КОШЕЛЁК GRAM И ЗВЁЗДЫ (FULLGRAM)"),
            .gramBalance("Баланс Gram / TON", gramStr),
            .grantGramAction("Настроить / сбросить баланс Gram…"),
            .transferGramAction("Перевести TON / Gram пользователю…"),
            .starsBalance("Баланс Звёзд Telegram", starsStr),
            .grantStarsAction("Настроить / сбросить баланс ★…"),
            .giftStarsAction("Подарить звёзды другу или себе…")
        ]
        if isPrivileged {
            entries.append(.grantToUserAction("Выдать Gram / ★ / @username / +888 пользователю…"))
        }
        entries.append(contentsOf: [
            .transactionsLink("История операций", "\(eco.transactions.count)"),

            .marketHeader("ПОДАРКИ FULLGRAM И АПГРЕЙДЫ NFT"),
            .giftMarketLink("Купить подарок (FullGram)", "\(FullGramEconomy.defaultCatalog.count) шт."),
            .myGiftsLink("Мои подарки и апгрейды NFT", upgradesCount > 0 ? "\(eco.ownedGifts.count) (\(upgradesCount) улучш.)" : "\(eco.ownedGifts.count)"),
            .marketInfo("Покупайте подарки по реальным ценам Telegram в ★, дарите себе или в чат — в чате появляется настоящая плашка подарка, а подарки можно улучшать в коллекционные NFT."),

            .fragmentHeader("КАСТОМНЫЕ НОМЕРА И ЮЗЕРНЕЙМЫ (FRAGMENT)"),
            .numbersLink("Анонимные номера (+888)", activeNumberStr),
            .usernamesLink("Коллекционные @юзернеймы", activeUsernamesCount > 0 ? "\(activeUsernamesCount) акт." : "Нет"),
            .fragmentInfo("Купленные кастомные номера +888 и @юзернеймы с ценой в TON отображаются прямо в вашем профиле с карточкой владения Fragment.")
        ])

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Кошелёк и Fragment"),
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
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}

// MARK: - Маркет «Купить подарок FullGram» (реальные цены в ★)

private final class FullGramGiftMarketArguments {
    let pickRecipient: () -> Void
    let grantStarsQuick: () -> Void
    let buyGift: (FullGramCatalogGift, Int64?) -> Void

    init(
        pickRecipient: @escaping () -> Void,
        grantStarsQuick: @escaping () -> Void,
        buyGift: @escaping (FullGramCatalogGift, Int64?) -> Void
    ) {
        self.pickRecipient = pickRecipient
        self.grantStarsQuick = grantStarsQuick
        self.buyGift = buyGift
    }
}

private enum FullGramGiftMarketEntry: ItemListNodeEntry {
    case balanceHeader(String)
    case balanceRow(String, String)
    case grantStars(String)
    case recipientRow(String, String)
    case catalogHeader(String)
    case catalogItem(Int32, FullGramCatalogGift, Int64?)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .balanceHeader, .balanceRow, .grantStars, .recipientRow: return 0
        case .catalogHeader, .catalogItem, .info: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .balanceHeader: return 0
        case .balanceRow: return 1
        case .grantStars: return 2
        case .recipientRow: return 3
        case .catalogHeader: return 100
        case let .catalogItem(idx, _, _): return 101 + idx
        case .info: return 900
        }
    }

    static func < (lhs: FullGramGiftMarketEntry, rhs: FullGramGiftMarketEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramGiftMarketArguments
        switch self {
        case let .balanceHeader(text), let .catalogHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .balanceRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {})
        case let .grantStars(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.grantStarsQuick)
        case let .recipientRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickRecipient)
        case let .catalogItem(_, gift, realGiftId):
            let nftTag = gift.canUpgradeToNFT ? " • NFT" : ""
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "\(gift.emoji) \(FullGramGrantedNFT.decoratedTitle(gift.title))",
                label: "\(gift.starsPrice) ★\(nftTag)",
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: { args.buyGift(gift, realGiftId) }
            )
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct FullGramGiftRecipient: Equatable {
    let id: EnginePeer.Id
    let name: String
}

public func fullGramGiftMarketController(
    context: AccountContext,
    targetPeerId: EnginePeer.Id?,
    targetPeerName: String?
) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: (@MainActor @Sendable (UIViewController) -> Void)?

    let initialRecipient = FullGramGiftRecipient(
        id: targetPeerId ?? context.account.peerId,
        name: (targetPeerId == nil || targetPeerId == context.account.peerId) ? "Себе (Избранное)" : (targetPeerName ?? "Получатель")
    )
    let recipientPromise = ValuePromise<FullGramGiftRecipient>(initialRecipient, ignoreRepeated: false)
    let latestRecipient = Atomic<FullGramGiftRecipient>(value: initialRecipient)

    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramEconomy.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let completePurchase: (FullGramCatalogGift, Int64?, String, Bool) -> Void = { gift, realGiftId, comment, preUpgrade in
        let rec = latestRecipient.with { $0 }
        let total = gift.starsPrice + (preUpgrade && gift.canUpgradeToNFT ? gift.upgradeStars : 0)
        guard FullGramEconomy.shared.starsBalance >= total else {
            let err = UIAlertController(
                title: "Недостаточно звёзд",
                message: "Нужно \(total) ★, на балансе \(FullGramEconomy.shared.starsBalance) ★. Выдайте звёзды вверху экрана!",
                preferredStyle: .alert
            )
            err.addAction(UIAlertAction(title: "OK", style: .default))
            presentNativeImpl?(err)
            return
        }
        guard let owned = FullGramEconomy.shared.purchaseGift(
            catalogGift: gift,
            realGiftId: realGiftId,
            forPeerId: rec.id.toInt64(),
            recipientName: rec.name,
            senderName: "FullGram",
            comment: comment,
            preUpgrade: preUpgrade
        ) else {
            return
        }

        let payload = FullGramChatGiftPayload(
            kind: owned.isUpgraded ? .nft : .gift,
            giftRecordId: owned.id,
            title: owned.title,
            emoji: owned.emoji,
            number: owned.nftNumber,
            starsPrice: owned.priceStars,
            modelName: owned.modelName,
            backdropName: owned.backdropName,
            backdropInnerHex: owned.backdropInnerHex,
            backdropOuterHex: owned.backdropOuterHex,
            patternName: owned.patternName,
            rarityText: owned.isUpgraded ? "Коллекционный NFT" : "Подарок Telegram",
            comment: owned.comment,
            canUpgrade: owned.canUpgradeToNFT && !owned.isUpgraded,
            senderName: "FullGram",
            slug: owned.slug,
            realGiftId: owned.realGiftId
        )
        fullGramSendGiftPayloadMessage(account: context.account, peerId: rec.id, payload: payload)

        let done = UIAlertController(
            title: owned.isUpgraded ? "🎁 NFT отправлен!" : "🎁 Подарок отправлен!",
            message: owned.isUpgraded
                ? "\(owned.emoji) \(owned.title) #\(owned.nftNumber ?? 1) (\(owned.modelName ?? "") · \(owned.backdropName ?? "")) отправлен в чат и добавлен в профиль."
                : "\(owned.emoji) \(owned.title) (\(owned.priceStars) ★) отправлен в чат! \(owned.canUpgradeToNFT ? "Вы можете улучшить его в NFT." : "")",
            preferredStyle: .alert
        )
        if owned.canUpgradeToNFT && !owned.isUpgraded {
            done.addAction(UIAlertAction(title: "Улучшить до NFT (25 ★)", style: .default) { _ in
                pushImpl?(fullGramGiftUpgradeController(context: context, ownedGift: owned))
            })
        }
        done.addAction(UIAlertAction(title: "Отлично", style: .cancel))
        presentNativeImpl?(done)
    }

    let args = FullGramGiftMarketArguments(
        pickRecipient: {
            let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.onlyWriteable, .excludeDisabled],
                hasChatListSelector: true,
                hasContactSelector: true,
                hasGlobalSearch: true,
                title: "Кому подарить подарок?"
            ))
            selector.peerSelected = { [weak selector] peer, _ in
                let isSelf = peer.id == context.account.peerId
                let title = isSelf ? "Себе (Избранное)" : peer.compactDisplayTitle
                let pair = FullGramGiftRecipient(id: peer.id, name: title)
                let _ = latestRecipient.swap(pair)
                recipientPromise.set(pair)
                selector?.dismiss()
            }
            presentControllerImpl?(selector)
        },
        grantStarsQuick: {
            let alert = UIAlertController(title: "Выдать звёзды FullGram", message: "Введите любое число ★:", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.keyboardType = .numberPad
                tf.placeholder = "Например: 10000"
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Выдать", style: .default) { [weak alert] _ in
                let raw = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let val = Int64(raw), val >= 0 {
                    FullGramEconomy.shared.setStarsBalance(val)
                }
            })
            presentNativeImpl?(alert)
        },
        buyGift: { gift, realGiftId in
            let rec = latestRecipient.with { $0 }
            let upgradeNote = gift.canUpgradeToNFT
                ? "\nМожно сразу улучшить до NFT (+\(gift.upgradeStars) ★) — появятся случайные модель, фон, узор и #номер."
                : ""
            let alert = UIAlertController(
                title: "\(gift.emoji) \(gift.title) — \(gift.starsPrice) ★",
                message: "Получатель: \(rec.name)\(upgradeNote)",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "Подпись к подарку (необязательно)"
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Купить за \(gift.starsPrice) ★", style: .default) { [weak alert] _ in
                let comment = alert?.textFields?.first?.text ?? ""
                completePurchase(gift, realGiftId, comment, false)
            })
            if gift.canUpgradeToNFT {
                let total = gift.starsPrice + gift.upgradeStars
                alert.addAction(UIAlertAction(title: "Купить + NFT (\(total) ★)", style: .default) { [weak alert] _ in
                    let comment = alert?.textFields?.first?.text ?? ""
                    completePurchase(gift, realGiftId, comment, true)
                })
            }
            presentNativeImpl?(alert)
        }
    )

    let cachedGiftsSignal: Signal<[StarGift.Gift], NoError> = context.engine.payments.cachedStarGifts()
    |> map { items in
        return (items ?? []).compactMap { entry in
            if case let .generic(g) = entry { return g }
            return nil
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, recipientPromise.get(), changed.get(), cachedGiftsSignal)
    |> deliverOnMainQueue
    |> map { presentationData, rec, _, cachedGeneric -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var catalog: [(FullGramCatalogGift, Int64?)] = FullGramEconomy.defaultCatalog.map { cat in
            let matched = cachedGeneric.first { g in
                g.price == cat.starsPrice && (g.upgradeStars != nil) == cat.canUpgradeToNFT
            } ?? cachedGeneric.first
            return (cat, matched?.id)
        }
        // Append any extra real cached Telegram StarGifts with real prices if available
        let knownPrices = Set(FullGramEconomy.defaultCatalog.map { $0.starsPrice })
        for realGift in cachedGeneric {
            let titleText = realGift.title?.isEmpty == false ? realGift.title! : "Подарок #\(realGift.id % 1000)"
            if !knownPrices.contains(realGift.price) {
                catalog.append((
                    FullGramCatalogGift(
                        key: "tg_\(realGift.id)",
                        title: titleText,
                        emoji: "🎁",
                        starsPrice: realGift.price,
                        canUpgradeToNFT: realGift.upgradeStars != nil,
                        upgradeStars: realGift.upgradeStars ?? 25,
                        suggestedRealGiftIds: [realGift.id]
                    ),
                    realGift.id
                ))
            }
        }

        var entries: [FullGramGiftMarketEntry] = [
            .balanceHeader("ВАШ БАЛАНС И ПОЛУЧАТЕЛЬ"),
            .balanceRow("Звёзды FullGram", "\(FullGramEconomy.shared.starsBalance) ★"),
            .grantStars("Пополнить / выдать звёзды…"),
            .recipientRow("Получатель подарка", rec.name),
            .catalogHeader("КУПИТЬ ПОДАРОК FULLGRAM (РЕАЛЬНЫЕ ЦЕНЫ ★)")
        ]
        for (idx, pair) in catalog.enumerated() {
            entries.append(.catalogItem(Int32(idx), pair.0, pair.1))
        }
        entries.append(.info("Цены соответствуют официальному каталогу подарков Telegram Stars (15 ★ – 2500 ★). Покупка происходит полностью локально за липовые звёзды FullGram."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Подарки FullGram"),
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
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}

// MARK: - Мои подарки и Система апгрейда до NFT (как в оригинальном Telegram)

private final class FullGramMyGiftsArguments {
    let openGift: (FullGramOwnedGift) -> Void
    let openMarket: () -> Void
    init(openGift: @escaping (FullGramOwnedGift) -> Void, openMarket: @escaping () -> Void) {
        self.openGift = openGift
        self.openMarket = openMarket
    }
}

private enum FullGramMyGiftsEntry: ItemListNodeEntry {
    case buyMore(String)
    case header(String)
    case giftRow(Int32, FullGramOwnedGift)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .buyMore: return 0
        default: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .buyMore: return 0
        case .header: return 10
        case let .giftRow(idx, _): return 20 + idx
        case .empty: return 999
        }
    }

    static func < (lhs: FullGramMyGiftsEntry, rhs: FullGramMyGiftsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramMyGiftsArguments
        switch self {
        case let .buyMore(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.openMarket)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .giftRow(_, g):
            let status: String
            if g.isUpgraded {
                status = "NFT #\(g.nftNumber ?? 1) • \(g.modelName ?? "")"
            } else if g.canUpgradeToNFT {
                status = "Улучшить за \(g.upgradeStars) ★"
            } else {
                status = "Подарок (\(g.priceStars) ★)"
            }
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "\(g.emoji) \(FullGramGrantedNFT.decoratedTitle(g.title)) → \(g.recipientName)",
                label: status,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: { args.openGift(g) }
            )
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramMyGiftsAndUpgradesController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: (@MainActor @Sendable (UIViewController) -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramEconomy.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramMyGiftsArguments(
        openGift: { gift in
            let sheet = UIAlertController(
                title: "\(gift.emoji) \(FullGramGrantedNFT.decoratedTitle(gift.title))",
                message: gift.isUpgraded
                    ? "NFT #\(gift.nftNumber ?? 1) • \(gift.modelName ?? "") • \(gift.backdropName ?? "")"
                    : "Подарок за \(gift.priceStars) ★ → \(gift.recipientName)",
                preferredStyle: .actionSheet
            )
            if gift.isUpgraded || gift.canUpgradeToNFT {
                sheet.addAction(UIAlertAction(title: gift.isUpgraded ? "Настроить модель / фон / узор" : "Улучшить до NFT", style: .default) { _ in
                    pushImpl?(fullGramGiftUpgradeController(context: context, ownedGift: gift))
                })
            }
            sheet.addAction(UIAlertAction(title: gift.pinnedToProfile ? "Открепить из профиля" : "Закрепить в профиле", style: .default) { _ in
                FullGramEconomy.shared.togglePinGift(id: gift.id)
            })
            let isHidden = gift.hiddenFromProfile ?? false
            sheet.addAction(UIAlertAction(title: isHidden ? "Показать в профиле" : "Скрыть из профиля", style: .default) { _ in
                FullGramEconomy.shared.toggleHideGift(id: gift.id)
            })
            sheet.addAction(UIAlertAction(title: "Переслать / передать пользователю…", style: .default) { _ in
                let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                    context: context,
                    filter: [.onlyWriteable, .excludeDisabled],
                    hasChatListSelector: true,
                    hasContactSelector: true,
                    hasGlobalSearch: true,
                    title: "Кому передать подарок / NFT?"
                ))
                selector.peerSelected = { [weak selector] peer, _ in
                    selector?.dismiss()
                    let toPeerId = peer.id.toInt64()
                    let toName = peer.compactDisplayTitle
                    if let moved = FullGramEconomy.shared.transferOwnedGift(id: gift.id, toPeerId: toPeerId, toPeerName: toName) {
                        let payload = FullGramChatGiftPayload(
                            kind: moved.isUpgraded ? .nft : .gift,
                            giftRecordId: moved.id,
                            title: moved.title,
                            emoji: moved.emoji,
                            number: moved.nftNumber,
                            starsPrice: moved.priceStars,
                            modelName: moved.modelName,
                            backdropName: moved.backdropName,
                            backdropInnerHex: moved.backdropInnerHex,
                            backdropOuterHex: moved.backdropOuterHex,
                            patternName: moved.patternName,
                            rarityText: moved.isUpgraded ? "Коллекционный NFT" : "Подарок Telegram",
                            comment: moved.comment,
                            canUpgrade: moved.canUpgradeToNFT && !moved.isUpgraded,
                            senderName: "FullGram",
                            slug: moved.slug,
                            realGiftId: moved.realGiftId
                        )
                        fullGramSendGiftPayloadMessage(account: context.account, peerId: peer.id, payload: payload)
                    }
                }
                presentControllerImpl?(selector)
            })
            sheet.addAction(UIAlertAction(title: "Удалить подарок / NFT", style: .destructive) { _ in
                FullGramEconomy.shared.removeOwnedGift(id: gift.id)
            })
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        openMarket: {
            pushImpl?(fullGramGiftMarketController(context: context, targetPeerId: peerId, targetPeerName: nil))
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let gifts = FullGramEconomy.shared.ownedGifts
        var entries: [FullGramMyGiftsEntry] = [
            .buyMore("Открыть маркет подарков FullGram…"),
            .header("КУПЛЕННЫЕ ПОДАРКИ И NFT (\(gifts.count))")
        ]
        if gifts.isEmpty {
            entries.append(.empty("У вас пока нет подарков FullGram. Купите любой подарок в маркете и улучшите его до коллекционного NFT."))
        } else {
            for (idx, g) in gifts.enumerated() {
                entries.append(.giftRow(Int32(idx), g))
            }
        }
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Подарки и апгрейды"),
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
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}

// MARK: - Экран апгрейда подарка в коллекционный NFT (Telegram-style)

private final class FullGramGiftUpgradeArguments {
    let pickModel: () -> Void
    let pickBackdrop: () -> Void
    let pickPattern: () -> Void
    let editNumber: () -> Void
    let performRandomUpgrade: () -> Void
    let performCustomUpgrade: () -> Void
    let sendNFTCardToChat: () -> Void
    let transferGift: () -> Void
    let deleteGift: () -> Void
    let togglePinned: () -> Void

    init(
        pickModel: @escaping () -> Void,
        pickBackdrop: @escaping () -> Void,
        pickPattern: @escaping () -> Void,
        editNumber: @escaping () -> Void,
        performRandomUpgrade: @escaping () -> Void,
        performCustomUpgrade: @escaping () -> Void,
        sendNFTCardToChat: @escaping () -> Void,
        transferGift: @escaping () -> Void,
        deleteGift: @escaping () -> Void,
        togglePinned: @escaping () -> Void
    ) {
        self.pickModel = pickModel
        self.pickBackdrop = pickBackdrop
        self.pickPattern = pickPattern
        self.editNumber = editNumber
        self.performRandomUpgrade = performRandomUpgrade
        self.performCustomUpgrade = performCustomUpgrade
        self.sendNFTCardToChat = sendNFTCardToChat
        self.transferGift = transferGift
        self.deleteGift = deleteGift
        self.togglePinned = togglePinned
    }
}

private enum FullGramGiftUpgradeEntry: ItemListNodeEntry {
    case header(String)
    case statusRow(String, String)
    case modelRow(String, String)
    case backdropRow(String, String)
    case patternRow(String, String)
    case numberRow(String, String)
    case upgradeRandomAction(String)
    case upgradeCustomAction(String)
    case sendCardAction(String)
    case transferAction(String)
    case pinToggle(Bool)
    case deleteAction(String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .statusRow, .modelRow, .backdropRow, .patternRow, .numberRow: return 0
        default: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .statusRow: return 1
        case .modelRow: return 2
        case .backdropRow: return 3
        case .patternRow: return 4
        case .numberRow: return 5
        case .upgradeRandomAction: return 10
        case .upgradeCustomAction: return 11
        case .sendCardAction: return 12
        case .transferAction: return 13
        case .pinToggle: return 14
        case .deleteAction: return 15
        case .info: return 16
        }
    }

    static func < (lhs: FullGramGiftUpgradeEntry, rhs: FullGramGiftUpgradeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramGiftUpgradeArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .statusRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {})
        case let .modelRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickModel)
        case let .backdropRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickBackdrop)
        case let .patternRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickPattern)
        case let .numberRow(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editNumber)
        case let .upgradeRandomAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.performRandomUpgrade)
        case let .upgradeCustomAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.performCustomUpgrade)
        case let .sendCardAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.sendNFTCardToChat)
        case let .transferAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.transferGift)
        case let .pinToggle(val):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Закрепить в профиле", value: val, sectionId: self.section, style: .blocks, updated: { _ in args.togglePinned() })
        case let .deleteAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.deleteGift)
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramGiftUpgradeController(context: AccountContext, ownedGift: FullGramOwnedGift) -> ViewController {
    var presentNativeImpl: ((UIViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var popImpl: (() -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramEconomy.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let draftModel = Atomic<(String, Int)>(value: (ownedGift.modelName ?? FullGramEconomy.defaultModels[0].0, ownedGift.modelRarityPermille ?? FullGramEconomy.defaultModels[0].1))
    let draftBackdrop = Atomic<FullGramEconomy.BackdropPreset>(value: FullGramEconomy.defaultBackdrops.first(where: { $0.name == ownedGift.backdropName }) ?? FullGramEconomy.defaultBackdrops[0])
    let draftPattern = Atomic<(String, Int)>(value: (ownedGift.patternName ?? FullGramEconomy.defaultPatterns[0].0, ownedGift.patternRarityPermille ?? FullGramEconomy.defaultPatterns[0].1))
    let draftNumber = Atomic<Int32>(value: ownedGift.nftNumber ?? Int32.random(in: 1 ... 9999))

    let bumpDraft: () -> Void = {
        changed.set(version.modify { $0 + 1 })
    }

    let finishUpgradeAlert: (FullGramOwnedGift) -> Void = { upgraded in
        let alert = UIAlertController(
            title: "✨ Улучшено до NFT!",
            message: "\(upgraded.emoji) \(upgraded.title) #\(upgraded.nftNumber ?? 1)\nМодель: \(upgraded.modelName ?? "")\nФон: \(upgraded.backdropName ?? "")\nУзор: \(upgraded.patternName ?? "")",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentNativeImpl?(alert)
    }

    let args = FullGramGiftUpgradeArguments(
        pickModel: {
            let sheet = UIAlertController(title: "Выбор модели NFT", message: nil, preferredStyle: .actionSheet)
            for m in FullGramEconomy.defaultModels {
                let pct = String(format: "%.1f%%", Double(m.1) / 10.0)
                sheet.addAction(UIAlertAction(title: "\(m.0) (\(pct))", style: .default) { _ in
                    let _ = draftModel.swap(m)
                    bumpDraft()
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        pickBackdrop: {
            let sheet = UIAlertController(title: "Выбор фона NFT", message: nil, preferredStyle: .actionSheet)
            for b in FullGramEconomy.defaultBackdrops {
                let pct = String(format: "%.1f%%", Double(b.rarityPermille) / 10.0)
                sheet.addAction(UIAlertAction(title: "\(b.name) (\(pct))", style: .default) { _ in
                    let _ = draftBackdrop.swap(b)
                    bumpDraft()
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        pickPattern: {
            let sheet = UIAlertController(title: "Выбор узора NFT", message: nil, preferredStyle: .actionSheet)
            for p in FullGramEconomy.defaultPatterns {
                let pct = String(format: "%.1f%%", Double(p.1) / 10.0)
                sheet.addAction(UIAlertAction(title: "\(p.0) (\(pct))", style: .default) { _ in
                    let _ = draftPattern.swap(p)
                    bumpDraft()
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        },
        editNumber: {
            let alert = UIAlertController(title: "Номер коллекции #", message: "Введите номер экземпляра NFT:", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.keyboardType = .numberPad
                tf.text = "\(draftNumber.with { $0 })"
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                if let n = Int32(alert?.textFields?.first?.text ?? ""), n > 0 {
                    let _ = draftNumber.swap(n)
                    bumpDraft()
                }
            })
            presentNativeImpl?(alert)
        },
        performRandomUpgrade: {
            guard let upgraded = FullGramEconomy.shared.upgradeGift(id: ownedGift.id, customModel: nil, customBackdrop: nil, customPattern: nil, customNumber: nil, chargeStars: true) else {
                let err = UIAlertController(title: "Недостаточно звёзд", message: "Для апгрейда требуется \(ownedGift.upgradeStars) ★.", preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                presentNativeImpl?(err)
                return
            }
            finishUpgradeAlert(upgraded)
        },
        performCustomUpgrade: {
            let m = draftModel.with { $0 }
            let b = draftBackdrop.with { $0 }
            let p = draftPattern.with { $0 }
            let num = draftNumber.with { $0 }
            guard let upgraded = FullGramEconomy.shared.upgradeGift(id: ownedGift.id, customModel: m, customBackdrop: b, customPattern: p, customNumber: num, chargeStars: true) else {
                let err = UIAlertController(title: "Недостаточно звёзд", message: "Для апгрейда требуется \(ownedGift.upgradeStars) ★.", preferredStyle: .alert)
                err.addAction(UIAlertAction(title: "OK", style: .default))
                presentNativeImpl?(err)
                return
            }
            finishUpgradeAlert(upgraded)
        },
        sendNFTCardToChat: {
            let latest = FullGramEconomy.shared.findOwnedGift(id: ownedGift.id) ?? ownedGift
            let payload = FullGramChatGiftPayload(
                kind: latest.isUpgraded ? .nft : .gift,
                giftRecordId: latest.id,
                title: latest.title,
                emoji: latest.emoji,
                number: latest.nftNumber,
                starsPrice: latest.priceStars,
                modelName: latest.modelName,
                backdropName: latest.backdropName,
                backdropInnerHex: latest.backdropInnerHex,
                backdropOuterHex: latest.backdropOuterHex,
                patternName: latest.patternName,
                rarityText: latest.isUpgraded ? "Коллекционный NFT" : "Подарок Telegram",
                comment: latest.comment,
                canUpgrade: latest.canUpgradeToNFT && !latest.isUpgraded,
                senderName: latest.senderName,
                slug: latest.slug,
                realGiftId: latest.realGiftId
            )
            fullGramSendGiftPayloadMessage(account: context.account, peerId: EnginePeer.Id(latest.ownerPeerId), payload: payload)
            let done = UIAlertController(title: "Отправлено", message: "Нативная плашка подарка/NFT отправлена в чат.", preferredStyle: .alert)
            done.addAction(UIAlertAction(title: "OK", style: .default))
            presentNativeImpl?(done)
        },
        transferGift: {
            let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                context: context,
                filter: [.onlyWriteable, .excludeDisabled],
                hasChatListSelector: true,
                hasContactSelector: true,
                hasGlobalSearch: true,
                title: "Кому переслать / передать?"
            ))
            selector.peerSelected = { [weak selector] peer, _ in
                selector?.dismiss()
                let toPeerId = peer.id.toInt64()
                let toName = peer.compactDisplayTitle
                if let moved = FullGramEconomy.shared.transferOwnedGift(id: ownedGift.id, toPeerId: toPeerId, toPeerName: toName) {
                    let payload = FullGramChatGiftPayload(
                        kind: moved.isUpgraded ? .nft : .gift,
                        giftRecordId: moved.id,
                        title: moved.title,
                        emoji: moved.emoji,
                        number: moved.nftNumber,
                        starsPrice: moved.priceStars,
                        modelName: moved.modelName,
                        backdropName: moved.backdropName,
                        backdropInnerHex: moved.backdropInnerHex,
                        backdropOuterHex: moved.backdropOuterHex,
                        patternName: moved.patternName,
                        rarityText: moved.isUpgraded ? "Коллекционный NFT" : "Подарок Telegram",
                        comment: moved.comment,
                        canUpgrade: moved.canUpgradeToNFT && !moved.isUpgraded,
                        senderName: "FullGram",
                        slug: moved.slug,
                        realGiftId: moved.realGiftId
                    )
                    fullGramSendGiftPayloadMessage(account: context.account, peerId: peer.id, payload: payload)
                    popImpl?()
                }
            }
            presentControllerImpl?(selector)
        },
        deleteGift: {
            let confirm = UIAlertController(title: "Удалить подарок / NFT?", message: "Подарок будет удалён из вашего профиля.", preferredStyle: .alert)
            confirm.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            confirm.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in
                FullGramEconomy.shared.removeOwnedGift(id: ownedGift.id)
                popImpl?()
            })
            presentNativeImpl?(confirm)
        },
        togglePinned: {
            FullGramEconomy.shared.togglePinGift(id: ownedGift.id)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let current = FullGramEconomy.shared.findOwnedGift(id: ownedGift.id) ?? ownedGift
        let m = draftModel.with { $0 }
        let b = draftBackdrop.with { $0 }
        let p = draftPattern.with { $0 }
        let num = draftNumber.with { $0 }

        var entries: [FullGramGiftUpgradeEntry] = [
            .header("\(current.emoji) \(current.title.uppercased())"),
            .statusRow("Статус", current.isUpgraded ? "Уникальный NFT #\(current.nftNumber ?? 1)" : "Обычный подарок (\(current.priceStars) ★)"),
            .modelRow("Модель", m.0),
            .backdropRow("Фон (Backdrop)", b.name),
            .patternRow("Узор (Symbol)", p.0),
            .numberRow("Номер экземпляра", "#\(num)")
        ]

        if current.canUpgradeToNFT && !current.isUpgraded {
            entries.append(.upgradeRandomAction("🎲 Случайный апгрейд в NFT (\(current.upgradeStars) ★)"))
            entries.append(.upgradeCustomAction("✨ Улучшить с выбранными трейтами (\(current.upgradeStars) ★)"))
        } else if current.isUpgraded {
            entries.append(.upgradeCustomAction("🎨 Применить новые выбранные трейты NFT"))
        }
        entries.append(.sendCardAction("🎁 Отправить плашку подарка в чат"))
        entries.append(.transferAction("📤 Переслать / передать пользователю…"))
        entries.append(.pinToggle(current.pinnedToProfile))
        entries.append(.deleteAction("🗑 Удалить подарок / NFT"))
        entries.append(.info("Как в настоящем Telegram: при апгрейде подарка выпадают редкие модель, градиентный фон, узор и уникальный номер #."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text(current.isUpgraded ? "NFT #\(current.nftNumber ?? 1)" : "Апгрейд до NFT"),
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
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    popImpl = { [weak controller] in _ = controller?.dismiss() }
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}

// MARK: - Кастомные анонимные номера (+888)

private final class FullGramNumbersArguments {
    let addNumber: () -> Void
    let tapNumber: (FullGramCollectibleNumber) -> Void
    init(addNumber: @escaping () -> Void, tapNumber: @escaping (FullGramCollectibleNumber) -> Void) {
        self.addNumber = addNumber
        self.tapNumber = tapNumber
    }
}

private enum FullGramNumbersEntry: ItemListNodeEntry {
    case buyAction(String)
    case header(String)
    case numberRow(Int32, FullGramCollectibleNumber)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .buyAction: return 0
        default: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .buyAction: return 0
        case .header: return 10
        case let .numberRow(idx, _): return 20 + idx
        case .info: return 999
        }
    }

    static func < (lhs: FullGramNumbersEntry, rhs: FullGramNumbersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramNumbersArguments
        switch self {
        case let .buyAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.addNumber)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .numberRow(_, item):
            let status = (item.isActive ? "✓ Профиль • " : "") + String(format: "%.0f TON", item.priceTon)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: item.number, label: status, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: { args.tapNumber(item) })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramCollectibleNumbersController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: (@MainActor @Sendable (UIViewController) -> Void)?
    let selfRawId = context.account.peerId.id._internalGetInt64Value()
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramEconomy.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramNumbersArguments(
        addNumber: {
            let alert = UIAlertController(title: "Купить кастомный номер +888", message: "Введите желаемые 8 цифр после +888 и цену в TON (как на Fragment):", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.keyboardType = .phonePad
                tf.placeholder = "+888 0000 0001"
                tf.text = "+888 \(Int.random(in: 1000...9999)) \(Int.random(in: 1000...9999))"
            }
            alert.addTextField { tf in
                tf.keyboardType = .decimalPad
                tf.placeholder = "Цена в TON (например: 250)"
                tf.text = "250"
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Оформить бесплатно (лип.)", style: .default) { [weak alert] _ in
                let num = alert?.textFields?.first?.text ?? ""
                let rawPrice = (alert?.textFields?.dropFirst().first?.text ?? "250").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                let price = rawPrice.isEmpty ? 250.0 : (Double(rawPrice) ?? -1.0)
                guard price.isFinite, price >= 0, price <= 1e12 else { return }
                let _ = FullGramEconomy.shared.buyAnonymousNumber(rawNumber: num, priceTon: price, deductFromBalance: false)
            })
            alert.addAction(UIAlertAction(title: "Купить за TON с баланса", style: .default) { [weak alert] _ in
                let num = alert?.textFields?.first?.text ?? ""
                let rawPrice = (alert?.textFields?.dropFirst().first?.text ?? "250").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                let price = rawPrice.isEmpty ? 250.0 : (Double(rawPrice) ?? -1.0)
                guard price.isFinite, price >= 0, price <= 1e12 else { return }
                if FullGramEconomy.shared.buyAnonymousNumber(rawNumber: num, priceTon: price, deductFromBalance: true) == nil {
                    let err = UIAlertController(title: "Недостаточно Gram / TON", message: "Пополните баланс Gram или выберите липовое оформление.", preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(err)
                }
            })
            presentNativeImpl?(alert)
        },
        tapNumber: { item in
            let sheet = UIAlertController(title: item.number, message: String(format: "Цена покупки: %.2f TON ($%.2f)", item.priceTon, item.priceUsd), preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Показать карточку Fragment", style: .default) { _ in
                pushImpl?(fullGramCollectibleNumberInfoController(context: context, item: item, ownerName: "Вы"))
            })
            sheet.addAction(UIAlertAction(title: item.isActive ? "Открепить / скрыть из профиля" : "Закрепить в профиле", style: .default) { _ in
                let nextActive = !item.isActive
                FullGramEconomy.shared.setActiveCustomNumber(id: nextActive ? item.id : nil)
                FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, action: "toggle_number", number: item.number, entryId: item.id, isActive: nextActive)
            })
            sheet.addAction(UIAlertAction(title: "Переслать / передать пользователю…", style: .default) { _ in
                let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                    context: context,
                    filter: [.onlyWriteable, .excludeDisabled],
                    hasChatListSelector: true,
                    hasContactSelector: true,
                    hasGlobalSearch: true,
                    title: "Кому передать номер \(item.number)?"
                ))
                selector.peerSelected = { [weak selector] peer, _ in
                    selector?.dismiss()
                    let toRaw = peer.id.id._internalGetInt64Value()
                    FullGramEconomy.shared.removeCustomNumber(id: item.id)
                    FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, toPeerId: toRaw, action: "transfer_number", number: item.number, entryId: item.id)
                    let payload = FullGramChatGiftPayload(
                        kind: .number,
                        giftRecordId: item.id,
                        title: item.number,
                        emoji: "📞",
                        tonAmount: item.priceTon,
                        rarityText: "Анонимный номер Fragment",
                        senderName: "FullGram"
                    )
                    fullGramSendGiftPayloadMessage(account: context.account, peerId: peer.id, payload: payload)
                }
                presentControllerImpl?(selector)
            })
            sheet.addAction(UIAlertAction(title: "Удалить номер", style: .destructive) { _ in
                FullGramEconomy.shared.removeCustomNumber(id: item.id)
                FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, action: "revoke_number", number: item.number, entryId: item.id)
            })
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let list = FullGramEconomy.shared.customNumbers
        var entries: [FullGramNumbersEntry] = [
            .buyAction("Приобрести кастомный номер +888…"),
            .header("МОИ АНОНИМНЫЕ НОМЕРА (\(list.count))")
        ]
        for (idx, item) in list.enumerated() {
            entries.append(.numberRow(Int32(idx), item))
        }
        entries.append(.info("Активный номер +888 появляется в вашем профиле как в настоящем Telegram. Его можно открепить, переслать другому пользователю или удалить."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Номера +888"),
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
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}

// MARK: - Кастомные коллекционные @юзернеймы

private final class FullGramUsernamesArguments {
    let addUsername: () -> Void
    let tapUsername: (FullGramCollectibleUsername) -> Void
    init(addUsername: @escaping () -> Void, tapUsername: @escaping (FullGramCollectibleUsername) -> Void) {
        self.addUsername = addUsername
        self.tapUsername = tapUsername
    }
}

private enum FullGramUsernamesEntry: ItemListNodeEntry {
    case buyAction(String)
    case header(String)
    case usernameRow(Int32, FullGramCollectibleUsername)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .buyAction: return 0
        default: return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .buyAction: return 0
        case .header: return 10
        case let .usernameRow(idx, _): return 20 + idx
        case .info: return 999
        }
    }

    static func < (lhs: FullGramUsernamesEntry, rhs: FullGramUsernamesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramUsernamesArguments
        switch self {
        case let .buyAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.addUsername)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .usernameRow(_, item):
            let badge = item.isPrimary ? "Основной • " : (item.isActive ? "Активен • " : "Скрыт • ")
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "@\(item.username)", label: badge + String(format: "%.0f TON", item.priceTon), sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: { args.tapUsername(item) })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramCollectibleUsernamesController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeImpl: (@MainActor @Sendable (UIViewController) -> Void)?
    let selfRawId = context.account.peerId.id._internalGetInt64Value()
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramEconomy.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }

    let args = FullGramUsernamesArguments(
        addUsername: {
            let alert = UIAlertController(title: "Купить коллекционный @username", message: "Введите любой юзернейм (от 4 символов) и цену покупки в TON:", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.placeholder = "@username"
                tf.autocapitalizationType = .none
                tf.autocorrectionType = .no
            }
            alert.addTextField { tf in
                tf.keyboardType = .decimalPad
                tf.placeholder = "Цена в TON (например: 1200)"
                tf.text = "1200"
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Получить в профиль (лип.)", style: .default) { [weak alert] _ in
                let uname = alert?.textFields?.first?.text ?? ""
                let rawPrice = (alert?.textFields?.dropFirst().first?.text ?? "1200").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                let price = rawPrice.isEmpty ? 1200.0 : (Double(rawPrice) ?? -1.0)
                guard price.isFinite, price >= 0, price <= 1e12 else { return }
                if FullGramEconomy.shared.buyCollectibleUsername(rawUsername: uname, priceTon: price, isPrimary: true, deductFromBalance: false) == nil {
                    let err = UIAlertController(title: "Некорректный юзернейм", message: "Минимум 4 латинских символа.", preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(err)
                }
            })
            alert.addAction(UIAlertAction(title: "Купить за TON с баланса", style: .default) { [weak alert] _ in
                let uname = alert?.textFields?.first?.text ?? ""
                let rawPrice = (alert?.textFields?.dropFirst().first?.text ?? "1200").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
                let price = rawPrice.isEmpty ? 1200.0 : (Double(rawPrice) ?? -1.0)
                guard price.isFinite, price >= 0, price <= 1e12 else { return }
                if FullGramEconomy.shared.buyCollectibleUsername(rawUsername: uname, priceTon: price, isPrimary: true, deductFromBalance: true) == nil {
                    let err = UIAlertController(title: "Не удалось купить", message: "Проверьте длину юзернейма (от 4 символов) и баланс TON.", preferredStyle: .alert)
                    err.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(err)
                }
            })
            presentNativeImpl?(alert)
        },
        tapUsername: { item in
            let sheet = UIAlertController(title: "@\(item.username)", message: String(format: "Fragment Цена: %.2f TON ($%.2f)", item.priceTon, item.priceUsd), preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: "Показать карточку Fragment", style: .default) { _ in
                pushImpl?(fullGramCollectibleUsernameInfoController(context: context, item: item, ownerName: "Вы"))
            })
            if item.isPrimary {
                sheet.addAction(UIAlertAction(title: "Открепить с основного места", style: .default) { _ in
                    FullGramEconomy.shared.detachPrimaryCollectibleUsername(id: item.id)
                    FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, action: "toggle_username", username: item.username, entryId: item.id, isActive: true, isPrimary: false)
                })
            } else {
                sheet.addAction(UIAlertAction(title: "Сделать основным в профиле", style: .default) { _ in
                    FullGramEconomy.shared.setPrimaryCollectibleUsername(id: item.id)
                    FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, action: "toggle_username", username: item.username, entryId: item.id, isActive: true, isPrimary: true)
                })
            }
            sheet.addAction(UIAlertAction(title: item.isActive ? "Открепить / скрыть из профиля" : "Показать в профиле", style: .default) { _ in
                let nextActive = !item.isActive
                FullGramEconomy.shared.toggleCollectibleUsernameActive(id: item.id)
                FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, action: "toggle_username", username: item.username, entryId: item.id, isActive: nextActive, isPrimary: false)
            })
            sheet.addAction(UIAlertAction(title: "Переслать / передать пользователю…", style: .default) { _ in
                let selector = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(
                    context: context,
                    filter: [.onlyWriteable, .excludeDisabled],
                    hasChatListSelector: true,
                    hasContactSelector: true,
                    hasGlobalSearch: true,
                    title: "Кому передать @\(item.username)?"
                ))
                selector.peerSelected = { [weak selector] peer, _ in
                    selector?.dismiss()
                    let toRaw = peer.id.id._internalGetInt64Value()
                    FullGramEconomy.shared.removeCollectibleUsername(id: item.id)
                    FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, toPeerId: toRaw, action: "transfer_username", username: item.username, entryId: item.id)
                    let payload = FullGramChatGiftPayload(
                        kind: .username,
                        giftRecordId: item.id,
                        title: "@\(item.username)",
                        emoji: "🔗",
                        tonAmount: item.priceTon,
                        rarityText: "Коллекционный адрес Fragment",
                        senderName: "FullGram"
                    )
                    fullGramSendGiftPayloadMessage(account: context.account, peerId: peer.id, payload: payload)
                }
                presentControllerImpl?(selector)
            })
            sheet.addAction(UIAlertAction(title: "Удалить юзернейм", style: .destructive) { _ in
                FullGramEconomy.shared.removeCollectibleUsername(id: item.id)
                FullGramAdmin.shared.performEconomyAction(actorPeerId: selfRawId, action: "revoke_username", username: item.username, entryId: item.id)
            })
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentNativeImpl?(sheet)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let list = FullGramEconomy.shared.customUsernames
        var entries: [FullGramUsernamesEntry] = [
            .buyAction("Приобрести коллекционный @username…"),
            .header("МОИ КОЛЛЕКЦИОННЫЕ ЮЗЕРНЕЙМЫ (\(list.count))")
        ]
        for (idx, item) in list.enumerated() {
            entries.append(.usernameRow(Int32(idx), item))
        }
        entries.append(.info("Коллекционные @юзернеймы отображаются в вашем профиле. Их можно открепить, переслать другому пользователю или удалить."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Юзернеймы Fragment"),
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
    pushImpl = { [weak controller] c in controller?.push(c) }
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    presentNativeImpl = { [weak controller] vc in
        if let pop = vc.popoverPresentationController, let view = controller?.view {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        controller?.present(vc, animated: true)
    }
    return controller
}

// MARK: - Карточки информации Fragment (для кастомных номеров и юзернеймов в профиле)

private enum FullGramCollectibleInfoEntry: ItemListNodeEntry {
    case header(String)
    case row(Int32, String, String)
    case copyAction(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .copyAction, .footer: return 1
        default: return 0
        }
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .row(idx, _, _): return 1 + idx
        case .copyAction: return 100
        case .footer: return 101
        }
    }

    static func < (lhs: FullGramCollectibleInfoEntry, rhs: FullGramCollectibleInfoEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let onCopy = arguments as? () -> Void
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .row(_, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {})
        case let .copyAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: { onCopy?() })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramCollectibleNumberInfoController(
    context: AccountContext,
    item: FullGramCollectibleNumber,
    ownerName: String
) -> ViewController {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    df.locale = Locale(identifier: "ru_RU")
    let dateStr = df.string(from: Date(timeIntervalSince1970: TimeInterval(item.purchasedAt)))
    let priceStr = String(format: "💎 %.2f TON (≈ $%.2f)", item.priceTon, item.priceUsd)

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramCollectibleInfoEntry] = [
            .header("АНОНИМНЫЙ НОМЕР FRAGMENT"),
            .row(0, "Номер", item.number),
            .row(1, "Владелец", ownerName),
            .row(2, "Цена покупки", priceStr),
            .row(3, "Дата покупки", dateStr),
            .copyAction("Скопировать номер"),
            .footer("Коллекционный анонимный номер в блокчейне TON. Отображается в вашем профиле FullGram.")
        ]
        let copyAction: () -> Void = {
            UIPasteboard.general.string = item.number
        }
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Коллекционный номер"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, copyAction))
    }
    return ItemListController(context: context, state: signal)
}

public func fullGramCollectibleUsernameInfoController(
    context: AccountContext,
    item: FullGramCollectibleUsername,
    ownerName: String
) -> ViewController {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    df.locale = Locale(identifier: "ru_RU")
    let dateStr = df.string(from: Date(timeIntervalSince1970: TimeInterval(item.purchasedAt)))
    let priceStr = String(format: "💎 %.2f TON (≈ $%.2f)", item.priceTon, item.priceUsd)

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramCollectibleInfoEntry] = [
            .header("КОЛЛЕКЦИОННЫЙ ЮЗЕРНЕЙМ FRAGMENT"),
            .row(0, "Юзернейм", "@\(item.username)"),
            .row(1, "Ссылка", "t.me/\(item.username)"),
            .row(2, "Владелец", ownerName),
            .row(3, "Цена покупки", priceStr),
            .row(4, "Дата покупки", dateStr),
            .copyAction("Скопировать @\(item.username)"),
            .footer("Коллекционное имя пользователя в блокчейне TON. Подключено через FullGram Fragment.")
        ]
        let copyAction: () -> Void = {
            UIPasteboard.general.string = "@\(item.username)"
        }
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Коллекционный адрес"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, copyAction))
    }
    return ItemListController(context: context, state: signal)
}

// MARK: - История транзакций кошелька и звёзд

private enum FullGramTransactionsEntry: ItemListNodeEntry {
    case header(String)
    case txRow(Int32, FullGramEconomyTransaction)
    case empty(String)

    var section: ItemListSectionId { return 0 }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case let .txRow(idx, _): return 1 + idx
        case .empty: return 999
        }
    }

    static func < (lhs: FullGramTransactionsEntry, rhs: FullGramTransactionsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .txRow(_, tx):
            let sign = tx.isIncoming ? "+" : "-"
            let safeAmount = tx.amount.isFinite ? max(0.0, min(tx.amount, 1_000_000_000_000.0)) : 0.0
            let amountStr = tx.currency == .stars
                ? "\(sign)\(Int64(safeAmount.rounded())) ★"
                : "\(sign)\(String(format: "%.2f", safeAmount)) TON"
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: tx.title, label: amountStr, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {})
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func fullGramEconomyTransactionsController(context: AccountContext) -> ViewController {
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let version = Atomic<Int>(value: 0)
    let observer = NotificationCenter.default.addObserver(forName: FullGramEconomy.didChangeNotification, object: nil, queue: .main) { _ in
        changed.set(version.modify { $0 + 1 })
    }
    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let txs = FullGramEconomy.shared.transactions
        var entries: [FullGramTransactionsEntry] = [.header("ПОСЛЕДНИЕ ОПЕРАЦИИ")]
        if txs.isEmpty {
            entries.append(.empty("Операций пока нет."))
        } else {
            for (idx, tx) in txs.enumerated() {
                entries.append(.txRow(Int32(idx), tx))
            }
        }
        let data = ItemListPresentationData(presentationData)
        let rightBtn: ItemListNavigationButton? = txs.isEmpty ? nil : ItemListNavigationButton(content: .text("Очистить"), style: .regular, enabled: true, action: {
            FullGramEconomy.shared.clearTransactions()
        })
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("История операций"),
            leftNavigationButton: nil,
            rightNavigationButton: rightBtn,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, ()))
    }
    |> afterDisposed {
        NotificationCenter.default.removeObserver(observer)
    }
    return ItemListController(context: context, state: signal)
}
