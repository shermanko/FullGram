import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import AccountContext
import AnimationCache
import MultiAnimationRenderer
import EntityKeyboard
import EmojiStatusSelectionComponent
import UndoUI

// MARK: - Owner Gate & Profile Row Helpers

func fullGramCanOpenAdmin(context: AccountContext) -> Bool {
    guard context.account.peerId.namespace == Namespaces.Peer.CloudUser else {
        return false
    }
    return FullGramAdmin.isOwnerUserId(context.account.peerId.id._internalGetInt64Value())
}

func fullGramBadgeMenuIcon() -> UIImage? {
    let size = CGSize(width: 29.0, height: 29.0)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        let rect = CGRect(origin: .zero, size: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 7.0)
        UIColor(rgb: 0x5E5CE6).setFill()
        path.fill()

        if let symbol = UIImage(systemName: "moon.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let iconSize = CGSize(width: 17.0, height: 17.0)
            let iconRect = CGRect(
                x: (size.width - iconSize.width) / 2.0,
                y: (size.height - iconSize.height) / 2.0,
                width: iconSize.width,
                height: iconSize.height
            )
            symbol.draw(in: iconRect)
        }
    }
}

func fullGramBadgeRowStatusLabel(peerId: Int64, username: String?, russian: Bool) -> String {
    guard let (_, role) = FullGramBadges.shared.rawAssignment(forPeerId: peerId, username: username) else {
        return russian ? "Нет" : "None"
    }
    if role.customEmojiId != nil {
        return russian ? "Эмодзи" : "Emoji"
    }
    let short = (role.shortLabel ?? role.label).trimmingCharacters(in: .whitespacesAndNewlines)
    return short.isEmpty ? (russian ? "Выдан" : "Active") : short
}

// MARK: - Badge Desk Controller (matches Telegram native Badge editor)

private struct FullGramBadgeDraft: Equatable {
    var enabled: Bool
    var roleId: String
    var customEmojiId: Int64?
    var emoji: String
    var label: String
    var shortLabel: String
    var color: String
}

private struct FullGramBadgeDeskState: Equatable {
    var original: FullGramBadgeDraft
    var draft: FullGramBadgeDraft
    var saving: Bool
}

private enum FullGramBadgeDeskSection: Int32 {
    case preview
    case badge
    case admin
}

private final class FullGramBadgeDeskArguments {
    let context: AccountContext
    let toggleEnabled: (Bool) -> Void
    let pickEmoji: () -> Void
    let resetEmoji: () -> Void
    let pickRole: () -> Void
    let editLabel: () -> Void
    let editShortLabel: () -> Void
    let editToken: () -> Void

    init(
        context: AccountContext,
        toggleEnabled: @escaping (Bool) -> Void,
        pickEmoji: @escaping () -> Void,
        resetEmoji: @escaping () -> Void,
        pickRole: @escaping () -> Void,
        editLabel: @escaping () -> Void,
        editShortLabel: @escaping () -> Void,
        editToken: @escaping () -> Void
    ) {
        self.context = context
        self.toggleEnabled = toggleEnabled
        self.pickEmoji = pickEmoji
        self.resetEmoji = resetEmoji
        self.pickRole = pickRole
        self.editLabel = editLabel
        self.editShortLabel = editShortLabel
        self.editToken = editToken
    }
}

private enum FullGramBadgeDeskEntry: ItemListNodeEntry {
    case previewHeader(String)
    case previewPeer(EnginePeer, FullGramBadgeDraft, Bool)
    case badgeHeader(String)
    case badgeSwitch(String, Bool)
    case badgeEmoji(String, String)
    case badgeEmojiReset(String)
    case badgeRole(String, String)
    case badgeLabel(String, String)
    case badgeShortLabel(String, String)
    case badgeFooter(String)
    case adminHeader(String)
    case adminToken(String, String)

