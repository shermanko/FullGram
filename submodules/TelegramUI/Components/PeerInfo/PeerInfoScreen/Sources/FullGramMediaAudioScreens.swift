import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Category Root: Медиа и Аудио

private final class FullGramMediaAudioCategoryArguments {
    let openVoice: () -> Void
    let openRoundVideo: () -> Void
    let openMixer: () -> Void
    let openLyricsSources: () -> Void

    init(
        openVoice: @escaping () -> Void,
        openRoundVideo: @escaping () -> Void,
        openMixer: @escaping () -> Void,
        openLyricsSources: @escaping () -> Void
    ) {
        self.openVoice = openVoice
        self.openRoundVideo = openRoundVideo
        self.openMixer = openMixer
        self.openLyricsSources = openLyricsSources
    }
}

private enum FullGramMediaAudioCategorySection: Int32 {
    case main
}

private enum FullGramMediaAudioCategoryEntry: ItemListNodeEntry {
    case voice(String, String)
    case roundVideo(String, String)
    case mixer(String, String)
    case lyricsSources(String, String)

    var section: ItemListSectionId {
        return FullGramMediaAudioCategorySection.main.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .voice: return 0
        case .roundVideo: return 1
        case .mixer: return 2
        case .lyricsSources: return 3
        }
    }

    static func < (lhs: FullGramMediaAudioCategoryEntry, rhs: FullGramMediaAudioCategoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramMediaAudioCategoryArguments
        switch self {
        case let .voice(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.openVoice)
        case let .roundVideo(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.openRoundVideo)
        case let .mixer(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.openMixer)
        case let .lyricsSources(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.openLyricsSources)
        }
    }
}

func fullGramMediaAudioCategoryController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
    }

    let args = FullGramMediaAudioCategoryArguments(
        openVoice: { pushImpl?(fullGramVoiceController(context: context, onChanged: bump)) },
        openRoundVideo: { pushImpl?(fullGramRoundVideoController(context: context, onChanged: bump)) },
        openMixer: { pushImpl?(fullGramMixerController(context: context, onChanged: bump)) },
        openLyricsSources: { pushImpl?(fullGramLyricsSourcesController(context: context, onChanged: bump)) }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let voiceValue = FullGramVoiceMode.current.title(ru)
        let roundValue = "\(FullGramRoundVideoSettings.resolution)p • \(FullGramRoundVideoSettings.fps) FPS"
        let mixerPreset = FullGramMixer.presets.first(where: { $0.id == FullGramMixer.presetId })?.title(ru) ?? (ru ? "Свой" : "Custom")
        let mixerValue = FullGramMixer.isEnabled ? mixerPreset : (ru ? "Выкл" : "Off")
        let sourcesCount = [
            FullGramLyricsProviderSettings.useLrclib,
            FullGramLyricsProviderSettings.useLyricsOvh,
            FullGramLyricsProviderSettings.useNetEase
        ].filter { $0 }.count

        let entries: [FullGramMediaAudioCategoryEntry] = [
            .voice("Голос", voiceValue),
            .roundVideo("Кружки и камера", roundValue),
            .mixer("Микшер", mixerValue),
            .lyricsSources("Источники текстов песен", "\(sourcesCount)/3")
        ]
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Медиа и Аудио"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, args))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in controller?.push(c) }
    return controller
}

// MARK: - Голос (шумоподавление + изменение голоса + конструктор + запикивание + авто-резюме)

private final class FullGramAudioPickerBridge: NSObject, UIDocumentPickerDelegate {
    var onPicked: ((URL) -> Void)?
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        self.onPicked?(url)
    }
}

private final class FullGramVoiceArguments {
    let selectNoise: (FullGramNoiseReductionMode) -> Void
    let selectVoice: (FullGramVoiceMode) -> Void
    let chooseCustomPitch: () -> Void
    let chooseCustomEcho: () -> Void
    let chooseCustomWarmth: () -> Void
    let resetCustomVoice: () -> Void
    let selectBleep: (FullGramBleepSound) -> Void
    let recordCustomBleep: () -> Void
    let importCustomBleepFile: () -> Void
    let selectSummaryMode: (FullGramVoiceSummaryMode) -> Void
    let runTest: () -> Void

