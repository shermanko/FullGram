import Foundation
import AVFoundation
import Speech

public enum FullGramSpeechBleep {
    private static let fallbackLocales = ["ru-RU", "en-US"]

    /// Normal Russian/English words that share letter sequences with profanity roots and must NEVER be bleeped.
    private static let safeWords: Set<String> = [
        "тебя", "себя", "ребята", "ребятам", "ребятами", "ребенок", "ребенка", "ребенку", "ребенком",
        "учеба", "учебы", "учебе", "учебу", "учебой", "учебник", "учебный", "учебная", "учебное",
        "небо", "неба", "небе", "небом", "небеса", "небесный",
        "хлеб", "хлеба", "хлебу", "хлебом", "хлебный", "хлебобулочный",
        "обед", "обеда", "обеду", "обедом", "обедать", "пообедать",
        "победа", "победы", "победе", "победу", "победой", "победить", "победитель",
        "мебель", "мебели", "мебельный", "лебедь", "лебеди", "лебединый",
        "стебель", "стебля", "стебли", "щебень", "щебня", "гребень", "гребня",
        "дебаты", "дебатов", "требовать", "требует", "требуется", "потребовать", "потребность",
        "истреблять", "истребление", "употреблять", "употребление", "злоупотреблять",
        "оскорблять", "оскорбление", "ослаблять", "ослабление", "влюблять", "влюбленный",
        "углублять", "углубление", "усугублять", "пособлять", "приспособлять", "обособлять",
        "корабль", "корабли", "корабля", "кораблем", "рубль", "рубля", "рублей", "рубли", "рублем",
        "дубль", "ансамбль", "сабля", "сабли", "грабли", "оглобля", "дирижабль", "констебль",
        "сукно", "сукна", "барсук", "барсука", "суккулент", "сук", "сучок",
        "команда", "команды", "команде", "команду", "командой", "командир", "командовать", "командование",
        "мандат", "мандарин", "мандарины", "мандаринов", "мандолина", "нормандский", "нормандия",
        "педагог", "педагогика", "педиатр", "педиатрия", "педикюр", "логопед", "ортопед", "велосипед", "мопед", "энциклопедия",
        "скипидар", "херсон", "херувим", "парикмахер", "парикмахерская", "мохер",
        "страхуй", "страхуйте", "застрахуй", "перестрахуй", "подстрахуй", "страховка", "страхование",
        "пастух", "петух", "лопух", "слух", "дух", "пух", "муха", "сухо", "сухой", "сухая", "сухое",
        "ухо", "брюхо", "кухня", "бухгалтер", "бухгалтерия", "бухта", "шахматы", "вахта", "яхта", "пихта",
        "сразу", "сражение", "сражаться", "сравнить", "сравнение", "сравнивать", "срабатывать", "сработать", "срастаться"
    ]

