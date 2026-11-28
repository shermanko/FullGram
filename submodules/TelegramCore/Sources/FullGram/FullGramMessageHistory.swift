import Foundation
import Postbox
import SwiftSignalKit

public final class FullGramDeletedMessageAttribute: MessageAttribute {
    public let timestamp: Int64

    public init(timestamp: Int64) {
        self.timestamp = timestamp
    }

    public init(decoder: PostboxDecoder) {
        self.timestamp = decoder.decodeInt64ForKey("t", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.timestamp, forKey: "t")
    }
}

public extension EngineMessage {
    var fullGramIsDeleted: Bool {
        return self.attributes.contains(where: { $0 is FullGramDeletedMessageAttribute })
    }
}

public struct FullGramArchivedAttachment: Codable, Equatable {
    public let id: String
    public let storedName: String
    public let displayName: String
    public let byteCount: Int64

    public init(id: String, storedName: String, displayName: String, byteCount: Int64) {
        self.id = id
        self.storedName = storedName
        self.displayName = displayName
        self.byteCount = byteCount
    }
}

public struct FullGramMessageHistoryRecord: Codable, Equatable {
    public enum Kind: String, Codable {
        case edited
        case deleted
    }

    public let id: Int32
    public let peerId: Int64
    public let messageId: Int32
    public let messageTimestamp: Int32
    public let capturedAt: Int64
    public let kind: Kind
    public let text: String
    public let attachments: [FullGramArchivedAttachment]?

    private enum CodingKeys: String, CodingKey {
        case id
        case peerId
        case messageId
        case messageTimestamp
        case capturedAt
        case kind
        case text
        case attachments
    }

    public init(
        id: Int32,
        peerId: Int64,
        messageId: Int32,
        messageTimestamp: Int32,
        capturedAt: Int64,
        kind: Kind,
        text: String,
        attachments: [FullGramArchivedAttachment]? = nil
    ) {
        self.id = id
        self.peerId = peerId
        self.messageId = messageId
        self.messageTimestamp = messageTimestamp
        self.capturedAt = capturedAt
        self.kind = kind
        self.text = text
        self.attachments = attachments
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try values.decode(Int32.self, forKey: .id)
        self.peerId = try values.decode(Int64.self, forKey: .peerId)
        self.messageId = try values.decode(Int32.self, forKey: .messageId)
        self.messageTimestamp = try values.decode(Int32.self, forKey: .messageTimestamp)
        self.capturedAt = try values.decode(Int64.self, forKey: .capturedAt)
        let rawKind = try values.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown FullGram history event")
        }
        self.kind = kind
        self.text = try values.decode(String.self, forKey: .text)
        self.attachments = try values.decodeIfPresent([FullGramArchivedAttachment].self, forKey: .attachments)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(self.id, forKey: .id)
        try values.encode(self.peerId, forKey: .peerId)
        try values.encode(self.messageId, forKey: .messageId)
        try values.encode(self.messageTimestamp, forKey: .messageTimestamp)
        try values.encode(self.capturedAt, forKey: .capturedAt)
        try values.encode(self.kind.rawValue, forKey: .kind)
        try values.encode(self.text, forKey: .text)
        try values.encodeIfPresent(self.attachments, forKey: .attachments)
    }
}

public struct FullGramMessageHistoryState: Codable, Equatable {
    public var saveEdits: Bool = true
    public var saveDeleted: Bool = true
    public var saveForBots: Bool = true
    public var saveMedia: Bool = true
    public var mediaPrivateChats: Bool = true
    public var mediaPublicChannels: Bool = true
    public var mediaPrivateChannels: Bool = true
    public var mediaPublicGroups: Bool = true
    public var mediaPrivateGroups: Bool = true
    public var mediaFileLimitMB: Int32 = 15
    public var mediaQuotaMB: Int32 = 250
    public private(set) var records: [FullGramMessageHistoryRecord] = []
    private var nextId: Int32 = 1

