import Foundation
import AVFoundation
import Speech

public enum FullGramSpeechBleep {
    private static let fallbackLocales = ["ru-RU", "en-US"]

    private static let russianExact: Set<String> = [
        "бля", "бляд", "блядь", "блять", "сука", "суки", "сучка", "хуй", "хуя", "хуе",
        "хуи", "пизда", "пиздец", "пизды", "пизду", "ебать", "ебал", "ебан", "ебло",
        "ебут", "ебёт", "ебет", "ёб", "еб", "мудак", "мудила", "гандон", "гондон",
        "пидор", "пидр", "педик", "шлюха", "дрочить", "залупа", "хер", "хрен", "мразь",
        "долбоеб", "долбоёб", "уебок", "уёбок", "пидорас", "блядина", "ебанат", "хуйня",
        "пиздеж", "пиздёж", "охуеть", "ахуеть", "нахуй", "похуй", "заебал", "выебан"
    ]

    private static let russianPrefixes: [String] = [
        "хуй", "хуя", "хуе", "хуи", "хую", "пизд", "бляд", "блят", "бля",
        "еба", "ебл", "ебн", "ебу", "ебы", "ёб", "заеб", "выёб", "выеб",
        "отъеб", "поеб", "проеб", "разъеб", "съеб", "уеб", "уёб", "долбоеб",
        "муда", "муди", "пидор", "пидр", "гандон", "гондон", "шлюх", "залуп", "сучк"
    ]

    private static let englishExact: Set<String> = [
        "fuck", "fucking", "fucked", "fucker", "motherfucker", "shit", "shitting",
        "bullshit", "bitch", "bitches", "asshole", "bastard", "cunt", "dick",
        "pussy", "whore", "slut", "cock", "faggot", "retard"
    ]

    private static let contextualHints: [String] = [
        "блять", "блядь", "бля", "сука", "хуй", "хуйня", "нахуй", "похуй",
        "пиздец", "пизда", "ебать", "заебал", "ебал", "мудак", "пидор", "гандон",
        "fuck", "fucking", "shit", "bitch", "asshole"
    ]

    public static func isProfanity(_ rawWord: String) -> Bool {
        let normalized = rawWord
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count >= 3 else { return false }
        if russianExact.contains(normalized) || englishExact.contains(normalized) {
            return true
        }
        for prefix in russianPrefixes where normalized.hasPrefix(prefix) {
            return true
        }
        return false
    }

