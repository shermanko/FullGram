import Foundation
import AVFoundation
import SwiftSignalKit
import Display
import AccountContext
import OpusBinding

/// Post-recording profanity bleeping (and deferred voice DSP when bleeping is active) for voice messages
/// using speech recognition on the clean voice before applying pitch/robot effects and bleep sound.
enum FullGramProfanityBleep {
    private static let opusSampleRate: Double = 48000.0

    static func process(_ data: RecordedAudioData) -> Signal<RecordedAudioData?, NoError> {
        let sound = FullGramBleepSound.current
        guard sound.isEnabled else {
            return .single(data)
        }
        let voiceMode = FullGramVoiceMode.current
        let noiseMode = FullGramNoiseReductionMode.current
        return Signal { subscriber in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_bleep_\(Int64.random(in: 1 ... Int64.max)).ogg")
            guard (try? data.compressedData.write(to: url)) != nil, let decodedSamples = decode(path: url.path) else {
                try? FileManager.default.removeItem(at: url)
                subscriber.putNext(data)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            try? FileManager.default.removeItem(at: url)

            // Recognize profanity on the clean, natural human voice BEFORE applying voice changer effects.
            FullGramSpeechBleep.recognizeSamples(decodedSamples, sampleRate: opusSampleRate) { ranges in
                guard !ranges.isEmpty || voiceMode != .off || noiseMode != .off else {
                    subscriber.putNext(data)
                    subscriber.putCompletion()
                    return
                }
                var samples = decodedSamples
                samples.withUnsafeMutableBufferPointer { buf in
                    guard let base = buf.baseAddress else { return }
                    if voiceMode != .off || noiseMode != .off {
                        let dsp = FullGramVoiceDSP(mode: voiceMode, noiseMode: noiseMode, sampleRate: opusSampleRate)
                        dsp.process(base, count: buf.count)
                    }
                    if !ranges.isEmpty {
                        FullGramSpeechBleep.applyBleep(to: base, count: buf.count, sampleRate: opusSampleRate, ranges: ranges, sound: sound)
                    }
                }
                if let encoded = encode(samples) {
                    subscriber.putNext(RecordedAudioData(compressedData: encoded, resumeData: nil, duration: data.duration, waveform: data.waveform, trimRange: data.trimRange))
                } else {
                    subscriber.putNext(data)
                }
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
        |> timeout(12.0, queue: .concurrentDefaultQueue(), alternate: .single(data))
    }

    /// OggOpusReader (`op_read`) decodes Opus at 48,000 Hz mono Int16, matching TGOggOpusWriter's 48,000 Hz input rate.
    private static func decode(path: String) -> [Int16]? {
        guard let reader = OggOpusReader(path: path) else { return nil }
        var result: [Int16] = []
        var buffer = [Int16](repeating: 0, count: 5760)
        while true {
            let capacity = Int32(buffer.count)
            let read = buffer.withUnsafeMutableBytes { raw in
                reader.read(raw.baseAddress!, bufSize: capacity)
            }
            if read <= 0 { break }
            let count = min(buffer.count, Int(read))
            result.append(contentsOf: buffer[0 ..< count])
        }
        return result.isEmpty ? nil : result
    }

    private static func encode(_ samples: [Int16]) -> Data? {
        let packet = 960
        let dataItem = TGDataItem()
        let writer = TGOggOpusWriter()
        guard writer.begin(with: dataItem) else { return nil }
        var chunk = [Int16](repeating: 0, count: packet)
        var offset = 0
        while offset < samples.count {
            let valid = min(packet, samples.count - offset)
            chunk.withUnsafeMutableBufferPointer { dst in
                samples.withUnsafeBufferPointer { src in
                    guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return }
                    dstBase.update(from: srcBase.advanced(by: offset), count: valid)
                    if valid < packet {
                        dstBase.advanced(by: valid).update(repeating: 0, count: packet - valid)
                    }
                }
            }
            chunk.withUnsafeMutableBytes { raw in
                _ = writer.writeFrame(raw.bindMemory(to: UInt8.self).baseAddress, frameByteCount: UInt(raw.count))
            }
            offset += packet
        }
        guard writer.writeFrame(nil, frameByteCount: 0) else { return nil }
        return dataItem.data()
    }

    /// Transcribe a recorded voice message (`RecordedAudioData`) to editable text for the "→A" button.
    static func transcribe(_ data: RecordedAudioData) -> Signal<String?, NoError> {
        return Signal { subscriber in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_transcribe_\(Int64.random(in: 1 ... Int64.max)).ogg")
            guard (try? data.compressedData.write(to: url)) != nil, let decodedSamples = decode(path: url.path) else {
                try? FileManager.default.removeItem(at: url)
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            try? FileManager.default.removeItem(at: url)

            FullGramSpeechBleep.transcribe(decodedSamples, sampleRate: opusSampleRate) { text in
                subscriber.putNext(text)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
        |> runOn(Queue.concurrentDefaultQueue())
        |> timeout(12.0, queue: .concurrentDefaultQueue(), alternate: .single(nil))
    }
}