    public static let maximumRecords = 200
    public static let retentionSeconds: Int64 = 7 * 24 * 60 * 60
    public static let maximumTextLength = 8192

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case saveEdits
        case saveDeleted
        case saveForBots
        case saveMedia
        case mediaPrivateChats
        case mediaPublicChannels
        case mediaPrivateChannels
        case mediaPublicGroups
        case mediaPrivateGroups
        case mediaFileLimitMB
        case mediaQuotaMB
        case records
        case nextId
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.saveEdits = try values.decodeIfPresent(Bool.self, forKey: .saveEdits) ?? true
        self.saveDeleted = try values.decodeIfPresent(Bool.self, forKey: .saveDeleted) ?? true
        self.saveForBots = try values.decodeIfPresent(Bool.self, forKey: .saveForBots) ?? true
        self.saveMedia = try values.decodeIfPresent(Bool.self, forKey: .saveMedia) ?? true
        self.mediaPrivateChats = try values.decodeIfPresent(Bool.self, forKey: .mediaPrivateChats) ?? true
        self.mediaPublicChannels = try values.decodeIfPresent(Bool.self, forKey: .mediaPublicChannels) ?? true
        self.mediaPrivateChannels = try values.decodeIfPresent(Bool.self, forKey: .mediaPrivateChannels) ?? true
        self.mediaPublicGroups = try values.decodeIfPresent(Bool.self, forKey: .mediaPublicGroups) ?? true
        self.mediaPrivateGroups = try values.decodeIfPresent(Bool.self, forKey: .mediaPrivateGroups) ?? true
        self.mediaFileLimitMB = max(1, min(100, try values.decodeIfPresent(Int32.self, forKey: .mediaFileLimitMB) ?? 15))
        self.mediaQuotaMB = max(50, min(2000, try values.decodeIfPresent(Int32.self, forKey: .mediaQuotaMB) ?? 250))
        self.records = try values.decodeIfPresent([FullGramMessageHistoryRecord].self, forKey: .records) ?? []
        self.nextId = try values.decodeIfPresent(Int32.self, forKey: .nextId) ?? 1
        if self.nextId <= 0 || self.records.contains(where: { $0.id >= self.nextId }) {
            let maximum = self.records.map { $0.id }.max() ?? 0
            if maximum == Int32.max {
                self.records.removeAll()
                self.nextId = 1
            } else {
                self.nextId = max(0, maximum) + 1
            }
        }
    }

    public mutating func setMediaLimits(fileLimitMB: Int32? = nil, quotaMB: Int32? = nil) {
        if let fileLimitMB {
            self.mediaFileLimitMB = max(1, min(100, fileLimitMB))
        }
        if let quotaMB {
            self.mediaQuotaMB = max(50, min(2000, quotaMB))
        }
    }

    public mutating func clear() {
        self.records.removeAll()
    }

    public mutating func remove(peerId: Int64, messageId: Int32? = nil) {
        self.records.removeAll { record in
            record.peerId == peerId && (messageId == nil || record.messageId == messageId)
        }
    }

    public mutating func removeMedia(storedNames: Set<String>) {
        guard !storedNames.isEmpty else {
            return
        }
        var updated: [FullGramMessageHistoryRecord] = []
        for record in self.records {
            guard let attachments = record.attachments, !attachments.isEmpty else {
                updated.append(record)
                continue
            }
            let remaining = attachments.filter { !storedNames.contains($0.storedName) }
            updated.append(
                FullGramMessageHistoryRecord(
                    id: record.id,
                    peerId: record.peerId,
                    messageId: record.messageId,
                    messageTimestamp: record.messageTimestamp,
                    capturedAt: record.capturedAt,
                    kind: record.kind,
                    text: record.text,
                    attachments: remaining.isEmpty ? nil : remaining
                )
            )
        }
        self.records = updated
    }

    public mutating func prune(now: Int64) {
        self.records.removeAll { $0.capturedAt <= now - Self.retentionSeconds || $0.capturedAt > now + 300 }
        if self.records.count > Self.maximumRecords {
            self.records.removeFirst(self.records.count - Self.maximumRecords)
        }
    }

    public mutating func append(
        peerId: Int64,
        messageId: Int32,
        messageTimestamp: Int32,
        kind: FullGramMessageHistoryRecord.Kind,
        text: String,
        attachments: [FullGramArchivedAttachment]? = nil,
        now: Int64
    ) {
        self.prune(now: now)
        let cleanedAttachments = attachments?.isEmpty == true ? nil : attachments
        guard (kind == .edited ? self.saveEdits : self.saveDeleted), (!text.isEmpty || cleanedAttachments != nil) else {
            return
        }
        guard text.utf8.count <= Self.maximumTextLength else {
            return
        }
        if let last = self.records.last(where: { $0.peerId == peerId && $0.messageId == messageId && $0.kind == kind }),
           last.text == text,
           (last.attachments ?? []) == (cleanedAttachments ?? []) {
            return
        }
        if self.nextId == Int32.max {
            self.records.removeAll()
            self.nextId = 1
        }
        self.records.append(
            FullGramMessageHistoryRecord(
                id: self.nextId,
                peerId: peerId,
                messageId: messageId,
                messageTimestamp: messageTimestamp,
                capturedAt: now,
                kind: kind,
                text: text,
                attachments: cleanedAttachments
            )
        )
        self.nextId += 1
        self.prune(now: now)
    }
}

