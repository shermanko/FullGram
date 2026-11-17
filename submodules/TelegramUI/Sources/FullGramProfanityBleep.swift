import Foundation
import AVFoundation
import SwiftSignalKit
import Display
import AccountContext
import OpusBinding

/// Post-recording profanity bleeping for voice messages using on-device speech recognition
/// and user-selected replacement sound (bell chime, silence, or SpongeBob dolphin chirp).
enum FullGramProfanityBleep {
    static func process(_ data: RecordedAudioData) -> Signal<RecordedAudioData?, NoError> {
        let sound = FullGramBleepSound.current
        guard sound.isEnabled else {
            return .single(data)
        }
        return Signal { subscriber in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_bleep_\(Int64.random(in: 1 ... Int64.max)).ogg")
            guard (try? data.compressedData.write(to: url)) != nil, var samples = decode(path: url.path) else {
                try? FileManager.default.removeItem(at: url)
                subscriber.putNext(data)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            try? FileManager.default.removeItem(at: url)

            FullGramSpeechBleep.recognizeSamples(samples, sampleRate: 16000.0) { ranges in
                guard !ranges.isEmpty else {
                    subscriber.putNext(data)
                    subscriber.putCompletion()
                    return
                }
                samples.withUnsafeMutableBufferPointer { buf in
                    if let base = buf.baseAddress {
                        FullGramSpeechBleep.applyBleep(to: base, count: buf.count, sampleRate: 16000.0, ranges: ranges, sound: sound)
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
        |> timeout(30.0, queue: .concurrentDefaultQueue(), alternate: .single(data))
    }

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
            let count = Int(read)
            var index = 0
            while index + 2 < count {
                result.append(Int16((Int(buffer[index]) + Int(buffer[index + 1]) + Int(buffer[index + 2])) / 3))
                index += 3
            }
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
}