    init(
        selectNoise: @escaping (FullGramNoiseReductionMode) -> Void,
        selectVoice: @escaping (FullGramVoiceMode) -> Void,
        chooseCustomPitch: @escaping () -> Void,
        chooseCustomEcho: @escaping () -> Void,
        chooseCustomWarmth: @escaping () -> Void,
        resetCustomVoice: @escaping () -> Void,
        selectBleep: @escaping (FullGramBleepSound) -> Void,
        recordCustomBleep: @escaping () -> Void,
        importCustomBleepFile: @escaping () -> Void,
        selectSummaryMode: @escaping (FullGramVoiceSummaryMode) -> Void,
        runTest: @escaping () -> Void
    ) {
        self.selectNoise = selectNoise
        self.selectVoice = selectVoice
        self.chooseCustomPitch = chooseCustomPitch
        self.chooseCustomEcho = chooseCustomEcho
        self.chooseCustomWarmth = chooseCustomWarmth
        self.resetCustomVoice = resetCustomVoice
        self.selectBleep = selectBleep
        self.recordCustomBleep = recordCustomBleep
        self.importCustomBleepFile = importCustomBleepFile
        self.selectSummaryMode = selectSummaryMode
        self.runTest = runTest
    }
}

private enum FullGramVoiceSection: Int32 {
    case previewTest
    case noiseReduction
    case voiceMode
    case customVoice
    case bleepSound
    case voiceSummary
}