public final class FullGramArchiveFileStore: @unchecked Sendable {
    private static let registryLock = NSLock()
    private nonisolated(unsafe) static var stores: [String: FullGramArchiveFileStore] = [:]

    public static func shared(basePath: String) -> FullGramArchiveFileStore {
        let normalized = URL(fileURLWithPath: basePath).standardizedFileURL.path
        self.registryLock.lock()
        defer { self.registryLock.unlock() }
        if let existing = self.stores[normalized] {
            return existing
        }
        let created = FullGramArchiveFileStore(basePath: normalized)
        self.stores[normalized] = created
        return created
    }

    private let lock = NSLock()
    private let directory: URL
    public private(set) var maxTotalBytes: Int64 = 250 * 1024 * 1024
    public private(set) var maxPerFileBytes: Int64 = 15 * 1024 * 1024

    public init(basePath: String) {
        self.directory = URL(fileURLWithPath: basePath, isDirectory: true).appendingPathComponent("fullgram-history-media", isDirectory: true)
        self.ensureDirectory()
    }

    private func ensureDirectory() {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: self.directory.path, isDirectory: &isDir), !isDir.boolValue {
            try? FileManager.default.removeItem(at: self.directory)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = self.directory
        try? url.setResourceValues(values)
    }

    public func configure(quota: Int64, perFileLimit: Int64) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.maxTotalBytes = max(10 * 1024 * 1024, quota)
        self.maxPerFileBytes = max(1 * 1024 * 1024, min(perFileLimit, self.maxTotalBytes))
    }

    public func copy(source: String, displayName: String) -> FullGramArchivedAttachment? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.ensureDirectory()
        let attrs = try? FileManager.default.attributesOfItem(atPath: source)
        guard (attrs?[.type] as? FileAttributeType) == .typeRegular,
              let size = (attrs?[.size] as? NSNumber)?.int64Value,
              size > 0, size <= self.maxPerFileBytes else {
            return nil
        }
        let cleaned = self.sanitize(displayName)
        let ext = URL(fileURLWithPath: cleaned).pathExtension
        let id = UUID().uuidString.lowercased()
        let storedName = ext.isEmpty ? id : "\(id).\(ext)"
        let destination = self.directory.appendingPathComponent(storedName, isDirectory: false)
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: destination)
            #if os(iOS)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path
            )
            #endif
            let copiedAttrs = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard (copiedAttrs[.type] as? FileAttributeType) == .typeRegular,
                  let copiedSize = (copiedAttrs[.size] as? NSNumber)?.int64Value,
                  copiedSize > 0, copiedSize <= self.maxPerFileBytes else {
                try? FileManager.default.removeItem(at: destination)
                return nil
            }
            return FullGramArchivedAttachment(id: id, storedName: storedName, displayName: cleaned, byteCount: copiedSize)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    public func url(for storedName: String) -> URL? {
        let base = URL(fileURLWithPath: storedName).lastPathComponent
        guard base == storedName, !base.isEmpty, base != ".", base != ".." else {
            return nil
        }
        let candidate = self.directory.appendingPathComponent(base, isDirectory: false).standardizedFileURL
        let root = self.directory.standardizedFileURL.path
        guard candidate.path.hasPrefix(root + "/") else {
            return nil
        }
        let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            return nil
        }
        return candidate
    }

    public func prune(validNames: Set<String>) {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: self.directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey],
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return
        }
        var kept: [(URL, Int64, Date)] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey])
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  validNames.contains(url.lastPathComponent) else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            kept.append((url, Int64(values?.fileSize ?? 0), values?.creationDate ?? .distantPast))
        }
        var total = kept.reduce(Int64(0)) { $0 + $1.1 }
        if total > self.maxTotalBytes {
            for (url, size, _) in kept.sorted(by: { $0.2 < $1.2 }) where total > self.maxTotalBytes {
                try? FileManager.default.removeItem(at: url)
                total -= size
            }
        }
    }

    public func allFiles() -> [(storedName: String, url: URL, byteCount: Int64, createdAt: Date)] {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: self.directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey],
            options: [.skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        var result: [(storedName: String, url: URL, byteCount: Int64, createdAt: Date)] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .creationDateKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                continue
            }
            result.append((
                storedName: url.lastPathComponent,
                url: url,
                byteCount: Int64(values?.fileSize ?? 0),
                createdAt: values?.creationDate ?? .distantPast
            ))
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    public func remove(storedNames: Set<String>) {
        self.lock.lock()
        defer { self.lock.unlock() }
        for name in storedNames {
            let base = URL(fileURLWithPath: name).lastPathComponent
            guard base == name, !base.isEmpty, base != ".", base != ".." else {
                continue
            }
            let target = self.directory.appendingPathComponent(base, isDirectory: false)
            try? FileManager.default.removeItem(at: target)
        }
    }

    private func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\0")
            .union(.controlCharacters)
            .union(CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"))
        let cleaned = name.unicodeScalars.map { forbidden.contains($0) ? "_" : Character($0) }
        let base = URL(fileURLWithPath: String(cleaned)).lastPathComponent.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if base.isEmpty {
            return "attachment.bin"
        }
        return String(base.prefix(120))
    }
}