    public static func detectProfanityRanges(inAudioFileAt url: URL, completion: @escaping ([ClosedRange<TimeInterval>]) -> Void) {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else {
                    completion([])
                    return
                }
                performRecognition(url: url, localeIndex: 0, completion: completion)
            }
            return
        }
        guard authStatus == .authorized else {
            completion([])
            return
        }
        performRecognition(url: url, localeIndex: 0, completion: completion)
    }

    public static func recognizeSamples(_ samples: [Int16], sampleRate: Double = 16000.0, completion: @escaping ([ClosedRange<TimeInterval>]) -> Void) {
        guard !samples.isEmpty, sampleRate > 0.0 else {
            completion([])
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_rec_\(UUID().uuidString).wav")
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let dst = buffer.int16ChannelData?[0] else {
            completion([])
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                dst.update(from: base, count: samples.count)
            }
        }
        do {
            let file = try AVAudioFile(forWriting: tempURL, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            try file.write(from: buffer)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            completion([])
            return
        }
        detectProfanityRanges(inAudioFileAt: tempURL) { ranges in
            try? FileManager.default.removeItem(at: tempURL)
            completion(ranges)
        }
    }

    private static func performRecognition(url: URL, localeIndex: Int, completion: @escaping ([ClosedRange<TimeInterval>]) -> Void) {
        let candidates = [Locale.current.identifier] + fallbackLocales
        var uniqueCandidates: [String] = []
        for id in candidates where !uniqueCandidates.contains(id) {
            uniqueCandidates.append(id)
        }
        guard localeIndex < uniqueCandidates.count else {
            completion([])
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: uniqueCandidates[localeIndex])), recognizer.isAvailable else {
            performRecognition(url: url, localeIndex: localeIndex + 1, completion: completion)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.contextualStrings = contextualHints
        if #available(iOS 16.0, *) {
            request.addsPunctuation = false
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        var finished = false
        recognizer.recognitionTask(with: request) { result, error in
            guard !finished else { return }
            if let result, result.isFinal {
                finished = true
                let ranges = extractProfanityRanges(from: result.bestTranscription)
                if ranges.isEmpty && localeIndex + 1 < uniqueCandidates.count && result.bestTranscription.segments.isEmpty {
                    performRecognition(url: url, localeIndex: localeIndex + 1, completion: completion)
                } else {
                    completion(merge(ranges: ranges))
                }
            } else if error != nil {
                finished = true
                performRecognition(url: url, localeIndex: localeIndex + 1, completion: completion)
            }
        }
    }

    private static func extractProfanityRanges(from transcription: SFTranscription) -> [ClosedRange<TimeInterval>] {
        var ranges: [ClosedRange<TimeInterval>] = []
        for segment in transcription.segments {
            if isProfanity(segment.substring) {
                let start = max(0.0, segment.timestamp - 0.04)
                let duration = max(0.22, segment.duration + 0.08)
                ranges.append(start ... (start + duration))
            }
        }
        return ranges
    }

    private static func merge(ranges: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<TimeInterval>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.08 {
                merged[merged.count - 1] = last.lowerBound ... max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    public static func sample(sound: FullGramBleepSound, index: Int, totalSamples: Int, sampleRate: Double) -> Float {
        guard totalSamples > 0, sampleRate > 0.0 else { return 0.0 }
        let t = Double(index) / sampleRate
        let progress = Double(index) / Double(totalSamples)
        let fadeIn = min(1.0, t / 0.012)
        let fadeOut = min(1.0, Double(totalSamples - 1 - index) / (sampleRate * 0.018))
        let env = max(0.0, min(fadeIn, fadeOut))

        switch sound {
        case .off, .silence:
            return 0.0
        case .bell:
            let decay = exp(-t * 4.5)
            let tone = 0.65 * sin(2.0 * .pi * 1046.5 * t) + 0.35 * sin(2.0 * .pi * 2093.0 * t)
            return Float(tone * decay * env * 0.48)
        case .dolphin:
            // SpongeBob dolphin chirp: rapid FM whistle sweep with bubbly warble bursts
            let burst = sin(.pi * progress * 3.0)
            let burstEnv = abs(burst)
            let modFreq = 26.0
            let carrierFreq = 3100.0 + 1350.0 * sin(2.0 * .pi * modFreq * t) + 600.0 * sin(2.0 * .pi * 7.5 * t)
            let signal = sin(2.0 * .pi * carrierFreq * t)
            return Float(signal * burstEnv * env * 0.42)
        }
    }

    public static func applyBleep(to samples: UnsafeMutablePointer<Int16>, count: Int, sampleRate: Double, ranges: [ClosedRange<TimeInterval>], sound: FullGramBleepSound) {
        guard sound != .off, !ranges.isEmpty else { return }
        for range in ranges {
            let startIdx = max(0, Int(range.lowerBound * sampleRate))
            let endIdx = min(count, Int(range.upperBound * sampleRate))
            guard endIdx > startIdx else { continue }
            let total = endIdx - startIdx
            for i in startIdx ..< endIdx {
                let value = sample(sound: sound, index: i - startIdx, totalSamples: total, sampleRate: sampleRate)
                let scaled = max(-32767.0, min(32767.0, Double(value) * 32767.0))
                samples[i] = Int16(scaled)
            }
        }
    }

    public static func processAudioOrVideoFile(inputURL: URL, outputURL: URL, sound: FullGramBleepSound, completion: @escaping (Bool) -> Void) {
        guard sound != .off else {
            completion(false)
            return
        }
        detectProfanityRanges(inAudioFileAt: inputURL) { ranges in
            guard !ranges.isEmpty else {
                completion(false)
                return
            }
            let asset = AVURLAsset(url: inputURL)
            guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
                completion(false)
                return
            }
            let mix = AVMutableAudioMix()
            let params = AVMutableAudioMixInputParameters(track: audioTrack)
            for range in ranges {
                let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
                let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
                params.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: CMTimeRange(start: start, duration: CMTime(seconds: 0.02, preferredTimescale: 600)))
                params.setVolume(0.0, at: CMTimeAdd(start, CMTime(seconds: 0.02, preferredTimescale: 600)))
                params.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: CMTimeRange(start: end, duration: CMTime(seconds: 0.02, preferredTimescale: 600)))
            }
            mix.inputParameters = [params]

            guard let composition = try? buildBleepComposition(asset: asset, audioTrack: audioTrack, ranges: ranges, sound: sound),
                  let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                exportWithMixOnly(asset: asset, mix: mix, outputURL: outputURL, completion: completion)
                return
            }
            try? FileManager.default.removeItem(at: outputURL)
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.audioMix = mix
            exporter.exportAsynchronously {
                completion(exporter.status == .completed)
            }
        }
    }

    private static func exportWithMixOnly(asset: AVAsset, mix: AVAudioMix, outputURL: URL, completion: @escaping (Bool) -> Void) {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(false)
            return
        }
        try? FileManager.default.removeItem(at: outputURL)
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.audioMix = mix
        exporter.exportAsynchronously {
            completion(exporter.status == .completed)
        }
    }

    private static func buildBleepComposition(asset: AVAsset, audioTrack: AVAssetTrack, ranges: [ClosedRange<TimeInterval>], sound: FullGramBleepSound) throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let duration = asset.duration
        if let videoTrack = asset.tracks(withMediaType: .video).first,
           let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
            compVideo.preferredTransform = videoTrack.preferredTransform
        }
        if let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
        }
        if sound != .silence, let bleepFile = generateBleepWav(sound: sound, duration: 1.0) {
            let bleepAsset = AVURLAsset(url: bleepFile)
            if let bleepTrack = bleepAsset.tracks(withMediaType: .audio).first,
               let compBleep = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                for range in ranges {
                    let len = min(1.0, max(0.15, range.upperBound - range.lowerBound))
                    let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
                    let dur = CMTime(seconds: len, preferredTimescale: 600)
                    try? compBleep.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: bleepTrack, at: start)
                }
            }
        }
        return composition
    }

    private static func generateBleepWav(sound: FullGramBleepSound, duration: TimeInterval) -> URL? {
        let sampleRate = 44100.0
        let totalSamples = Int(duration * sampleRate)
        guard totalSamples > 0 else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_bleep_\(sound.rawValue).caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        guard let format, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalSamples)),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(totalSamples)
        for i in 0 ..< totalSamples {
            channelData[i] = sample(sound: sound, index: i, totalSamples: totalSamples, sampleRate: sampleRate)
        }
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        try? file.write(from: buffer)
        return url
    }

    // MARK: - Free Local Voice & Video-Note Transcription

    public static func transcribeMediaFile(
        at path: String,
        preferredLanguage: String? = nil,
        defaultExtension: String = "m4a",
        completion: @escaping (String?) -> Void
    ) {
        let performWithAuth = {
            let srcURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                completion(nil)
                return
            }
            let supportedExts = ["m4a", "mp4", "mov", "wav", "caf", "mp3", "aac"]
            let ext = srcURL.pathExtension.lowercased()
            let workingURL: URL
            var shouldCleanup = false
            if supportedExts.contains(ext) {
                workingURL = srcURL
            } else {
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("fullgram_stt_\(UUID().uuidString).\(defaultExtension)")
                do {
                    try FileManager.default.copyItem(at: srcURL, to: tmpURL)
                    workingURL = tmpURL
                    shouldCleanup = true
                } catch {
                    completion(nil)
                    return
                }
            }

            var candidates: [String] = []
            for raw in [preferredLanguage, Locale.current.identifier, "ru-RU", "en-US"] {
                if let id = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty, !candidates.contains(id) {
                    candidates.append(id)
                }
            }

            func attempt(index: Int) {
                guard index < candidates.count else {
                    if shouldCleanup { try? FileManager.default.removeItem(at: workingURL) }
                    completion(nil)
                    return
                }
                guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: candidates[index])), recognizer.isAvailable else {
                    attempt(index: index + 1)
                    return
                }
                let request = SFSpeechURLRecognitionRequest(url: workingURL)
                request.shouldReportPartialResults = false
                request.taskHint = .dictation
                if #available(iOS 16.0, *) {
                    request.addsPunctuation = true
                }
                if recognizer.supportsOnDeviceRecognition {
                    request.requiresOnDeviceRecognition = true
                }

                var handled = false
                recognizer.recognitionTask(with: request) { result, error in
                    guard !handled else { return }
                    if let result, result.isFinal {
                        handled = true
                        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            if shouldCleanup { try? FileManager.default.removeItem(at: workingURL) }
                            completion(text)
                        } else {
                            attempt(index: index + 1)
                        }
                    } else if error != nil {
                        handled = true
                        attempt(index: index + 1)
                    }
                }
            }

            attempt(index: 0)
        }

        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { newStatus in
                if newStatus == .authorized {
                    performWithAuth()
                } else {
                    completion(nil)
                }
            }
        } else if status == .authorized {
            performWithAuth()
        } else {
            completion(nil)
        }
    }
}
