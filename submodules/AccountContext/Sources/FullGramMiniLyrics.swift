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

    public var fetch: ((String, String?, Double) -> Signal<[Line]?, NoError>)?

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
        guard Self.isEnabled, self.key != key, let fetch = self.fetch, duration > 0.0 else {
            return
        }
        self.key = key
        self.lines = []
        self.disposable.set((fetch(title, artist, duration)
        |> deliverOnMainQueue).startStrict(next: { [weak self] lines in
            guard let self, self.key == key else { return }
            self.lines = lines ?? []
            NotificationCenter.default.post(name: FullGramMiniLyrics.didUpdateNotification, object: nil)
        }))
    }

    public func update(title: String, artist: String?, lines: [Line]?) {
        let key = Self.makeKey(title: title, artist: artist)
        self.disposable.set(nil)
        self.key = key
        self.lines = lines ?? []
        NotificationCenter.default.post(name: FullGramMiniLyrics.didUpdateNotification, object: nil)
    }

    public func line(title: String, artist: String?, at timestamp: Double) -> String? {
        guard Self.isEnabled,
              self.key == Self.makeKey(title: title, artist: artist),
              !self.lines.isEmpty else {
            return nil
        }
        var matched: Line?
        for item in self.lines {
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