private let fullGramHistoryKey = applicationSpecificPreferencesKey(19901)

private func fullGramDecodeHistoryState(entry: PreferencesEntry?) -> FullGramMessageHistoryState {
    guard let entry = entry else {
        return FullGramMessageHistoryState()
    }
    if let state = try? JSONDecoder().decode(FullGramMessageHistoryState.self, from: entry.data) {
        return state
    }
    return entry.get(FullGramMessageHistoryState.self) ?? FullGramMessageHistoryState()
}

private func fullGramEncodeHistoryState(_ state: FullGramMessageHistoryState) -> PreferencesEntry {
    if let data = try? JSONEncoder().encode(state) {
        return PreferencesEntry(data: data)
    }
    return PreferencesEntry(state) ?? PreferencesEntry(data: Data())
}

private func fullGramHistoryPeerAllowsArchiving(transaction: Transaction, peerId: PeerId) -> Bool {
    guard [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel].contains(peerId.namespace),
          let peer = transaction.getPeer(peerId),
          !peer.isCopyProtectionEnabled else {
        return false
    }
    let timeout: CachedPeerAutoremoveTimeout
    switch transaction.getPeerCachedData(peerId: peerId) {
    case let data as CachedUserData:
        guard !data.flags.contains(.copyProtectionEnabled), !data.flags.contains(.myCopyProtectionEnabled) else {
            return false
        }
        timeout = data.autoremoveTimeout
    case let data as CachedGroupData:
        timeout = data.autoremoveTimeout
    case let data as CachedChannelData:
        timeout = data.autoremoveTimeout
    default:
        return false
    }
    if case .known(nil) = timeout {
        return true
    }
    if case let .known(value?) = timeout {
        return value.effectiveValue == 0
    }
    return false
}

