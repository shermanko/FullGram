import Foundation
import UIKit
import SwiftSignalKit
import Display

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

    private static func normalizeMetadata(rawTitle: String, rawArtist: String?) -> (title: String, artist: String?) {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var artist = rawArtist?.trimmingCharacters(in: .whitespacesAndNewlines)

        let extPattern = #"\.(mp3|flac|m4a|wav|ogg|aac|opus)$"#
        if let extRegex = try? NSRegularExpression(pattern: extPattern, options: .caseInsensitive) {
            let ns = title as NSString
            title = extRegex.stringByReplacingMatches(in: title, range: NSRange(location: 0, length: ns.length), withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tagPattern = #"\s*[\(\[](?:official\s*(?:music\s*)?(?:video|audio|lyric\s*video)|lyrics?|hd|hq|4k|320\s*kbps|prod\.[^\)\]]*)[\)\]]"#
        if let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: .caseInsensitive) {
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

    static func fetch(title: String, artist: String?, duration: Double) -> Signal<FullGramLyricsResult, NoError> {
        let normalized = normalizeMetadata(rawTitle: title, rawArtist: artist)
        let cleanTitle = normalized.title
        guard !cleanTitle.isEmpty else {
            return .single(.empty)
        }
        let cleanArtist = normalized.artist

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

            let lock = NSLock()
            let total = signals.count
            var completedCount = 0
            var didFinish = false
            var bestPlain: FullGramLyricsResult?
            let compositeDisposable = MetaDisposable()
            let disposables = DisposableSet()

            for sig in signals {
                let d = sig.startStandalone(next: { item in
                    lock.lock()
                    guard !didFinish else {
                        lock.unlock()
                        return
                    }
                    completedCount += 1
                    if let item {
                        switch item {
                        case .synced:
                            didFinish = true
                            lock.unlock()
                            subscriber.putNext(item)
                            subscriber.putCompletion()
                            disposables.dispose()
                            return
                        case .plain:
                            if bestPlain == nil {
                                bestPlain = item
                            }
                        case .empty:
                            break
                        }
                    }
                    if completedCount >= total {
                        didFinish = true
                        let finalResult = bestPlain ?? .empty
                        lock.unlock()
                        subscriber.putNext(finalResult)
                        subscriber.putCompletion()
                        return
                    }
                    lock.unlock()
                })
                disposables.add(d)
            }
            compositeDisposable.set(disposables)
            return compositeDisposable
        }
    }

    private static func fetchLRCLIB(title: String, artist: String?, duration: Double) -> Signal<FullGramLyricsResult?, NoError> {
        return Signal { subscriber in
            var components = URLComponents(string: "https://lrclib.net/api/get")!
            var query: [URLQueryItem] = [URLQueryItem(name: "track_name", value: title)]
            if let artist, !artist.isEmpty {
                query.append(URLQueryItem(name: "artist_name", value: artist))
            }
            if duration > 1.0 {
                query.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
            }
            components.queryItems = query
            guard let url = components.url else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            var request = URLRequest(url: url)
            request.setValue("FullGram/1.0 (https://fullgram.app)", forHTTPHeaderField: "User-Agent")
            let task = session.dataTask(with: request) { data, response, _ in
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                        let lines = parseLRC(synced, duration: duration)
                        if !lines.isEmpty {
                            subscriber.putNext(.synced(lines))
                            subscriber.putCompletion()
                            return
                        }
                    }
                    if let plain = json["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        subscriber.putNext(.plain(plain))
                        subscriber.putCompletion()
                        return
                    }
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

    private static func searchLRCLIB(title: String, artist: String?, duration: Double, completion: @escaping (FullGramLyricsResult?) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        let q = [artist ?? "", title].filter { !$0.isEmpty }.joined(separator: " ")
        components.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = components.url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("FullGram/1.0 (https://fullgram.app)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, _, _ in
            guard let data, let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = array.first else {
                completion(nil)
                return
            }
            if let synced = first["syncedLyrics"] as? String, !synced.isEmpty {
                let lines = parseLRC(synced, duration: duration)
                if !lines.isEmpty {
                    completion(.synced(lines))
                    return
                }
            }
            if let plain = first["plainLyrics"] as? String, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(.plain(plain))
                return
            }
            completion(nil)
        }.resume()
    }

    /// Completely free REST API without API key or rate-limit registration: https://api.lyrics.ovh/v1/{artist}/{title}
    private static func fetchLyricsOvh(title: String, artist: String?) -> Signal<FullGramLyricsResult?, NoError> {
        let artistPart = (artist?.isEmpty == false ? artist! : "Unknown")
        guard let encodedArtist = artistPart.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
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
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://music.163.com/api/cloudsearch/pc?s=\(encoded)&type=1&limit=3") else {
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
        for idx in entries.indices {
            let start = entries[idx].0
            let end = idx + 1 < entries.count ? max(start + 0.3, entries[idx + 1].0) : max(start + 3.0, duration)
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
            self.setNeedsLayout()
        }
    }

    var isCurrent: Bool = false {
        didSet {
            self.dimLabel.alpha = self.isCurrent ? 0.35 : 0.28
            self.brightLabel.isHidden = !self.isCurrent
            self.transform = self.isCurrent ? CGAffineTransform(scaleX: 1.03, y: 1.03) : .identity
        }
    }

    /// 0.0 ... 1.0 karaoke sweep progress across the line.
    var progress: CGFloat = 0.0 {
        didSet {
            let p = max(0.0, min(1.0, self.progress))
            let feather: CGFloat = 0.08
            self.maskLayer.locations = [
                0.0 as NSNumber,
                NSNumber(value: Double(max(0.0, p - feather))),
                NSNumber(value: Double(min(1.0, p + feather))),
                1.0 as NSNumber
            ]
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.dimLabel.font = .systemFont(ofSize: 24.0, weight: .bold)
        self.dimLabel.textColor = .white
        self.dimLabel.alpha = 0.28
        self.dimLabel.numberOfLines = 0

        self.brightLabel.font = .systemFont(ofSize: 24.0, weight: .bold)
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
    }

    required init?(coder: NSCoder) { return nil }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fit = self.dimLabel.sizeThatFits(CGSize(width: size.width, height: .greatestFiniteMagnitude))
        return CGSize(width: size.width, height: ceil(fit.height))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.dimLabel.frame = self.bounds
        self.brightLabel.frame = self.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.maskLayer.frame = self.bounds
        CATransaction.commit()
    }
}

final class FullGramLyricsOverlayView: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let headerLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let statusLabel = UILabel()

    private var lines: [FullGramLyricsLine] = []
    private var lineViews: [FullGramKaraokeLineView] = []
    private var currentLineIndex: Int = -1
    private var fetchDisposable = MetaDisposable()

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

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.scrollView)

        self.stackView.axis = .vertical
        self.stackView.spacing = 18.0
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        self.statusLabel.font = .systemFont(ofSize: 15.0, weight: .medium)
        self.statusLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        self.statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.statusLabel)

        NSLayoutConstraint.activate([
            self.blurView.topAnchor.constraint(equalTo: self.topAnchor),
            self.blurView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.blurView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.blurView.trailingAnchor.constraint(equalTo: self.trailingAnchor),

            self.headerLabel.topAnchor.constraint(equalTo: self.safeAreaLayoutGuide.topAnchor, constant: 16.0),
            self.headerLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 20.0),
            self.headerLabel.trailingAnchor.constraint(equalTo: self.closeButton.leadingAnchor, constant: -12.0),

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

    func load(title: String, artist: String?, duration: Double) {
        self.headerLabel.text = [artist, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
        self.statusLabel.text = "Поиск текста..."
        self.statusLabel.isHidden = false
        self.clearLines()

        self.fetchDisposable.set((FullGramLyricsFetcher.fetch(title: title, artist: artist, duration: duration)
        |> deliverOnMainQueue).startStrict(next: { [weak self] result in
            self?.apply(result: result)
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
                view.isCurrent = false
                self.stackView.addArrangedSubview(view)
                self.lineViews.append(view)
            }
        case .empty:
            self.statusLabel.text = "Текст песни не найден"
            self.statusLabel.isHidden = false
        }
    }
}
