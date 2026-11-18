import Foundation
import AVFoundation

/// Real-time mono Int16 voice processor shared by recorder and voice preview tester.
/// Includes multi-mode Noise Suppression (Soft / Studio Mic / Aggressive), Voice Changer presets,
/// and Custom Voice Constructor (Pitch + Echo + Warmth).
public final class FullGramVoiceDSP {
    private let mode: FullGramVoiceMode
    private let noiseMode: FullGramNoiseReductionMode
    private let sampleRate: Double
    private var robotPhase: Double = 0.0
    private var lfoPhase: Double = 0.0
    private var grainPhase: Double = 0.0
    private var lpState: Double = 0.0
    private var warmthState: Double = 0.0

    // Noise suppression state
    private var hpPrevX: Double = 0.0
    private var hpPrevY: Double = 0.0
    private var envFollower: Double = 0.0
    private var noiseFloor: Double = 0.008
    private var gateGain: Double = 1.0
    private var agcGain: Double = 1.0

    // Pitch ring buffer
    private var ring: [Double]
    private var writePos: Int = 0
    private var filledCount: Int = 0
    private let ringSize = 16384

    // Echo delay buffer (up to ~170ms at 48kHz)
    private var echoRing: [Double]
    private var echoPos: Int = 0
    private let echoSize = 8192

    public init(
        mode: FullGramVoiceMode,
        noiseMode: FullGramNoiseReductionMode = FullGramNoiseReductionMode.current,
        sampleRate: Double = 48000.0
    ) {
        self.mode = mode
        self.noiseMode = noiseMode
        self.sampleRate = max(8000.0, sampleRate)
        self.ring = [Double](repeating: 0.0, count: 16384)
        self.echoRing = [Double](repeating: 0.0, count: 8192)
    }

    public static func makeIfEnabled(sampleRate: Double = 48000.0) -> FullGramVoiceDSP? {
        let mode = FullGramVoiceMode.current
        let noise = FullGramNoiseReductionMode.current
        guard mode != .off || noise != .off else { return nil }
        return FullGramVoiceDSP(mode: mode, noiseMode: noise, sampleRate: sampleRate)
    }

    public func process(_ samples: UnsafeMutablePointer<Int16>, count: Int) {
        guard count > 0 else { return }

        // Step 1: Apply Noise Suppression / Studio Mic first on clean input
        if self.noiseMode != .off {
            self.processNoiseReduction(samples, count: count)
        }

        // Step 2: Apply Voice Mode / Custom Voice Constructor
        switch self.mode {
        case .off:
            return
        case .robot:
            self.processRobot(samples, count: count)
        case .low:
            self.processPitch(samples, count: count, basePitch: 0.74, lfoDepth: 0.0)
        case .cartoon:
            self.processPitch(samples, count: count, basePitch: 1.42, lfoDepth: 0.0)
        case .trippy:
            self.processPitch(samples, count: count, basePitch: 1.05, lfoDepth: 0.34)
        case .custom:
            let customPitch = Double(FullGramCustomVoiceSettings.pitch)
            let customEcho = Double(FullGramCustomVoiceSettings.echo)
            let customWarmth = Double(FullGramCustomVoiceSettings.warmth)
            if abs(customPitch - 1.0) > 0.02 {
                self.processPitch(samples, count: count, basePitch: customPitch, lfoDepth: 0.0)
            }
            if abs(customWarmth) > 0.02 || customEcho > 0.01 {
                self.processWarmthAndEcho(samples, count: count, warmth: customWarmth, echo: customEcho)
            }
        }
    }