private func fullGramHistoryHasExpiringAttribute(_ attributes: [MessageAttribute]) -> Bool {
    return attributes.contains {
        $0 is AutoremoveTimeoutMessageAttribute
            || $0 is AutoclearTimeoutMessageAttribute
            || $0 is EphemeralMessageAttribute
            || $0 is EphemeralReplacementMessageAttribute
            || $0 is EphemeralOutgoingMessageAttribute
    }
}

private func fullGramRemoveExpiredTombstones(transaction: Transaction, previous: FullGramMessageHistoryState, updated: FullGramMessageHistoryState) {
    let kept = Set(updated.records.filter { $0.kind == .deleted }.map {
        MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId)
    })
    let removed = Set(previous.records.filter { $0.kind == .deleted }.map {
        MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId)
    }).subtracting(kept)
    let ids = removed.filter { id in
        transaction.getMessage(id)?.attributes.contains(where: { $0 is FullGramDeletedMessageAttribute }) == true
    }
    if !ids.isEmpty {
        transaction.deleteMessages(Array(ids), forEachMedia: nil)
    }
}

@discardableResult
func fullGramPruneHistory(transaction: Transaction) -> FullGramMessageHistoryState {
    let original = fullGramDecodeHistoryState(entry: transaction.getPreferencesEntry(key: fullGramHistoryKey))
    var state = original
    state.prune(now: Int64(Date().timeIntervalSince1970))
    for peerId in Set(state.records.map { $0.peerId }) where !fullGramHistoryPeerAllowsArchiving(transaction: transaction, peerId: PeerId(peerId)) {
        state.remove(peerId: peerId)
    }
    if state != original {
        fullGramRemoveExpiredTombstones(transaction: transaction, previous: original, updated: state)
        transaction.updatePreferencesEntry(key: fullGramHistoryKey, { _ in fullGramEncodeHistoryState(state) })
    }
    return state
}

private func fullGramPeerAllowsMediaCapture(transaction: Transaction, peerId: PeerId, state: FullGramMessageHistoryState) -> Bool {
    guard state.saveMedia, let peer = transaction.getPeer(peerId) else {
        return false
    }
    if peer is TelegramUser {
        return state.mediaPrivateChats
    }
    if peer is TelegramGroup {
        return state.mediaPrivateGroups
    }
    if let channel = peer as? TelegramChannel {
        let isPublic = !(channel.addressName ?? "").isEmpty
        switch channel.info {
        case .broadcast:
            return isPublic ? state.mediaPublicChannels : state.mediaPrivateChannels
        case .group:
            return isPublic ? state.mediaPublicGroups : state.mediaPrivateGroups
        }
    }
    return false
}

private func fullGramCaptureAttachments(
    mediaBox: MediaBox,
    mediaList: [Media],
    state: FullGramMessageHistoryState
) -> [FullGramArchivedAttachment] {
    let store = FullGramArchiveFileStore.shared(basePath: mediaBox.basePath)
    store.configure(
        quota: Int64(state.mediaQuotaMB) * 1024 * 1024,
        perFileLimit: Int64(state.mediaFileLimitMB) * 1024 * 1024
    )
    var attachments: [FullGramArchivedAttachment] = []
    for item in mediaList {
        if let image = item as? TelegramMediaImage,
           let representation = image.representations.max(by: { (Int64($0.dimensions.width) * Int64($0.dimensions.height)) < (Int64($1.dimensions.width) * Int64($1.dimensions.height)) }),
           let path = mediaBox.completedResourcePath(representation.resource),
           let saved = store.copy(source: path, displayName: "photo.jpg") {
            attachments.append(saved)
        } else if let file = item as? TelegramMediaFile, !file.isSticker, !file.isAnimatedSticker, !file.isVideoSticker,
                  let path = mediaBox.completedResourcePath(file.resource) {
            let fallback: String
            if file.isInstantVideo {
                fallback = "video_note.mp4"
            } else if file.isVoice {
                fallback = "voice.ogg"
            } else if file.isVideo {
                fallback = "video.mp4"
            } else {
                fallback = "document.bin"
            }
            if let saved = store.copy(source: path, displayName: file.fileName ?? fallback) {
                attachments.append(saved)
            }
        }
    }
    return attachments
}

