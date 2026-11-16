import Foundation
import AVFoundation

/// Real-time 16 kHz mono Int16 voice processor shared by recorder and voice preview tester.
public final class FullGramVoiceDSP {
    private let mode: FullGramVoiceMode
    private let sampleRate: Double = 16000.0
    private var robotPhase: Double = 0.0
    private var lfoPhase: Double = 0.0

    private var ring: [Double]
    private var writePos: Int = 0
    private var readPos: Double = 0.0
    private let ringSize = 8192

    public init(mode: FullGramVoiceMode) {
        self.mode = mode
        self.ring = [Double](repeating: 0.0, count: 8192)
    }

    public static func makeIfEnabled() -> FullGramVoiceDSP? {
        let mode = FullGramVoiceMode.current
        guard mode != .off else { return nil }
        return FullGramVoiceDSP(mode: mode)
    }

    public func process(_ samples: UnsafeMutablePointer<Int16>, count: Int) {
        guard count > 0 else { return }
        switch self.mode {
        case .off:
            return
        case .robot:
            let step = 2.0 * .pi * 110.0 / self.sampleRate
            for i in 0 ..< count {
                let x = Double(samples[i]) / 32768.0
                let mod = 0.65 * sin(self.robotPhase) + 0.35 * sin(self.robotPhase * 2.0)
                self.robotPhase += step
                if self.robotPhase > 2.0 * .pi {
                    self.robotPhase -= 2.0 * .pi
                }
                let y = max(-1.0, min(1.0, x * mod * 1.4))
                samples[i] = Int16(y * 32767.0)
            }
        case .low:
            self.processPitch(samples, count: count, basePitch: 0.72, lfoDepth: 0.0)
        case .cartoon:
            self.processPitch(samples, count: count, basePitch: 1.45, lfoDepth: 0.0)
        case .trippy:
            self.processPitch(samples, count: count, basePitch: 1.08, lfoDepth: 0.40)
        }
    }

    private func processPitch(_ samples: UnsafeMutablePointer<Int16>, count: Int, basePitch: Double, lfoDepth: Double) {
        let mask = self.ringSize - 1
        let lfoStep = 2.0 * .pi * 1.35 / self.sampleRate
        let windowSize = 512.0

        for i in 0 ..< count {
            self.ring[self.writePos & mask] = Double(samples[i])
            self.writePos += 1

            let pitch: Double
            if lfoDepth > 0.0 {
                pitch = basePitch + lfoDepth * sin(self.lfoPhase)
                self.lfoPhase += lfoStep
                if self.lfoPhase > 2.0 * .pi {
                    self.lfoPhase -= 2.0 * .pi
                }
            } else {
                pitch = basePitch
            }

            let rp0 = self.readPos
            let idx0 = Int(floor(rp0))
            let frac0 = rp0 - Double(idx0)
            let s0 = self.ring[idx0 & mask] * (1.0 - frac0) + self.ring[(idx0 + 1) & mask] * frac0

            let rp1 = rp0 + windowSize
            let idx1 = Int(floor(rp1))
            let frac1 = rp1 - Double(idx1)
            let s1 = self.ring[idx1 & mask] * (1.0 - frac1) + self.ring[(idx1 + 1) & mask] * frac1

            let distance = Double(self.writePos) - rp0
            let phase = (distance.truncatingRemainder(dividingBy: windowSize) + windowSize).truncatingRemainder(dividingBy: windowSize) / windowSize
            let weight = 0.5 - 0.5 * cos(2.0 * .pi * phase)
            let mixed = s0 * weight + s1 * (1.0 - weight)

            samples[i] = Int16(max(-32768.0, min(32767.0, mixed)))
            self.readPos += pitch

            let ahead = Double(self.writePos) - self.readPos
            if ahead < 64.0 || ahead > windowSize * 2.0 {
                self.readPos = Double(self.writePos) - windowSize * 0.5
            }
        }
    }
}

/// Records up to 3 seconds from microphone and plays back processed voice + bleep sound.
public final class FullGramVoiceTester: NSObject, AVAudioPlayerDelegate {
    public enum State: Equatable {
        case idle
        case recording(remainingSeconds: Int)
        case processing
        case playing
        case error(String)
    }