    private func processNoiseReduction(_ samples: UnsafeMutablePointer<Int16>, count: Int) {
        let cutoffHz: Double = (self.noiseMode == .aggressive) ? 120.0 : 85.0
        let rc = 1.0 / (2.0 * .pi * cutoffHz)
        let dt = 1.0 / self.sampleRate
        let hpAlpha = rc / (rc + dt)

        let attackCoeff = exp(-1.0 / (self.sampleRate * 0.004))
        let releaseCoeff = exp(-1.0 / (self.sampleRate * 0.045))

        let thresholdMultiplier: Double
        let floorAttenuation: Double
        switch self.noiseMode {
        case .off:
            return
        case .soft:
            thresholdMultiplier = 2.0
            floorAttenuation = 0.28
        case .studio:
            thresholdMultiplier = 2.4
            floorAttenuation = 0.16
        case .aggressive:
            thresholdMultiplier = 3.2
            floorAttenuation = 0.04
        }

        for i in 0 ..< count {
            let x = Double(samples[i]) / 32768.0

            // High-pass filter removes wind rumble and mic handling thumps
            let hp = hpAlpha * (self.hpPrevY + x - self.hpPrevX)
            self.hpPrevX = x
            self.hpPrevY = hp

            let absVal = abs(hp)
            if absVal > self.envFollower {
                self.envFollower = attackCoeff * self.envFollower + (1.0 - attackCoeff) * absVal
            } else {
                self.envFollower = releaseCoeff * self.envFollower + (1.0 - releaseCoeff) * absVal
            }

            // Track background noise floor slowly
            if self.envFollower < self.noiseFloor {
                self.noiseFloor = 0.992 * self.noiseFloor + 0.008 * max(0.0015, self.envFollower)
            } else {
                self.noiseFloor = min(0.045, self.noiseFloor * 1.00008)
            }

            let gateThreshold = max(0.008, self.noiseFloor * thresholdMultiplier)
            let targetGate: Double
            if self.envFollower >= gateThreshold {
                targetGate = 1.0
            } else {
                let ratio = self.envFollower / gateThreshold
                targetGate = max(floorAttenuation, ratio * ratio)
            }
            self.gateGain = 0.96 * self.gateGain + 0.04 * targetGate

            var y = hp * self.gateGain

            // Studio Mic mode: add broadcast vocal warmth + auto-leveler AGC
            if self.noiseMode == .studio {
                self.warmthState += 0.18 * (y - self.warmthState)
                let presence = y - self.warmthState
                y = y + 0.24 * self.warmthState + 0.22 * presence

                if self.envFollower > gateThreshold * 1.2 {
                    let desiredGain = min(2.2, max(0.85, 0.32 / max(0.05, self.envFollower)))
                    self.agcGain = 0.9985 * self.agcGain + 0.0015 * desiredGain
                }
                y *= self.agcGain
            }

            let out = softClip(y) * 32767.0
            samples[i] = Int16(max(-32767.0, min(32767.0, out)))
        }
    }

    private func processWarmthAndEcho(_ samples: UnsafeMutablePointer<Int16>, count: Int, warmth: Double, echo: Double) {
        let echoMask = self.echoSize - 1
        let delaySamples = min(self.echoSize - 4, max(64, Int((self.sampleRate * 0.110).rounded())))

        for i in 0 ..< count {
            var x = Double(samples[i]) / 32768.0

            if abs(warmth) > 0.02 {
                self.warmthState += 0.16 * (x - self.warmthState)
                let high = x - self.warmthState
                if warmth > 0.0 {
                    // Boost warm low-mids, soften harsh highs
                    x = x + warmth * 0.65 * self.warmthState - warmth * 0.25 * high
                } else {
                    // Boost crisp radio highs, trim lows
                    let amt = -warmth
                    x = x + amt * 0.60 * high - amt * 0.30 * self.warmthState
                }
            }

            if echo > 0.01 {
                let readIdx = (self.echoPos - delaySamples) & echoMask
                let delayed = self.echoRing[readIdx]
                let fb = min(0.55, echo * 0.62)
                self.echoRing[self.echoPos & echoMask] = max(-1.0, min(1.0, x + delayed * fb))
                self.echoPos += 1
                x = x * (1.0 - echo * 0.28) + delayed * (echo * 0.68)
            }

            let out = softClip(x) * 32767.0
            samples[i] = Int16(max(-32767.0, min(32767.0, out)))
        }
    }

