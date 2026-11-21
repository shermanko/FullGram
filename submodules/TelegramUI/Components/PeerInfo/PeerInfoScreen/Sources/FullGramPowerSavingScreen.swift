import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI

// MARK: - Power Saving Screen (FullGram → Прочее → Энергосбережение)

private final class FullGramPowerSavingArguments {
    let selectMode: (FullGramPowerSaving.Mode) -> Void
    let adjustThreshold: (Int) -> Void
    let toggleFollowLowPower: (Bool) -> Void
    let toggleOnBatteryOnly: (Bool) -> Void
    let toggleLimit: (FullGramPowerSaving.Limit, Bool) -> Void
    let resetProfile: () -> Void

    init(
        selectMode: @escaping (FullGramPowerSaving.Mode) -> Void,
        adjustThreshold: @escaping (Int) -> Void,
        toggleFollowLowPower: @escaping (Bool) -> Void,
        toggleOnBatteryOnly: @escaping (Bool) -> Void,
        toggleLimit: @escaping (FullGramPowerSaving.Limit, Bool) -> Void,
        resetProfile: @escaping () -> Void
    ) {
        self.selectMode = selectMode
        self.adjustThreshold = adjustThreshold
        self.toggleFollowLowPower = toggleFollowLowPower
        self.toggleOnBatteryOnly = toggleOnBatteryOnly
        self.toggleLimit = toggleLimit
        self.resetProfile = resetProfile
    }
}

private enum FullGramPowerSavingSection: Int32 {
    case mode = 0
    case conditions = 1
    case limits = 2
    case reset = 3
}

private enum FullGramPowerSavingEntry: ItemListNodeEntry {
    case modeHeader(String)
    case modeRow(Int32, FullGramPowerSaving.Mode, Bool)
    case conditionsHeader(String)
    case thresholdRow(Int)
    case followLowPower(Bool)
    case onBatteryOnly(Bool)
    case limitsHeader(String)
    case limitRow(Int32, FullGramPowerSaving.Limit, Bool)
    case resetAction(String)

    var section: ItemListSectionId {
        switch self {
        case .modeHeader, .modeRow: return FullGramPowerSavingSection.mode.rawValue
        case .conditionsHeader, .thresholdRow, .followLowPower, .onBatteryOnly: return FullGramPowerSavingSection.conditions.rawValue
        case .limitsHeader, .limitRow: return FullGramPowerSavingSection.limits.rawValue
        case .resetAction: return FullGramPowerSavingSection.reset.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .modeHeader: return 10
        case let .modeRow(i, _, _): return 11 + i
        case .conditionsHeader: return 20
        case .thresholdRow: return 21
        case .followLowPower: return 22
        case .onBatteryOnly: return 23
        case .limitsHeader: return 30
        case let .limitRow(i, _, _): return 31 + i
        case .resetAction: return 50
        }
    }