    var section: ItemListSectionId {
        switch self {
        case .previewHeader, .previewPeer:
            return FullGramBadgeDeskSection.preview.rawValue
        case .badgeHeader, .badgeSwitch, .badgeEmoji, .badgeEmojiReset, .badgeRole, .badgeLabel, .badgeShortLabel, .badgeFooter:
            return FullGramBadgeDeskSection.badge.rawValue
        case .adminHeader, .adminToken:
            return FullGramBadgeDeskSection.admin.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .previewHeader: return 0
        case .previewPeer: return 1
        case .badgeHeader: return 10
        case .badgeSwitch: return 11
        case .badgeEmoji: return 12
        case .badgeEmojiReset: return 13
        case .badgeRole: return 14
        case .badgeLabel: return 15
        case .badgeShortLabel: return 16
        case .badgeFooter: return 17
        case .adminHeader: return 30
        case .adminToken: return 31
        }
    }

    static func < (lhs: FullGramBadgeDeskEntry, rhs: FullGramBadgeDeskEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramBadgeDeskArguments
        switch self {
        case let .previewHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .previewPeer(peer, draft, ru):
            var previewPeer = peer
            if draft.enabled, let emojiId = draft.customEmojiId {
                let status = PeerEmojiStatus(content: .emoji(fileId: emojiId), expirationDate: nil)
                if case let .user(user) = peer {
                    previewPeer = .user(user.withUpdatedEmojiStatus(status))
                } else if case let .channel(channel) = peer {
                    previewPeer = .channel(channel.withUpdatedEmojiStatus(status))
                }
            }
            let subtitle: String
            if !draft.enabled {
                subtitle = ru ? "Без бейджа FullGram" : "No FullGram badge"
            } else if draft.customEmojiId != nil {
                subtitle = "\(draft.label)"
            } else {
                subtitle = "\(draft.emoji) \(draft.shortLabel) • \(draft.label)"
            }
            return ItemListPeerItem(
                presentationData: presentationData,
                systemStyle: .glass,
                dateTimeFormat: presentationData.dateTimeFormat,
                nameDisplayOrder: presentationData.nameDisplayOrder,
                context: .account(args.context),
                peer: previewPeer,
                height: .generic,
                aliasHandling: .standard,
                nameColor: .primary,
                presence: nil,
                text: .text(subtitle, .secondary),
                label: .none,
                editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false),
                revealOptions: nil,
                switchValue: nil,
                enabled: true,
                selectable: false,
                sectionId: self.section,
                action: nil,
                setPeerIdWithRevealedOptions: { _, _ in },
                removePeer: { _ in }
            )
        case let .badgeHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .badgeSwitch(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: args.toggleEnabled)
        case let .badgeEmoji(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickEmoji)
        case let .badgeEmojiReset(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.resetEmoji)
        case let .badgeRole(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.pickRole)
        case let .badgeLabel(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editLabel)
        case let .badgeShortLabel(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editShortLabel)
        case let .badgeFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .adminHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .adminToken(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.editToken)
        }
    }
}

private func fullGramRoleDisplayName(_ roleId: String, russian: Bool) -> String {
    switch roleId {
    case "creator": return russian ? "Создатель FullGram" : "FullGram Creator"
    case "official": return russian ? "Официальный ресурс" : "Official"
    case "premium": return "FullGram+"
    case "dev": return russian ? "Разработчик" : "Developer"
    default: return russian ? "Свой" : "Custom"
    }
}