func fullGramArchiveMessage(transaction: Transaction, mediaBox: MediaBox? = nil, message: Message, kind: FullGramMessageHistoryRecord.Kind, updated: StoreMessage? = nil) {
    let original = fullGramDecodeHistoryState(entry: transaction.getPreferencesEntry(key: fullGramHistoryKey))
    var state = original
    let now = Int64(Date().timeIntervalSince1970)
    state.prune(now: now)
    let peerAllows = fullGramHistoryPeerAllowsArchiving(transaction: transaction, peerId: message.id.peerId)
    let updateAllows = updated.map { !$0.flags.contains(.CopyProtected) && !fullGramHistoryHasExpiringAttribute($0.attributes) } ?? true
    let contentChanged = updated.map {
        $0.text != message.text || $0.media.map({ $0.id }) != message.media.map({ $0.id })
    } ?? true
    let isBot = (transaction.getPeer(message.id.peerId) as? TelegramUser)?.botInfo != nil || (message.author as? TelegramUser)?.botInfo != nil
    let shouldCapture = kind == .edited ? state.saveEdits : state.saveDeleted
    if !peerAllows {
        state.remove(peerId: message.id.peerId.toInt64())
    } else if message.id.namespace != Namespaces.Message.Cloud || message.isCopyProtected() || fullGramHistoryHasExpiringAttribute(message.attributes) || !updateAllows {
        state.remove(peerId: message.id.peerId.toInt64(), messageId: message.id.id)
    } else if shouldCapture, state.saveForBots || !isBot, contentChanged, (!message.text.isEmpty || !message.media.isEmpty), message.text.utf8.count <= FullGramMessageHistoryState.maximumTextLength {
        var attachments: [FullGramArchivedAttachment] = []
        if let mediaBox = mediaBox, fullGramPeerAllowsMediaCapture(transaction: transaction, peerId: message.id.peerId, state: state) {
            attachments = fullGramCaptureAttachments(mediaBox: mediaBox, mediaList: message.media, state: state)
        }
        let archivedText = message.text.isEmpty ? (message.media.first is TelegramMediaImage ? "📷 Фото" : (message.media.first is TelegramMediaFile ? "📎 Файл" : "💬 Медиа")) : message.text
        state.append(
            peerId: message.id.peerId.toInt64(),
            messageId: message.id.id,
            messageTimestamp: message.timestamp,
            kind: kind,
            text: archivedText,
            attachments: attachments,
            now: now
        )
    }
    if state != original {
        fullGramRemoveExpiredTombstones(transaction: transaction, previous: original, updated: state)
        transaction.updatePreferencesEntry(key: fullGramHistoryKey, { _ in fullGramEncodeHistoryState(state) })
        if let mediaBox = mediaBox {
            let store = FullGramArchiveFileStore.shared(basePath: mediaBox.basePath)
            store.configure(
                quota: Int64(state.mediaQuotaMB) * 1024 * 1024,
                perFileLimit: Int64(state.mediaFileLimitMB) * 1024 * 1024
            )
            let validNames = Set(state.records.flatMap { $0.attachments ?? [] }.map { $0.storedName })
            store.prune(validNames: validNames)
        }
    }
}