    private static let russianExact: Set<String> = [
        "бля", "бляд", "блядь", "блять", "бляди", "блядей", "блядям", "блядью", "блядина", "блядство", "блядский",
        "сука", "суки", "суке", "суку", "сукой", "сучка", "сучки", "сучку", "сучкой", "сучара", "сученыш", "сучий", "сучья", "сучье",
        "хуй", "хуя", "хуе", "хуи", "хую", "хуем", "хуями", "хуях", "хуйня", "хуйни", "хуйню", "хуйней", "хуета", "хуетень",
        "хуевый", "хуевая", "хуевое", "хуево", "хуесос", "хуила", "хуище", "нахуй", "нахуя", "похуй", "похую", "нехуй", "нихуя", "дохуя",
        "пизда", "пизды", "пизде", "пизду", "пиздой", "пиздец", "пиздеца", "пиздеж", "пиздатый", "пиздатая", "пиздатое", "пиздато",
        "пиздобол", "пиздабол", "пиздюк", "пиздюки", "пиздюлина", "пиздень", "пиздеть", "спиздить", "спиздил", "распиздяй",
        "еб", "ебать", "ебал", "ебала", "ебали", "ебаный", "ебаная", "ебаное", "ебанутый", "ебанутая", "ебанат", "ебанашка",
        "ебан", "еблан", "ебло", "ебало", "ебальник", "ебут", "ебет", "ебешь", "ебем", "ебете", "еби", "ебите", "ебля", "ебливый",
        "ебашить", "ебошить", "заебал", "заебала", "заебали", "заебать", "заебись", "заебок", "выебал", "выебан", "выебываться",
        "наебал", "наебать", "наебалово", "отъебись", "отьебись", "подъеб", "подьеб", "разъеб", "разьеб", "съебался", "сьебался",
        "уебок", "уебище", "уебан", "долбоеб", "долбоебы", "долбоящер", "охуеть", "охуел", "охуенно", "охуенный", "ахуеть", "ахуел", "ахуенно",
        "мудак", "мудаки", "мудила", "мудило", "мудозвон", "мудень", "мудя",
        "гандон", "гондон", "гандоны", "гондоны",
        "пидор", "пидоры", "пидар", "пидары", "пидр", "пидры", "педик", "педики", "пидорас", "пидорасы", "пидарас", "пидрила", "пидорасина",
        "шлюха", "шлюхи", "шлюху", "шлюхой", "шалава", "шалавы", "проститутка", "курва",
        "дрочить", "дрочу", "дрочит", "дрочила", "дрочка", "залупа", "залупы", "залупу", "манда", "манды", "манду", "елда",
        "хер", "хера", "херу", "хером", "херня", "херовый", "херово", "нахер", "нахера", "похер", "нихера", "охереть", "ахереть",
        "говно", "говна", "говном", "говнюк", "дерьмо", "дерьма", "жопа", "жопы", "жопу", "жопой", "срать", "срака", "засранец", "обосрался",
        "мразь", "мрази", "мразота", "гнида", "падла", "ублюдок", "ублюдки", "выблядок",
        "фак", "факинг", "шит", "бич", "булшит", "мазафакер"
    ]

    /// Morphological roots matched anywhere inside a non-whitelisted word (catches all prefixes & suffixes).
    private static let russianRoots: [String] = [
        "хуй", "хуя", "хуе", "хуи", "хую",
        "пизд",
        "бляд", "блят", "блядин", "выбляд", "ублюд",
        "еба", "еблан", "ебан", "еби", "ебу", "ебну", "ебш", "ебош", "ебл", "ебт", "ебыв", "ебеш", "ебет",
        "ъеб", "ьеб", "долбоеб", "долбоящ", "уеб", "выеб", "заеб", "наеб", "доеб", "приеб", "проеб", "отьеб", "подьеб", "поеб", "сьеб", "разьеб", "вьеб", "обьеб",
        "мудак", "мудач", "мудил", "мудо",
        "пидор", "пидар", "пидр", "пидри", "педик", "педераст",
        "гандон", "гондон",
        "шлюх", "шлюш", "шалав",
        "залуп", "дроч", "елда",
        "сучар", "сучк", "сучен",
        "херн", "херов", "похер", "нахер", "нихер", "охер", "ахер",
        "говн", "дерьм", "жоп", "засран", "обоср", "проср", "насра", "высра", "срать", "сран", "срак",
        "мразот", "падл", "гнид"
    ]

    private static let russianPrefixes: [String] = [
        "бля", "сук", "хер", "манд"
    ]

    private static let englishExact: Set<String> = [
        "fuck", "fucking", "fucked", "fucker", "fuckers", "fucks", "motherfucker", "motherfucking", "mf",
        "shit", "shits", "shitting", "shitty", "bullshit", "horseshit", "dipshit",
        "bitch", "bitches", "bitching", "bitchy", "sonofabitch",
        "ass", "asses", "asshole", "assholes", "arse", "arsehole", "jackass", "dumbass", "badass", "fatass",
        "bastard", "bastards", "cunt", "cunts", "dick", "dicks", "dickhead",
        "pussy", "pussies", "whore", "whores", "slut", "sluts", "cock", "cocks", "cocksucker",
        "fag", "fags", "faggot", "faggots", "retard", "retarded", "nigger", "niggers", "nigga", "niggas",
        "wanker", "prick", "twat", "douche", "douchebag", "cum", "slutty", "goddamn", "damn"
    ]