func fullGramBadgeDeskController(
    context: AccountContext,
    peer: EnginePeer,
    peerId: Int64,
    username: String?
) -> ViewController {
    let existing = FullGramBadges.shared.rawAssignment(forPeerId: peerId, username: username)
    let defaultRole = FullGramBadges.builtInRoles["premium"]!
    let baseRoleId: String
    if let existingId = existing?.roleId, FullGramBadges.builtInRoles[existingId] != nil {
        baseRoleId = existingId
    } else if existing != nil {
        baseRoleId = "custom"
    } else {
        baseRoleId = "premium"
    }

    let initialDraft = FullGramBadgeDraft(
        enabled: existing != nil,
        roleId: baseRoleId,
        customEmojiId: existing?.role.customEmojiId.flatMap { Int64($0) },
        emoji: existing?.role.emoji ?? defaultRole.emoji,
        label: existing?.role.label ?? defaultRole.label,
        shortLabel: existing?.role.shortLabel ?? defaultRole.shortLabel ?? "FG+",
        color: existing?.role.color ?? defaultRole.color
    )
    let initialState = FullGramBadgeDeskState(original: initialDraft, draft: initialDraft, saving: false)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((inout FullGramBadgeDeskState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { current in
            var updated = current
            f(&updated)
            return updated
        })
    }

    weak var weakController: ItemListController?
    var presentNativeImpl: ((UIViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushImpl: ((ViewController) -> Void)?

    let promptAdminToken: ((() -> Void)?) -> Void = { onSaved in
        let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
        let alert = UIAlertController(
            title: ru ? "Токен администратора" : "Admin token",
            message: ru
                ? "Введите ADMIN_TOKEN от сервера fullgram.korsakovx.workers.dev. Токен сохранится только в iOS Keychain."
                : "Enter ADMIN_TOKEN for fullgram.korsakovx.workers.dev. It is stored securely in iOS Keychain.",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "ADMIN_TOKEN"
            tf.isSecureTextEntry = true
            tf.autocorrectionType = .no
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { _ in
            let token = alert.textFields?.first?.text ?? ""
            FullGramAdmin.shared.setToken(token)
            updateState { _ in }
            onSaved?()
        }))
        if FullGramAdmin.shared.hasToken {
            alert.addAction(UIAlertAction(title: ru ? "Очистить токен" : "Clear token", style: .destructive, handler: { _ in
                FullGramAdmin.shared.clearToken()
                updateState { _ in }
            }))
        }
        alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
        presentNativeImpl?(alert)
    }

    let commitSave: () -> Void = {
        let currentState = stateValue.with { $0 }
        guard !currentState.saving else { return }
        let draft = currentState.draft
        let performRequest = {
            updateState { $0.saving = true }
            FullGramAdmin.shared.updateBadge(
                peerId: peerId,
                username: username,
                enabled: draft.enabled,
                roleId: draft.roleId,
                customEmojiId: draft.customEmojiId,
                emoji: draft.emoji,
                label: draft.label,
                shortLabel: draft.shortLabel,
                color: draft.color
            ) { result in
                updateState { state in
                    state.saving = false
                    if case .success = result {
                        state.original = draft
                    }
                }
                let pData = context.sharedContext.currentPresentationData.with { $0 }
                let ru = pData.strings.baseLanguageCode.hasPrefix("ru")
                switch result {
                case .success:
                    let banner = UndoOverlayController(
                        presentationData: pData,
                        content: .succeed(
                            text: draft.enabled
                                ? (ru ? "Бейдж обновлён" : "Badge updated")
                                : (ru ? "Бейдж снят" : "Badge removed"),
                            timeout: nil,
                            customUndoText: nil
                        ),
                        elevatedLayout: false,
                        action: { _ in return false }
                    )
                    presentControllerImpl?(banner)
                case let .failure(error):
                    let alert = UIAlertController(
                        title: ru ? "Ошибка сохранения" : "Save failed",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    presentNativeImpl?(alert)
                }
            }
        }

        if !FullGramAdmin.shared.hasToken {
            promptAdminToken {
                if FullGramAdmin.shared.hasToken {
                    performRequest()
                }
            }
        } else {
            performRequest()
        }
    }

    let args = FullGramBadgeDeskArguments(
        context: context,
        toggleEnabled: { value in
            updateState { $0.draft.enabled = value }
        },
        pickEmoji: {
            guard let controller = weakController else { return }
            let currentId = stateValue.with { $0.draft.customEmojiId }
            var selectedItems = Set<AnyHashable>()
            if let currentId {
                selectedItems.insert(EngineMedia.Id(namespace: Namespaces.Media.CloudFile, id: currentId))
            }
            let emojiController = EmojiStatusSelectionController(
                context: context,
                mode: .customStatusSelection(completion: { file, _ in
                    updateState { state in
                        state.draft.customEmojiId = file?.fileId.id
                    }
                }),
                sourceView: controller.view,
                emojiContent: EmojiPagerContentComponent.emojiInputData(
                    context: context,
                    animationCache: context.animationCache,
                    animationRenderer: context.animationRenderer,
                    isStandalone: false,
                    subject: .status,
                    hasTrending: false,
                    topReactionItems: [],
                    areUnicodeEmojiEnabled: false,
                    areCustomEmojiEnabled: true,
                    chatPeerId: context.account.peerId,
                    selectedItems: selectedItems,
                    topStatusTitle: nil
                ),
                currentSelection: currentId,
                destinationItemView: { [weak controller] in
                    return controller?.view
                }
            )
            emojiController.pushController = { c in
                pushImpl?(c)
            }
            presentControllerImpl?(emojiController)
        },
        resetEmoji: {
            updateState { $0.draft.customEmojiId = nil }
        },
        pickRole: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            let sheet = UIAlertController(title: ru ? "Выберите роль" : "Select role", message: nil, preferredStyle: .actionSheet)
            let order = ["premium", "dev", "official", "creator"]
            for key in order {
                if let role = FullGramBadges.builtInRoles[key] {
                    sheet.addAction(UIAlertAction(title: "\(role.emoji) \(fullGramRoleDisplayName(key, russian: ru))", style: .default, handler: { _ in
                        updateState { state in
                            state.draft.roleId = key
                            state.draft.emoji = role.emoji
                            state.draft.label = role.label
                            state.draft.shortLabel = role.shortLabel ?? role.label
                            state.draft.color = role.color
                        }
                    }))
                }
            }
            sheet.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
            presentNativeImpl?(sheet)
        },
        editLabel: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            let currentText = stateValue.with { $0.draft.label }
            let alert = UIAlertController(title: ru ? "Текст бейджа" : "Badge text", message: nil, preferredStyle: .alert)
            alert.addTextField { tf in
                tf.text = currentText
                tf.placeholder = "FullGram+"
            }
            alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { _ in
                let val = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !val.isEmpty {
                    updateState { $0.draft.label = val }
                }
            }))
            alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
            presentNativeImpl?(alert)
        },
        editShortLabel: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            let currentShort = stateValue.with { $0.draft.shortLabel }
            let alert = UIAlertController(title: ru ? "Короткая метка" : "Short tag", message: ru ? "Показывается, если не выбран кастомный эмодзи." : "Shown when no custom emoji is chosen.", preferredStyle: .alert)
            alert.addTextField { tf in
                tf.text = currentShort
                tf.placeholder = "FG+"
            }
            alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { _ in
                let val = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !val.isEmpty {
                    updateState { $0.draft.shortLabel = val }
                }
            }))
            alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
            presentNativeImpl?(alert)
        },
        editToken: {
            promptAdminToken(nil)
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let changed = state.draft != state.original
        let rightButton: ItemListNavigationButton
        if state.saving {
            rightButton = ItemListNavigationButton(content: .none, style: .activity, enabled: false, action: {})
        } else {
            rightButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: changed, action: commitSave)
        }

        var entries: [FullGramBadgeDeskEntry] = [
            .previewHeader(ru ? "ПРЕДПРОСМОТР" : "PREVIEW"),
            .previewPeer(peer, state.draft, ru),
            .badgeHeader(ru ? "БЕЙДЖ FULLGRAM" : "FULLGRAM BADGE"),
            .badgeSwitch(ru ? "Бейдж" : "Badge", state.draft.enabled)
        ]

        if state.draft.enabled {
            let emojiStatus = state.draft.customEmojiId != nil ? (ru ? "Выбран" : "Chosen") : (ru ? "По умолчанию" : "Default")
            entries.append(.badgeEmoji(ru ? "Эмодзи" : "Emoji", emojiStatus))
            if state.draft.customEmojiId != nil {
                entries.append(.badgeEmojiReset(ru ? "Сбросить эмодзи" : "Reset emoji"))
            }
            entries.append(.badgeRole(ru ? "Роль" : "Role", fullGramRoleDisplayName(state.draft.roleId, russian: ru)))
            entries.append(.badgeLabel(ru ? "Текст бейджа" : "Badge text", state.draft.label))
            entries.append(.badgeShortLabel(ru ? "Короткая метка" : "Short tag", state.draft.shortLabel))
            entries.append(.badgeFooter(ru ? "Без эмодзи: стандартный значок роли" : "No emoji: the developer mark"))
        }

        entries.append(.adminHeader(ru ? "СЕРВЕР FULLGRAM" : "FULLGRAM SERVER"))
        entries.append(.adminToken(ru ? "Токен администратора" : "Admin token", FullGramAdmin.shared.hasToken ? (ru ? "Сохранён" : "Saved") : (ru ? "Не задан" : "Not set")))

        let data = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(
            presentationData: data,
            title: .text(ru ? "Бейдж" : "Badge"),
            leftNavigationButton: nil,
            rightNavigationButton: rightButton,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, args))
    }

    let controller = ItemListController(context: context, state: signal)
    weakController = controller
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    presentControllerImpl = { [weak controller] c in controller?.present(c, in: .window(.root)) }
    pushImpl = { [weak controller] c in controller?.push(c) }
    return controller
}