func fullGramRetainDeletedMessage(transaction: Transaction, mediaBox: MediaBox? = nil, message: Message) -> Bool {
    let alreadyDeleted = message.attributes.contains(where: { $0 is FullGramDeletedMessageAttribute })
    if alreadyDeleted {
        fullGramPruneHistory(transaction: transaction)
    } else {
        fullGramArchiveMessage(transaction: transaction, mediaBox: mediaBox, message: message, kind: .deleted)
    }
    let state = fullGramDecodeHistoryState(entry: transaction.getPreferencesEntry(key: fullGramHistoryKey))
    let hasContent = !message.text.isEmpty || !message.media.isEmpty
    guard hasContent,
          state.records.contains(where: { $0.kind == .deleted && $0.peerId == message.id.peerId.toInt64() && $0.messageId == message.id.id }) else {
        return false
    }
    if alreadyDeleted {
        return true
    }
    transaction.updateMessage(message.id, update: { previous in
        var forwardInfo: StoreMessageForwardInfo?
        if let current = previous.forwardInfo {
            forwardInfo = StoreMessageForwardInfo(
                authorId: current.author?.id,
                sourceId: current.source?.id,
                sourceMessageId: current.sourceMessageId,
                date: current.date,
                authorSignature: current.authorSignature,
                psaType: current.psaType,
                flags: current.flags
            )
        }
        var attributes = previous.attributes.filter {
            !($0 is FullGramDeletedMessageAttribute) && !($0 is ReplyMarkupMessageAttribute)
        }
        attributes.append(FullGramDeletedMessageAttribute(timestamp: Int64(Date().timeIntervalSince1970)))
        var flags = StoreMessageFlags(previous.flags)
        flags.remove(.TopIndexable)
        flags.remove(.CountedAsIncoming)
        flags.remove(.ReactionsArePossible)
        let tombstoneText = previous.text.isEmpty ? (previous.media.first is TelegramMediaImage ? "📷" : (previous.media.first is TelegramMediaFile ? "📎" : "💬")) : previous.text
        return .update(
            StoreMessage(
                id: previous.id,
                customStableId: nil,
                globallyUniqueId: previous.globallyUniqueId,
                groupingKey: nil,
                threadId: previous.threadId,
                timestamp: previous.timestamp,
                flags: flags,
                tags: [],
                globalTags: [],
                localTags: [],
                forwardInfo: forwardInfo,
                authorId: previous.author?.id,
                text: tombstoneText,
                attributes: attributes,
                media: []
            )
        )
    })
    return true
}

func fullGramManageArchiveFiles(postbox: Postbox) -> Signal<Void, NoError> {
    let store = FullGramArchiveFileStore.shared(basePath: postbox.mediaBox.basePath)
    return postbox.preferencesView(keys: [fullGramHistoryKey])
    |> mapToSignal { _ in
        return postbox.transaction { transaction -> FullGramMessageHistoryState in
            return fullGramPruneHistory(transaction: transaction)
        }
    }
    |> map { state in
        store.configure(
            quota: Int64(state.mediaQuotaMB) * 1024 * 1024,
            perFileLimit: Int64(state.mediaFileLimitMB) * 1024 * 1024
        )
        let validNames = Set(state.records.flatMap { $0.attachments ?? [] }.map { $0.storedName })
        store.prune(validNames: validNames)
    }
}

public extension TelegramEngine.Messages {
    func fullGramArchivedAttachmentUrl(storedName: String) -> URL? {
        return FullGramArchiveFileStore.shared(basePath: self.account.postbox.mediaBox.basePath).url(for: storedName)
    }

    func fullGramArchivedMediaFiles() -> [(storedName: String, url: URL, byteCount: Int64, createdAt: Date)] {
        return FullGramArchiveFileStore.shared(basePath: self.account.postbox.mediaBox.basePath).allFiles()
    }