    private func processRobot(_ samples: UnsafeMutablePointer<Int16>, count: Int) {
        let mask = self.ringSize - 1
        let carrierFreq = 105.0
        let step = 2.0 * .pi * carrierFreq / self.sampleRate
        let combDelay = max(16, Int((self.sampleRate * 0.0075).rounded()))

        for i in 0 ..< count {
            let dry = Double(samples[i]) / 32768.0
            let delayedIndex = (self.writePos - combDelay) & mask
            let combOut = dry + 0.36 * self.ring[delayedIndex]
            self.ring[self.writePos & mask] = max(-1.0, min(1.0, combOut))
            self.writePos += 1

            let carrier = 0.60 * sin(self.robotPhase)
                + 0.28 * sin(self.robotPhase * 2.0)
                + 0.12 * cos(self.robotPhase * 3.0)
            self.robotPhase += step
            if self.robotPhase > 2.0 * .pi {
                self.robotPhase -= 2.0 * .pi
            }

            // Blend ring-modulated harmonic carrier with comb-filtered dry voice for clear intelligibility
            let ringMod = combOut * carrier * 1.35
            let raw = 0.68 * ringMod + 0.32 * combOut
            self.lpState += 0.55 * (raw - self.lpState)
            let limited = softClip(self.lpState * 1.15)
            samples[i] = Int16(max(-32767.0, min(32767.0, limited * 32767.0)))
        }
    }

    /// Dual-tap synchronous Hann-windowed overlap-add pitch shifter.
    /// Both read taps always stay strictly behind `writePos` and wrap only when their Hann window weight is 0.
    private func processPitch(_ samples: UnsafeMutablePointer<Int16>, count: Int, basePitch: Double, lfoDepth: Double) {
        let mask = self.ringSize - 1
        let lfoStep = 2.0 * .pi * 1.45 / self.sampleRate
        let windowSize = max(256.0, (self.sampleRate * 0.036).rounded())
        let minDelay = 32.0

        for i in 0 ..< count {
            let inputSample = Double(samples[i])
            let latestWrite = self.writePos
            self.ring[latestWrite & mask] = inputSample
            self.writePos = latestWrite + 1
            if self.filledCount < self.ringSize {
                self.filledCount += 1
            }

            let pitch: Double
            if lfoDepth > 0.0 {
                pitch = max(0.55, min(1.75, basePitch + lfoDepth * sin(self.lfoPhase)))
                self.lfoPhase += lfoStep
                if self.lfoPhase > 2.0 * .pi {
                    self.lfoPhase -= 2.0 * .pi
                }
            } else {
                pitch = basePitch
            }

            // Delay d(n) changes by (1 - pitch) per sample so read position advances by `pitch` per sample.
            let phaseStep = (1.0 - pitch) / windowSize
            self.grainPhase += phaseStep
            self.grainPhase -= floor(self.grainPhase)

            let phi0 = self.grainPhase
            var phi1 = phi0 + 0.5
            if phi1 >= 1.0 {
                phi1 -= 1.0
            }

            let maxAvailableDelay = Double(max(2, self.filledCount - 2))
            let d0 = min(maxAvailableDelay, minDelay + phi0 * windowSize)
            let d1 = min(maxAvailableDelay, minDelay + phi1 * windowSize)

            let s0 = self.readInterpolated(writeIndex: latestWrite, delay: d0, mask: mask)
            let s1 = self.readInterpolated(writeIndex: latestWrite, delay: d1, mask: mask)

            // Complementary Hann weights: w0(0) = 0, w0(0.5) = 1, w0(1) = 0, and w0 + w1 == 1 everywhere.
            let w0 = 0.5 - 0.5 * cos(2.0 * .pi * phi0)
            let w1 = 1.0 - w0
            let mixed = (s0 * w0 + s1 * w1) / 32768.0

            self.lpState += 0.65 * (mixed - self.lpState)
            let out = softClip(self.lpState) * 32767.0
            samples[i] = Int16(max(-32767.0, min(32767.0, out)))
        }
    }