    static func < (lhs: FullGramPowerSavingEntry, rhs: FullGramPowerSavingEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramPowerSavingArguments
        switch self {
        case let .modeHeader(text), let .conditionsHeader(text), let .limitsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .modeRow(_, mode, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: mode.title, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section) {
                args.selectMode(mode)
            }
        case let .thresholdRow(threshold):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Порог заряда батареи", label: "\(threshold)%", sectionId: self.section, style: .blocks, disclosureStyle: .arrow) {
                let next = threshold >= 95 ? 5 : threshold + 5
                args.adjustThreshold(next)
            }
        case let .followLowPower(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Системный режим экономии", value: value, sectionId: self.section, style: .blocks, updated: args.toggleFollowLowPower)
        case let .onBatteryOnly(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Всегда без зарядки", value: value, sectionId: self.section, style: .blocks, updated: args.toggleOnBatteryOnly)
        case let .limitRow(_, limit, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: limit.title, value: enabled, sectionId: self.section, style: .blocks) { v in
                args.toggleLimit(limit, v)
            }
        case let .resetAction(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.resetProfile)
        }
    }
}

func fullGramPowerSavingController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
    }

    let args = FullGramPowerSavingArguments(
        selectMode: { mode in
            var profile = FullGramPowerSaving.profile()
            profile.mode = mode
            FullGramPowerSaving.setProfile(profile)
            bump()
        },
        adjustThreshold: { next in
            var profile = FullGramPowerSaving.profile()
            profile.threshold = next
            FullGramPowerSaving.setProfile(profile)
            bump()
        },
        toggleFollowLowPower: { value in
            var profile = FullGramPowerSaving.profile()
            profile.followLowPowerMode = value
            FullGramPowerSaving.setProfile(profile)
            bump()
        },
        toggleOnBatteryOnly: { value in
            var profile = FullGramPowerSaving.profile()
            profile.onBatteryOnly = value
            FullGramPowerSaving.setProfile(profile)
            bump()
        },
        toggleLimit: { limit, shouldDisable in
            var profile = FullGramPowerSaving.profile()
            if shouldDisable {
                profile.limits.insert(limit)
            } else {
                profile.limits.remove(limit)
            }
            FullGramPowerSaving.setProfile(profile)
            bump()
        },
        resetProfile: {
            FullGramPowerSaving.reset()
            bump()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let profile = FullGramPowerSaving.profile()
        var entries: [FullGramPowerSavingEntry] = [
            .modeHeader("РЕЖИМ ЭНЕРГОСБЕРЕЖЕНИЯ")
        ]
        for (idx, mode) in FullGramPowerSaving.Mode.allCases.enumerated() {
            entries.append(.modeRow(Int32(idx), mode, mode == profile.mode))
        }
        if profile.mode == .battery {
            entries.append(.conditionsHeader("УСЛОВИЯ ВКЛЮЧЕНИЯ"))
            entries.append(.thresholdRow(profile.threshold))
            entries.append(.followLowPower(profile.followLowPowerMode))
            entries.append(.onBatteryOnly(profile.onBatteryOnly))
        }
        if profile.mode == .battery || profile.mode == .always {
            entries.append(.limitsHeader("ОТКЛЮЧАТЬ ПРИ ЭКОНОМИИ"))
            for (idx, limit) in FullGramPowerSaving.Limit.allCases.enumerated() {
                entries.append(.limitRow(Int32(idx), limit, profile.limits.contains(limit)))
            }
        }
        entries.append(.resetAction("Сбросить настройки"))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Энергосбережение"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - Player Night Look Screen (FullGram → Медиа и Аудио → Ночной режим плеера)

private final class FullGramPlayerNightLookArguments {
    let toggleEnabled: (Bool) -> Void
    let selectMode: (FullGramPlayerNightLook.Mode) -> Void
    let cycleStartHour: () -> Void
    let cycleEndHour: () -> Void
    let selectStrength: (FullGramPlayerNightLook.Strength) -> Void
    let selectTint: (FullGramPlayerNightLook.Tint) -> Void
    let reset: () -> Void

    init(
        toggleEnabled: @escaping (Bool) -> Void,
        selectMode: @escaping (FullGramPlayerNightLook.Mode) -> Void,
        cycleStartHour: @escaping () -> Void,
        cycleEndHour: @escaping () -> Void,
        selectStrength: @escaping (FullGramPlayerNightLook.Strength) -> Void,
        selectTint: @escaping (FullGramPlayerNightLook.Tint) -> Void,
        reset: @escaping () -> Void
    ) {
        self.toggleEnabled = toggleEnabled
        self.selectMode = selectMode
        self.cycleStartHour = cycleStartHour
        self.cycleEndHour = cycleEndHour
        self.selectStrength = selectStrength
        self.selectTint = selectTint
        self.reset = reset
    }
}

private enum FullGramPlayerNightLookEntry: ItemListNodeEntry {
    case enabled(Bool)
    case modeHeader(String)
    case modeRow(Int32, FullGramPlayerNightLook.Mode, Bool)
    case startHour(Int)
    case endHour(Int)
    case strengthHeader(String)
    case strengthRow(Int32, FullGramPlayerNightLook.Strength, Bool)
    case tintHeader(String)
    case tintRow(Int32, FullGramPlayerNightLook.Tint, Bool)
    case resetAction

    var section: ItemListSectionId {
        switch self {
        case .enabled: return 0
        case .modeHeader, .modeRow, .startHour, .endHour: return 1
        case .strengthHeader, .strengthRow: return 2
        case .tintHeader, .tintRow: return 3
        case .resetAction: return 4
        }
    }

    var stableId: Int32 {
        switch self {
        case .enabled: return 0
        case .modeHeader: return 10
        case let .modeRow(i, _, _): return 11 + i
        case .startHour: return 15
        case .endHour: return 16
        case .strengthHeader: return 20
        case let .strengthRow(i, _, _): return 21 + i
        case .tintHeader: return 30
        case let .tintRow(i, _, _): return 31 + i
        case .resetAction: return 40
        }
    }

    static func < (lhs: FullGramPlayerNightLookEntry, rhs: FullGramPlayerNightLookEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramPlayerNightLookArguments
        switch self {
        case let .enabled(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Ночной режим плеера", value: value, sectionId: self.section, style: .blocks, updated: args.toggleEnabled)
        case let .modeHeader(text), let .strengthHeader(text), let .tintHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .modeRow(_, mode, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: mode.title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section) {
                args.selectMode(mode)
            }
        case let .startHour(hour):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Начало", label: String(format: "%02d:00", hour), sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.cycleStartHour)
        case let .endHour(hour):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Конец", label: String(format: "%02d:00", hour), sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: args.cycleEndHour)
        case let .strengthRow(_, strength, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: strength.title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section) {
                args.selectStrength(strength)
            }
        case let .tintRow(_, tint, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: tint.title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section) {
                args.selectTint(tint)
            }
        case .resetAction:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Сбросить настройки", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: args.reset)
        }
    }
}

func fullGramPlayerNightLookController(context: AccountContext, onChanged: @escaping () -> Void = {}) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
        onChanged()
    }

    let args = FullGramPlayerNightLookArguments(
        toggleEnabled: { value in
            FullGramPlayerNightLook.isEnabled = value
            bump()
        },
        selectMode: { mode in
            FullGramPlayerNightLook.mode = mode
            bump()
        },
        cycleStartHour: {
            FullGramPlayerNightLook.startHour = (FullGramPlayerNightLook.startHour + 1) % 24
            bump()
        },
        cycleEndHour: {
            FullGramPlayerNightLook.endHour = (FullGramPlayerNightLook.endHour + 1) % 24
            bump()
        },
        selectStrength: { strength in
            FullGramPlayerNightLook.strength = strength
            bump()
        },
        selectTint: { tint in
            FullGramPlayerNightLook.tint = tint
            bump()
        },
        reset: {
            FullGramPlayerNightLook.reset()
            bump()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [FullGramPlayerNightLookEntry] = [
            .enabled(FullGramPlayerNightLook.isEnabled)
        ]
        if FullGramPlayerNightLook.isEnabled {
            entries.append(.modeHeader("РЕЖИМ РАБОТЫ"))
            for (i, mode) in FullGramPlayerNightLook.Mode.allCases.enumerated() {
                entries.append(.modeRow(Int32(i), mode, mode == FullGramPlayerNightLook.mode))
            }
            if FullGramPlayerNightLook.mode == .schedule {
                entries.append(.startHour(FullGramPlayerNightLook.startHour))
                entries.append(.endHour(FullGramPlayerNightLook.endHour))
            }
            entries.append(.strengthHeader("СИЛА ЗАТЕМНЕНИЯ"))
            for (i, s) in FullGramPlayerNightLook.Strength.allCases.enumerated() {
                entries.append(.strengthRow(Int32(i), s, s == FullGramPlayerNightLook.strength))
            }
            entries.append(.tintHeader("ОТТЕНОК"))
            for (i, t) in FullGramPlayerNightLook.Tint.allCases.enumerated() {
                entries.append(.tintRow(Int32(i), t, t == FullGramPlayerNightLook.tint))
            }
            entries.append(.resetAction)
        }
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Ночной режим плеера"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, args))
    }

    return ItemListController(context: context, state: signal)
}
