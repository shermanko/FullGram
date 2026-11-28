import Foundation
import UIKit
@preconcurrency import SwiftSignalKit
import Display
import AccountContext

struct FullGramLyricsWord: Equatable {
    let time: Double
    let endTime: Double
    let text: String
}

struct FullGramLyricsLine: Equatable {
    let time: Double
    let endTime: Double
    let text: String
    let words: [FullGramLyricsWord]
}

enum FullGramLyricsResult: Equatable {
    case synced([FullGramLyricsLine])
    case plain(String)
    case empty
}

enum FullGramLyricsFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.5
        config.timeoutIntervalForResource = 7.0
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    private static let featRegex = try? NSRegularExpression(pattern: "\\s*[\\(\\[]?(?:feat\\.?|ft\\.?)\\s+[^\\)\\]]+[\\)\\]]?", options: .caseInsensitive)
    private static let extRegex = try? NSRegularExpression(pattern: #"\.(mp3|flac|m4a|wav|ogg|aac|opus)$"#, options: .caseInsensitive)
    private static let tagRegex = try? NSRegularExpression(pattern: #"\s*[\(\[](?:official\s*(?:music\s*)?(?:video|audio|lyric\s*video)|lyrics?|hd|hq|4k|320\s*kbps|prod\.[^\)\]]*)[\)\]]"#, options: .caseInsensitive)

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var lyricsCache: [String: FullGramLyricsResult] = [:]
    private nonisolated(unsafe) static var lyricsCacheOrder: [String] = []

    private static func normalizeMetadata(rawTitle: String, rawArtist: String?) -> (title: String, artist: String?) {
        var title = rawTitle.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        var artist = rawArtist?.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if let featRegex = self.featRegex {
            let tns = title as NSString
            title = featRegex.stringByReplacingMatches(in: title, range: NSRange(location: 0, length: tns.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let a = artist {
                let ans = a as NSString
                artist = featRegex.stringByReplacingMatches(in: a, range: NSRange(location: 0, length: ans.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let extRegex = self.extRegex {
            let ns = title as NSString
            title = extRegex.stringByReplacingMatches(in: title, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let tagRegex = self.tagRegex {
            let ns = title as NSString
            title = tagRegex.stringByReplacingMatches(in: title, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let a = artist, a.lowercased() == "unknown" || a.lowercased() == "unknown artist" || a == "<unknown>" {
            artist = nil
        }

        if artist == nil || artist?.isEmpty == true {
            for sep in [" — ", " – ", " - "] {
                if let range = title.range(of: sep) {
                    let left = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let right = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !left.isEmpty && !right.isEmpty {
                        artist = left
                        title = right
                        break
                    }
                }
            }
        }

        return (title, artist)
    }

    static func invalidateCache(title: String, artist: String?) {
        let normalized = normalizeMetadata(rawTitle: title, rawArtist: artist)
        let cacheKey = "\(normalized.artist?.lowercased() ?? "")|\(normalized.title.lowercased())"
        let rawKey = "\(artist?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "")|\(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        self.cacheLock.lock()
        self.lyricsCache.removeValue(forKey: cacheKey)
        self.lyricsCache.removeValue(forKey: rawKey)
        self.lyricsCacheOrder.removeAll { $0 == cacheKey || $0 == rawKey }
        self.cacheLock.unlock()
    }

    static func fetch(title: String, artist: String?, duration: Double) -> Signal<FullGramLyricsResult, NoError> {
        if let custom = FullGramUserLyrics.load(title: title, artist: artist, duration: duration) {
            return .single(custom)
        }
        let normalized = normalizeMetadata(rawTitle: title, rawArtist: artist)
        let cleanTitle = normalized.title
        guard !cleanTitle.isEmpty else {
            return .single(.empty)
        }
        let cleanArtist = normalized.artist
        if let customNormalized = FullGramUserLyrics.load(title: cleanTitle, artist: cleanArtist, duration: duration) {
            return .single(customNormalized)
        }
        let cacheKey = "\(cleanArtist?.lowercased() ?? "")|\(cleanTitle.lowercased())"

        self.cacheLock.lock()
        if let cached = self.lyricsCache[cacheKey] {
            self.cacheLock.unlock()
            return .single(cached)
        }
        self.cacheLock.unlock()

        return Signal { subscriber in
            var signals: [Signal<FullGramLyricsResult?, NoError>] = []
            if FullGramLyricsProviderSettings.useLrclib {
                signals.append(fetchLRCLIB(title: cleanTitle, artist: cleanArtist, duration: duration))
            }
            if FullGramLyricsProviderSettings.useLyricsOvh {
                signals.append(fetchLyricsOvh(title: cleanTitle, artist: cleanArtist))
            }
            if FullGramLyricsProviderSettings.useNetEase {
                signals.append(fetchNetEase(title: cleanTitle, artist: cleanArtist, duration: duration))
            }
            if signals.isEmpty {
                subscriber.putNext(.empty)
                subscriber.putCompletion()
                return EmptyDisposable
            }

            let state = LyricsFetchState(total: signals.count)
            let disposables = DisposableSet()

            for sig in signals {
                let d = sig.startStandalone(next: { item in
                    let decision = state.record(item: item)
                    if let finalResult = decision.finalResult {
                        if finalResult != .empty {
                            self.cacheLock.lock()
                            if self.lyricsCache[cacheKey] == nil {
                                self.lyricsCacheOrder.append(cacheKey)
                                if self.lyricsCacheOrder.count > 32 {
                                    let evict = self.lyricsCacheOrder.removeFirst()
                                    self.lyricsCache.removeValue(forKey: evict)
                                }
                            }
                            self.lyricsCache[cacheKey] = finalResult
                            self.cacheLock.unlock()
                        }
                        subscriber.putNext(finalResult)
                        subscriber.putCompletion()
                        if decision.shouldDisposeOthers {
                            disposables.dispose()
                        }
                    }
                })
                disposables.add(d)
            }
            return disposables
        }
    }

    private final class LyricsFetchState: @unchecked Sendable {
        private let lock = NSLock()
        private let total: Int
        private var completedCount: Int = 0
        private var didFinish: Bool = false
        private var bestPlain: FullGramLyricsResult?

        init(total: Int) {
            self.total = total
        }

        func record(item: FullGramLyricsResult?) -> (finalResult: FullGramLyricsResult?, shouldDisposeOthers: Bool) {
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.didFinish else {
                return (nil, false)
            }
            self.completedCount += 1
            if let item {
                switch item {
                case .synced:
                    self.didFinish = true
                    return (item, true)
                case .plain:
                    if self.bestPlain == nil {
                        self.bestPlain = item
                    }
                case .empty:
                    break
                }
            }
            if self.completedCount >= self.total {
                self.didFinish = true
                return (self.bestPlain ?? .empty, false)
            }
            return (nil, false)
        }
    }

    private static func makeLRCLIBRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("FullGram/1.0 (https://fullgram.app)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func parseLRCLIBEntry(_ json: [String: Any], duration: Double) -> FullGramLyricsResult? {
        if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
            let lines = parseLRC(synced, duration: duration)
            if !lines.isEmpty {
                return .synced(lines)
            }
        }
        if let plain = json["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .plain(plain)
        }
        return nil
    }

    private static func fetchLRCLIB(title: String, artist: String?, duration: Double) -> Signal<FullGramLyricsResult?, NoError> {
        return Signal { subscriber in
            guard var components = URLComponents(string: "https://lrclib.net/api/get") else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            var query: [URLQueryItem] = [URLQueryItem(name: "track_name", value: title)]
            if let artist, !artist.isEmpty {
                query.append(URLQueryItem(name: "artist_name", value: artist))
            }
            if duration.isFinite && duration > 1.0 && duration < Double(Int.max / 2) {
                query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
            }
            components.queryItems = query
            guard let url = components.url else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let task = session.dataTask(with: makeLRCLIBRequest(url: url)) { data, response, error in
                if (error as? URLError)?.code == .cancelled {
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = parseLRCLIBEntry(json, duration: duration) {
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                    return
                }
                // Fallback to LRCLIB search endpoint
                searchLRCLIB(title: title, artist: artist, duration: duration) { result in
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                }
            }
            task.resume()
            return ActionDisposable { task.cancel() }
        }
    }

    private static func searchLRCLIB(title: String, artist: String?, duration: Double, completion: @escaping @Sendable (FullGramLyricsResult?) -> Void) {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else {
            completion(nil)
            return
        }
        let q = [artist ?? "", title].filter { !$0.isEmpty }.joined(separator: " ")
        components.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = components.url else {
            completion(nil)
            return
        }
        session.dataTask(with: makeLRCLIBRequest(url: url)) { data, _, _ in
            if let data,
               let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let best = array.first(where: { ($0["syncedLyrics"] as? String)?.isEmpty == false }) ?? array.first,
               let parsed = parseLRCLIBEntry(best, duration: duration) {
                completion(parsed)
                return
            }
            if artist?.isEmpty == false && !title.isEmpty,
               var fallbackComp = URLComponents(string: "https://lrclib.net/api/search") {
                fallbackComp.queryItems = [URLQueryItem(name: "q", value: title)]
                if let fallbackUrl = fallbackComp.url {
                    session.dataTask(with: makeLRCLIBRequest(url: fallbackUrl)) { fData, _, _ in
                        guard let fData,
                              let arr = try? JSONSerialization.jsonObject(with: fData) as? [[String: Any]],
                              let best = arr.first(where: { ($0["syncedLyrics"] as? String)?.isEmpty == false }) ?? arr.first else {
                            completion(nil)
                            return
                        }
                        completion(parseLRCLIBEntry(best, duration: duration))
                    }.resume()
                    return
                }
            }
            completion(nil)
        }.resume()
    }

    /// Completely free REST API without API key or rate-limit registration: https://api.lyrics.ovh/v1/{artist}/{title}
    private static func fetchLyricsOvh(title: String, artist: String?) -> Signal<FullGramLyricsResult?, NoError> {
        let artistPart = (artist?.isEmpty == false ? artist! : "Unknown")
        var segmentAllowed = CharacterSet.urlPathAllowed
        segmentAllowed.remove(charactersIn: "/?#")
        guard let encodedArtist = artistPart.addingPercentEncoding(withAllowedCharacters: segmentAllowed),
              let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: segmentAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encodedArtist)/\(encodedTitle)") else {
            return .single(nil)
        }
        return Signal { subscriber in
            let task = session.dataTask(with: url) { data, response, _ in
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let lyrics = json["lyrics"] as? String,
                      !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                subscriber.putNext(.plain(lyrics.trimmingCharacters(in: .whitespacesAndNewlines)))
                subscriber.putCompletion()
            }
            task.resume()
            return ActionDisposable { task.cancel() }
        }
    }

    private static func fetchNetEase(title: String, artist: String?, duration: Double) -> Signal<FullGramLyricsResult?, NoError> {
        let query = [artist ?? "", title].filter { !$0.isEmpty }.joined(separator: " ")
        var components = URLComponents(string: "https://music.163.com/api/cloudsearch/pc")
        components?.queryItems = [
            URLQueryItem(name: "s", value: query),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let searchURL = components?.url else {
            return .single(nil)
        }
        return Signal { subscriber in
            var request = URLRequest(url: searchURL)
            request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
            let task = session.dataTask(with: request) { data, _, _ in
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? [String: Any],
                      let songs = result["songs"] as? [[String: Any]],
                      let firstId = (songs.first?["id"] as? NSNumber)?.int64Value,
                      let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(firstId)&lv=1&tv=1") else {
                    subscriber.putNext(nil)
                    subscriber.putCompletion()
                    return
                }
                var lyricReq = URLRequest(url: lyricURL)
                lyricReq.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
                session.dataTask(with: lyricReq) { lyricData, _, _ in
                    guard let lyricData,
                          let lyricJson = try? JSONSerialization.jsonObject(with: lyricData) as? [String: Any],
                          let lrc = lyricJson["lrc"] as? [String: Any],
                          let text = lrc["lyric"] as? String, !text.isEmpty else {
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }
                    let lines = parseLRC(text, duration: duration)
                    subscriber.putNext(lines.isEmpty ? .plain(text) : .synced(lines))
                    subscriber.putCompletion()
                }.resume()
            }
            task.resume()
            return ActionDisposable { task.cancel() }
        }
    }

    static func parseLRC(_ raw: String, duration: Double) -> [FullGramLyricsLine] {
        var entries: [(Double, String)] = []
        let pattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in raw.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }
            let lastEnd = matches.last!.range.location + matches.last!.range.length
            let text = nsLine.substring(from: lastEnd).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                let msRange = match.range(at: 3)
                let frac: Double
                if msRange.location != NSNotFound {
                    let s = nsLine.substring(with: msRange)
                    let val = Double(s) ?? 0.0
                    frac = s.count == 3 ? val / 1000.0 : (s.count == 2 ? val / 100.0 : val / 10.0)
                } else {
                    frac = 0.0
                }
                let timestamp = (Double(minStr) ?? 0.0) * 60.0 + (Double(secStr) ?? 0.0) + frac
                entries.append((timestamp, text))
            }
        }

        entries.sort { $0.0 < $1.0 }
        var lines: [FullGramLyricsLine] = []
        let safeDuration = duration.isFinite ? duration : 0.0
        for idx in entries.indices {
            let start = entries[idx].0
            let end = idx + 1 < entries.count ? max(start + 0.3, entries[idx + 1].0) : max(start + 3.0, safeDuration)
            let wordsText = entries[idx].1.split(separator: " ").map(String.init)
            let span = max(0.3, end - start)
            let wordDur = span / Double(max(1, wordsText.count))
            let words = wordsText.enumerated().map { i, w in
                FullGramLyricsWord(
                    time: start + Double(i) * wordDur,
                    endTime: start + Double(i + 1) * wordDur,
                    text: w
                )
            }
            lines.append(FullGramLyricsLine(time: start, endTime: end, text: entries[idx].1, words: words))
        }
        return lines
    }
}

/// Default Karaoke lyrics line label: smooth left-to-right gradient fill per word, no visible style setting.
final class FullGramKaraokeLineView: UIView {
    private let dimLabel = UILabel()
    private let brightLabel = UILabel()
    private let maskLayer = CAGradientLayer()

    var text: String = "" {
        didSet {
            self.dimLabel.text = self.text
            self.brightLabel.text = self.text
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
    }

    var isPlain: Bool = false {
        didSet {
            self.dimLabel.alpha = self.isPlain ? 0.92 : (self.isCurrent ? 0.42 : 0.34)
        }
    }

    var isCurrent: Bool = false {
        didSet {
            self.dimLabel.alpha = self.isPlain ? 0.92 : (self.isCurrent ? 0.42 : 0.34)
            self.brightLabel.isHidden = !self.isCurrent
            self.transform = self.isCurrent ? CGAffineTransform(scaleX: 1.03, y: 1.03) : .identity
        }
    }

    /// 0.0 ... 1.0 karaoke sweep progress across the line.
    var progress: CGFloat = 0.0 {
        didSet {
            let p = max(0.0, min(1.0, self.progress))
            let feather: CGFloat = 0.08
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.maskLayer.locations = [
                0.0 as NSNumber,
                NSNumber(value: Double(max(0.0, p - feather))),
                NSNumber(value: Double(min(1.0, p + feather))),
                1.0 as NSNumber
            ]
            CATransaction.commit()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.dimLabel.translatesAutoresizingMaskIntoConstraints = false
        self.dimLabel.font = .systemFont(ofSize: 23.0, weight: .bold)
        self.dimLabel.textColor = .white
        self.dimLabel.alpha = 0.34
        self.dimLabel.numberOfLines = 0
        self.dimLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        self.dimLabel.setContentHuggingPriority(.required, for: .vertical)

        self.brightLabel.translatesAutoresizingMaskIntoConstraints = false
        self.brightLabel.font = .systemFont(ofSize: 23.0, weight: .bold)
        self.brightLabel.textColor = .white
        self.brightLabel.numberOfLines = 0
        self.brightLabel.isHidden = true

        self.maskLayer.colors = [
            UIColor.white.cgColor,
            UIColor.white.cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor
        ]
        self.maskLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.maskLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.maskLayer.locations = [0.0, 0.0, 0.08, 1.0]
        self.brightLabel.layer.mask = self.maskLayer

        self.addSubview(self.dimLabel)
        self.addSubview(self.brightLabel)

        NSLayoutConstraint.activate([
            self.dimLabel.topAnchor.constraint(equalTo: self.topAnchor),
            self.dimLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.dimLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.dimLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.brightLabel.topAnchor.constraint(equalTo: self.topAnchor),
            self.brightLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.brightLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.brightLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fit = self.dimLabel.sizeThatFits(CGSize(width: size.width, height: .greatestFiniteMagnitude))
        return CGSize(width: size.width, height: ceil(fit.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.maskLayer.frame = self.brightLabel.bounds
        CATransaction.commit()
    }
}

final class FullGramLyricsOverlayView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let headerLabel = UILabel()
    private let editButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let statusLabel = UILabel()
    private var currentTitle: String = ""
    private var currentArtist: String?
    private var currentDuration: Double = 0.0
    private var currentResult: FullGramLyricsResult = .empty
    var onEditRequested: ((String, String?, String, Bool) -> Void)?

    private var lines: [FullGramLyricsLine] = []
    private var lineViews: [FullGramKaraokeLineView] = []
    private var currentLineIndex: Int = -1
    private nonisolated(unsafe) let fetchDisposable = MetaDisposable()

    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.clipsToBounds = true

        self.blurView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.blurView)

        self.headerLabel.font = .systemFont(ofSize: 16.0, weight: .semibold)
        self.headerLabel.textColor = .white
        self.headerLabel.numberOfLines = 1
        self.headerLabel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.headerLabel)

        self.closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.75)
        self.closeButton.addTarget(self, action: #selector(self.closeTapped), for: .touchUpInside)
        self.closeButton.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.closeButton)

        self.editButton.setImage(UIImage(systemName: "square.and.pencil"), for: .normal)
        self.editButton.tintColor = UIColor(white: 1.0, alpha: 0.82)
        self.editButton.addTarget(self, action: #selector(self.editTapped), for: .touchUpInside)
        self.editButton.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.editButton)

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.scrollView)

        self.stackView.axis = .vertical
        self.stackView.spacing = 18.0
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        self.statusLabel.font = .systemFont(ofSize: 15.0, weight: .medium)
        self.statusLabel.textColor = UIColor(white: 1.0, alpha: 0.78)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.statusLabel.isUserInteractionEnabled = true
        self.statusLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.editTapped)))
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.statusLabel)

        NSLayoutConstraint.activate([
            self.blurView.topAnchor.constraint(equalTo: self.topAnchor),
            self.blurView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.blurView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.blurView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.headerLabel.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor, constant: 16.0),
            self.headerLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 20.0),
            self.headerLabel.trailingAnchor.constraint(equalTo: self.editButton.leadingAnchor, constant: -10.0),

            self.editButton.centerYAnchor.constraint(equalTo: self.headerLabel.centerYAnchor),
            self.editButton.trailingAnchor.constraint(equalTo: self.closeButton.leadingAnchor, constant: -8.0),
            self.editButton.widthAnchor.constraint(equalToConstant: 32.0),
            self.editButton.heightAnchor.constraint(equalToConstant: 32.0),

            self.closeButton.centerYAnchor.constraint(equalTo: self.headerLabel.centerYAnchor),
            self.closeButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16.0),
            self.closeButton.widthAnchor.constraint(equalToConstant: 32.0),
            self.closeButton.heightAnchor.constraint(equalToConstant: 32.0),

            self.scrollView.topAnchor.constraint(equalTo: self.headerLabel.bottomAnchor, constant: 16.0),
            self.scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.stackView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 24.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -80.0),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.leadingAnchor, constant: 24.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.trailingAnchor, constant: -24.0),

            self.statusLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.statusLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.statusLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 32.0),
            self.statusLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -32.0)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    deinit {
        self.fetchDisposable.dispose()
    }

    @objc private func closeTapped() {
        self.onClose?()
    }

    @objc private func editTapped() {
        guard !self.currentTitle.isEmpty else { return }
        let initial = FullGramUserLyrics.source(title: self.currentTitle, artist: self.currentArtist)
            ?? FullGramUserLyrics.formatEditableText(from: self.currentResult)
        let hasCustom = FullGramUserLyrics.hasCustom(title: self.currentTitle, artist: self.currentArtist)
        self.onEditRequested?(self.currentTitle, self.currentArtist, initial, hasCustom)
    }

    func load(title: String, artist: String?, duration: Double) {
        self.currentTitle = title
        self.currentArtist = artist
        self.currentDuration = duration.isFinite ? duration : 0.0
        self.currentResult = .empty
        self.headerLabel.text = [artist, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        self.statusLabel.text = "Поиск текста..."
        self.statusLabel.isHidden = false
        self.clearLines()

        self.fetchDisposable.set((FullGramLyricsFetcher.fetch(title: title, artist: artist, duration: duration)
        |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            guard let self else { return }
            self.currentResult = result
            if case let .synced(lines) = result {
                FullGramMiniLyrics.shared.update(
                    title: title,
                    artist: artist,
                    lines: lines.map { FullGramMiniLyrics.Line(time: $0.time, endTime: $0.endTime, text: $0.text) }
                )
            }
            self.apply(result: result)
        }))
    }

    func updatePlayback(time: Double) {
        guard !self.lines.isEmpty else { return }
        var active = -1
        for (idx, line) in self.lines.enumerated() {
            if time >= line.time && time < line.endTime {
                active = idx
                break
            } else if time >= line.time {
                active = idx
            }
        }
        if active != self.currentLineIndex {
            if self.currentLineIndex >= 0 && self.currentLineIndex < self.lineViews.count {
                self.lineViews[self.currentLineIndex].isCurrent = false
            }
            self.currentLineIndex = active
            if active >= 0 && active < self.lineViews.count {
                let target = self.lineViews[active]
                target.isCurrent = true
                let rect = target.convert(target.bounds, to: self.scrollView)
                let centerY = max(0.0, rect.midY - self.scrollView.bounds.height * 0.4)
                self.scrollView.setContentOffset(CGPoint(x: 0.0, y: centerY), animated: true)
            }
        }
        if active >= 0 && active < self.lines.count && active < self.lineViews.count {
            let line = self.lines[active]
            let span = max(0.1, line.endTime - line.time)
            self.lineViews[active].progress = CGFloat((time - line.time) / span)
        }
    }

    private func clearLines() {
        for v in self.lineViews { v.removeFromSuperview() }
        self.lineViews = []
        self.lines = []
        self.currentLineIndex = -1
    }

    private func apply(result: FullGramLyricsResult) {
        self.clearLines()
        switch result {
        case let .synced(lines):
            self.statusLabel.isHidden = true
            self.lines = lines
            for line in lines {
                let view = FullGramKaraokeLineView()
                view.text = line.text
                view.isCurrent = false
                self.stackView.addArrangedSubview(view)
                self.lineViews.append(view)
            }
        case let .plain(text):
            self.statusLabel.isHidden = true
            for paragraph in text.components(separatedBy: .newlines) {
                let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let view = FullGramKaraokeLineView()
                view.text = trimmed
                view.isPlain = true
                view.isCurrent = false
                self.stackView.addArrangedSubview(view)
                self.lineViews.append(view)
            }
        case .empty:
            self.statusLabel.text = "Текст песни не найден\nНажмите, чтобы написать свой"
            self.statusLabel.isHidden = false
        }
    }
}