    private static let englishRoots: [String] = [
        "fuck", "shit", "bitch", "asshole", "bastard", "cunt", "dickhead", "cocksuck",
        "motherfuck", "bullshit", "pussy", "whore", "slut", "faggot", "nigger", "nigga", "retard", "douche"
    ]

    private static let splitPrefixes: Set<String> = [
        "на", "по", "не", "ни", "до", "за", "во", "в", "от", "об", "при", "про", "вы", "у", "о", "а"
    ]

    private static let contextualHints: [String] = [
        "блять", "блядь", "бля", "сука", "сучка", "хуй", "хуйня", "нахуй", "похуй", "охуеть", "ахуеть", "дохуя", "нихуя",
        "пиздец", "пизда", "пиздеть", "спиздил", "пиздатый",
        "ебать", "заебал", "заебись", "ебал", "ебаный", "еблан", "долбоеб", "уебок", "выебываться", "отъебись", "разъеб",
        "мудак", "пидор", "пидорас", "гандон", "шлюха", "залупа", "херня", "говно", "дерьмо", "жопа", "падла", "мразь",
        "fuck", "fucking", "motherfucker", "shit", "bullshit", "bitch", "asshole", "cunt", "dick"
    ]

    public static func isProfanity(_ rawWord: String) -> Bool {
        let trimmedRaw = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else { return false }

        // 1. iOS SFSpeechRecognizer replaces recognized swear words with asterisks (e.g. "б***ь", "х**", "f**k", "***")
        if trimmedRaw.contains("*") {
            return true
        }

        let normalized = normalizeWord(trimmedRaw)
        guard normalized.count >= 2 else { return false }

        // 2. Check safe-word whitelist first to prevent false positives on normal words
        if safeWords.contains(normalized) {
            return false
        }

        // 3. Exact match (handles 2-letter and full words like "еб", "бля", "хуй", "сука", "fuck", "ass")
        if russianExact.contains(normalized) || englishExact.contains(normalized) {
            return true
        }

        guard normalized.count >= 3 else { return false }

        // 4. Substring root match (catches all Russian/English prefixes and case/verb endings)
        for root in russianRoots where normalized.contains(root) {
            return true
        }
        for root in englishRoots where normalized.contains(root) {
            return true
        }

        // 5. Prefix match for short stems ("бля...", "сук...", "хер...", "манд...")
        for prefix in russianPrefixes where normalized.hasPrefix(prefix) {
            return true
        }

        return false
    }

    private static func normalizeWord(_ word: String) -> String {
        var s = word
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        // Strip internal punctuation such as hyphens or apostrophes
        s.removeAll { !$0.isLetter && !$0.isNumber }
        return s
    }