    @inline(__always)
    private func readInterpolated(writeIndex: Int, delay: Double, mask: Int) -> Double {
        let pos = Double(writeIndex) - delay
        let idx0 = Int(floor(pos))
        let frac = pos - Double(idx0)
        let a = self.ring[idx0 & mask]
        let b = self.ring[(idx0 + 1) & mask]
        return a + (b - a) * frac
    }

    @inline(__always)
    private func softClip(_ x: Double) -> Double {
        if x > 1.25 { return 1.0 }
        if x < -1.25 { return -1.0 }
        // Smooth cubic soft-knee limiter around [-1, 1]
        if x > 0.8 {
            let t = (x - 0.8) / 0.45
            return 0.8 + 0.2 * (t / (1.0 + abs(t)))
        } else if x < -0.8 {
            let t = (x + 0.8) / 0.45
            return -0.8 + 0.2 * (t / (1.0 + abs(t)))
        }
        return x
    }

    // MARK: - Direct Spec-Compliant RIFF/WAVE PCM16 Helpers

    public static func writeWAV16Mono(samples: [Int16], sampleRate: Int, to url: URL) -> Bool {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataByteCount = UInt32(samples.count * 2)
        let chunkSize = 36 &+ dataByteCount

        var data = Data(capacity: 44 + Int(dataByteCount))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendUInt32LE(&data, chunkSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendUInt32LE(&data, 16)                          // Subchunk1Size (16 for PCM)
        appendUInt16LE(&data, 1)                           // AudioFormat (1 = PCM)
        appendUInt16LE(&data, numChannels)
        appendUInt32LE(&data, UInt32(sampleRate))
        appendUInt32LE(&data, byteRate)
        appendUInt16LE(&data, blockAlign)
        appendUInt16LE(&data, bitsPerSample)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendUInt32LE(&data, dataByteCount)

        samples.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                data.append(UnsafeBufferPointer(start: UnsafeRawPointer(base).assumingMemoryBound(to: UInt8.self), count: samples.count * 2))
            }
        }

        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func readWAV16Mono(from url: URL) -> (samples: [Int16], sampleRate: Double)? {
        // 1. Fast & exact RIFF/WAVE chunk parser (handles FLLR/JUNK/LIST padding chunks from AVAudioRecorder)
        if let raw = try? Data(contentsOf: url), raw.count > 44 {
            if raw[0] == 0x52, raw[1] == 0x49, raw[2] == 0x46, raw[3] == 0x46,
               raw[8] == 0x57, raw[9] == 0x41, raw[10] == 0x56, raw[11] == 0x45 {
                var offset = 12
                var audioFormat: UInt16 = 1
                var channels: UInt16 = 1
                var sampleRate: UInt32 = 16000
                var bitsPerSample: UInt16 = 16

                while offset + 8 <= raw.count {
                    let c0 = raw[offset]
                    let c1 = raw[offset + 1]
                    let c2 = raw[offset + 2]
                    let c3 = raw[offset + 3]
                    let chunkSize = Int(readUInt32LE(raw, offset + 4))
                    let bodyStart = offset + 8
                    guard chunkSize >= 0, bodyStart <= raw.count else { break }
                    let bodyEnd = min(raw.count, bodyStart + chunkSize)

                    if c0 == 0x66 && c1 == 0x6D && c2 == 0x74 && c3 == 0x20 && bodyEnd - bodyStart >= 16 {
                        audioFormat = readUInt16LE(raw, bodyStart)
                        channels = max(1, readUInt16LE(raw, bodyStart + 2))
                        sampleRate = max(8000, readUInt32LE(raw, bodyStart + 4))
                        bitsPerSample = readUInt16LE(raw, bodyStart + 14)
                    } else if c0 == 0x64 && c1 == 0x61 && c2 == 0x74 && c3 == 0x61 {
                        let byteLen = bodyEnd - bodyStart
                        let ch = Int(channels)
                        if audioFormat == 1 && bitsPerSample == 16 && byteLen >= 2 * ch {
                            let frameCount = byteLen / (2 * ch)
                            var out = [Int16](repeating: 0, count: frameCount)
                            for f in 0 ..< frameCount {
                                var sum = 0
                                for c in 0 ..< ch {
                                    let samplePos = bodyStart + (f * ch + c) * 2
                                    let u = readUInt16LE(raw, samplePos)
                                    sum += Int(Int16(bitPattern: u))
                                }
                                out[f] = Int16(max(-32768, min(32767, sum / ch)))
                            }
                            if !out.isEmpty {
                                return (out, Double(sampleRate))
                            }
                        } else if audioFormat == 3 && bitsPerSample == 32 && byteLen >= 4 * ch {
                            let frameCount = byteLen / (4 * ch)
                            var out = [Int16](repeating: 0, count: frameCount)
                            for f in 0 ..< frameCount {
                                var sum: Float = 0.0
                                for c in 0 ..< ch {
                                    let samplePos = bodyStart + (f * ch + c) * 4
                                    let bits = readUInt32LE(raw, samplePos)
                                    let val = Float(bitPattern: bits)
                                    if val.isFinite {
                                        sum += val
                                    }
                                }
                                let avg = Double(sum) / Double(ch)
                                out[f] = Int16(max(-32767.0, min(32767.0, avg * 32767.0)))
                            }
                            if !out.isEmpty {
                                return (out, Double(sampleRate))
                            }
                        }
                    }

                    let paddedSize = chunkSize + (chunkSize & 1)
                    offset = bodyStart + paddedSize
                }
            }
        }

        // 2. Fallback via AVAudioFile using file.processingFormat (Float32) so format mismatch never occurs
        guard let file = try? AVAudioFile(forReading: url) else {
            return nil
        }
        let procFormat = file.processingFormat
        let capacity = AVAudioFrameCount(max(1, file.length))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: procFormat, frameCapacity: capacity) else {
            return nil
        }
        do {
            try file.read(into: buffer)
        } catch {
            return nil
        }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        if let floatCh = buffer.floatChannelData?[0] {
            var out = [Int16](repeating: 0, count: count)
            for i in 0 ..< count {
                let v = Double(floatCh[i])
                if v.isFinite {
                    out[i] = Int16(max(-32767.0, min(32767.0, v * 32767.0)))
                }
            }
            return (out, procFormat.sampleRate)
        } else if let int16Ch = buffer.int16ChannelData?[0] {
            return (Array(UnsafeBufferPointer(start: int16Ch, count: count)), procFormat.sampleRate)
        }
        return nil
    }

    private static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        let le = value.littleEndian
        withUnsafeBytes(of: le) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        let le = value.littleEndian
        withUnsafeBytes(of: le) { data.append(contentsOf: $0) }
    }

    private static func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

