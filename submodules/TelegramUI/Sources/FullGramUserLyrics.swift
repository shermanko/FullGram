import Foundation
import UIKit
import CryptoKit
import AccountContext

/// Custom / user-edited lyrics persisted in Application Support per track (title + artist).
/// Supports LRC timestamps `[mm:ss.xx]` for synchronized playback as well as plain text.
enum FullGramUserLyrics {
    private struct Entry: Codable {
        let updated: Date
        let title: String
        let artist: String?
        let source: String
    }

    private static var directory: URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("fullgram-user-lyrics-v1", isDirectory: true)
    }

    private static func fileKey(title: String, artist: String?) -> String {
        let identity = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            + "\u{0}"
            + (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func source(title: String, artist: String?) -> String? {
        guard let dir = self.directory,
              let data = try? Data(contentsOf: dir.appendingPathComponent(self.fileKey(title: title, artist: artist) + ".json")),
              data.count <= 1_048_576,
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return entry.source
    }

    static func hasCustom(title: String, artist: String?) -> Bool {
        guard let dir = self.directory else { return false }
        let path = dir.appendingPathComponent(self.fileKey(title: title, artist: artist) + ".json").path
        return FileManager.default.fileExists(atPath: path)
    }

    static func load(title: String, artist: String?, duration: Double) -> FullGramLyricsResult? {
        guard let raw = self.source(title: title, artist: artist) else { return nil }
        return self.parse(raw, duration: duration)
    }

    static func parse(_ source: String, duration: Double) -> FullGramLyricsResult? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let synced = FullGramLyricsFetcher.parseLRC(trimmed, duration: duration > 0.0 ? duration : 240.0)
        if !synced.isEmpty {
            return .synced(synced)
        }
        return .plain(trimmed)
    }

    static func formatEditableText(from result: FullGramLyricsResult) -> String {
        switch result {
        case let .synced(lines):
            return lines.map { line in
                let totalSec = max(0.0, line.time)
                let mins = Int(totalSec) / 60
                let secs = totalSec - Double(mins * 60)
                return String(format: "[%02d:%05.2f] %@", mins, secs, line.text)
            }.joined(separator: "\n")
        case let .plain(text):
            return text
        case .empty:
            return ""
        }
    }

    @discardableResult
    static func save(_ source: String, title: String, artist: String?) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dir = self.directory else { return false }
        let url = dir.appendingPathComponent(self.fileKey(title: title, artist: artist) + ".json")
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
            FullGramLyricsFetcher.invalidateCache(title: title, artist: artist)
            FullGramMiniLyrics.shared.update(title: title, artist: artist, lines: nil)
            return true
        }
        guard trimmed.utf8.count <= 512 * 1024,
              let data = try? JSONEncoder().encode(Entry(updated: Date(), title: title, artist: artist, source: trimmed)) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            FullGramLyricsFetcher.invalidateCache(title: title, artist: artist)
            if case let .synced(lines) = self.parse(trimmed, duration: 240.0) {
                FullGramMiniLyrics.shared.update(
                    title: title,
                    artist: artist,
                    lines: lines.map { FullGramMiniLyrics.Line(time: $0.time, endTime: $0.endTime, text: $0.text) }
                )
            } else {
                FullGramMiniLyrics.shared.update(title: title, artist: artist, lines: nil)
            }
            return true
        } catch {
            return false
        }
    }

    static func remove(title: String, artist: String?) {
        guard let dir = self.directory else { return }
        let url = dir.appendingPathComponent(self.fileKey(title: title, artist: artist) + ".json")
        try? FileManager.default.removeItem(at: url)
        FullGramLyricsFetcher.invalidateCache(title: title, artist: artist)
        FullGramMiniLyrics.shared.update(title: title, artist: artist, lines: nil)
    }

    @MainActor
    static func presentEditor(
        from hostController: UIViewController,
        title: String,
        artist: String?,
        initialText: String,
        hasCustom: Bool,
        onSaved: @escaping (String?) -> Void
    ) {
        let editor = FullGramLyricsEditorViewController(
            trackTitle: title,
            artist: artist,
            initialText: initialText,
            hasCustom: hasCustom,
            onSaved: onSaved
        )
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .pageSheet
        hostController.present(nav, animated: true)
    }
}

private final class FullGramLyricsEditorViewController: UIViewController {
    private let trackTitle: String
    private let artist: String?
    private let initialText: String
    private let hasCustom: Bool
    private let onSaved: (String?) -> Void

    private let hintLabel = UILabel()
    private let textView = UITextView()

    init(
        trackTitle: String,
        artist: String?,
        initialText: String,
        hasCustom: Bool,
        onSaved: @escaping (String?) -> Void
    ) {
        self.trackTitle = trackTitle
        self.artist = artist
        self.initialText = initialText
        self.hasCustom = hasCustom
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        self.title = self.hasCustom ? "Изменить текст песни" : "Свой текст песни"

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Отмена", style: .plain, target: self, action: #selector(self.cancelTapped))
        var rightItems: [UIBarButtonItem] = [
            UIBarButtonItem(title: "Сохранить", style: .plain, target: self, action: #selector(self.saveTapped))
        ]
        if self.hasCustom {
            rightItems.append(UIBarButtonItem(title: "Сбросить", style: .plain, target: self, action: #selector(self.resetTapped)))
        }
        self.navigationItem.rightBarButtonItems = rightItems

        self.hintLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        self.hintLabel.textColor = .secondaryLabel
        self.hintLabel.numberOfLines = 0
        self.hintLabel.text = "Поддерживаются метки времени [мм:сс.сс] для синхронного текста (караоке и мини-плеер) или обычный текст."
        self.hintLabel.translatesAutoresizingMaskIntoConstraints = false

        self.textView.font = .monospacedSystemFont(ofSize: 14.0, weight: .regular)
        self.textView.backgroundColor = .secondarySystemBackground
        self.textView.layer.cornerRadius = 12.0
        self.textView.textContainerInset = UIEdgeInsets(top: 12.0, left: 10.0, bottom: 12.0, right: 10.0)
        self.textView.text = self.initialText
        self.textView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.hintLabel)
        self.view.addSubview(self.textView)

        let bottomConstraint: NSLayoutConstraint
        if #available(iOS 15.0, *) {
            bottomConstraint = self.textView.bottomAnchor.constraint(equalTo: self.view.keyboardLayoutGuide.topAnchor, constant: -12.0)
        } else {
            bottomConstraint = self.textView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -12.0)
        }

        NSLayoutConstraint.activate([
            self.hintLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 12.0),
            self.hintLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            self.hintLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),

            self.textView.topAnchor.constraint(equalTo: self.hintLabel.bottomAnchor, constant: 10.0),
            self.textView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            self.textView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            bottomConstraint
        ])
    }

    @objc private func cancelTapped() {
        self.dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let raw = self.textView.text ?? ""
        FullGramUserLyrics.save(raw, title: self.trackTitle, artist: self.artist)
        self.dismiss(animated: true) { [onSaved] in
            onSaved(raw)
        }
    }

    @objc private func resetTapped() {
        FullGramUserLyrics.remove(title: self.trackTitle, artist: self.artist)
        self.dismiss(animated: true) { [onSaved] in
            onSaved(nil)
        }
    }
}