    public static func detectProfanityRanges(
        inAudioFileAt url: URL,
        leadOffset: TimeInterval = 0.0,
        completion: @escaping ([ClosedRange<TimeInterval>]) -> Void
    ) {
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        if authStatus == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else {
                    completion([])
                    return
                }
                performRecognition(url: url, attemptIndex: 0, leadOffset: leadOffset, accumulatedRanges: [], completion: completion)
            }
            return
        }
        guard authStatus == .authorized else {
            completion([])
            return
        }
        performRecognition(url: url, attemptIndex: 0, leadOffset: leadOffset, accumulatedRanges: [], completion: completion)
    }

    public static func recognizeSamples(
        _ samples: [Int16],
        sampleRate: Double = 16000.0,
        completion: @escaping ([ClosedRange<TimeInterval>]) -> Void
    ) {
        guard !samples.isEmpty, sampleRate > 0.0 else {
            completion([])
            return
        }

        // Prepare a 16 kHz normalized speech WAV with leading/trailing silence padding so SFSpeechRecognizer VAD
        // never clips swear words spoken at the very start or very end of a recording.
        let targetRate = 16000.0
        let resampled: [Int16]
        if abs(sampleRate - targetRate) < 1.0 {
            resampled = samples
        } else {
            let ratio = sampleRate / targetRate
            let outCount = max(1, Int((Double(samples.count) / ratio).rounded()))
            var out = [Int16](repeating: 0, count: outCount)
            let span = max(1, Int(ratio.rounded()))
            for i in 0 ..< outCount {
                let start = min(samples.count - 1, Int(Double(i) * ratio))
                let end = min(samples.count, start + span)
                var sum = 0
                for j in start ..< end {
                    sum += Int(samples[j])
                }
                out[i] = Int16(max(-32768, min(32767, sum / max(1, end - start))))
            }
            resampled = out
        }

        // Peak-normalize speech so quiet microphone recordings are recognized accurately
        var maxPeak: Int = 0
        for s in resampled {
            let a = abs(Int(s))
            if a > maxPeak { maxPeak = a }
        }
        let gain: Double = (maxPeak > 180 && maxPeak < 24000) ? min(5.5, 26000.0 / Double(maxPeak)) : 1.0

        let leadSeconds: TimeInterval = 0.16
        let trailSeconds: TimeInterval = 0.28
        let leadSamples = Int(targetRate * leadSeconds)
        let trailSamples = Int(targetRate * trailSeconds)

        var padded = [Int16](repeating: 0, count: leadSamples + resampled.count + trailSamples)
        for i in 0 ..< resampled.count {
            let scaled = Double(resampled[i]) * gain
            padded[leadSamples + i] = Int16(max(-32767.0, min(32767.0, scaled)))
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_rec_\(UUID().uuidString).wav")
        guard FullGramVoiceDSP.writeWAV16Mono(samples: padded, sampleRate: Int(targetRate), to: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            completion([])
            return
        }

        detectProfanityRanges(inAudioFileAt: tempURL, leadOffset: leadSeconds) { ranges in
            try? FileManager.default.removeItem(at: tempURL)
            completion(ranges)
        }
    }

    private struct RecognitionAttempt {
        let localeId: String
        let forceOnDevice: Bool
    }

    private static func buildAttempts() -> [RecognitionAttempt] {
        // Prioritize ru-RU first so Russian profanity is always matched first, then current locale, then en-US.
        var locales: [String] = []
        for id in ["ru-RU", Locale.current.identifier, "en-US"] + fallbackLocales {
            if !id.isEmpty && !locales.contains(id) {
                locales.append(id)
            }
        }
        var attempts: [RecognitionAttempt] = []
        for id in locales {
            attempts.append(RecognitionAttempt(localeId: id, forceOnDevice: false))
            attempts.append(RecognitionAttempt(localeId: id, forceOnDevice: true))
        }
        return attempts
    }

    private static func performRecognition(
        url: URL,
        attemptIndex: Int,
        leadOffset: TimeInterval,
        accumulatedRanges: [ClosedRange<TimeInterval>],
        completion: @escaping ([ClosedRange<TimeInterval>]) -> Void
    ) {
        let attempts = buildAttempts()
        guard attemptIndex < attempts.count else {
            completion(merge(ranges: accumulatedRanges))
            return
        }

        let current = attempts[attemptIndex]
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: current.localeId)), recognizer.isAvailable else {
            performRecognition(url: url, attemptIndex: attemptIndex + 1, leadOffset: leadOffset, accumulatedRanges: accumulatedRanges, completion: completion)
            return
        }
        if current.forceOnDevice && !recognizer.supportsOnDeviceRecognition {
            performRecognition(url: url, attemptIndex: attemptIndex + 1, leadOffset: leadOffset, accumulatedRanges: accumulatedRanges, completion: completion)
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualHints
        if #available(iOS 16.0, *) {
            request.addsPunctuation = false
        }
        if current.forceOnDevice {
            request.requiresOnDeviceRecognition = true
        }

        let lock = NSLock()
        var finished = false
        var partialRanges: [ClosedRange<TimeInterval>] = accumulatedRanges
        var hadAnySegments = false

        let task = recognizer.recognitionTask(with: request) { result, error in
            lock.lock()
            if finished {
                lock.unlock()
                return
            }

            if let result {
                let extracted = extractProfanityRanges(from: result, leadOffset: leadOffset)
                if !extracted.isEmpty {
                    partialRanges.append(contentsOf: extracted)
                }
                if !result.bestTranscription.segments.isEmpty {
                    hadAnySegments = true
                }
                if result.isFinal {
                    finished = true
                    let finalRanges = merge(ranges: partialRanges)
                    lock.unlock()
                    if !finalRanges.isEmpty {
                        completion(finalRanges)
                    } else if !hadAnySegments && attemptIndex + 1 < attempts.count {
                        performRecognition(url: url, attemptIndex: attemptIndex + 1, leadOffset: leadOffset, accumulatedRanges: partialRanges, completion: completion)
                    } else {
                        // If ru-RU produced segments with no profanity, still complete quickly
                        completion(finalRanges)
                    }
                    return
                }
            }

            if error != nil {
                finished = true
                let collected = merge(ranges: partialRanges)
                lock.unlock()
                if !collected.isEmpty {
                    completion(collected)
                } else {
                    performRecognition(url: url, attemptIndex: attemptIndex + 1, leadOffset: leadOffset, accumulatedRanges: partialRanges, completion: completion)
                }
                return
            }
            lock.unlock()
        }

        // Safety watchdog so a hung recognition task never stalls voice testing or sending
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5.5) {
            lock.lock()
            guard !finished else {
                lock.unlock()
                return
            }
            finished = true
            let collected = merge(ranges: partialRanges)
            lock.unlock()
            task.cancel()
            completion(collected)
        }
    }

    private static func extractProfanityRanges(from result: SFSpeechRecognitionResult, leadOffset: TimeInterval) -> [ClosedRange<TimeInterval>] {
        var ranges: [ClosedRange<TimeInterval>] = []
        ranges.append(contentsOf: extractProfanityRanges(from: result.bestTranscription, leadOffset: leadOffset))

        // Check alternative hypotheses in case bestTranscription substituted a polite homophone
        let primarySegments = result.bestTranscription.segments
        for alt in result.transcriptions where alt !== result.bestTranscription {
            let altRanges = extractProfanityRanges(from: alt, fallbackSegments: primarySegments, leadOffset: leadOffset)
            ranges.append(contentsOf: altRanges)
        }
        return ranges
    }

    private static func extractProfanityRanges(
        from transcription: SFTranscription,
        fallbackSegments: [SFTranscriptionSegment] = [],
        leadOffset: TimeInterval
    ) -> [ClosedRange<TimeInterval>] {
        var ranges: [ClosedRange<TimeInterval>] = []
        let segments = transcription.segments
        guard !segments.isEmpty else { return ranges }

        for (idx, segment) in segments.enumerated() {
            let sub = segment.substring
            var matched = isProfanity(sub)

            // Also check individual whitespace/punctuation-delimited tokens if a segment spans multiple words
            if !matched && sub.contains(" ") {
                for token in sub.components(separatedBy: .whitespacesAndNewlines) where isProfanity(token) {
                    matched = true
                    break
                }
            }

            // Check two-segment compound profanity (e.g. "на" + "хуй", "по" + "хуй", "в" + "пизду")
            var includePreviousPrefix = false
            if !matched, idx + 1 < segments.count {
                let combined = normalizeWord(sub) + normalizeWord(segments[idx + 1].substring)
                if combined.count >= 4 && isProfanity(combined) && !isProfanity(segments[idx + 1].substring) {
                    matched = true
                }
            }
            if matched, idx > 0 {
                let prevNorm = normalizeWord(segments[idx - 1].substring)
                if splitPrefixes.contains(prevNorm) {
                    includePreviousPrefix = true
                }
            }

            guard matched else { continue }

            var rawStart = segment.timestamp
            var rawDuration = segment.duration
            if rawStart <= 0.0 && rawDuration <= 0.0 && idx < fallbackSegments.count {
                rawStart = fallbackSegments[idx].timestamp
                rawDuration = fallbackSegments[idx].duration
            }
            if includePreviousPrefix, idx > 0 {
                let prevStart = segments[idx - 1].timestamp
                if prevStart > 0.0 && rawStart - prevStart <= 0.32 {
                    rawDuration += (rawStart - prevStart)
                    rawStart = prevStart
                }
            }

            let adjustedStart = max(0.0, rawStart - leadOffset - 0.07)
            let effectiveDur = max(0.26, rawDuration + 0.14)
            ranges.append(adjustedStart ... (adjustedStart + effectiveDur))
        }
        return ranges
    }

    private static func merge(ranges: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<TimeInterval>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.09 {
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
        let fadeIn = min(1.0, t / 0.014)
        let fadeOut = min(1.0, Double(totalSamples - 1 - index) / (sampleRate * 0.020))
        let env = max(0.0, min(fadeIn, fadeOut))

        switch sound {
        case .off, .silence:
            return 0.0
        case .bell:
            let decay = exp(-t * 4.2)
            let tone = 0.65 * sin(2.0 * .pi * 1046.5 * t) + 0.35 * sin(2.0 * .pi * 2093.0 * t)
            return Float(tone * decay * env * 0.52)
        case .dolphin:
            // SpongeBob dolphin chirp: rapid FM whistle sweep with bubbly warble bursts
            let burst = sin(.pi * progress * 3.0)
            let burstEnv = abs(burst)
            let modFreq = 26.0
            let carrierFreq = 2900.0 + 1250.0 * sin(2.0 * .pi * modFreq * t) + 550.0 * sin(2.0 * .pi * 7.5 * t)
            let signal = sin(2.0 * .pi * carrierFreq * t)
            return Float(signal * burstEnv * env * 0.44)
        }
    }

    public static func applyBleep(to samples: UnsafeMutablePointer<Int16>, count: Int, sampleRate: Double, ranges: [ClosedRange<TimeInterval>], sound: FullGramBleepSound) {
        guard sound != .off, !ranges.isEmpty else { return }
        let crossfadeSamples = max(1, Int(sampleRate * 0.010))
        for range in ranges {
            let startIdx = max(0, Int(range.lowerBound * sampleRate))
            let endIdx = min(count, Int(range.upperBound * sampleRate))
            guard endIdx > startIdx else { continue }
            let total = endIdx - startIdx
            for i in startIdx ..< endIdx {
                let localIdx = i - startIdx
                let bleepVal = Double(sample(sound: sound, index: localIdx, totalSamples: total, sampleRate: sampleRate)) * 32767.0
                let dryVal = Double(samples[i])

                // Smooth 10ms crossfade at edges so cutting the voice never clicks
                let wetWeight: Double
                if localIdx < crossfadeSamples {
                    wetWeight = Double(localIdx) / Double(crossfadeSamples)
                } else if total - 1 - localIdx < crossfadeSamples {
                    wetWeight = Double(total - 1 - localIdx) / Double(crossfadeSamples)
                } else {
                    wetWeight = 1.0
                }
                let mixed = dryVal * (1.0 - wetWeight) + bleepVal * wetWeight
                samples[i] = Int16(max(-32767.0, min(32767.0, mixed)))
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_bleep_\(sound.rawValue).wav")
        var pcm = [Int16](repeating: 0, count: totalSamples)
        for i in 0 ..< totalSamples {
            let v = Double(sample(sound: sound, index: i, totalSamples: totalSamples, sampleRate: sampleRate))
            pcm[i] = Int16(max(-32767.0, min(32767.0, v * 32767.0)))
        }
        guard FullGramVoiceDSP.writeWAV16Mono(samples: pcm, sampleRate: Int(sampleRate), to: url) else {
            return nil
        }
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
