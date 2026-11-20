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

        // 1. iOS SFSpeechRecognizer replaces recognized swear words with asterisks (e.g. "б***ь", "х**", "f**k")
        if trimmedRaw.contains("*") && (trimmedRaw.rangeOfCharacter(from: .letters) != nil || trimmedRaw.contains("**")) {
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

        // 5. Prefix match for short stems ("бля...", "сук...", "хер...", "манд...") including behind Russian verb/adverb prefixes
        for prefix in russianPrefixes where normalized.hasPrefix(prefix) {
            return true
        }
        for sp in splitPrefixes where normalized.hasPrefix(sp) && normalized.count > sp.count + 2 {
            let tail = String(normalized.dropFirst(sp.count))
            if russianExact.contains(tail) {
                return true
            }
            for rp in russianPrefixes where tail.hasPrefix(rp) {
                return true
            }
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

            if let result, result.isFinal {
                let extracted = extractProfanityRanges(from: result, leadOffset: leadOffset)
                if !extracted.isEmpty {
                    partialRanges.append(contentsOf: extracted)
                }
                if !result.bestTranscription.segments.isEmpty {
                    hadAnySegments = true
                }
                finished = true
                let finalRanges = merge(ranges: partialRanges)
                lock.unlock()
                if !finalRanges.isEmpty {
                    completion(finalRanges)
                } else if !hadAnySegments && attemptIndex + 1 < attempts.count {
                    performRecognition(url: url, attemptIndex: attemptIndex + 1, leadOffset: leadOffset, accumulatedRanges: partialRanges, completion: completion)
                } else {
                    completion(finalRanges)
                }
                return
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
            guard rawDuration > 0.02 else { continue }
            if rawStart <= 0.0 && leadOffset > 0.05 { continue }

            if includePreviousPrefix, idx > 0 {
                let prevStart = segments[idx - 1].timestamp
                if prevStart > 0.0 && rawStart - prevStart <= 0.32 {
                    rawDuration += (rawStart - prevStart)
                    rawStart = prevStart
                }
            }

            let adjustedStart = max(0.0, rawStart - leadOffset - 0.05)
            let effectiveDur = max(0.24, rawDuration + 0.10)
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

    private static let bundledSamplesLock = NSLock()
    private static var bundledSamplesCache: [String: [Float]] = [:]

    private static func bundledAudioSamples48k(resourceName: String) -> [Float] {
        bundledSamplesLock.lock()
        if let cached = bundledSamplesCache[resourceName] {
            bundledSamplesLock.unlock()
            return cached
        }
        bundledSamplesLock.unlock()

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3") else {
            bundledSamplesLock.lock()
            bundledSamplesCache[resourceName] = []
            bundledSamplesLock.unlock()
            return []
        }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else {
            bundledSamplesLock.lock()
            bundledSamplesCache[resourceName] = []
            bundledSamplesLock.unlock()
            return []
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        var samples: [Float] = []
        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }
            let count = length / MemoryLayout<Float>.size
            var chunk = [Float](repeating: 0.0, count: count)
            chunk.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress {
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                }
            }
            samples.append(contentsOf: chunk)
        }

        // Peak-normalize to 0.90 for crisp, audible playback over speech
        var peak: Float = 0.0
        for s in samples {
            let a = abs(s)
            if a > peak { peak = a }
        }
        if peak > 0.01 && peak < 0.85 {
            let gain = min(4.0, 0.90 / peak)
            for i in 0 ..< samples.count {
                samples[i] = max(-0.98, min(0.98, samples[i] * gain))
            }
        }

        bundledSamplesLock.lock()
        bundledSamplesCache[resourceName] = samples
        bundledSamplesLock.unlock()
        return samples
    }

    public static func sample(sound: FullGramBleepSound, index: Int, totalSamples: Int, sampleRate: Double) -> Float {
        let clip: [Float]?
        switch sound {
        case .dolphin:
            clip = bundledAudioSamples48k(resourceName: "fullgram_dolphin")
        case .duck:
            clip = bundledAudioSamples48k(resourceName: "fullgram_duck")
        default:
            clip = nil
        }
        return sampleFast(sound: sound, index: index, totalSamples: totalSamples, sampleRate: sampleRate, preloadedClip: clip)
    }

    private static func sampleFast(sound: FullGramBleepSound, index: Int, totalSamples: Int, sampleRate: Double, preloadedClip: [Float]?) -> Float {
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
            let clip = preloadedClip ?? []
            if !clip.isEmpty {
                let pos = Int((Double(index) / max(1.0, sampleRate)) * 48000.0) % clip.count
                return clip[pos] * Float(env)
            }
            let burstEnv = abs(sin(.pi * progress * 3.0))
            let carrierFreq = 2900.0 + 1250.0 * sin(2.0 * .pi * 26.0 * t)
            return Float(sin(2.0 * .pi * carrierFreq * t) * burstEnv * env * 0.44)
        case .duck:
            let clip = preloadedClip ?? []
            if !clip.isEmpty {
                let pos = Int((Double(index) / max(1.0, sampleRate)) * 48000.0) % clip.count
                return clip[pos] * Float(env)
            }
            let quackEnv = sin(.pi * min(1.0, progress * 1.15))
            let f0 = 285.0 - 75.0 * progress
            let p = 2.0 * .pi * f0 * t
            return Float((0.45 * sin(p) + 0.35 * sin(2.0 * p)) * quackEnv * env * 0.52)
        case .custom:
            if let customVal = FullGramCustomBleepStore.shared.sampleAt(index: index, totalSamples: totalSamples, sampleRate: sampleRate) {
                return customVal * Float(env)
            }
            let decay = exp(-t * 4.2)
            let tone = 0.65 * sin(2.0 * .pi * 1046.5 * t) + 0.35 * sin(2.0 * .pi * 2093.0 * t)
            return Float(tone * decay * env * 0.52)
        }
    }

    public static func applyBleep(to samples: UnsafeMutablePointer<Int16>, count: Int, sampleRate: Double, ranges: [ClosedRange<TimeInterval>], sound: FullGramBleepSound) {
        guard sound != .off, !ranges.isEmpty else { return }
        let preloadedClip: [Float]?
        switch sound {
        case .dolphin:
            preloadedClip = bundledAudioSamples48k(resourceName: "fullgram_dolphin")
        case .duck:
            preloadedClip = bundledAudioSamples48k(resourceName: "fullgram_duck")
        default:
            preloadedClip = nil
        }
        let crossfadeSamples = max(1, Int(sampleRate * 0.010))
        for range in ranges {
            let startIdx = max(0, Int(range.lowerBound * sampleRate))
            let endIdx = min(count, Int(range.upperBound * sampleRate))
            guard endIdx > startIdx else { continue }
            let total = endIdx - startIdx
            for i in startIdx ..< endIdx {
                let localIdx = i - startIdx
                let bleepVal = Double(sampleFast(sound: sound, index: localIdx, totalSamples: total, sampleRate: sampleRate, preloadedClip: preloadedClip)) * 32767.0
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
            let built = try? buildBleepComposition(asset: asset, audioTrack: audioTrack, ranges: ranges, sound: sound)
            guard let built,
                  let exporter = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
                if let tempURL = built?.tempBleepURL {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                let fallbackMix = AVMutableAudioMix()
                let fallbackParams = AVMutableAudioMixInputParameters(track: audioTrack)
                for range in ranges {
                    let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
                    let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
                    fallbackParams.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: CMTimeRange(start: start, duration: CMTime(seconds: 0.02, preferredTimescale: 600)))
                    fallbackParams.setVolume(0.0, at: CMTimeAdd(start, CMTime(seconds: 0.02, preferredTimescale: 600)))
                    fallbackParams.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: CMTimeRange(start: end, duration: CMTime(seconds: 0.02, preferredTimescale: 600)))
                }
                fallbackMix.inputParameters = [fallbackParams]
                exportWithMixOnly(asset: asset, mix: fallbackMix, outputURL: outputURL, completion: completion)
                return
            }

            let mix = AVMutableAudioMix()
            let params = AVMutableAudioMixInputParameters(track: built.originalAudioTrack)
            for range in ranges {
                let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
                let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
                params.setVolumeRamp(fromStartVolume: 1.0, toEndVolume: 0.0, timeRange: CMTimeRange(start: start, duration: CMTime(seconds: 0.02, preferredTimescale: 600)))
                params.setVolume(0.0, at: CMTimeAdd(start, CMTime(seconds: 0.02, preferredTimescale: 600)))
                params.setVolumeRamp(fromStartVolume: 0.0, toEndVolume: 1.0, timeRange: CMTimeRange(start: end, duration: CMTime(seconds: 0.02, preferredTimescale: 600)))
            }
            mix.inputParameters = [params]

            let tempBleepURL = built.tempBleepURL
            try? FileManager.default.removeItem(at: outputURL)
            exporter.outputURL = outputURL
            exporter.outputFileType = .mp4
            exporter.audioMix = mix
            exporter.exportAsynchronously {
                if let tempBleepURL {
                    try? FileManager.default.removeItem(at: tempBleepURL)
                }
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

    private static func buildBleepComposition(
        asset: AVAsset,
        audioTrack: AVAssetTrack,
        ranges: [ClosedRange<TimeInterval>],
        sound: FullGramBleepSound
    ) throws -> (composition: AVMutableComposition, originalAudioTrack: AVMutableCompositionTrack, tempBleepURL: URL?) {
        let composition = AVMutableComposition()
        let duration = asset.duration
        if let videoTrack = asset.tracks(withMediaType: .video).first,
           let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
            compVideo.preferredTransform = videoTrack.preferredTransform
        }
        guard let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "FullGramSpeechBleep", code: -1, userInfo: nil)
        }
        try compAudio.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)

        var tempBleepURL: URL?
        if sound != .silence, let bleepFile = generateBleepWav(sound: sound, duration: 1.0) {
            tempBleepURL = bleepFile
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
        return (composition, compAudio, tempBleepURL)
    }

    private static func generateBleepWav(sound: FullGramBleepSound, duration: TimeInterval) -> URL? {
        let sampleRate = 44100.0
        let totalSamples = Int(duration * sampleRate)
        guard totalSamples > 0 else { return nil }
        let preloadedClip: [Float]?
        switch sound {
        case .dolphin:
            preloadedClip = bundledAudioSamples48k(resourceName: "fullgram_dolphin")
        case .duck:
            preloadedClip = bundledAudioSamples48k(resourceName: "fullgram_duck")
        default:
            preloadedClip = nil
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fullgram_bleep_\(sound.rawValue)_\(UUID().uuidString).wav")
        var pcm = [Int16](repeating: 0, count: totalSamples)
        for i in 0 ..< totalSamples {
            let v = Double(sampleFast(sound: sound, index: i, totalSamples: totalSamples, sampleRate: sampleRate, preloadedClip: preloadedClip))
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
                            formatTranscriptionWithSummary(text: text, mode: FullGramVoiceSummaryMode.current, completion: completion)
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

    // MARK: - Smart Voice Summary (Auto TL;DR for Voice & Round Video Messages)

    private static func formatTranscriptionWithSummary(
        text: String,
        mode: FullGramVoiceSummaryMode,
        completion: @escaping (String?) -> Void
    ) {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        // Only summarize voice messages that have at least 12 words
        guard mode != .off, words.count >= 12 else {
            completion(text)
            return
        }

        let fallbackSummary = buildExtractiveSummary(from: text, words: words)
        let deliverFormatted: (String) -> Void = { summary in
            let cleanSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanSummary.isEmpty else {
                completion(text)
                return
            }
            switch mode {
            case .off:
                completion(text)
            case .summaryAndText:
                completion("⚡️ Суть ГС: \(cleanSummary)\n\n📝 Текст: \(text)")
            case .summaryOnly:
                completion("⚡️ Суть ГС: \(cleanSummary)")
            }
        }

        guard let url = URL(string: "https://text.pollinations.ai/openai") else {
            deliverFormatted(fallbackSummary)
            return
        }

        var req = URLRequest(url: url, timeoutInterval: 3.4)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": "openai",
            "temperature": 0.2,
            "messages": [
                [
                    "role": "system",
                    "content": "Сожми расшифровку голосового сообщения в 1-2 коротких предложения (только сама суть, факты, вопросы или договорённости, без вступлений и кавычек, на языке оригинала)."
                ],
                [
                    "role": "user",
                    "content": String(text.prefix(1500))
                ]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let lock = NSLock()
        var done = false
        let finishOnce: (String) -> Void = { res in
            lock.lock()
            guard !done else {
                lock.unlock()
                return
            }
            done = true
            lock.unlock()
            deliverFormatted(res)
        }

        let task = URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    finishOnce(trimmed)
                    return
                }
            }
            finishOnce(fallbackSummary)
        }
        task.resume()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3.5) {
            task.cancel()
            finishOnce(fallbackSummary)
        }
    }

    private static func buildExtractiveSummary(from text: String, words: [String]) -> String {
        let separators = CharacterSet(charactersIn: ".!?;\n")
        let clauses = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 }

        if clauses.count >= 2 {
            // Score clauses by presence of numbers, question words, action verbs, and compact length
            let priorityKeywords = ["нужно", "надо", "давай", "когда", "во сколько", "завтра", "сегодня", "оплат", "деньг", "скин", "позвон", "встрет", "вопрос", "важно", "главное", "итог", "короче"]
            let scored = clauses.enumerated().map { idx, clause -> (Int, Double, String) in
                let lower = clause.lowercased()
                var score = (idx == 0 || idx == clauses.count - 1) ? 1.5 : 1.0
                if clause.contains(where: \.isNumber) { score += 2.2 }
                for kw in priorityKeywords where lower.contains(kw) {
                    score += 1.6
                }
                return (idx, score, clause)
            }
            let top = scored.sorted { $0.1 > $1.1 }.prefix(2).sorted { $0.0 < $1.0 }.map { $0.2 }
            return top.joined(separator: ". ") + "."
        }

        let headCount = min(14, words.count)
        return words.prefix(headCount).joined(separator: " ") + (words.count > headCount ? "…" : "")
    }

    /// Transcribe mono Int16 PCM samples into editable text for "→A" on locked voice recordings.
    public static func transcribe(
        _ samples: [Int16],
        sampleRate: Double = 48000.0,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        guard !samples.isEmpty else {
            completion(nil)
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                completion(nil)
                return
            }
            let preferred = Locale.preferredLanguages.first ?? "ru-RU"
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: preferred))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                ?? SFSpeechRecognizer()
            guard let recognizer, recognizer.isAvailable else {
                completion(nil)
                return
            }
            // Downsample 48 kHz -> 16 kHz if needed for crisp speech recognition
            let targetRate: Double = sampleRate >= 32000.0 ? 16000.0 : sampleRate
            let step = max(1, Int((sampleRate / targetRate).rounded()))
            let count = samples.count / step
            guard count > 0,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let channel = buffer.floatChannelData?[0] else {
                completion(nil)
                return
            }
            buffer.frameLength = AVAudioFrameCount(count)
            for i in 0 ..< count {
                channel[i] = Float(samples[i * step]) / 32768.0
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.shouldReportPartialResults = false
            if #available(iOS 16.0, *) {
                request.addsPunctuation = true
            }
            request.append(buffer)
            request.endAudio()

            final class OnceGate: @unchecked Sendable {
                private let lock = NSLock()
                private var done = false
                func enter() -> Bool {
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    if self.done { return false }
                    self.done = true
                    return true
                }
            }
            final class TaskBox: @unchecked Sendable {
                let task: SFSpeechRecognitionTask
                init(_ task: SFSpeechRecognitionTask) { self.task = task }
            }

            let gate = OnceGate()
            let finish: @Sendable (String?) -> Void = { text in
                guard gate.enter() else { return }
                let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
                completion((trimmed?.isEmpty == false) ? trimmed : nil)
            }

            let taskBox = TaskBox(recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    finish(result.bestTranscription.formattedString)
                } else if error != nil {
                    finish(nil)
                }
            })
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 10.0) {
                taskBox.task.cancel()
                finish(nil)
            }
        }
    }
}
