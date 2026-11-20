import Foundation
import SwiftSignalKit

/// Current synchronized lyrics line for the minimized music player header bar.
public final class FullGramMiniLyrics: @unchecked Sendable {
    public static let shared = FullGramMiniLyrics()

    public struct Line: Equatable, Sendable {
        public let time: Double
        public let endTime: Double
        public let text: String

        public init(time: Double, endTime: Double, text: String) {
            self.time = time
            self.endTime = endTime
            self.text = text
        }
    }

    private static let enabledKey = "fullgram.player.miniLyrics"
    public static let didUpdateNotification = Notification.Name("FullGram.MiniLyricsUpdated")

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: didUpdateNotification, object: nil)
        }
    }

    private let lock = NSLock()
    private var _fetch: ((String, String?, Double) -> Signal<[Line]?, NoError>)?
    public var fetch: ((String, String?, Double) -> Signal<[Line]?, NoError>)? {
        get {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self._fetch
        }
        set {
            self.lock.lock()
            self._fetch = newValue
            self.lock.unlock()
        }
    }

    private var key: String?
    private var lines: [Line] = []
    private let disposable = MetaDisposable()

    private init() {}

    private static func makeKey(title: String, artist: String?) -> String {
        return title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            + "\u{0}"
            + (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func request(title: String, artist: String?, duration: Double) {
        let key = Self.makeKey(title: title, artist: artist)
        guard Self.isEnabled, duration > 0.0 else {
            return
        }
        self.lock.lock()
        guard self.key != key, let fetch = self._fetch else {
            self.lock.unlock()
            return
        }
        self.key = key
        self.lines = []
        self.lock.unlock()

        self.disposable.set((fetch(title, artist, duration)
        |> deliverOnMainQueue).startStrict(next: { [weak self] lines in
            guard let self else { return }
            self.lock.lock()
            let matches = (self.key == key)
            if matches {
                self.lines = lines ?? []
            }
            self.lock.unlock()
            if matches {
                NotificationCenter.default.post(name: FullGramMiniLyrics.didUpdateNotification, object: nil)
            }
        }))
    }

    public func update(title: String, artist: String?, lines: [Line]?) {
        let key = Self.makeKey(title: title, artist: artist)
        self.disposable.set(nil)
        self.lock.lock()
        self.key = key
        self.lines = lines ?? []
        self.lock.unlock()
        NotificationCenter.default.post(name: FullGramMiniLyrics.didUpdateNotification, object: nil)
    }

    public func line(title: String, artist: String?, at timestamp: Double) -> String? {
        guard Self.isEnabled else {
            return nil
        }
        let targetKey = Self.makeKey(title: title, artist: artist)
        self.lock.lock()
        guard self.key == targetKey, !self.lines.isEmpty else {
            self.lock.unlock()
            return nil
        }
        let snapshot = self.lines
        self.lock.unlock()

        var matched: Line?
        for item in snapshot {
            if item.time <= timestamp + 0.12 {
                matched = item
            } else {
                break
            }
        }
        guard let current = matched else { return nil }
        if current.endTime > current.time && timestamp > current.endTime + 1.2 {
            return nil
        }
        let text = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