private enum FullGramVoiceEntry: ItemListNodeEntry {
    case testHeader(String)
    case testButton(String, ItemListActionKind)
    case testFooter(String)
    case noiseHeader(String)
    case noiseOption(Int32, FullGramNoiseReductionMode, String, Bool)
    case noiseFooter(String)
    case voiceHeader(String)
    case voiceOption(Int32, FullGramVoiceMode, String, Bool)
    case voiceFooter(String)
    case customHeader(String)
    case customPitch(String, String)
    case customEcho(String, String)
    case customWarmth(String, String)
    case customReset(String)
    case customFooter(String)
    case bleepHeader(String)
    case bleepOption(Int32, FullGramBleepSound, String, Bool)
    case bleepRecordCustom(String, ItemListActionKind)
    case bleepImportCustom(String)
    case bleepFooter(String)
    case summaryHeader(String)
    case summaryOption(Int32, FullGramVoiceSummaryMode, String, Bool)
    case summaryFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .testHeader, .testButton, .testFooter: return FullGramVoiceSection.previewTest.rawValue
        case .noiseHeader, .noiseOption, .noiseFooter: return FullGramVoiceSection.noiseReduction.rawValue
        case .voiceHeader, .voiceOption, .voiceFooter: return FullGramVoiceSection.voiceMode.rawValue
        case .customHeader, .customPitch, .customEcho, .customWarmth, .customReset, .customFooter: return FullGramVoiceSection.customVoice.rawValue
        case .bleepHeader, .bleepOption, .bleepRecordCustom, .bleepImportCustom, .bleepFooter: return FullGramVoiceSection.bleepSound.rawValue
        case .summaryHeader, .summaryOption, .summaryFooter: return FullGramVoiceSection.voiceSummary.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .testHeader: return 0
        case .testButton: return 1
        case .testFooter: return 2
        case .noiseHeader: return 10
        case let .noiseOption(idx, _, _, _): return 11 + idx
        case .noiseFooter: return 29
        case .voiceHeader: return 30
        case let .voiceOption(idx, _, _, _): return 31 + idx
        case .voiceFooter: return 59
        case .customHeader: return 60
        case .customPitch: return 61
        case .customEcho: return 62
        case .customWarmth: return 63
        case .customReset: return 64
        case .customFooter: return 65
        case .bleepHeader: return 100
        case let .bleepOption(idx, _, _, _): return 110 + idx
        case .bleepRecordCustom: return 140
        case .bleepImportCustom: return 141
        case .bleepFooter: return 150
        case .summaryHeader: return 200
        case let .summaryOption(idx, _, _, _): return 201 + idx
        case .summaryFooter: return 220
        }
    }

    static func < (lhs: FullGramVoiceEntry, rhs: FullGramVoiceEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramVoiceArguments
        switch self {
        case let .testHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .testButton(title, kind):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: kind, alignment: .center, sectionId: self.section, style: .blocks, action: {
                args.runTest()
            })
        case let .testFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .noiseHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .noiseOption(_, mode, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectNoise(mode)
            })
        case let .noiseFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .voiceHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .voiceOption(_, mode, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectVoice(mode)
            })
        case let .voiceFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .customHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .customPitch(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.chooseCustomPitch)
        case let .customEcho(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.chooseCustomEcho)
        case let .customWarmth(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: args.chooseCustomWarmth)
        case let .customReset(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.resetCustomVoice)
        case let .customFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .bleepHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .bleepOption(_, sound, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectBleep(sound)
            })
        case let .bleepRecordCustom(title, kind):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: kind, alignment: .natural, sectionId: self.section, style: .blocks, action: args.recordCustomBleep)
        case let .bleepImportCustom(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: args.importCustomBleepFile)
        case let .bleepFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .summaryHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .summaryOption(_, mode, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectSummaryMode(mode)
            })
        case let .summaryFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramVoiceController(context: AccountContext, onChanged: @escaping () -> Void = {}) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
        onChanged()
    }

    let tester = FullGramVoiceTester()
    tester.onStateChange = { _ in
        tick += 1
        refresh.set(tick)
    }

    let customRecorder = FullGramCustomBleepRecorder()
    customRecorder.onStateChange = { _ in
        tick += 1
        refresh.set(tick)
    }
    customRecorder.onCompleted = { _ in
        bump()
    }

    let pickerBridge = FullGramAudioPickerBridge()
    pickerBridge.onPicked = { url in
        if FullGramCustomBleepStore.shared.importAudioFile(from: url) {
            FullGramBleepSound.current = .custom
        }
        bump()
    }

    var presentUIKitImpl: ((UIViewController) -> Void)?

    let args = FullGramVoiceArguments(
        selectNoise: { mode in
            FullGramNoiseReductionMode.current = mode
            bump()
        },
        selectVoice: { mode in
            FullGramVoiceMode.current = mode
            bump()
        },
        chooseCustomPitch: {
            let sheet = UIAlertController(title: "Тон голоса (Pitch)", message: "Выберите высоту тона для своего голоса:", preferredStyle: .actionSheet)
            let options: [(String, Float)] = [
                ("0.60x — Ультра-бас (-9 пт)", 0.60),
                ("0.72x — Глубокий бас (-6 пт)", 0.72),
                ("0.85x — Мягкий баритон (-3 пт)", 0.85),
                ("1.00x — Оригинальный тон (0 пт)", 1.00),
                ("1.18x — Слегка выше (+3 пт)", 1.18),
                ("1.35x — Мультяшный (+5 пт)", 1.35),
                ("1.55x — Гелий / Бурундук (+8 пт)", 1.55)
            ]
            for (label, val) in options {
                sheet.addAction(UIAlertAction(title: label, style: .default) { _ in
                    FullGramCustomVoiceSettings.pitch = val
                    FullGramVoiceMode.current = .custom
                    bump()
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentUIKitImpl?(sheet)
        },
        chooseCustomEcho: {
            let sheet = UIAlertController(title: "Эхо и Реверберация", message: "Выберите уровень объёмного эха:", preferredStyle: .actionSheet)
            let options: [(String, Float)] = [
                ("Выкл (0%)", 0.0),
                ("Лёгкая комната (15%)", 0.15),
                ("Студийный холл (30%)", 0.30),
                ("Глубокое эхо (50%)", 0.50),
                ("Космос / Собор (70%)", 0.70)
            ]
            for (label, val) in options {
                sheet.addAction(UIAlertAction(title: label, style: .default) { _ in
                    FullGramCustomVoiceSettings.echo = val
                    FullGramVoiceMode.current = .custom
                    bump()
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentUIKitImpl?(sheet)
        },
        chooseCustomWarmth: {
            let sheet = UIAlertController(title: "Тембр (Warmth / EQ)", message: "Настройте окраску голоса:", preferredStyle: .actionSheet)
            let options: [(String, Float)] = [
                ("Яркий радио-голос (-80%)", -0.8),
                ("Чёткий диктор (-40%)", -0.4),
                ("Нейтральный (0%)", 0.0),
                ("Тёплый подкаст (+50%)", 0.5),
                ("Бархатный бас (+100%)", 1.0)
            ]
            for (label, val) in options {
                sheet.addAction(UIAlertAction(title: label, style: .default) { _ in
                    FullGramCustomVoiceSettings.warmth = val
                    FullGramVoiceMode.current = .custom
                    bump()
                })
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            presentUIKitImpl?(sheet)
        },
        resetCustomVoice: {
            FullGramCustomVoiceSettings.reset()
            bump()
        },
        selectBleep: { sound in
            FullGramBleepSound.current = sound
            bump()
        },
        recordCustomBleep: {
            customRecorder.toggleRecord()
        },
        importCustomBleepFile: {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
            picker.delegate = pickerBridge
            presentUIKitImpl?(picker)
        },
        selectSummaryMode: { mode in
            FullGramVoiceSummaryMode.current = mode
            bump()
        },
        runTest: {
            tester.toggleTest()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let currentNoise = FullGramNoiseReductionMode.current
        let currentVoice = FullGramVoiceMode.current
        let currentBleep = FullGramBleepSound.current
        let currentSummary = FullGramVoiceSummaryMode.current

        let testTitle: String
        let testKind: ItemListActionKind
        switch tester.state {
        case .idle:
            testTitle = "🎙 Тест голоса, шумодава и запикивания (3 сек)"
            testKind = .generic
        case let .recording(remaining):
            testTitle = "🔴 Запись: \(remaining) сек… (нажмите чтобы прослушать)"
            testKind = .destructive
        case .processing:
            testTitle = "⏳ Обработка эффекта и распознавание…"
            testKind = .neutral
        case .playing:
            testTitle = "🔊 Воспроизведение… (нажмите чтобы остановить)"
            testKind = .generic
        case let .error(message):
            testTitle = "⚠️ \(message) — повторить тест"
            testKind = .destructive
        }

        var entries: [FullGramVoiceEntry] = []
        entries.append(.testHeader("ПРОВЕРКА ПЕРЕД ОТПРАВКОЙ"))
        entries.append(.testButton(testTitle, testKind))
        entries.append(.testFooter("Запишите 3 секунды голоса и сразу услышьте результат: шумодав (\(currentNoise.title(ru))), голос (\(currentVoice.title(ru))) и анти-мат (\(currentBleep.title(ru)))."))

        entries.append(.noiseHeader("ШУМОПОДАВЛЕНИЕ И СТУДИЙНЫЙ МИКРОФОН"))
        for (idx, nMode) in FullGramNoiseReductionMode.allCases.enumerated() {
            entries.append(.noiseOption(Int32(idx), nMode, nMode.title(ru), nMode == currentNoise))
        }
        entries.append(.noiseFooter(currentNoise.subtitle(ru)))

        entries.append(.voiceHeader("ИЗМЕНЕНИЕ ГОЛОСА"))
        for (idx, mode) in FullGramVoiceMode.allCases.enumerated() {
            entries.append(.voiceOption(Int32(idx), mode, mode.title(ru), mode == currentVoice))
        }
        entries.append(.voiceFooter("Выберите готовый эффект или включите «🎛 Свой голос (Конструктор)» для ручной настройки тона, эха и тембра."))

        entries.append(.customHeader("КОНСТРУКТОР СВОЕГО ГОЛОСА"))
        entries.append(.customPitch("Тон голоса (Pitch)", FullGramCustomVoiceSettings.pitchFormatted()))
        entries.append(.customEcho("Эхо / Реверберация", FullGramCustomVoiceSettings.echoFormatted()))
        entries.append(.customWarmth("Тембр (Warmth EQ)", FullGramCustomVoiceSettings.warmthFormatted()))
        entries.append(.customReset("Сбросить настройки конструктора"))
        entries.append(.customFooter("При изменении любого параметра конструктор автоматически включает режим «🎛 Свой голос»."))

        entries.append(.bleepHeader("ЗАПИКИВАНИЕ МАТОВ И СВОЙ ЗВУК"))
        for (idx, sound) in FullGramBleepSound.allCases.enumerated() {
            let title: String
            if sound == .custom {
                title = "\(sound.title(ru)) (\(FullGramCustomBleepStore.shared.customSoundName))"
            } else {
                title = sound.title(ru)
            }
            entries.append(.bleepOption(Int32(idx), sound, title, sound == currentBleep))
        }
        let recTitle = customRecorder.isRecording
            ? "🔴 Идёт запись звука (1.5 сек)… Нажмите чтобы сохранить"
            : "🎤 Записать свой звук запикивания (1.5 сек)"
        entries.append(.bleepRecordCustom(recTitle, customRecorder.isRecording ? .destructive : .generic))
        entries.append(.bleepImportCustom("📂 Загрузить свой звук из файла (.wav / .mp3 / .m4a)"))
        entries.append(.bleepFooter("Улучшенная морфологическая система распознаёт русские и английские маты (включая все приставки и окончания) на чистом голосе и заменяет их на выбранный или ваш собственный звук."))

        entries.append(.summaryHeader("АВТО-РЕЗЮМЕ ГОЛОСОВЫХ (⚡️ СУТЬ ГС)"))
        for (idx, sMode) in FullGramVoiceSummaryMode.allCases.enumerated() {
            entries.append(.summaryOption(Int32(idx), sMode, sMode.title(ru), sMode == currentSummary))
        }
        entries.append(.summaryFooter("При нажатии на расшифровку длинного ГС или кружка сверху автоматически добавляется краткая выжимка главных мыслей (⚡️ Суть ГС)."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Голос и Шумодав"),
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

// MARK: - Кружки и камера

private final class FullGramRoundVideoArguments {
    let selectMask: (FullGramRoundMask) -> Void
    let selectResolution: (Int) -> Void
    let selectFps: (Int) -> Void

    init(
        selectMask: @escaping (FullGramRoundMask) -> Void,
        selectResolution: @escaping (Int) -> Void,
        selectFps: @escaping (Int) -> Void
    ) {
        self.selectMask = selectMask
        self.selectResolution = selectResolution
        self.selectFps = selectFps
    }
}

private enum FullGramRoundVideoSection: Int32 {
    case masks
    case resolution
    case fps
}

private enum FullGramRoundVideoEntry: ItemListNodeEntry {
    case masksHeader(String)
    case maskOption(Int32, FullGramRoundMask, String, Bool)
    case masksFooter(String)
    case resolutionHeader(String)
    case resolutionOption(Int32, Int, String, Bool)
    case fpsHeader(String)
    case fpsOption(Int32, Int, String, Bool)
    case fpsFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .masksHeader, .maskOption, .masksFooter: return FullGramRoundVideoSection.masks.rawValue
        case .resolutionHeader, .resolutionOption: return FullGramRoundVideoSection.resolution.rawValue
        case .fpsHeader, .fpsOption, .fpsFooter: return FullGramRoundVideoSection.fps.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .masksHeader: return 0
        case let .maskOption(idx, _, _, _): return 10 + idx
        case .masksFooter: return 50
        case .resolutionHeader: return 100
        case let .resolutionOption(idx, _, _, _): return 110 + idx
        case .fpsHeader: return 200
        case let .fpsOption(idx, _, _, _): return 210 + idx
        case .fpsFooter: return 250
        }
    }

    static func < (lhs: FullGramRoundVideoEntry, rhs: FullGramRoundVideoEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramRoundVideoArguments
        switch self {
        case let .masksHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .maskOption(_, mask, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectMask(mask)
            })
        case let .masksFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .resolutionHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .resolutionOption(_, res, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectResolution(res)
            })
        case let .fpsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .fpsOption(_, fps, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.selectFps(fps)
            })
        case let .fpsFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramRoundVideoController(context: AccountContext, onChanged: @escaping () -> Void = {}) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
        onChanged()
    }

    let args = FullGramRoundVideoArguments(
        selectMask: { mask in
            FullGramRoundMask.current = mask
            bump()
        },
        selectResolution: { res in
            FullGramRoundVideoSettings.resolution = res
            bump()
        },
        selectFps: { fps in
            FullGramRoundVideoSettings.fps = fps
            bump()
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let currentMask = FullGramRoundMask.current
        let currentRes = FullGramRoundVideoSettings.resolution
        let currentFps = FullGramRoundVideoSettings.fps

        var entries: [FullGramRoundVideoEntry] = []
        entries.append(.masksHeader("МАСКИ"))
        for (idx, mask) in FullGramRoundMask.allCases.enumerated() {
            entries.append(.maskOption(Int32(idx), mask, mask.title(ru), mask == currentMask))
        }
        entries.append(.masksFooter("Меняет лицо в кружке"))

        entries.append(.resolutionHeader("РАЗРЕШЕНИЕ КРУЖКОВ"))
        for (idx, res) in FullGramRoundVideoSettings.availableResolutions.enumerated() {
            entries.append(.resolutionOption(Int32(idx), res, "\(res)×\(res)", res == currentRes))
        }

        entries.append(.fpsHeader("ЧАСТОТА КАДРОВ"))
        for (idx, fps) in FullGramRoundVideoSettings.availableFps.enumerated() {
            entries.append(.fpsOption(Int32(idx), fps, "\(fps) FPS", fps == currentFps))
        }
        entries.append(.fpsFooter("Если камера устройства не поддерживает 60 FPS для выбранного режима, автоматически используется 30 FPS."))

        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Кружки и камера"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, args))
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - Источники текстов песен

private final class FullGramLyricsSourcesArguments {
    let toggleLrclib: (Bool) -> Void
    let toggleLyricsOvh: (Bool) -> Void
    let toggleNetEase: (Bool) -> Void

    init(
        toggleLrclib: @escaping (Bool) -> Void,
        toggleLyricsOvh: @escaping (Bool) -> Void,
        toggleNetEase: @escaping (Bool) -> Void
    ) {
        self.toggleLrclib = toggleLrclib
        self.toggleLyricsOvh = toggleLyricsOvh
        self.toggleNetEase = toggleNetEase
    }
}

private enum FullGramLyricsSourcesSection: Int32 {
    case providers
}

private enum FullGramLyricsSourcesEntry: ItemListNodeEntry {
    case header(String)
    case lrclib(Bool)
    case lyricsOvh(Bool)
    case netease(Bool)
    case footer(String)

    var section: ItemListSectionId {
        return FullGramLyricsSourcesSection.providers.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .lrclib: return 1
        case .lyricsOvh: return 2
        case .netease: return 3
        case .footer: return 4
        }
    }

    static func < (lhs: FullGramLyricsSourcesEntry, rhs: FullGramLyricsSourcesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! FullGramLyricsSourcesArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .lrclib(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "LRCLIB (lrclib.net)", value: value, sectionId: self.section, style: .blocks, updated: args.toggleLrclib)
        case let .lyricsOvh(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Lyrics.ovh (api.lyrics.ovh)", value: value, sectionId: self.section, style: .blocks, updated: args.toggleLyricsOvh)
        case let .netease(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "NetEase Music (music.163.com)", value: value, sectionId: self.section, style: .blocks, updated: args.toggleNetEase)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

func fullGramLyricsSourcesController(context: AccountContext, onChanged: @escaping () -> Void = {}) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var tick = 0
    let bump: () -> Void = {
        tick += 1
        refresh.set(tick)
        onChanged()
    }

    let args = FullGramLyricsSourcesArguments(
        toggleLrclib: { FullGramLyricsProviderSettings.useLrclib = $0; bump() },
        toggleLyricsOvh: { FullGramLyricsProviderSettings.useLyricsOvh = $0; bump() },
        toggleNetEase: { FullGramLyricsProviderSettings.useNetEase = $0; bump() }
    )

    let signal = combineLatest(context.sharedContext.presentationData, refresh.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [FullGramLyricsSourcesEntry] = [
            .header("ИСТОЧНИКИ ТЕКСТОВ ПЕСЕН"),
            .lrclib(FullGramLyricsProviderSettings.useLrclib),
            .lyricsOvh(FullGramLyricsProviderSettings.useLyricsOvh),
            .netease(FullGramLyricsProviderSettings.useNetEase),
            .footer("LRCLIB и Lyrics.ovh полностью бесплатны, работают без API-ключей и без ограничений на запросы. При поиске текстов передаются только название и исполнитель трека.")
        ]
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(
            presentationData: data,
            title: .text("Источники текстов песен"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: data, entries: entries, style: .blocks)
        return (state, (listState, args))
    }

    return ItemListController(context: context, state: signal)
}

// MARK: - Микшер (редезайн полос + пресеты Дефолт, Басы, Вокал, Рок)

private final class FullGramBandFaderView: UIControl {
    var accentColor: UIColor = .systemBlue { didSet { self.updateColors() } }
    var trackColor: UIColor = UIColor.secondarySystemFill { didSet { self.updateColors() } }
    var textColor: UIColor = .label { didSet { self.valueLabel.textColor = self.textColor } }
    var secondaryColor: UIColor = .secondaryLabel { didSet { self.freqLabel.textColor = self.secondaryColor } }

    var value: Float = 0.0 {
        didSet {
            self.value = min(12.0, max(-12.0, self.value))
            self.updateLayoutAndLabel()
        }
    }

    private let valueLabel = UILabel()
    private let trackView = UIView()
    private let zeroLine = UIView()
    private let fillView = UIView()
    private let thumbView = UIView()
    private let freqLabel = UILabel()
    private let haptic = UISelectionFeedbackGenerator()
    private var lastSnappedZero = false

    init(frequency: Float) {
        super.init(frame: .zero)

        self.valueLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        self.valueLabel.textAlignment = .center
        self.valueLabel.text = "0"

        self.trackView.layer.cornerRadius = 4.0
        self.trackView.isUserInteractionEnabled = false

        self.zeroLine.backgroundColor = UIColor.label.withAlphaComponent(0.22)
        self.zeroLine.isUserInteractionEnabled = false

        self.fillView.layer.cornerRadius = 4.0
        self.fillView.isUserInteractionEnabled = false

        self.thumbView.layer.cornerRadius = 6.0
        self.thumbView.layer.shadowColor = UIColor.black.cgColor
        self.thumbView.layer.shadowOpacity = 0.18
        self.thumbView.layer.shadowRadius = 3.0
        self.thumbView.layer.shadowOffset = CGSize(width: 0.0, height: 1.5)
        self.thumbView.isUserInteractionEnabled = false

        self.freqLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        self.freqLabel.textAlignment = .center
        self.freqLabel.text = frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"

        self.addSubview(self.valueLabel)
        self.addSubview(self.trackView)
        self.trackView.addSubview(self.zeroLine)
        self.trackView.addSubview(self.fillView)
        self.addSubview(self.thumbView)
        self.addSubview(self.freqLabel)

        self.updateColors()
    }

    required init?(coder: NSCoder) { return nil }

    private func updateColors() {
        self.trackView.backgroundColor = self.trackColor
        self.fillView.backgroundColor = self.accentColor
        self.thumbView.backgroundColor = .white
        self.thumbView.layer.borderWidth = 1.5
        self.thumbView.layer.borderColor = self.accentColor.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.bounds.width
        let h = self.bounds.height
        self.valueLabel.frame = CGRect(x: 0.0, y: 0.0, width: w, height: 16.0)
        self.freqLabel.frame = CGRect(x: 0.0, y: h - 16.0, width: w, height: 16.0)

        let trackTop: CGFloat = 22.0
        let trackBottom: CGFloat = h - 22.0
        let trackHeight = max(40.0, trackBottom - trackTop)
        let trackWidth: CGFloat = 8.0
        self.trackView.frame = CGRect(x: (w - trackWidth) / 2.0, y: trackTop, width: trackWidth, height: trackHeight)
        self.zeroLine.frame = CGRect(x: -4.0, y: trackHeight / 2.0 - 0.5, width: trackWidth + 8.0, height: 1.0)
        self.updateLayoutAndLabel()
    }

    private func updateLayoutAndLabel() {
        let text = self.value == 0.0 ? "0" : String(format: self.value == self.value.rounded() ? "%+.0f" : "%+.1f", self.value)
        self.valueLabel.text = text

        let trackHeight = self.trackView.bounds.height
        guard trackHeight > 0.0 else { return }
        let normalized = CGFloat((12.0 - self.value) / 24.0) // 0 at +12, 1 at -12
        let centerY = self.trackView.frame.minY + normalized * trackHeight
        let midY = trackHeight / 2.0
        let relY = normalized * trackHeight

        if relY <= midY {
            self.fillView.frame = CGRect(x: 0.0, y: relY, width: self.trackView.bounds.width, height: midY - relY)
        } else {
            self.fillView.frame = CGRect(x: 0.0, y: midY, width: self.trackView.bounds.width, height: relY - midY)
        }

        let thumbW: CGFloat = min(22.0, max(16.0, self.bounds.width - 6.0))
        let thumbH: CGFloat = 12.0
        self.thumbView.frame = CGRect(x: (self.bounds.width - thumbW) / 2.0, y: centerY - thumbH / 2.0, width: thumbW, height: thumbH)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.haptic.prepare()
        self.updateValue(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        self.updateValue(for: touch)
        return true
    }

    private func updateValue(for touch: UITouch) {
        let y = touch.location(in: self.trackView).y
        let height = max(1.0, self.trackView.bounds.height)
        let ratio = min(1.0, max(0.0, y / height))
        var raw = Float(12.0 - ratio * 24.0)
        if abs(raw) < 0.45 {
            raw = 0.0
            if !self.lastSnappedZero {
                self.haptic.selectionChanged()
                self.lastSnappedZero = true
            }
        } else {
            self.lastSnappedZero = false
            raw = (raw * 2.0).rounded() / 2.0
        }
        self.value = raw
        self.sendActions(for: .valueChanged)
    }
}

private final class FullGramMixerUIViewController: UIViewController {
    private let theme: PresentationTheme
    private let onChanged: () -> Void
    private let enabledSwitch = UISwitch()
    private var presetButtons: [String: UIButton] = [:]
    private var faders: [FullGramBandFaderView] = []
    private var observer: NSObjectProtocol?

    init(theme: PresentationTheme, onChanged: @escaping () -> Void) {
        self.theme = theme
        self.onChanged = onChanged
        super.init(nibName: nil, bundle: nil)
        self.title = "Микшер"
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.theme.list.blocksBackgroundColor
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сброс", style: .plain, target: self, action: #selector(self.resetTapped))

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scroll)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 14.0
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: self.view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16.0),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24.0),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16.0),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16.0)
        ])

        content.addArrangedSubview(self.makeSwitchCard())
        content.addArrangedSubview(self.makeCaption("ПРЕСЕТЫ"))
        content.addArrangedSubview(self.makePresetsRow())
        content.addArrangedSubview(self.makeCaption("ПОЛОСЫ"))
        content.addArrangedSubview(self.makeBandsCard())

        let footer = self.makeCaption("Настройки микшера применяются в реальном времени к музыке и видео. Громкие пресеты автоматически снижают общий уровень, чтобы избежать перегруза.")
        footer.numberOfLines = 0
        content.addArrangedSubview(footer)

        self.observer = NotificationCenter.default.addObserver(forName: FullGramMixer.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        self.refresh()
    }

    @objc private func resetTapped() {
        if let flat = FullGramMixer.presets.first {
            FullGramMixer.apply(preset: flat)
            self.onChanged()
        }
    }

    @objc private func switchToggled() {
        FullGramMixer.isEnabled = self.enabledSwitch.isOn
        self.onChanged()
    }

    @objc private func presetTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0 && index < FullGramMixer.presets.count else { return }
        FullGramMixer.apply(preset: FullGramMixer.presets[index])
        self.onChanged()
    }

    @objc private func faderChanged(_ sender: FullGramBandFaderView) {
        var gains = FullGramMixer.gains
        guard sender.tag >= 0 && sender.tag < gains.count else { return }
        gains[sender.tag] = sender.value
        FullGramMixer.presetId = nil
        FullGramMixer.gains = gains
        if !FullGramMixer.isEnabled {
            FullGramMixer.isEnabled = true
        }
        self.onChanged()
    }

    private func makeCard() -> UIView {
        let view = UIView()
        view.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        view.layer.cornerRadius = 14.0
        return view
    }

    private func makeCaption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = self.theme.list.freeTextColor
        return label
    }

    private func makeSwitchCard() -> UIView {
        let card = self.makeCard()
        let label = UILabel()
        label.text = "Включить микшер"
        label.font = .systemFont(ofSize: 16.0)
        label.textColor = self.theme.list.itemPrimaryTextColor
        label.translatesAutoresizingMaskIntoConstraints = false
        self.enabledSwitch.onTintColor = self.theme.list.itemAccentColor
        self.enabledSwitch.addTarget(self, action: #selector(self.switchToggled), for: .valueChanged)
        self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        card.addSubview(self.enabledSwitch)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16.0),
            label.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            self.enabledSwitch.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16.0),
            self.enabledSwitch.topAnchor.constraint(equalTo: card.topAnchor, constant: 10.0),
            self.enabledSwitch.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10.0)
        ])
        return card
    }

    private func makePresetsRow() -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8.0
        for (idx, preset) in FullGramMixer.presets.enumerated() {
            var config = UIButton.Configuration.filled()
            config.title = preset.title(true)
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 10.0, leading: 6.0, bottom: 10.0, trailing: 6.0)
            let button = UIButton(configuration: config)
            button.tag = idx
            button.addTarget(self, action: #selector(self.presetTapped(_:)), for: .touchUpInside)
            self.presetButtons[preset.id] = button
            stack.addArrangedSubview(button)
        }
        return stack
    }

    private func makeBandsCard() -> UIView {
        let card = self.makeCard()
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 2.0
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        for (index, freq) in FullGramMixer.frequencies.enumerated() {
            let fader = FullGramBandFaderView(frequency: freq)
            fader.accentColor = self.theme.list.itemAccentColor
            fader.trackColor = self.theme.list.itemSecondaryTextColor.withAlphaComponent(0.18)
            fader.textColor = self.theme.list.itemPrimaryTextColor
            fader.secondaryColor = self.theme.list.itemSecondaryTextColor
            fader.tag = index
            fader.addTarget(self, action: #selector(self.faderChanged(_:)), for: .valueChanged)
            self.faders.append(fader)
            row.addArrangedSubview(fader)
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16.0),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16.0),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8.0),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8.0),
            row.heightAnchor.constraint(equalToConstant: 240.0)
        ])
        return card
    }

    private func refresh() {
        self.enabledSwitch.isOn = FullGramMixer.isEnabled
        let gains = FullGramMixer.gains
        for (index, fader) in self.faders.enumerated() where index < gains.count {
            if !fader.isTracking {
                fader.value = gains[index]
            }
        }
        let selected = FullGramMixer.isEnabled ? FullGramMixer.presetId : nil
        for (id, button) in self.presetButtons {
            var config = button.configuration ?? UIButton.Configuration.filled()
            let isSelected = id == selected
            config.baseBackgroundColor = isSelected ? self.theme.list.itemAccentColor : self.theme.list.itemBlocksBackgroundColor
            config.baseForegroundColor = isSelected ? .white : self.theme.list.itemPrimaryTextColor
            button.configuration = config
        }
    }
}

private final class FullGramMixerContainerController: FullGramHostedViewController<FullGramMixerUIViewController> {
    init(context: AccountContext, onChanged: @escaping () -> Void) {
        super.init(context: context, title: "Микшер") { theme in
            FullGramMixerUIViewController(theme: theme, onChanged: onChanged)
        }
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сброс", style: .plain, target: self, action: #selector(self.resetTapped))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func resetTapped() {
        if let flat = FullGramMixer.presets.first {
            FullGramMixer.apply(preset: flat)
        }
    }
}

func fullGramMixerController(context: AccountContext, onChanged: @escaping () -> Void = {}) -> ViewController {
    return FullGramMixerContainerController(context: context, onChanged: onChanged)
}