/// Records up to 3 seconds from microphone and plays back processed voice + noise reduction + bleep sound.
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
    private let recordingSampleRate: Double = 48000.0

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
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            self.state = .error("Не удалось включить аудиосессию")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fg_voice_test_raw_\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: self.recordingSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            guard rec.record(forDuration: 3.2) else {
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
        let noiseMode = FullGramNoiseReductionMode.current
        let bleepSound = FullGramBleepSound.current

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let loaded = FullGramVoiceDSP.readWAV16Mono(from: rawURL), !loaded.samples.isEmpty else {
                self.cleanupFiles()
                self.state = .error("Пустая запись")
                return
            }
            let samples = loaded.samples
            let sampleRate = loaded.sampleRate

            let finalizeAndPlay: ([Int16]) -> Void = { finalSamples in
                let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("fg_voice_test_out_\(UUID().uuidString).wav")
                guard FullGramVoiceDSP.writeWAV16Mono(samples: finalSamples, sampleRate: Int(sampleRate.rounded()), to: outURL) else {
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
                FullGramSpeechBleep.recognizeSamples(samples, sampleRate: sampleRate) { ranges in
                    var buffer = samples
                    if voiceMode != .off || noiseMode != .off {
                        let dsp = FullGramVoiceDSP(mode: voiceMode, noiseMode: noiseMode, sampleRate: sampleRate)
                        buffer.withUnsafeMutableBufferPointer { ptr in
                            if let base = ptr.baseAddress {
                                dsp.process(base, count: ptr.count)
                            }
                        }
                    }
                    if !ranges.isEmpty {
                        buffer.withUnsafeMutableBufferPointer { ptr in
                            if let base = ptr.baseAddress {
                                FullGramSpeechBleep.applyBleep(to: base, count: ptr.count, sampleRate: sampleRate, ranges: ranges, sound: bleepSound)
                            }
                        }
                    } else {
                        // Append a short pause + preview of the chosen bleep sound when no profanity was detected.
                        let pauseCount = Int(sampleRate * 0.14)
                        let bleepCount = Int(sampleRate * 0.45)
                        buffer.append(contentsOf: [Int16](repeating: 0, count: pauseCount))
                        let tailStart = buffer.count
                        buffer.append(contentsOf: [Int16](repeating: 0, count: bleepCount))
                        buffer.withUnsafeMutableBufferPointer { ptr in
                            if let base = ptr.baseAddress {
                                for i in 0 ..< bleepCount {
                                    let val = FullGramSpeechBleep.sample(sound: bleepSound, index: i, totalSamples: bleepCount, sampleRate: sampleRate)
                                    base[tailStart + i] = Int16(max(-32767.0, min(32767.0, Double(val) * 32767.0)))
                                }
                            }
                        }
                    }
                    finalizeAndPlay(buffer)
                }
            } else {
                var buffer = samples
                if voiceMode != .off || noiseMode != .off {
                    let dsp = FullGramVoiceDSP(mode: voiceMode, noiseMode: noiseMode, sampleRate: sampleRate)
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
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.overrideOutputAudioPort(.speaker)
            try session.setActive(true)
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.delegate = self
            audioPlayer.volume = 1.0
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
}

/// Records a 1.5-second custom bleep sound from microphone and saves it into `FullGramCustomBleepStore`.
public final class FullGramCustomBleepRecorder: NSObject {
    public private(set) var isRecording: Bool = false {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onStateChange?(self.isRecording)
            }
        }
    }

    public var onStateChange: ((Bool) -> Void)?
    public var onCompleted: ((Bool) -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var tempURL: URL?

    public func toggleRecord() {
        if self.isRecording {
            self.finish()
        } else {
            self.start()
        }
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, granted else {
                    self?.onCompleted?(false)
                    return
                }
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try session.setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fg_custom_bleep_rec_\(UUID().uuidString).wav")
                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatLinearPCM),
                        AVSampleRateKey: 48000.0,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                    let rec = try AVAudioRecorder(url: url, settings: settings)
                    rec.prepareToRecord()
                    guard rec.record(forDuration: 1.6) else {
                        self.onCompleted?(false)
                        return
                    }
                    self.tempURL = url
                    self.recorder = rec
                    self.isRecording = true
                    self.timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        self?.finish()
                    }
                } catch {
                    self.onCompleted?(false)
                }
            }
        }
    }

    private func finish() {
        self.timer?.invalidate()
        self.timer = nil
        self.recorder?.stop()
        self.recorder = nil
        self.isRecording = false

        guard let url = self.tempURL else {
            self.onCompleted?(false)
            return
        }
        self.tempURL = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { try? FileManager.default.removeItem(at: url) }
            guard let loaded = FullGramVoiceDSP.readWAV16Mono(from: url), !loaded.samples.isEmpty else {
                DispatchQueue.main.async { self?.onCompleted?(false) }
                return
            }
            let ok = FullGramCustomBleepStore.shared.saveCustomSamples(loaded.samples, sampleRate: loaded.sampleRate, name: "Запись с микрофона")
            if ok {
                FullGramBleepSound.current = .custom
            }
            DispatchQueue.main.async {
                self?.onCompleted?(ok)
            }
        }
    }
}