// MARK: - FullGram Owner Admin Panel (Settings -> FullGram -> Admin Panel)

private final class FullGramAdminPanelArguments {
    let configureToken: () -> Void
    let grantBadgeById: () -> Void
    let publishLocalPlugin: () -> Void
    let removeMarketPlugin: () -> Void
    let activateBotWebhook: () -> Void

    init(
        configureToken: @escaping () -> Void,
        grantBadgeById: @escaping () -> Void,
        publishLocalPlugin: @escaping () -> Void,
        removeMarketPlugin: @escaping () -> Void,
        activateBotWebhook: @escaping () -> Void
    ) {
        self.configureToken = configureToken
        self.grantBadgeById = grantBadgeById
        self.publishLocalPlugin = publishLocalPlugin
        self.removeMarketPlugin = removeMarketPlugin
        self.activateBotWebhook = activateBotWebhook
    }
}

private enum FullGramAdminPanelSection: Int32 {
    case auth
    case actions
}

private enum FullGramAdminPanelEntry: ItemListNodeEntry {
    case authHeader(String)
    case ownerIdRow(String, String)
    case tokenRow(String, String)
    case authFooter(String)
    case actionsHeader(String)
    case grantBadge(String)
    case publishPlugin(String)
    case deletePlugin(String)
    case activateBot(String)
    case actionsFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .authHeader, .ownerIdRow, .tokenRow, .authFooter:
            return FullGramAdminPanelSection.auth.rawValue
        case .actionsHeader, .grantBadge, .publishPlugin, .deletePlugin, .activateBot, .actionsFooter:
            return FullGramAdminPanelSection.actions.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .authHeader: return 0
        case .ownerIdRow: return 1
        case .tokenRow: return 2
        case .authFooter: return 3
        case .actionsHeader: return 10
        case .grantBadge: return 11
        case .publishPlugin: return 12
        case .deletePlugin: return 13
        case .activateBot: return 14
        case .actionsFooter: return 15
        }
    }

    static func < (lhs: FullGramAdminPanelEntry, rhs: FullGramAdminPanelEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramAdminPanelArguments
        switch self {
        case let .authHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ownerIdRow(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {})
        case let .tokenRow(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.configureToken)
        case let .authFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .actionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .grantBadge(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.grantBadgeById)
        case let .publishPlugin(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.publishLocalPlugin)
        case let .deletePlugin(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.removeMarketPlugin)
        case let .activateBot(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.activateBotWebhook)
        case let .actionsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramAdminController(context: AccountContext) -> ViewController {
    guard fullGramCanOpenAdmin(context: context) else {
        return fullGramPluginsController(context: context)
    }

    var presentNativeImpl: ((UIViewController) -> Void)?
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
    }

    let showAlert: (String, String) -> Void = { title, message in
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentNativeImpl?(alert)
    }

    let args = FullGramAdminPanelArguments(
        configureToken: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            let alert = UIAlertController(
                title: ru ? "Токен администратора" : "Admin token",
                message: ru ? "Сохраняется только локально в iOS Keychain." : "Stored locally in iOS Keychain only.",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "ADMIN_TOKEN"
                tf.isSecureTextEntry = true
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: ru ? "Сохранить" : "Save", style: .default, handler: { _ in
                FullGramAdmin.shared.setToken(alert.textFields?.first?.text ?? "")
                bump()
            }))
            if FullGramAdmin.shared.hasToken {
                alert.addAction(UIAlertAction(title: ru ? "Удалить" : "Clear", style: .destructive, handler: { _ in
                    FullGramAdmin.shared.clearToken()
                    bump()
                }))
            }
            alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
            presentNativeImpl?(alert)
        },
        grantBadgeById: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            let alert = UIAlertController(
                title: ru ? "Выдать / снять бейдж" : "Grant / remove badge",
                message: ru ? "Укажите Telegram ID или @username и роль (creator, official, premium, dev или off)." : "Enter Telegram ID or @username and role (creator, official, premium, dev, or off).",
                preferredStyle: .alert
            )
            alert.addTextField { tf in
                tf.placeholder = "ID / @username"
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addTextField { tf in
                tf.text = "premium"
                tf.placeholder = "premium / dev / official / creator / off"
                tf.autocorrectionType = .no
                tf.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: ru ? "Применить" : "Apply", style: .default, handler: { _ in
                let target = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let role = (alert.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !target.isEmpty, !role.isEmpty else { return }
                let numericId = Int64(target)
                let enabled = role != "off" && role != "none" && role != "remove"
                FullGramAdmin.shared.updateBadge(
                    peerId: numericId,
                    username: numericId == nil ? target : nil,
                    enabled: enabled,
                    roleId: enabled ? role : nil,
                    customEmojiId: nil,
                    emoji: nil,
                    label: nil,
                    shortLabel: nil,
                    color: nil
                ) { res in
                    switch res {
                    case .success:
                        showAlert(ru ? "Готово" : "Done", enabled ? (ru ? "Бейдж выдан." : "Badge granted.") : (ru ? "Бейдж снят." : "Badge removed."))
                    case let .failure(err):
                        showAlert(ru ? "Ошибка" : "Error", err.localizedDescription)
                    }
                }
            }))
            alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
            presentNativeImpl?(alert)
        },
        publishLocalPlugin: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            let plugins = FullGramPluginManager.shared.allPlugins()
            let sheet = UIAlertController(
                title: ru ? "Опубликовать плагин в маркет" : "Publish plugin to market",
                message: ru ? "Выберите локальный плагин для публикации на сервер:" : "Choose a local plugin to publish:",
                preferredStyle: .actionSheet
            )
            for item in plugins {
                sheet.addAction(UIAlertAction(title: "\(item.name) [\(item.language.displayName)]", style: .default, handler: { _ in
                    FullGramAdmin.shared.publishPlugin(
                        id: item.id,
                        name: item.name,
                        language: item.language,
                        version: item.version,
                        author: item.author.isEmpty ? "shermanko" : item.author,
                        description: item.description,
                        code: item.code
                    ) { res in
                        switch res {
                        case let .success(published):
                            showAlert(ru ? "Опубликовано" : "Published", "\(published.name) (\(published.id))")
                        case let .failure(err):
                            showAlert(ru ? "Ошибка" : "Error", err.localizedDescription)
                        }
                    }
                }))
            }
            sheet.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
            presentNativeImpl?(sheet)
        },
        removeMarketPlugin: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            FullGramPluginManager.shared.fetchRemoteCatalog { res in
                switch res {
                case let .failure(err):
                    showAlert(ru ? "Ошибка" : "Error", err.localizedDescription)
                case let .success(catalog):
                    guard !catalog.plugins.isEmpty else {
                        showAlert(ru ? "Маркет пуст" : "Market is empty", ru ? "В маркете сейчас нет плагинов." : "No plugins in market.")
                        return
                    }
                    let sheet = UIAlertController(title: ru ? "Удалить из маркета" : "Delete from market", message: nil, preferredStyle: .actionSheet)
                    for item in catalog.plugins {
                        sheet.addAction(UIAlertAction(title: "\(item.name) (\(item.id))", style: .destructive, handler: { _ in
                            FullGramAdmin.shared.deleteMarketPlugin(id: item.id) { delRes in
                                switch delRes {
                                case .success:
                                    showAlert(ru ? "Удалено" : "Deleted", item.name)
                                case let .failure(err):
                                    showAlert(ru ? "Ошибка" : "Error", err.localizedDescription)
                                }
                            }
                        }))
                    }
                    sheet.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
                    presentNativeImpl?(sheet)
                }
            }
        },
        activateBotWebhook: {
            let ru = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("ru")
            FullGramAdmin.shared.setupTelegramWebhook { res in
                switch res {
                case let .success(url):
                    showAlert(ru ? "Бот активирован" : "Bot webhook active", url)
                case let .failure(err):
                    showAlert(ru ? "Ошибка" : "Error", err.localizedDescription)
                }
            }
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, refresh.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let entries: [FullGramAdminPanelEntry] = [
            .authHeader(ru ? "ДОСТУП ВЛАДЕЛЬЦА" : "OWNER ACCESS"),
            .ownerIdRow(ru ? "Ваш Telegram ID" : "Owner Telegram ID", String(FullGramAdmin.ownerUserId)),
            .tokenRow(ru ? "Токен администратора" : "Admin token", FullGramAdmin.shared.hasToken ? (ru ? "Сохранён" : "Saved") : (ru ? "Не задан" : "Not set")),
            .authFooter(ru ? "Админ-панель и кнопка «Бейдж» в профилях видны только аккаунту с вашим ID." : "The admin panel and profile Badge row are visible only to your owner account ID."),
            .actionsHeader(ru ? "УПРАВЛЕНИЕ БЕЙДЖАМИ И МАРКЕТОМ" : "BADGES & PLUGIN MARKET"),
            .grantBadge(ru ? "Выдать или снять бейдж по ID / @username" : "Grant or remove badge by ID / @username"),
            .publishPlugin(ru ? "Опубликовать локальный плагин в маркет" : "Publish local plugin to market"),
            .deletePlugin(ru ? "Удалить плагин из маркета" : "Delete plugin from market"),
            .activateBot(ru ? "Проверить / обновить Telegram-бота" : "Verify / refresh Telegram bot webhook"),
            .actionsFooter(ru ? "Плагины также можно публиковать напрямую через вашего Telegram-бота — просто отправьте ему файл .lua или .py." : "You can also publish plugins by sending .lua or .py files directly to your Telegram admin bot.")
        ]

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text(ru ? "Админ-панель FullGram" : "FullGram Admin"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }

    let controller = ItemListController(context: context, state: signal)
    presentNativeImpl = { [weak controller] vc in controller?.present(vc, animated: true) }
    return controller
}