    func fullGramRemoveArchivedMedia(storedNames: Set<String>) -> Signal<Void, NoError> {
        let store = FullGramArchiveFileStore.shared(basePath: self.account.postbox.mediaBox.basePath)
        return self.account.postbox.transaction { transaction -> Void in
            store.remove(storedNames: storedNames)
            transaction.updatePreferencesEntry(key: fullGramHistoryKey, { entry in
                var state = fullGramDecodeHistoryState(entry: entry)
                state.removeMedia(storedNames: storedNames)
                return fullGramEncodeHistoryState(state)
            })
        }
    }

    func fullGramSetMediaArchiveLimits(fileLimitMB: Int32? = nil, quotaMB: Int32? = nil) -> Signal<Void, NoError> {
        let store = FullGramArchiveFileStore.shared(basePath: self.account.postbox.mediaBox.basePath)
        return self.account.postbox.transaction { transaction -> Void in
            transaction.updatePreferencesEntry(key: fullGramHistoryKey, { entry in
                var state = fullGramDecodeHistoryState(entry: entry)
                state.setMediaLimits(fileLimitMB: fileLimitMB, quotaMB: quotaMB)
                store.configure(
                    quota: Int64(state.mediaQuotaMB) * 1024 * 1024,
                    perFileLimit: Int64(state.mediaFileLimitMB) * 1024 * 1024
                )
                let validNames = Set(state.records.flatMap { $0.attachments ?? [] }.map { $0.storedName })
                store.prune(validNames: validNames)
                return fullGramEncodeHistoryState(state)
            })
        }
    }

    func fullGramMessageHistory() -> Signal<FullGramMessageHistoryState, NoError> {
        return self.account.postbox.preferencesView(keys: [fullGramHistoryKey])
        |> mapToSignal { _ in
            return self.account.postbox.transaction { transaction -> FullGramMessageHistoryState in
                return fullGramPruneHistory(transaction: transaction)
            }
        }
        |> distinctUntilChanged
    }

    func updateFullGramMessageHistory(
        saveEdits: Bool? = nil,
        saveDeleted: Bool? = nil,
        saveForBots: Bool? = nil,
        saveMedia: Bool? = nil,
        mediaPrivateChats: Bool? = nil,
        mediaPublicChannels: Bool? = nil,
        mediaPrivateChannels: Bool? = nil,
        mediaPublicGroups: Bool? = nil,
        mediaPrivateGroups: Bool? = nil,
        clear: Bool = false
    ) -> Signal<Void, NoError> {
        let store = FullGramArchiveFileStore.shared(basePath: self.account.postbox.mediaBox.basePath)
        return self.account.postbox.transaction { transaction -> Void in
            transaction.updatePreferencesEntry(key: fullGramHistoryKey, { entry in
                var state = fullGramDecodeHistoryState(entry: entry)
                let previous = state
                if let saveEdits {
                    state.saveEdits = saveEdits
                }
                if let saveDeleted {
                    state.saveDeleted = saveDeleted
                }
                if let saveForBots {
                    state.saveForBots = saveForBots
                }
                if let saveMedia {
                    state.saveMedia = saveMedia
                }
                if let mediaPrivateChats {
                    state.mediaPrivateChats = mediaPrivateChats
                }
                if let mediaPublicChannels {
                    state.mediaPublicChannels = mediaPublicChannels
                }
                if let mediaPrivateChannels {
                    state.mediaPrivateChannels = mediaPrivateChannels
                }
                if let mediaPublicGroups {
                    state.mediaPublicGroups = mediaPublicGroups
                }
                if let mediaPrivateGroups {
                    state.mediaPrivateGroups = mediaPrivateGroups
                }
                if clear {
                    state.clear()
                }
                state.prune(now: Int64(Date().timeIntervalSince1970))
                fullGramRemoveExpiredTombstones(transaction: transaction, previous: previous, updated: state)
                let validNames = Set(state.records.flatMap { $0.attachments ?? [] }.map { $0.storedName })
                store.prune(validNames: validNames)
                return fullGramEncodeHistoryState(state)
            })
        }
    }
}