    public private(set) var state: State = .idle {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onStateChange?(self.state)
            }
        }
    }

    public var onStateChange: ((State) -> Void)?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var countdownTimer: Timer?
    private var remainingSeconds: Int = 0
    private var rawURL: URL?
    private var processedURL: URL?

    deinit {
        self.stop()
    }

    public func toggleTest() {
        switch self.state {
        case .idle, .error:
            self.startRecording()
        case .recording:
            self.finishRecordingAndPlay()
        case .processing, .playing:
            self.stop()
        }
    }

    public func stop() {
        self.countdownTimer?.invalidate()
        self.countdownTimer = nil
        self.recorder?.stop()
        self.recorder = nil
        self.player?.stop()
        self.player = nil
        self.cleanupFiles()
        if self.state != .idle {
            self.state = .idle
        }
    }

    private func cleanupFiles() {
        if let rawURL {
            try? FileManager.default.removeItem(at: rawURL)
            self.rawURL = nil
        }
        if let processedURL {
            try? FileManager.default.removeItem(at: processedURL)
            self.processedURL = nil
        }
    }

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.state = .error("Нет доступа к микрофону")
                    return
                }
                self.beginCapture()
            }
        }
    }

    private func beginCapture() {
        self.stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            self.state = .error("Не удалось включить аудиосессию")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fg_voice_test_raw_\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            guard rec.record(forDuration: 3.0) else {
                self.state = .error("Запись не запустилась")
                return
            }
            self.rawURL = url
            self.recorder = rec
            self.remainingSeconds = 3
            self.state = .recording(remainingSeconds: 3)

            self.countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.finishRecordingAndPlay()
                } else {
                    self.state = .recording(remainingSeconds: self.remainingSeconds)
                }
            }
        } catch {
            self.state = .error("Ошибка записи")
        }
    }

    private func finishRecordingAndPlay() {
        self.countdownTimer?.invalidate()
        self.countdownTimer = nil
        self.recorder?.stop()
        self.recorder = nil

        guard let rawURL = self.rawURL else {
            self.state = .idle
            return
        }
        self.state = .processing

        let voiceMode = FullGramVoiceMode.current
        let bleepSound = FullGramBleepSound.current

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let samples = self.loadPCM16Mono(from: rawURL), !samples.isEmpty else {
                self.cleanupFiles()
                self.state = .error("Пустая запись")
                return
            }

            let finalizeAndPlay: ([Int16]) -> Void = { finalSamples in
                let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("fg_voice_test_out_\(UUID().uuidString).wav")
                guard self.writePCM16Mono(samples: finalSamples, to: outURL) else {
                    self.cleanupFiles()
                    self.state = .error("Не удалось сохранить тест")
                    return
                }
                DispatchQueue.main.async {
                    self.processedURL = outURL
                    self.playFile(at: outURL)
                }
            }

            if bleepSound != .off {
                FullGramSpeechBleep.recognizeSamples(samples, sampleRate: 16000.0) { ranges in
                    var buffer = samples
                    if voiceMode != .off {
                        let dsp = FullGramVoiceDSP(mode: voiceMode)
                        buffer.withUnsafeMutableBufferPointer { ptr in
                            if let base = ptr.baseAddress {
                                dsp.process(base, count: ptr.count)
                            }
                        }
                    }
                    if !ranges.isEmpty {
                        buffer.withUnsafeMutableBufferPointer { ptr in
                            if let base = ptr.baseAddress {
                                FullGramSpeechBleep.applyBleep(to: base, count: ptr.count, sampleRate: 16000.0, ranges: ranges, sound: bleepSound)
                            }
                        }
                    } else {
                        // Append a short preview of the chosen bleep sound when no profanity was spoken.
                        let bleepCount = Int(16000.0 * 0.55)
                        let tailStart = buffer.count
                        buffer.append(contentsOf: [Int16](repeating: 0, count: bleepCount))
                        buffer.withUnsafeMutableBufferPointer { ptr in
                            if let base = ptr.baseAddress {
                                for i in 0 ..< bleepCount {
                                    let val = FullGramSpeechBleep.sample(sound: bleepSound, index: i, totalSamples: bleepCount, sampleRate: 16000.0)
                                    base[tailStart + i] = Int16(max(-32767.0, min(32767.0, Double(val) * 32767.0)))
                                }
                            }
                        }
                    }
                    finalizeAndPlay(buffer)
                }
            } else {
                var buffer = samples
                if voiceMode != .off {
                    let dsp = FullGramVoiceDSP(mode: voiceMode)
                    buffer.withUnsafeMutableBufferPointer { ptr in
                        if let base = ptr.baseAddress {
                            dsp.process(base, count: ptr.count)
                        }
                    }
                }
                finalizeAndPlay(buffer)
            }
        }
    }

    private func playFile(at url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
            self.player = audioPlayer
            self.state = .playing
            audioPlayer.play()
        } catch {
            self.cleanupFiles()
            self.state = .error("Ошибка воспроизведения")
        }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.cleanupFiles()
        self.state = .idle
    }

    private func loadPCM16Mono(from url: URL) -> [Int16]? {
        guard let file = try? AVAudioFile(forReading: url),
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: true) else {
            return nil
        }
        let capacity = AVAudioFrameCount(max(1, file.length))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        let count = Int(buffer.frameLength)
        guard count > 0, let channel = buffer.int16ChannelData?[0] else {
            return nil
        }
        return Array(UnsafeBufferPointer(start: channel, count: count))
    }

    private func writePCM16Mono(samples: [Int16], to url: URL) -> Bool {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000.0, channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let dst = buffer.int16ChannelData?[0] else {
            return false
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                dst.update(from: base, count: samples.count)
            }
        }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }
}
