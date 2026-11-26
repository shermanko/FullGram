import Foundation
import UIKit
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit
import Security
import ImageIO
import UniformTypeIdentifiers
import Network

public struct FullGramInterfaceSettings: Codable, Equatable {
    public var hideFastShare: Bool
    public var showReactionPicker: Bool
    public var showReadSummary: Bool
    public var showEditedInfo: Bool
    public var showAuthorSearch: Bool
    public var showCopyMessageIds: Bool
    public var hideStickerTime: Bool
    public var unlimitedRecentStickers: Bool
    public var disableJumpToNextChannel: Bool
    public var hideKeyboardOnScroll: Bool
    public var addCommaAfterMention: Bool
    public var horizonLockVideoMessages: Bool

    public init(
        hideFastShare: Bool = false,
        showReactionPicker: Bool = true,
        showReadSummary: Bool = true,
        showEditedInfo: Bool = true,
        showAuthorSearch: Bool = true,
        showCopyMessageIds: Bool = true,
        hideStickerTime: Bool = false,
        unlimitedRecentStickers: Bool = false,
        disableJumpToNextChannel: Bool = false,
        hideKeyboardOnScroll: Bool = false,
        addCommaAfterMention: Bool = false,
        horizonLockVideoMessages: Bool = false
    ) {
        self.hideFastShare = hideFastShare
        self.showReactionPicker = showReactionPicker
        self.showReadSummary = showReadSummary
        self.showEditedInfo = showEditedInfo
        self.showAuthorSearch = showAuthorSearch
        self.showCopyMessageIds = showCopyMessageIds
        self.hideStickerTime = hideStickerTime
        self.unlimitedRecentStickers = unlimitedRecentStickers
        self.disableJumpToNextChannel = disableJumpToNextChannel
        self.hideKeyboardOnScroll = hideKeyboardOnScroll
        self.addCommaAfterMention = addCommaAfterMention
        self.horizonLockVideoMessages = horizonLockVideoMessages
    }

    private enum CodingKeys: String, CodingKey {
        case hideFastShare
        case showReactionPicker
        case showReadSummary
        case showEditedInfo
        case showAuthorSearch
        case showCopyMessageIds
        case hideStickerTime
        case unlimitedRecentStickers
        case disableJumpToNextChannel
        case hideKeyboardOnScroll
        case addCommaAfterMention
        case horizonLockVideoMessages
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.hideFastShare = try values.decodeIfPresent(Bool.self, forKey: .hideFastShare) ?? false
        self.showReactionPicker = try values.decodeIfPresent(Bool.self, forKey: .showReactionPicker) ?? true
        self.showReadSummary = try values.decodeIfPresent(Bool.self, forKey: .showReadSummary) ?? true
        self.showEditedInfo = try values.decodeIfPresent(Bool.self, forKey: .showEditedInfo) ?? true
        self.showAuthorSearch = try values.decodeIfPresent(Bool.self, forKey: .showAuthorSearch) ?? true
        self.showCopyMessageIds = try values.decodeIfPresent(Bool.self, forKey: .showCopyMessageIds) ?? true
        self.hideStickerTime = try values.decodeIfPresent(Bool.self, forKey: .hideStickerTime) ?? false
        self.unlimitedRecentStickers = try values.decodeIfPresent(Bool.self, forKey: .unlimitedRecentStickers) ?? false
        self.disableJumpToNextChannel = try values.decodeIfPresent(Bool.self, forKey: .disableJumpToNextChannel) ?? false
        self.hideKeyboardOnScroll = try values.decodeIfPresent(Bool.self, forKey: .hideKeyboardOnScroll) ?? false
        self.addCommaAfterMention = try values.decodeIfPresent(Bool.self, forKey: .addCommaAfterMention) ?? false
        self.horizonLockVideoMessages = try values.decodeIfPresent(Bool.self, forKey: .horizonLockVideoMessages) ?? false
    }
}

public struct FullGramReactionDisplaySettings: Codable, Equatable {
    public var enabled: Bool
    public var showCounts: Bool
    public var maxVisibleCount: Int32

    public init(enabled: Bool = true, showCounts: Bool = true, maxVisibleCount: Int32 = 8) {
        self.enabled = enabled
        self.showCounts = showCounts
        self.maxVisibleCount = min(11, max(1, maxVisibleCount))
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case showCounts
        case maxVisibleCount
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.showCounts = try values.decodeIfPresent(Bool.self, forKey: .showCounts) ?? true
        self.maxVisibleCount = min(11, max(1, try values.decodeIfPresent(Int32.self, forKey: .maxVisibleCount) ?? 8))
    }
}

public struct FullGramTranslationSettings: Codable, Equatable {
    public enum Provider: String, Codable, CaseIterable {
        case telegram
        case libreTranslate
        case deepLFree

        public var title: String {
            switch self {
            case .telegram:
                return "Telegram"
            case .libreTranslate:
                return "LibreTranslate"
            case .deepLFree:
                return "DeepL API Free"
            }
        }
    }

    public static let supportedLanguageCodes: [String] = [
        "ru", "en", "uk", "de", "fr", "es", "it", "pt", "pl", "tr", "ar", "zh", "ja", "ko"
    ]

    public var provider: Provider
    public var targetLanguage: String
    public var libreTranslateURL: String

    public init(
        provider: Provider = .telegram,
        targetLanguage: String = "ru",
        libreTranslateURL: String = ""
    ) {
        self.provider = provider
        self.targetLanguage = Self.normalizeLanguageCode(targetLanguage)
        self.libreTranslateURL = Self.normalizeEndpoint(libreTranslateURL)
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case targetLanguage
        case libreTranslateURL
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = (try? values.decode(Provider.self, forKey: .provider)) ?? .telegram
        self.targetLanguage = Self.normalizeLanguageCode(try values.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "ru")
        self.libreTranslateURL = Self.normalizeEndpoint(try values.decodeIfPresent(String.self, forKey: .libreTranslateURL) ?? "")
    }

    public static func normalizeLanguageCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = String(trimmed.split(separator: "-").first ?? Substring(trimmed))
        if supportedLanguageCodes.contains(base) {
            return base
        }
        return "ru"
    }

    public static func normalizeEndpoint(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else {
            return ""
        }
        return String(trimmed.prefix(512))
    }
}

public enum FullGramTranslationError: Error {
    case emptyText
    case missingEndpoint
    case missingApiKey
    case invalidEndpoint
    case networkFailure(String)
    case serviceError(String)
    case invalidResponse
}

private enum FullGramCoreKeychain {
    static func readWithStatus(service: String, account: String) -> (data: Data?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return (data, status)
        }
        return (nil, status)
    }

    static func read(service: String, account: String) -> Data? {
        return readWithStatus(service: service, account: account).data
    }

    static func write(_ data: Data, service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            _ = SecItemAdd(newItem as CFDictionary, nil)
        }
        // Clean up any legacy plaintext fallback entry if present.
        UserDefaults.standard.removeObject(forKey: "fullgram.kc.\(service).\(account)")
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fullgram.kc.\(service).\(account)")
    }
}

public enum FullGramTranslationKeys {
    private static let service = "FullGram.TranslationKeys"

    public static func apiKey(for provider: FullGramTranslationSettings.Provider, accountId: Int64) -> String {
        guard let data = FullGramCoreKeychain.read(service: self.service, account: "\(accountId):\(provider.rawValue)"),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    public static func setApiKey(_ value: String, for provider: FullGramTranslationSettings.Provider, accountId: Int64) {
        let account = "\(accountId):\(provider.rawValue)"
        let trimmed = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            FullGramCoreKeychain.delete(service: self.service, account: account)
            return
        }
        FullGramCoreKeychain.write(data, service: self.service, account: account)
    }
}

public enum FullGramTranslationRequest {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    public static func translateExternal(
        text: String,
        targetLanguage: String,
        settings: FullGramTranslationSettings,
        accountId: Int64
    ) -> Signal<String, FullGramTranslationError> {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4096))
        guard !trimmed.isEmpty else {
            return .fail(.emptyText)
        }
        let target = FullGramTranslationSettings.normalizeLanguageCode(targetLanguage)
        switch settings.provider {
        case .telegram:
            return .fail(.invalidResponse)
        case .libreTranslate:
            return self.translateLibre(text: trimmed, targetLanguage: target, settings: settings, accountId: accountId)
        case .deepLFree:
            return self.translateDeepL(text: trimmed, targetLanguage: target, accountId: accountId)
        }
    }

    private static func translateLibre(
        text: String,
        targetLanguage: String,
        settings: FullGramTranslationSettings,
        accountId: Int64
    ) -> Signal<String, FullGramTranslationError> {
        let rawEndpoint = settings.libreTranslateURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawEndpoint.isEmpty else {
            return .fail(.missingEndpoint)
        }
        let normalizedPath: String
        if rawEndpoint.lowercased().hasSuffix("/translate") {
            normalizedPath = rawEndpoint
        } else if rawEndpoint.hasSuffix("/") {
            normalizedPath = rawEndpoint + "translate"
        } else {
            normalizedPath = rawEndpoint + "/translate"
        }
        guard let url = URL(string: normalizedPath), url.scheme?.lowercased() == "https", url.host != nil else {
            return .fail(.invalidEndpoint)
        }
        var payload: [String: String] = [
            "q": text,
            "source": "auto",
            "target": targetLanguage,
            "format": "text"
        ]
        let key = FullGramTranslationKeys.apiKey(for: .libreTranslate, accountId: accountId)
        if !key.isEmpty {
            payload["api_key"] = key
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return .fail(.invalidResponse)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return self.perform(request: request) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return .failure(.invalidResponse)
            }
            if let translated = object["translatedText"] as? String, !translated.isEmpty {
                return .success(translated)
            }
            if let errorMessage = object["error"] as? String, !errorMessage.isEmpty {
                return .failure(.serviceError(String(errorMessage.prefix(200))))
            }
            return .failure(.invalidResponse)
        }
    }

    private static func translateDeepL(
        text: String,
        targetLanguage: String,
        accountId: Int64
    ) -> Signal<String, FullGramTranslationError> {
        let apiKey = FullGramTranslationKeys.apiKey(for: .deepLFree, accountId: accountId)
        guard !apiKey.isEmpty else {
            return .fail(.missingApiKey)
        }
        let host = "api-free.deepl.com"
        guard let url = URL(string: "https://\(host)/v2/translate") else {
            return .fail(.invalidEndpoint)
        }
        let deepLCode: String
        switch targetLanguage {
        case "en":
            deepLCode = "EN"
        case "pt":
            deepLCode = "PT-PT"
        default:
            deepLCode = targetLanguage.uppercased()
        }
        let payload: [String: Any] = [
            "text": [text],
            "target_lang": deepLCode
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return .fail(.invalidResponse)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return self.perform(request: request) { data in
            guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return .failure(.invalidResponse)
            }
            if let translations = object["translations"] as? [[String: Any]],
               let first = translations.first,
               let result = first["text"] as? String,
               !result.isEmpty {
                return .success(result)
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return .failure(.serviceError(String(message.prefix(200))))
            }
            return .failure(.invalidResponse)
        }
    }

    private static func perform(
        request: URLRequest,
        parse: @escaping (Data) -> Result<String, FullGramTranslationError>
    ) -> Signal<String, FullGramTranslationError> {
        return Signal { subscriber in
            let task = self.session.dataTask(with: request) { data, response, error in
                if let error = error {
                    subscriber.putError(.networkFailure(String(error.localizedDescription.prefix(160))))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, let data = data, data.count <= 262_144 else {
                    subscriber.putError(.invalidResponse)
                    return
                }
                switch parse(data) {
                case let .success(text):
                    if (200 ..< 300).contains(httpResponse.statusCode) {
                        subscriber.putNext(text)
                        subscriber.putCompletion()
                    } else {
                        subscriber.putError(.serviceError("HTTP \(httpResponse.statusCode)"))
                    }
                case let .failure(parseError):
                    if !(200 ..< 300).contains(httpResponse.statusCode) {
                        if case .serviceError = parseError {
                            subscriber.putError(parseError)
                        } else {
                            subscriber.putError(.serviceError("HTTP \(httpResponse.statusCode)"))
                        }
                    } else {
                        subscriber.putError(parseError)
                    }
                }
            }
            task.resume()
            return ActionDisposable {
                task.cancel()
            }
        }
    }
}

public extension TelegramEngine.Messages {
    func fullGramTranslate(text: String, toLang: String? = nil) -> Signal<(String, [MessageTextEntity]), FullGramTranslationError> {
        let settings = self.account.network.fullGramGhostMode.current.translation
        let target = FullGramTranslationSettings.normalizeLanguageCode(toLang ?? settings.targetLanguage)
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4096))
        guard !trimmed.isEmpty else {
            return .fail(.emptyText)
        }
        switch settings.provider {
        case .telegram:
            return self.translate(text: trimmed, toLang: target)
            |> mapError { error -> FullGramTranslationError in
                switch error {
                case .limitExceeded:
                    return .serviceError("Превышен лимит запросов Telegram")
                case .invalidLanguage:
                    return .serviceError("Неподдерживаемый язык")
                case .textIsEmpty:
                    return .emptyText
                case .textTooLong:
                    return .serviceError("Текст слишком длинный для перевода")
                case .invalidMessageId, .tryAlternative:
                    return .serviceError("Не удалось перевести через Telegram")
                case .generic:
                    return .networkFailure("Ошибка соединения с Telegram")
                }
            }
            |> mapToSignal { result -> Signal<(String, [MessageTextEntity]), FullGramTranslationError> in
                guard let result = result else {
                    return .fail(.invalidResponse)
                }
                return .single(result)
            }
        case .libreTranslate, .deepLFree:
            let accountId = self.account.peerId.toInt64()
            return FullGramTranslationRequest.translateExternal(
                text: trimmed,
                targetLanguage: target,
                settings: settings,
                accountId: accountId
            )
            |> map { ($0, []) }
        }
    }
}

public enum FullGramDisplayOptions {
    private static let lock = NSLock()
    private static var activePeerId: Int64?
    private static var valuesByPeer: [Int64: (
        hideStickerTime: Bool,
        unlimitedRecentStickers: Bool,
        hideFastShare: Bool,
        reactionDisplay: FullGramReactionDisplaySettings
    )] = [:]

    public static func update(
        peerId: Int64,
        hideStickerTime: Bool,
        unlimitedRecentStickers: Bool,
        hideFastShare: Bool,
        reactionDisplay: FullGramReactionDisplaySettings
    ) {
        self.lock.lock()
        self.activePeerId = peerId
        self.valuesByPeer[peerId] = (hideStickerTime, unlimitedRecentStickers, hideFastShare, reactionDisplay)
        self.lock.unlock()
    }

    public static func activate(peerId: Int64) {
        self.lock.lock()
        self.activePeerId = peerId
        self.lock.unlock()
    }

    private static var currentValues: (
        hideStickerTime: Bool,
        unlimitedRecentStickers: Bool,
        hideFastShare: Bool,
        reactionDisplay: FullGramReactionDisplaySettings
    ) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let peerId = self.activePeerId, let values = self.valuesByPeer[peerId] {
            return values
        }
        return self.valuesByPeer.values.first ?? (false, false, false, FullGramReactionDisplaySettings())
    }

    public static var hideStickerTime: Bool {
        return self.currentValues.hideStickerTime
    }

    public static var unlimitedRecentStickers: Bool {
        return self.currentValues.unlimitedRecentStickers
    }

    public static var hideFastShare: Bool {
        return self.currentValues.hideFastShare
    }

    public static var reactionDisplay: FullGramReactionDisplaySettings {
        return self.currentValues.reactionDisplay
    }

    public static var recentStickersLimit: Int {
        return self.unlimitedRecentStickers ? 200 : 20
    }

    public static var disableNumberRounding: Bool {
        return FullGramExtras.shared.disableNumberRounding
    }

    public static func fullCountString(_ count: Int64) -> String {
        let negative = count < 0
        let digits = Array(String(count.magnitude))
        var result = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 {
                result.append(" ")
            }
            result.append(digit)
        }
        return negative ? "-" + result : result
    }
}

public enum FullGramLocalPremium {
    public static func isLocalOnlyPremium(peerId: PeerId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let state = self.states[peerId] {
            return (state.local || FullGramExtras.shared.localPremium) && !state.server
        }
        return FullGramExtras.shared.localPremium
    }
    private struct State {
        var local = false
        var server = false
    }

    private static let lock = NSLock()
    private static var states: [PeerId: State] = [:]

    public static let emojiUrlPrefix = "tg://emoji?id="

    public static func contains(_ peerId: PeerId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let state = self.states[peerId] {
            return state.local
        }
        return false
    }

    public static func update(peerId: PeerId, local: Bool? = nil, server: Bool? = nil) {
        self.lock.lock()
        defer { self.lock.unlock() }
        var state = self.states[peerId] ?? State()
        if let local { state.local = local }
        if let server { state.server = server }
        self.states[peerId] = state
    }

    public static func rewritesCustomEmoji(accountPeerId: PeerId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let state = self.states[accountPeerId] else { return false }
        return state.local && !state.server
    }

    public static func emojiFileId(url: String) -> Int64? {
        guard url.hasPrefix(self.emojiUrlPrefix) else { return nil }
        let digits = url.dropFirst(self.emojiUrlPrefix.count)
        guard !digits.isEmpty, digits.count <= 19, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int64(digits), id > 0 else { return nil }
        return id
    }

    public static func displayEntities(text: String, entities: [MessageTextEntity]) -> [MessageTextEntity] {
        guard entities.contains(where: { if case let .TextUrl(url) = $0.type { return url.hasPrefix(self.emojiUrlPrefix) } else { return false } }) else {
            return entities
        }
        let nsText = text as NSString
        return entities.map { entity in
            guard case let .TextUrl(url) = entity.type, let fileId = self.emojiFileId(url: url) else { return entity }
            let range = NSRange(location: entity.range.lowerBound, length: entity.range.upperBound - entity.range.lowerBound)
            guard range.location >= 0, range.length > 0, range.upperBound <= nsText.length, self.isSingleEmoji(nsText.substring(with: range)) else { return entity }
            return MessageTextEntity(range: entity.range, type: .CustomEmoji(stickerPack: nil, fileId: fileId))
        }
    }

    static func outgoingEntities(_ entities: [MessageTextEntity], accountPeerId: PeerId, peerId: PeerId) -> [MessageTextEntity] {
        guard peerId != accountPeerId, entities.contains(where: { if case .CustomEmoji = $0.type { return true } else { return false } }), self.rewritesCustomEmoji(accountPeerId: accountPeerId) else {
            return entities
        }
        return entities.map { entity in
            guard case let .CustomEmoji(_, fileId) = entity.type else { return entity }
            return MessageTextEntity(range: entity.range, type: .TextUrl(url: self.emojiUrlPrefix + "\(fileId)"))
        }
    }

    static func outgoingAttribute(_ attribute: TextEntitiesMessageAttribute, accountPeerId: PeerId, peerId: PeerId) -> TextEntitiesMessageAttribute {
        let entities = self.outgoingEntities(attribute.entities, accountPeerId: accountPeerId, peerId: peerId)
        return entities == attribute.entities ? attribute : TextEntitiesMessageAttribute(entities: entities)
    }

    private static func isSingleEmoji(_ string: String) -> Bool {
        guard string.count == 1, let first = string.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && string.unicodeScalars.count > 1)
    }
}

public func fullGramManageLocalPremium(postbox: Postbox, network: Network, peerId: PeerId) -> Signal<Void, NoError> {
    FullGramLocalPremium.update(peerId: peerId, local: FullGramExtras.shared.localPremium)
    let localSignal = Signal<Bool, NoError> { subscriber in
        subscriber.putNext(FullGramExtras.shared.localPremium)
        let observer = NotificationCenter.default.addObserver(forName: FullGramExtras.didChangeNotification, object: nil, queue: nil) { _ in
            subscriber.putNext(FullGramExtras.shared.localPremium)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
    |> map { value -> Void in
        FullGramLocalPremium.update(peerId: peerId, local: value)
    }
    let server = postbox.peerView(id: peerId)
    |> map { view -> Bool in view.peers[peerId]?.isServerPremium ?? false }
    |> distinctUntilChanged
    |> map { value -> Void in FullGramLocalPremium.update(peerId: peerId, server: value) }
    return combineLatest(localSignal, server) |> map { _ in }
}

public enum FullGramActivityFilter {
    public enum Kind: String, CaseIterable {
        case typing
        case recordingVoice
        case choosingSticker
        case uploadingFile
        case uploadingPhoto
        case uploadingVideo
        case playingGame
        case watchingEmoji
        case recordingVideoMessage
        case uploadingVideoMessage

        public var titleRu: String {
            switch self {
            case .typing: return "печатает"
            case .recordingVoice: return "записывает голосовое"
            case .choosingSticker: return "выбирает стикер"
            case .uploadingFile: return "отправляет файл"
            case .uploadingPhoto: return "отправляет фото"
            case .uploadingVideo: return "отправляет видео"
            case .playingGame: return "играет"
            case .watchingEmoji: return "смотрит анимацию эмодзи"
            case .recordingVideoMessage: return "записывает кружок"
            case .uploadingVideoMessage: return "отправляет кружок"
            }
        }
    }

    private static let key = "fullgram.activity.hidden"
    private static let lock = NSLock()
    private static var cache: Set<String>?

    public static var hidden: Set<Kind> {
        lock.lock()
        defer { lock.unlock() }
        if cache == nil {
            cache = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        }
        return Set((cache ?? []).compactMap(Kind.init(rawValue:)))
    }

    public static func isHidden(_ kind: Kind) -> Bool {
        return self.hidden.contains(kind)
    }

    public static func setHidden(_ kind: Kind, _ value: Bool) {
        lock.lock()
        var set = cache ?? Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if value {
            set.insert(kind.rawValue)
        } else {
            set.remove(kind.rawValue)
        }
        cache = set
        lock.unlock()
        UserDefaults.standard.set(Array(set), forKey: key)
        NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: key)
    }

    static func kind(_ activity: PeerInputActivity) -> Kind? {
        switch activity {
        case .typingText: return .typing
        case .recordingVoice: return .recordingVoice
        case .choosingSticker: return .choosingSticker
        case .uploadingFile: return .uploadingFile
        case .uploadingPhoto: return .uploadingPhoto
        case .uploadingVideo: return .uploadingVideo
        case .playingGame: return .playingGame
        case .seeingEmojiInteraction, .interactingWithEmoji: return .watchingEmoji
        case .recordingInstantVideo: return .recordingVideoMessage
        case .uploadingInstantVideo: return .uploadingVideoMessage
        case .speakingInGroupCall: return nil
        }
    }

    public static func isHidden(_ activity: PeerInputActivity) -> Bool {
        guard let mapped = kind(activity) else { return false }
        lock.lock()
        defer { lock.unlock() }
        if cache == nil {
            cache = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        }
        guard let cache, !cache.isEmpty else { return false }
        return cache.contains(mapped.rawValue)
    }
}

public enum FullGramChatPrivacy {
    public static let didChangeNotification = Notification.Name("FullGram.ChatPrivacyChanged")
    public static let didRelockNotification = Notification.Name("FullGram.ChatPrivacyDidRelock")
    private static let legacyEnabledKey = "fullgram.privacy.faceIdEnabled"
    private static let legacyLockedKey = "fullgram.privacy.lockedChats"
    private static let keychainService = "FullGram.ChatPrivacy"
    private static let keychainEnabledAccount = "faceIdEnabled"
    private static let keychainLockedAccount = "lockedChats"
    private static let lock = NSLock()
    private static var lockedCache: Set<Int64>?
    private static var enabledCache: Bool?
    private static var unlocked: Set<Int64> = []
    private static var migrated = false

    private static func keychainReadWithStatus(account: String) -> (data: Data?, status: OSStatus) {
        return FullGramCoreKeychain.readWithStatus(service: keychainService, account: account)
    }

    private static func keychainWrite(_ data: Data, account: String) {
        FullGramCoreKeychain.write(data, service: keychainService, account: account)
    }

    private static func migrateFromLegacyDefaultsIfNeededLocked() {
        guard !migrated else { return }
        migrated = true
        let defaults = UserDefaults.standard
        if defaults.object(forKey: legacyEnabledKey) != nil {
            let val = defaults.bool(forKey: legacyEnabledKey)
            keychainWrite(Data([val ? 1 : 0]), account: keychainEnabledAccount)
            enabledCache = val
            defaults.removeObject(forKey: legacyEnabledKey)
        }
        if let legacy = defaults.array(forKey: legacyLockedKey) as? [NSNumber] {
            let ids = Set(legacy.map { $0.int64Value })
            if let data = try? JSONEncoder().encode(Array(ids).sorted()) {
                keychainWrite(data, account: keychainLockedAccount)
            }
            lockedCache = ids
            defaults.removeObject(forKey: legacyLockedKey)
        }
    }

    private static func loadLocked() -> (ids: Set<Int64>, authoritative: Bool) {
        migrateFromLegacyDefaultsIfNeededLocked()
        let res = keychainReadWithStatus(account: keychainLockedAccount)
        if res.status == errSecSuccess, let data = res.data,
           let ids = try? JSONDecoder().decode([Int64].self, from: data) {
            return (Set(ids), true)
        }
        if res.status == errSecItemNotFound {
            return ([], true)
        }
        // Transient Keychain error (e.g. errSecInteractionNotAllowed): do not cache empty set.
        return ([], false)
    }

    private static func saveLocked(_ value: Set<Int64>) {
        if let data = try? JSONEncoder().encode(value.sorted()) {
            keychainWrite(data, account: keychainLockedAccount)
        }
    }

    public static var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            migrateFromLegacyDefaultsIfNeededLocked()
            if let cached = enabledCache { return cached }
            let res = keychainReadWithStatus(account: keychainEnabledAccount)
            if res.status == errSecSuccess, let data = res.data, let first = data.first {
                let val = first != 0
                enabledCache = val
                return val
            }
            if res.status == errSecItemNotFound {
                enabledCache = true
            }
            return true
        }
        set {
            lock.lock()
            enabledCache = newValue
            keychainWrite(Data([newValue ? 1 : 0]), account: keychainEnabledAccount)
            lock.unlock()
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
            NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: legacyEnabledKey)
        }
    }

    public static var locked: Set<Int64> {
        lock.lock()
        defer { lock.unlock() }
        if let cached = lockedCache { return cached }
        let loaded = loadLocked()
        if loaded.authoritative {
            lockedCache = loaded.ids
        }
        return loaded.ids
    }

    public static func isLocked(_ peerId: Int64) -> Bool {
        guard isEnabled else { return false }
        return locked.contains(peerId)
    }

    public static func setLocked(_ peerId: Int64, _ value: Bool) {
        lock.lock()
        var set = lockedCache ?? loadLocked().ids
        if value {
            set.insert(peerId)
        } else {
            set.remove(peerId)
            unlocked.remove(peerId)
        }
        lockedCache = set
        saveLocked(set)
        lock.unlock()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: legacyLockedKey)
    }

    public static func isUnlocked(_ peerId: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return unlocked.contains(peerId)
    }

    public static func markUnlocked(_ peerId: Int64) {
        lock.lock()
        unlocked.insert(peerId)
        lock.unlock()
    }

    public static func relock(peerId: Int64) {
        lock.lock()
        let removed = unlocked.remove(peerId) != nil
        lock.unlock()
        if removed {
            NotificationCenter.default.post(name: didRelockNotification, object: peerId)
        }
    }

    public static func relock() {
        lock.lock()
        unlocked.removeAll()
        lock.unlock()
        NotificationCenter.default.post(name: didRelockNotification, object: nil)
    }
}

public enum FullGramPaidAds {
    private static let results: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 4096
        return cache
    }()

    public static func isAd(_ text: String, messageKey: String, version: UInt32) -> Bool {
        let key = "\(messageKey):\(version):\(text.hashValue)" as NSString
        if let value = results.object(forKey: key) { return value.boolValue }
        let value = isAd(text)
        results.setObject(NSNumber(value: value), forKey: key)
        return value
    }

    private static let pattern = try? NSRegularExpression(
        pattern: "(\\berid\\b|#реклама|\\bреклама\\b|на правах рекламы|\\bинн\\s*[:№]?\\s*\\d{10,12}|\\bооо\\s+[«\"]|\\bогрн|рекламодатель|#ad\\b|#sponsored|\\bsponsored\\b)",
        options: [.caseInsensitive]
    )

    public static func isAd(_ text: String) -> Bool {
        guard !text.isEmpty, let pattern else { return false }
        return pattern.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }
}

public func fullGramManageDisplayOptions(network: Network, peerId: PeerId) -> Signal<Void, NoError> {
    let rawPeerId = peerId.toInt64()
    return network.fullGramGhostMode.signal
    |> map { settings in
        FullGramDisplayOptions.update(
            peerId: rawPeerId,
            hideStickerTime: settings.interface.hideStickerTime,
            unlimitedRecentStickers: settings.interface.unlimitedRecentStickers,
            hideFastShare: settings.interface.hideFastShare,
            reactionDisplay: settings.reactionDisplay
        )
    }
}

public struct FullGramGhostModeSettings: Codable, Equatable {
    public enum SilentSendMode: String, Codable {
        case never
        case inGhostMode
        case always
    }

    public var hideReadReceipts: Bool
    public var hideOnline: Bool
    public var hideTyping: Bool
    public var hideUploadProgress: Bool
    public var silentSendMode: SilentSendMode
    public var markReadAfterSend: Bool
    /// Chats where Ghost Mode never applies: read receipts, typing, and upload progress are sent normally.
    public var exceptionPeerIds: [Int64]
    public var interface: FullGramInterfaceSettings
    public var reactionDisplay: FullGramReactionDisplaySettings
    public var translation: FullGramTranslationSettings

    private enum CodingKeys: String, CodingKey {
        case hideReadReceipts
        case hideOnline
        case hideTyping
        case hideUploadProgress
        case silentSendMode
        case markReadAfterSend
        case exceptionPeerIds
        case interface
        case reactionDisplay
        case translation
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.hideReadReceipts = try values.decodeIfPresent(Bool.self, forKey: .hideReadReceipts) ?? false
        self.hideOnline = try values.decodeIfPresent(Bool.self, forKey: .hideOnline) ?? false
        self.hideTyping = try values.decodeIfPresent(Bool.self, forKey: .hideTyping) ?? false
        self.hideUploadProgress = try values.decodeIfPresent(Bool.self, forKey: .hideUploadProgress) ?? false
        self.silentSendMode = (try? values.decode(SilentSendMode.self, forKey: .silentSendMode)) ?? .never
        self.markReadAfterSend = try values.decodeIfPresent(Bool.self, forKey: .markReadAfterSend) ?? false
        self.exceptionPeerIds = Array(Set((try? values.decodeIfPresent([Int64].self, forKey: .exceptionPeerIds)) ?? [])).sorted().prefix(2000).map { $0 }
        self.interface = (try? values.decodeIfPresent(FullGramInterfaceSettings.self, forKey: .interface)) ?? FullGramInterfaceSettings()
        self.reactionDisplay = (try? values.decodeIfPresent(FullGramReactionDisplaySettings.self, forKey: .reactionDisplay)) ?? FullGramReactionDisplaySettings()
        self.translation = (try? values.decodeIfPresent(FullGramTranslationSettings.self, forKey: .translation)) ?? FullGramTranslationSettings()
    }

    public init(
        hideReadReceipts: Bool = false,
        hideOnline: Bool = false,
        hideTyping: Bool = false,
        hideUploadProgress: Bool = false,
        silentSendMode: SilentSendMode = .never,
        markReadAfterSend: Bool = false,
        exceptionPeerIds: [Int64] = [],
        interface: FullGramInterfaceSettings = FullGramInterfaceSettings(),
        reactionDisplay: FullGramReactionDisplaySettings = FullGramReactionDisplaySettings(),
        translation: FullGramTranslationSettings = FullGramTranslationSettings()
    ) {
        self.hideReadReceipts = hideReadReceipts
        self.hideOnline = hideOnline
        self.hideTyping = hideTyping
        self.hideUploadProgress = hideUploadProgress
        self.silentSendMode = silentSendMode
        self.markReadAfterSend = markReadAfterSend
        self.exceptionPeerIds = exceptionPeerIds
        self.interface = interface
        self.reactionDisplay = reactionDisplay
        self.translation = translation
    }

    public var allEnabled: Bool {
        return self.hideReadReceipts && self.hideOnline && self.hideTyping && self.hideUploadProgress
    }

    public var isActive: Bool {
        return self.hideReadReceipts || self.hideOnline || self.hideTyping || self.hideUploadProgress
    }

    public var shouldSendSilently: Bool {
        switch self.silentSendMode {
        case .never:
            return false
        case .inGhostMode:
            return self.isActive
        case .always:
            return true
        }
    }

    public mutating func setAllEnabled(_ enabled: Bool) {
        self.hideReadReceipts = enabled
        self.hideOnline = enabled
        self.hideTyping = enabled
        self.hideUploadProgress = enabled
    }

    public func isExcepted(peerId: Int64) -> Bool {
        return self.exceptionPeerIds.contains(peerId)
    }

    public mutating func setException(_ excepted: Bool, peerId: Int64) {
        var set = Set(self.exceptionPeerIds)
        if excepted {
            set.insert(peerId)
        } else {
            set.remove(peerId)
        }
        self.exceptionPeerIds = Array(set).sorted().suffix(2000).map { $0 }
    }

    public func effective(forPeer peerId: Int64) -> FullGramGhostModeSettings {
        var copy = self
        if self.isExcepted(peerId: peerId) {
            copy.hideReadReceipts = false
            copy.hideTyping = false
            copy.hideUploadProgress = false
        }
        return copy
    }
}

public final class FullGramGhostModeStore {
    private let lock = NSRecursiveLock()
    private let fileURL: URL
    private var value: FullGramGhostModeSettings
    private var observers: [UUID: (FullGramGhostModeSettings) -> Void] = [:]
    private let observationQueue = DispatchQueue(label: "FullGram.GhostModeNotifications")
    public let hadLoadError: Bool

    public init(accountPath: String) {
        self.fileURL = URL(fileURLWithPath: accountPath).appendingPathComponent("fullgram-ghost-mode.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                self.value = try JSONDecoder().decode(FullGramGhostModeSettings.self, from: Data(contentsOf: self.fileURL))
                self.hadLoadError = false
            } catch {
                self.value = FullGramGhostModeSettings()
                self.hadLoadError = true
            }
        } else {
            self.value = FullGramGhostModeSettings()
            self.hadLoadError = false
        }
    }

    public var current: FullGramGhostModeSettings {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }

    public func update(_ transform: (inout FullGramGhostModeSettings) throws -> Void) throws {
        self.lock.lock()
        defer { self.lock.unlock() }
        var updated = self.value
        try transform(&updated)
        guard updated != self.value else { return }
        let data = try JSONEncoder().encode(updated)
        #if os(iOS)
        try data.write(to: self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: self.fileURL, options: .atomic)
        #endif
        self.value = updated
        let observers = Array(self.observers.values)
        let committed = updated
        self.observationQueue.async {
            for observer in observers {
                observer(committed)
            }
        }
    }

    func observe(_ observer: @escaping (FullGramGhostModeSettings) -> Void) -> UUID {
        self.lock.lock()
        defer { self.lock.unlock() }
        let id = UUID()
        self.observers[id] = observer
        let initial = self.value
        self.observationQueue.async {
            observer(initial)
        }
        return id
    }

    func removeObserver(_ id: UUID) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.observers.removeValue(forKey: id)
    }

    public var signal: Signal<FullGramGhostModeSettings, NoError> {
        return Signal { subscriber in
            let id = self.observe { settings in
                subscriber.putNext(settings)
            }
            return ActionDisposable {
                self.removeObserver(id)
            }
        }
        |> distinctUntilChanged
    }
}

extension Network {
    func fullGramReassertOfflineAfterSending() {
        guard self.fullGramGhostMode.current.hideOnline else {
            return
        }
        let _ = (deferred { () -> Signal<Api.Bool, MTRpcError> in
            guard self.fullGramGhostMode.current.hideOnline else {
                return .complete()
            }
            return self.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .complete()
        }).startStandalone()
    }

    func requestFullGramCloudRead<T>(_ data: (FunctionDescription, Buffer, DeserializeFunctionResponse<T>), peerId: Int64? = nil) -> Signal<T, MTRpcError> {
        return deferred {
            let settings = self.fullGramGhostMode.current
            if (peerId.map { settings.effective(forPeer: $0) } ?? settings).hideReadReceipts {
                return .complete()
            }
            return self.request(data)
        }
    }
}

func fullGramSuppressInputActivity(_ activity: PeerInputActivity, settings: FullGramGhostModeSettings) -> Bool {
    if FullGramActivityFilter.isHidden(activity) {
        return true
    }
    switch activity {
    case .uploadingFile, .uploadingPhoto, .uploadingVideo, .uploadingInstantVideo:
        return settings.hideUploadProgress
    case .typingText, .recordingVoice, .recordingInstantVideo, .choosingSticker:
        return settings.hideTyping
    default:
        return false
    }
}

func fullGramMarkReadAfterSending(postbox: Postbox, network: Network, stateManager: AccountStateManager, messages: [Message]) {
    guard network.fullGramGhostMode.current.markReadAfterSend,
          let first = messages.first,
          first.id.peerId.namespace != Namespaces.Peer.SecretChat,
          messages.allSatisfy({ $0.id.peerId == first.id.peerId && $0.threadId == nil && !$0.attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute }) }) else {
        return
    }
    let peerId = first.id.peerId
    let _ = (postbox.transaction { transaction -> (Peer, MessageIndex)? in
        guard let peer = transaction.getPeer(peerId),
              !peer.isForumOrMonoForum,
              peerKeepsReadState(peer),
              let index = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud) else {
            return nil
        }
        return (peer, index)
    }
    |> mapToSignal { value -> Signal<Void, NoError> in
        guard let (peer, index) = value,
              network.fullGramGhostMode.current.markReadAfterSend,
              let input = apiInputPeer(peer) else {
            return .complete()
        }
        let receipt: Signal<Bool, NoError>
        if let channel = apiInputChannel(peer) {
            receipt = network.request(Api.functions.channels.readHistory(channel: channel, maxId: index.id.id), automaticFloodWait: false)
            |> map { _ in true }
            |> `catch` { _ in .single(false) }
        } else {
            receipt = network.request(Api.functions.messages.readHistory(peer: input, maxId: index.id.id), automaticFloodWait: false)
            |> map { result -> Bool in
                switch result {
                case let .affectedMessages(data):
                    stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
                }
                return true
            }
            |> `catch` { _ in .single(false) }
        }
        return receipt
        |> mapToSignal { accepted -> Signal<Void, NoError> in
            guard accepted else {
                return .complete()
            }
            network.fullGramReassertOfflineAfterSending()
            return _internal_applyMaxReadIndexInteractively(postbox: postbox, stateManager: stateManager, index: index)
        }
    }).startStandalone()
}

public final class FullGramExtras: @unchecked Sendable {
    public static let shared = FullGramExtras()

    private let defaults = UserDefaults.standard
    private let prefix = "fullgram.extras."
    private let cacheLock = NSLock()
    private var boolCache: [String: Bool] = [:]
    private var intCache: [String: Int] = [:]
    private var stringCache: [String: String] = [:]

    private func bool(_ key: String, default fallback: Bool = false) -> Bool {
        self.cacheLock.lock()
        if let cached = self.boolCache[key] {
            self.cacheLock.unlock()
            return cached
        }
        let full = prefix + key
        let resolved: Bool = (defaults.object(forKey: full) == nil) ? fallback : defaults.bool(forKey: full)
        self.boolCache[key] = resolved
        self.cacheLock.unlock()
        return resolved
    }

    private func setBool(_ key: String, _ value: Bool) {
        self.cacheLock.lock()
        let prev = self.boolCache[key]
        self.boolCache[key] = value
        self.cacheLock.unlock()
        if prev != value || defaults.object(forKey: prefix + key) == nil {
            defaults.set(value, forKey: prefix + key)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: key)
        }
    }

    private func int(_ key: String, default fallback: Int = 0) -> Int {
        self.cacheLock.lock()
        if let cached = self.intCache[key] {
            self.cacheLock.unlock()
            return cached
        }
        let full = prefix + key
        let resolved: Int = (defaults.object(forKey: full) == nil) ? fallback : defaults.integer(forKey: full)
        self.intCache[key] = resolved
        self.cacheLock.unlock()
        return resolved
    }

    private func setInt(_ key: String, _ value: Int) {
        self.cacheLock.lock()
        let prev = self.intCache[key]
        self.intCache[key] = value
        self.cacheLock.unlock()
        if prev != value || defaults.object(forKey: prefix + key) == nil {
            defaults.set(value, forKey: prefix + key)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: key)
        }
    }

    private func string(_ key: String, default fallback: String = "") -> String {
        self.cacheLock.lock()
        if let cached = self.stringCache[key] {
            self.cacheLock.unlock()
            return cached
        }
        let resolved = defaults.string(forKey: prefix + key) ?? fallback
        self.stringCache[key] = resolved
        self.cacheLock.unlock()
        return resolved
    }

    private func setString(_ key: String, _ value: String) {
        self.cacheLock.lock()
        self.stringCache[key] = value
        self.cacheLock.unlock()
        defaults.set(value, forKey: prefix + key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: key)
    }

    public static let didChangeNotification = Notification.Name("FullGramExtrasDidChange")

    // MARK: - Обход ограничений (Одноразовые фото/видео/кружки)

    public var saveViewOnce: Bool {
        get { bool("saveViewOnce", default: false) }
        set { setBool("saveViewOnce", newValue) }
    }

    public var viewOnceMenuSave: Bool {
        get { bool("viewOnceMenuSave", default: true) }
        set { setBool("viewOnceMenuSave", newValue) }
    }

    public var viewOnceKeepInChat: Bool {
        get { bool("viewOnceKeepInChat", default: false) }
        set { setBool("viewOnceKeepInChat", newValue) }
    }

    public var viewOnceReview: Bool {
        get { bool("viewOnceReview", default: false) }
        set { setBool("viewOnceReview", newValue) }
    }

    // MARK: - Сообщение (бывшее «Отправка»)

    public var antiCaps: Bool {
        get { bool("antiCaps", default: false) }
        set { setBool("antiCaps", newValue) }
    }

    public var translateBeforeSend: Bool {
        get { bool("translateBeforeSend", default: false) }
        set { setBool("translateBeforeSend", newValue) }
    }

    public var translateTo: String {
        get { string("translateTo", default: "en") }
        set { setString("translateTo", newValue) }
    }

    public var cleanLinks: Bool {
        get { bool("cleanLinks", default: true) }
        set { setBool("cleanLinks", newValue) }
    }

    public var undoSendSeconds: Int {
        get { int("undoSendSeconds", default: 0) }
        set { setInt("undoSendSeconds", max(0, min(3600, newValue))) }
    }

    public var quickFormattingBar: Bool {
        get { bool("quickFormattingBar", default: true) }
        set { setBool("quickFormattingBar", newValue) }
    }

    // MARK: - Приватность → Деятельность и следы (1.2, 1.4, 1.5)

    public var alwaysOnline: Bool {
        get { bool("alwaysOnline", default: false) }
        set { setBool("alwaysOnline", newValue) }
    }

    public var confirmCalls: Bool {
        get { bool("confirmCalls", default: false) }
        set { setBool("confirmCalls", newValue) }
    }

    public var removePhotoMetadata: Bool {
        get {
            if defaults.object(forKey: prefix + "removePhotoMetadata") != nil {
                return bool("removePhotoMetadata", default: false)
            }
            return bool("spoofPhotoMetadata", default: false)
        }
        set {
            setBool("spoofPhotoMetadata", newValue)
            setBool("removePhotoMetadata", newValue)
        }
    }

    public var randomFileNames: Bool {
        get { bool("randomFileNames", default: false) }
        set { setBool("randomFileNames", newValue) }
    }

    // MARK: - Безопасность (3.1, 3.2, 3.3)

    public var hidePhoneNumber: Bool {
        get { bool("hidePhoneNumber", default: false) }
        set { setBool("hidePhoneNumber", newValue) }
    }

    public var blurInAppSwitcher: Bool {
        get { bool("blurInAppSwitcher", default: false) }
        set { setBool("blurInAppSwitcher", newValue) }
    }

    // MARK: - Прочее (4.1, 4.2, 4.3)

    public var localPremium: Bool {
        get { bool("localPremium", default: false) }
        set { setBool("localPremium", newValue) }
    }

    public var disableNumberRounding: Bool {
        get { bool("disableNumberRounding", default: false) }
        set { setBool("disableNumberRounding", newValue) }
    }

    public var showMessageSeconds: Bool {
        get { bool("showMessageSeconds", default: false) }
        set { setBool("showMessageSeconds", newValue) }
    }

    public var showPeerIds: Bool {
        get { bool("showPeerIds", default: false) }
        set { setBool("showPeerIds", newValue) }
    }

    public var hidePaidAds: Bool {
        get { bool("hidePaidAds", default: false) }
        set { setBool("hidePaidAds", newValue) }
    }

    public var dimRepliesToMe: Bool {
        get { bool("dimRepliesToMe", default: false) }
        set { setBool("dimRepliesToMe", newValue) }
    }

    public var dimDeletedMessages: Bool {
        get { bool("dimDeletedMessages", default: true) }
        set { setBool("dimDeletedMessages", newValue) }
    }

    public var deletedMessageOpacityPercent: Int {
        get { max(5, min(95, int("deletedMessageOpacityPercent", default: 52))) }
        set { setInt("deletedMessageOpacityPercent", max(5, min(95, newValue))) }
    }

    public var deletedMessageAlpha: CGFloat {
        return CGFloat(self.deletedMessageOpacityPercent) / 100.0
    }

    public var trackOnLockScreen: Bool {
        get { bool("trackOnLockScreen", default: true) }
        set { setBool("trackOnLockScreen", newValue) }
    }

    public var noAutoplayNextVoice: Bool {
        get { bool("noAutoplayNextVoice", default: false) }
        set { setBool("noAutoplayNextVoice", newValue) }
    }

    public var keepScreenOnInPlayer: Bool {
        get { bool("keepScreenOnInPlayer", default: false) }
        set { setBool("keepScreenOnInPlayer", newValue) }
    }

    public var keepScreenOnInVoice: Bool {
        get { bool("keepScreenOnInVoice", default: false) }
        set { setBool("keepScreenOnInVoice", newValue) }
    }

    public var downloadBoost: Bool {
        get {
            if defaults.object(forKey: prefix + "downloadBoost") != nil {
                return bool("downloadBoost", default: false)
            }
            return bool("downloadSpeedBoost", default: false)
        }
        set { setBool("downloadBoost", newValue) }
    }

    public static let downloadBoostMultiplierOptions: [Int] = [2, 3, 4, 6, 8]

    public var downloadBoostMultiplier: Int {
        get {
            let stored = int("downloadBoostMultiplier", default: 2)
            return Self.downloadBoostMultiplierOptions.contains(stored) ? stored : 2
        }
        set {
            let sanitized = Self.downloadBoostMultiplierOptions.contains(newValue) ? newValue : 2
            setInt("downloadBoostMultiplier", sanitized)
        }
    }

    public var localFreeTranscription: Bool {
        get { bool("localFreeTranscription", default: true) }
        set { setBool("localFreeTranscription", newValue) }
    }

    // MARK: - FullGram v1.6.1 Features

    public var audioTrimSpliceBeforeSend: Bool {
        get { bool("audioTrimSpliceBeforeSend", default: false) }
        set { setBool("audioTrimSpliceBeforeSend", newValue) }
    }

    public var confirmSendBeforePosting: Bool {
        get { bool("confirmSendBeforePosting", default: true) }
        set { setBool("confirmSendBeforePosting", newValue) }
    }

    public var confirmSendForAllChats: Bool {
        get { bool("confirmSendForAllChats", default: false) }
        set { setBool("confirmSendForAllChats", newValue) }
    }

    public var videoSubtitlesEnabled: Bool {
        get { bool("videoSubtitlesEnabled", default: true) }
        set { setBool("videoSubtitlesEnabled", newValue) }
    }

    public var renameFileBeforeSend: Bool {
        get { bool("renameFileBeforeSend", default: false) }
        set { setBool("renameFileBeforeSend", newValue) }
    }

    public var smartTransferQueue: Bool {
        get { bool("smartTransferQueue", default: true) }
        set { setBool("smartTransferQueue", newValue) }
    }

    public var autoResumeDownloadsOnReconnect: Bool {
        get { bool("autoResumeDownloadsOnReconnect", default: true) }
        set { setBool("autoResumeDownloadsOnReconnect", newValue) }
    }

    public var autoCropScreenshots: Bool {
        get { bool("autoCropScreenshots", default: false) }
        set { setBool("autoCropScreenshots", newValue) }
    }

    public var chooseVideoNoteCoverBeforeSend: Bool {
        get { bool("chooseVideoNoteCoverBeforeSend", default: false) }
        set { setBool("chooseVideoNoteCoverBeforeSend", newValue) }
    }

    public var editForwardedBeforeSend: Bool {
        get { bool("editForwardedBeforeSend", default: false) }
        set { setBool("editForwardedBeforeSend", newValue) }
    }

    public var autoCleanTempCaches: Bool {
        get { bool("autoCleanTempCaches", default: true) }
        set { setBool("autoCleanTempCaches", newValue) }
    }

    public var confirmSendPeerIds: Set<Int64> {
        get {
            let key = prefix + "confirmSendPeerIds"
            guard let arr = defaults.array(forKey: key) as? [NSNumber] else {
                return []
            }
            return Set(arr.map { $0.int64Value })
        }
        set {
            let key = prefix + "confirmSendPeerIds"
            defaults.set(newValue.sorted().map { NSNumber(value: $0) }, forKey: key)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: "confirmSendPeerIds")
        }
    }

    public func isConfirmSendChat(_ peerId: Int64) -> Bool {
        return self.confirmSendPeerIds.contains(peerId)
    }

    public func setConfirmSendChat(_ peerId: Int64, enabled: Bool) {
        var current = self.confirmSendPeerIds
        if enabled {
            current.insert(peerId)
        } else {
            current.remove(peerId)
        }
        self.confirmSendPeerIds = current
    }

    @discardableResult
    public func toggleConfirmSendChat(_ peerId: Int64) -> Bool {
        let next = !self.isConfirmSendChat(peerId)
        self.setConfirmSendChat(peerId, enabled: next)
        return next
    }

    public enum ConfirmSendMediaKind: String, CaseIterable, Sendable {
        case text
        case voice
        case videoNote
        case video
        case file
    }

    public var confirmSendText: Bool {
        get { bool("confirmSendText", default: true) }
        set { setBool("confirmSendText", newValue) }
    }

    public var confirmSendVoice: Bool {
        get { bool("confirmSendVoice", default: true) }
        set { setBool("confirmSendVoice", newValue) }
    }

    public var confirmSendVideoNotes: Bool {
        get { bool("confirmSendVideoNotes", default: true) }
        set { setBool("confirmSendVideoNotes", newValue) }
    }

    public var confirmSendVideo: Bool {
        get { bool("confirmSendVideo", default: true) }
        set { setBool("confirmSendVideo", newValue) }
    }

    public var confirmSendFiles: Bool {
        get { bool("confirmSendFiles", default: true) }
        set { setBool("confirmSendFiles", newValue) }
    }

    public func isConfirmSendKindEnabled(_ kind: ConfirmSendMediaKind) -> Bool {
        switch kind {
        case .text: return self.confirmSendText
        case .voice: return self.confirmSendVoice
        case .videoNote: return self.confirmSendVideoNotes
        case .video: return self.confirmSendVideo
        case .file: return self.confirmSendFiles
        }
    }

    public var archivePreviewWithoutDownload: Bool {
        get { bool("archivePreviewWithoutDownload", default: true) }
        set { setBool("archivePreviewWithoutDownload", newValue) }
    }

    public var builtInDocumentViewer: Bool {
        get { bool("builtInDocumentViewer", default: true) }
        set { setBool("builtInDocumentViewer", newValue) }
    }

    public var profileNFTBubbles: Bool {
        get { bool("profileNFTBubbles", default: true) }
        set { setBool("profileNFTBubbles", newValue) }
    }

    public var anonymousStoryViewing: Bool {
        get { bool("anonymousStoryViewing", default: false) }
        set { setBool("anonymousStoryViewing", newValue) }
    }

    public var allowStoryDownload: Bool {
        get { bool("allowStoryDownload", default: true) }
        set { setBool("allowStoryDownload", newValue) }
    }

    // MARK: - 10 Smart FullGram Features

    public var focusModeHideBadges: Bool {
        get { bool("focusModeHideBadges", default: false) }
        set { setBool("focusModeHideBadges", newValue) }
    }

    public var autoCleanCopiedLinks: Bool {
        get { bool("autoCleanCopiedLinks", default: true) }
        set { setBool("autoCleanCopiedLinks", newValue) }
    }

    public var disableEdgeSwipeBackInChat: Bool {
        get { bool("disableEdgeSwipeBackInChat", default: false) }
        set { setBool("disableEdgeSwipeBackInChat", newValue) }
    }

    public var autoLayoutFixCommand: Bool {
        get { bool("autoLayoutFixCommand", default: true) }
        set { setBool("autoLayoutFixCommand", newValue) }
    }

    public var turboVoiceSpeedEnabled: Bool {
        get { bool("turboVoiceSpeedEnabled", default: true) }
        set { setBool("turboVoiceSpeedEnabled", newValue) }
    }

    public var showComposeCharCounter: Bool {
        get { bool("showComposeCharCounter", default: true) }
        set { setBool("showComposeCharCounter", newValue) }
    }

    public var smartTypographyEnabled: Bool {
        get { bool("smartTypographyEnabled", default: false) }
        set { setBool("smartTypographyEnabled", newValue) }
    }

    public var incognitoLinkOpening: Bool {
        get { bool("incognitoLinkOpening", default: false) }
        set { setBool("incognitoLinkOpening", newValue) }
    }

    public var confirmScreenShareAndVideoCalls: Bool {
        get { bool("confirmScreenShareAndVideoCalls", default: false) }
        set { setBool("confirmScreenShareAndVideoCalls", newValue) }
    }

    public var quickBookmarksEnabled: Bool {
        get { bool("quickBookmarksEnabled", default: true) }
        set { setBool("quickBookmarksEnabled", newValue) }
    }

    public struct FullGramBookmark: Codable, Equatable, Sendable {
        public let id: String
        public let peerId: Int64
        public let peerTitle: String
        public let text: String
        public let timestamp: Int32

        public init(id: String = UUID().uuidString, peerId: Int64, peerTitle: String, text: String, timestamp: Int32 = Int32(Date().timeIntervalSince1970)) {
            self.id = id
            self.peerId = peerId
            self.peerTitle = peerTitle
            self.text = text
            self.timestamp = timestamp
        }
    }

    public var bookmarks: [FullGramBookmark] {
        get {
            guard let data = defaults.data(forKey: prefix + "bookmarks"),
                  let decoded = try? JSONDecoder().decode([FullGramBookmark].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(Array(newValue.prefix(200))) {
                defaults.set(encoded, forKey: prefix + "bookmarks")
                NotificationCenter.default.post(name: Self.didChangeNotification, object: "bookmarks")
            }
        }
    }

    public func addBookmark(peerId: Int64, peerTitle: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = self.bookmarks
        list.removeAll { $0.peerId == peerId && $0.text == trimmed }
        list.insert(FullGramBookmark(peerId: peerId, peerTitle: peerTitle, text: trimmed), at: 0)
        self.bookmarks = list
    }

    public func removeBookmark(id: String) {
        var list = self.bookmarks
        list.removeAll { $0.id == id }
        self.bookmarks = list
    }

    public func clearBookmarks() {
        self.bookmarks = []
    }

    public func applySmartTypography(_ text: String) -> String {
        guard self.smartTypographyEnabled, !text.isEmpty else { return text }
        var out = text
        out = out.replacingOccurrences(of: " -- ", with: " — ")
        out = out.replacingOccurrences(of: "...", with: "…")
        if out.contains("<<") && out.contains(">>") {
            out = out.replacingOccurrences(of: "<<", with: "«").replacingOccurrences(of: ">>", with: "»")
        }
        return out
    }

    public func applyAutoLayoutFixIfNeeded(_ text: String) -> String {
        guard self.autoLayoutFixCommand else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let prefixStr: String
        let body: String
        if trimmed.hasPrefix("!!") {
            prefixStr = "!!"
            body = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if trimmed.lowercased().hasPrefix(".fix ") {
            prefixStr = ".fix "
            body = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else {
            return text
        }
        guard !prefixStr.isEmpty, !body.isEmpty else { return text }
        let ruChars = Array("йцукенгшщзхъфывапролджэячсмитьбюёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮЁ")
        let enChars = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>~")
        let ruCount = body.filter { ruChars.contains($0) }.count
        let enCount = body.filter { enChars.contains($0) }.count
        let ruToEn = ruCount >= enCount
        var result = ""
        result.reserveCapacity(body.count)
        for ch in body {
            if ruToEn {
                if let idx = ruChars.firstIndex(of: ch) {
                    result.append(enChars[idx])
                } else {
                    result.append(ch)
                }
            } else {
                if let idx = enChars.firstIndex(of: ch) {
                    result.append(ruChars[idx])
                } else {
                    result.append(ch)
                }
            }
        }
        return result
    }

    public func addConfirmSendChat(_ peerId: Int64) {
        self.setConfirmSendChat(peerId, enabled: true)
    }

    public func removeConfirmSendChat(_ peerId: Int64) {
        self.setConfirmSendChat(peerId, enabled: false)
    }

    public func clearConfirmSendChats() {
        self.confirmSendPeerIds = []
    }

    public func shouldConfirmSend(forPeerId peerId: Int64) -> Bool {
        guard self.confirmSendBeforePosting else { return false }
        return self.confirmSendForAllChats || self.confirmSendPeerIds.contains(peerId)
    }

    public func shouldConfirmSend(forPeerId peerId: Int64, kind: ConfirmSendMediaKind) -> Bool {
        guard self.shouldConfirmSend(forPeerId: peerId) else { return false }
        return self.isConfirmSendKindEnabled(kind)
    }

    // MARK: - Оформление → Дизайн / Темы / Иконки (2.2, 2.3, 2.4)

    public var oledMode: Bool {
        get { bool("oledMode", default: false) }
        set { setBool("oledMode", newValue) }
    }

    public var classicDesign: Bool {
        get {
            guard FullGramFeatureFlags.isEnabled(.classicDesign) else { return false }
            return bool("classicDesign", default: false)
        }
        set {
            if newValue {
                FullGramDesignWatchdog.armPendingClassicDesign()
            } else {
                FullGramDesignWatchdog.clearPendingClassicDesign()
            }
            setBool("classicDesign", newValue)
        }
    }

    public var removeGlass: Bool {
        get { bool("removeGlass", default: false) }
        set { setBool("removeGlass", newValue) }
    }

    public var removeGlassColorHex: String? {
        get {
            let raw = string("removeGlassColorHex", default: "")
            return raw.isEmpty ? nil : raw
        }
        set {
            let cleaned = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            setString("removeGlassColorHex", cleaned)
        }
    }

    public var glowingReactions: Bool {
        get { bool("glowingReactions", default: true) }
        set { setBool("glowingReactions", newValue) }
    }

    public var monochromeAppIcons: Bool {
        get { bool("monochromeAppIcons", default: false) }
        set { setBool("monochromeAppIcons", newValue) }
    }

    // MARK: - Спойлеры, Анимация удаления и Приватный режим

    public var autoRevealSpoilers: Bool {
        get { bool("autoRevealSpoilers", default: false) }
        set { setBool("autoRevealSpoilers", newValue) }
    }

    public enum DeleteAnimationStyle: Int, CaseIterable, Sendable {
        case none = 0
        case paperTrash = 1
        case particles = 2
        case blackHole = 3
        case explosion = 4

        public func title(russian: Bool) -> String {
            switch self {
            case .none: return russian ? "Выкл." : "Off"
            case .paperTrash: return russian ? "Бумага в мусорку" : "Paper trash"
            case .particles: return russian ? "Частицы (пыль)" : "Particles"
            case .blackHole: return russian ? "Чёрная дыра" : "Black hole"
            case .explosion: return russian ? "Взрыв" : "Explosion"
            }
        }
    }

    public var deletePaperAnimation: Bool {
        get { bool("deletePaperAnimation", default: true) }
        set { setBool("deletePaperAnimation", newValue) }
    }

    public var skipSilenceInVoiceAndCircles: Bool {
        get { bool("skipSilenceInVoiceAndCircles", default: false) }
        set { setBool("skipSilenceInVoiceAndCircles", newValue) }
    }

    /// 0 means default player speed (use 1.0 / 1.25 / 1.5 / 1.75 / 2.0 / 2.5 when overridden)
    public var voicePlaybackSpeed: Float {
        get {
            let v = self.defaults.float(forKey: self.prefix + "voicePlaybackSpeed")
            return v > 0.1 ? v : 1.0
        }
        set {
            let clamped = max(0.5, min(2.5, newValue))
            self.defaults.set(clamped, forKey: self.prefix + "voicePlaybackSpeed")
            NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: nil)
        }
    }

    public var autoCleanCacheIntervalDays: Int {
        get { int("autoCleanCacheIntervalDays", default: 0) }
        set { setInt("autoCleanCacheIntervalDays", max(0, newValue)) }
    }

    public var autoCleanCacheMaxMB: Int {
        get { int("autoCleanCacheMaxMB", default: 0) }
        set { setInt("autoCleanCacheMaxMB", max(0, newValue)) }
    }

    public var lastAutoCacheCleanTimestamp: TimeInterval {
        get { self.defaults.double(forKey: self.prefix + "lastAutoCacheCleanTimestamp") }
        set { self.defaults.set(newValue, forKey: self.prefix + "lastAutoCacheCleanTimestamp") }
    }

    public var deleteAnimationStyle: DeleteAnimationStyle {
        get {
            if !self.deletePaperAnimation {
                return .none
            }
            let raw = int("deleteAnimationStyle", default: DeleteAnimationStyle.paperTrash.rawValue)
            return DeleteAnimationStyle(rawValue: raw) ?? .paperTrash
        }
        set {
            if newValue == .none {
                self.deletePaperAnimation = false
            } else {
                setInt("deleteAnimationStyle", newValue.rawValue)
                self.deletePaperAnimation = true
            }
        }
    }

    public var privateMode: Bool {
        get { bool("privateMode", default: false) }
        set { setBool("privateMode", newValue) }
    }

    public var privateModeHidePreviews: Bool {
        get { bool("privateModeHidePreviews", default: true) }
        set { setBool("privateModeHidePreviews", newValue) }
    }

    public var privateModeHideUsername: Bool {
        get { bool("privateModeHideUsername", default: true) }
        set { setBool("privateModeHideUsername", newValue) }
    }

    // MARK: - Screen Capture / Streamer Auto-Activation

    private final class ScreenCaptureMonitor: @unchecked Sendable {
        static let shared = ScreenCaptureMonitor()
        private let lock = NSLock()
        private var captured: Bool = false
        private var screenshotActiveUntil: CFAbsoluteTime = 0.0
        private var observers: [NSObjectProtocol] = []

        private init() {
            if Thread.isMainThread {
                self.captured = MainActor.assumeIsolated {
                    UIScreen.screens.contains { $0.isCaptured }
                }
            }
            let nc = NotificationCenter.default
            let c1 = nc.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshCapturedState()
                }
            }
            let c2 = nc.addObserver(forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main) { [weak self] _ in
                self?.triggerScreenshotGrace()
            }
            let c3 = nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshCapturedState()
                }
            }
            self.observers = [c1, c2, c3]
            Task { @MainActor [weak self] in
                self?.refreshCapturedState()
            }
        }

        deinit {
            for observer in self.observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        @MainActor
        private func refreshCapturedState() {
            let nowCaptured = UIScreen.screens.contains { $0.isCaptured }
            self.lock.lock()
            let changed = self.captured != nowCaptured
            self.captured = nowCaptured
            self.lock.unlock()
            if changed {
                NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: "screenCapture")
            }
        }

        private func triggerScreenshotGrace() {
            let until = CFAbsoluteTimeGetCurrent() + 10.0
            self.lock.lock()
            self.screenshotActiveUntil = until
            self.lock.unlock()
            NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: "screenCapture")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.2) { [weak self] in
                guard let self = self else { return }
                let now = CFAbsoluteTimeGetCurrent()
                self.lock.lock()
                let expired = now >= self.screenshotActiveUntil
                self.lock.unlock()
                if expired {
                    NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: "screenCapture")
                }
            }
        }

        var isActive: Bool {
            let now = CFAbsoluteTimeGetCurrent()
            self.lock.lock()
            let active = self.captured || now < self.screenshotActiveUntil
            self.lock.unlock()
            return active
        }
    }

    public var isScreenCaptureActive: Bool {
        guard FullGramFeatureFlags.isEnabled(.screenCapturePrivacy) else { return false }
        return ScreenCaptureMonitor.shared.isActive
    }

    public var shouldHidePhoneNumberNow: Bool {
        guard self.isScreenCaptureActive else { return false }
        return self.hidePhoneNumber || self.privateMode
    }

    public var shouldHidePreviewsNow: Bool {
        guard self.isScreenCaptureActive else { return false }
        return self.privateMode && self.privateModeHidePreviews
    }

    public var shouldHideUsernameNow: Bool {
        guard self.isScreenCaptureActive else { return false }
        return self.privateMode && self.privateModeHideUsername
    }

    // MARK: - Helpers for 1.4 (Удаление метаданных) and 1.5 (Случайные имена файлов)

    public func outgoingFileName(_ name: String) -> String {
        guard self.randomFileNames else { return name }
        let ext = (name as NSString).pathExtension.lowercased()
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let stem = String((0 ..< 10).map { _ in chars.randomElement()! })
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// Strips all EXIF, GPS, TIFF, IPTC, MakerApple, XMP and ICC metadata by re-rendering the bitmap
    /// in standard sRGB (baking pixel orientation) and normalizing container header fields.
    public static func strippedImageData(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= 25_000_000 else {
            return nil
        }
        return autoreleasepool {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source),
                  CGImageSourceGetCount(source) > 0 else {
                return nil
            }
            if let utType = UTType(type as String), !utType.conforms(to: .image) || utType.conforms(to: .gif) {
                return nil
            }
            guard let orientedImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            let width = orientedImage.width
            let height = orientedImage.height
            guard width > 0, height > 0 else { return nil }
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            let cleanImage: CGImage
            if let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) {
                ctx.draw(orientedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                cleanImage = ctx.makeImage() ?? orientedImage
            } else {
                cleanImage = orientedImage
            }
            let output = NSMutableData()
            let destType = UTType.jpeg.identifier as CFString
            guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, destType, 1, nil) else {
                return nil
            }
            // Explicitly remove metadata dictionaries and normalize technical container fields (orientation=1, 72 DPI)
            let nullRef: Any = kCFNull as Any
            let cleanProperties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.94,
                kCGImagePropertyOrientation: 1,
                kCGImagePropertyDPIWidth: 72,
                kCGImagePropertyDPIHeight: 72,
                kCGImagePropertyExifDictionary: nullRef,
                kCGImagePropertyGPSDictionary: nullRef,
                kCGImagePropertyTIFFDictionary: nullRef,
                kCGImagePropertyIPTCDictionary: nullRef,
                kCGImagePropertyExifAuxDictionary: nullRef,
                kCGImagePropertyMakerAppleDictionary: nullRef,
                kCGImageProperty8BIMDictionary: nullRef,
                kCGImagePropertyCIFFDictionary: nullRef,
                kCGImagePropertyJFIFDictionary: [
                    kCGImagePropertyJFIFDensityUnit: 1,
                    kCGImagePropertyJFIFXDensity: 72,
                    kCGImagePropertyJFIFYDensity: 72,
                    kCGImagePropertyJFIFVersion: [1, 1]
                ] as [CFString: Any]
            ]
            CGImageDestinationAddImage(destination, cleanImage, cleanProperties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                return nil
            }
            return output as Data
        }
    }

    /// Detects phone screenshots (by screen aspect ratio or filename) and crops off the iOS status bar
    /// (time, signal, battery indicator) at the top and home indicator at the bottom before sending.
    public static func autoCroppedScreenshotData(_ data: Data, fileName: String? = nil) -> (data: Data, dimensions: PixelDimensions)? {
        guard !data.isEmpty, data.count <= 25_000_000 else {
            return nil
        }
        return autoreleasepool {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: false
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source),
                  CGImageSourceGetCount(source) > 0 else {
                return nil
            }
            if let utType = UTType(type as String), !utType.conforms(to: .image) || utType.conforms(to: .gif) {
                return nil
            }
            guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            let width = oriented.width
            let height = oriented.height
            guard width >= 500, height > width else { return nil }

            let aspect = Double(height) / Double(width)
            let isModernIPhone = abs(aspect - (19.5 / 9.0)) < 0.09
            let isClassicIPhone = abs(aspect - (16.0 / 9.0)) < 0.05
            let lowerName = (fileName ?? "").lowercased()
            let namedScreenshot = lowerName.contains("screenshot") || lowerName.contains("снимок") || lowerName.hasPrefix("img_")
            guard isModernIPhone || (isClassicIPhone && namedScreenshot) else {
                return nil
            }

            let topRatio = isModernIPhone ? 0.054 : 0.032
            let bottomRatio = isModernIPhone ? 0.026 : 0.0
            let topCrop = Int(round(Double(height) * topRatio))
            let bottomCrop = Int(round(Double(height) * bottomRatio))
            let croppedHeight = height - topCrop - bottomCrop
            guard topCrop > 12, croppedHeight > height / 2,
                  let cropped = oriented.cropping(to: CGRect(x: 0, y: topCrop, width: width, height: croppedHeight)) else {
                return nil
            }

            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, cropped, [kCGImageDestinationLossyCompressionQuality: 0.94] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                return nil
            }
            return (output as Data, PixelDimensions(width: Int32(width), height: Int32(croppedHeight)))
        }
    }
}

public enum FullGramLinkCleaner {
    private static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id", "utm_name",
        "fbclid", "gclid", "dclid", "msclkid", "yclid", "ymclid", "twclid", "ttclid", "igshid",
        "mc_cid", "mc_eid", "ref_src", "ref_url", "_hsenc", "_hsmi", "mkt_tok", "si", "feature", "spm"
    ]

    public static func clean(_ text: String) -> String {
        guard !text.isEmpty, text.contains("://") else { return text }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return text }
        let nsText = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let raw = nsText.substring(with: match.range)
            if let cleaned = cleanSingleURL(raw), cleaned != raw {
                mutable.replaceCharacters(in: match.range, with: cleaned)
            }
        }
        return mutable as String
    }

    private static func cleanSingleURL(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw), let items = components.queryItems, !items.isEmpty else {
            return nil
        }
        let filtered = items.filter { item in
            let lower = item.name.lowercased()
            return !trackingParams.contains(lower) && !lower.hasPrefix("utm_")
        }
        guard filtered.count != items.count else { return nil }
        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.string
    }

    public static func cleanOutgoing(_ message: EnqueueMessage) -> EnqueueMessage {
        switch message {
        case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets):
            var newText = text
            var newAttributes = attributes
            var newMediaReference = mediaReference
            if FullGramExtras.shared.cleanLinks {
                let cleaned = Self.clean(newText)
                if cleaned != newText {
                    newText = cleaned
                    newAttributes = newAttributes.map { attr in
                        guard let entitiesAttr = attr as? TextEntitiesMessageAttribute else { return attr }
                        let filtered = entitiesAttr.entities.filter { entity in
                            switch entity.type {
                            case .Url: return false
                            default: return entity.range.upperBound <= (newText as NSString).length
                            }
                        }
                        return TextEntitiesMessageAttribute(entities: filtered)
                    }
                }
            }
            if let file = newMediaReference?.media as? TelegramMediaFile {
                var updatedAttributes = file.attributes
                var updatedResource = file.resource
                var updatedSize = file.size
                var modified = false
                if FullGramExtras.shared.randomFileNames {
                    updatedAttributes = updatedAttributes.map { attr in
                        if case let .FileName(fileName) = attr {
                            modified = true
                            return .FileName(fileName: FullGramExtras.shared.outgoingFileName(fileName))
                        }
                        return attr
                    }
                }
                if file.mimeType.hasPrefix("image/"), let localRef = updatedResource as? LocalFileReferenceMediaResource,
                   FileManager.default.fileExists(atPath: localRef.localFilePath) {
                    let fSize = ((try? FileManager.default.attributesOfItem(atPath: localRef.localFilePath))?[.size] as? NSNumber)?.int64Value ?? 0
                    if fSize > 0 && fSize <= 25_000_000,
                       var rawData = try? Data(contentsOf: URL(fileURLWithPath: localRef.localFilePath), options: .mappedIfSafe) {
                        var workingData: Data?
                        if FullGramExtras.shared.autoCropScreenshots,
                           let cropped = FullGramExtras.autoCroppedScreenshotData(rawData, fileName: file.fileName) {
                            rawData = cropped.data
                            workingData = cropped.data
                        }
                        if FullGramExtras.shared.removePhotoMetadata,
                           let stripped = FullGramExtras.strippedImageData(rawData) {
                            workingData = stripped
                        }
                        if let finalData = workingData {
                            let cleanPath = NSTemporaryDirectory() + "fg-clean-\(Int64.random(in: 1 ... Int64.max)).jpg"
                            if (try? finalData.write(to: URL(fileURLWithPath: cleanPath), options: .atomic)) != nil {
                                var randomId: Int64 = 0
                                arc4random_buf(&randomId, 8)
                                updatedResource = LocalFileReferenceMediaResource(localFilePath: cleanPath, randomId: randomId)
                                updatedSize = Int64(finalData.count)
                                modified = true
                            }
                        }
                    }
                }
                if modified {
                    let newFile = TelegramMediaFile(
                        fileId: file.fileId,
                        partialReference: file.partialReference,
                        resource: updatedResource,
                        previewRepresentations: file.previewRepresentations,
                        videoThumbnails: file.videoThumbnails,
                        immediateThumbnailData: file.immediateThumbnailData,
                        mimeType: file.mimeType,
                        size: updatedSize,
                        attributes: updatedAttributes,
                        alternativeRepresentations: file.alternativeRepresentations
                    )
                    newMediaReference = .standalone(media: newFile)
                }
            } else if FullGramExtras.shared.autoCropScreenshots,
                      let image = newMediaReference?.media as? TelegramMediaImage,
                      let largestRep = image.representations.max(by: { $0.dimensions.width * $0.dimensions.height < $1.dimensions.width * $1.dimensions.height }),
                      let localRef = largestRep.resource as? LocalFileReferenceMediaResource,
                      FileManager.default.fileExists(atPath: localRef.localFilePath),
                      let rawData = try? Data(contentsOf: URL(fileURLWithPath: localRef.localFilePath), options: .mappedIfSafe),
                      let cropped = FullGramExtras.autoCroppedScreenshotData(rawData, fileName: nil) {
                let croppedURL = URL(fileURLWithPath: NSTemporaryDirectory() + "fg-clean-shot-\(Int64.random(in: 1 ... Int64.max)).jpg")
                if (try? cropped.data.write(to: croppedURL, options: .atomic)) != nil {
                    var randomId: Int64 = 0
                    arc4random_buf(&randomId, 8)
                    let croppedRes = LocalFileReferenceMediaResource(localFilePath: croppedURL.path, randomId: randomId)
                    let updatedRep = TelegramMediaImageRepresentation(
                        dimensions: cropped.dimensions,
                        resource: croppedRes,
                        progressiveSizes: [],
                        immediateThumbnailData: nil,
                        hasVideo: false,
                        isPersonal: false
                    )
                    let newImage = TelegramMediaImage(
                        imageId: image.imageId,
                        representations: [updatedRep],
                        videoRepresentations: image.videoRepresentations,
                        immediateThumbnailData: nil,
                        emojiMarkup: image.emojiMarkup,
                        reference: image.reference,
                        partialReference: image.partialReference,
                        flags: image.flags,
                        video: image.video
                    )
                    newMediaReference = .standalone(media: newImage)
                }
            }
            // Regular photos without auto-crop remain untouched to preserve camera capture paths.
            return .message(
                text: newText,
                attributes: newAttributes,
                inlineStickers: inlineStickers,
                mediaReference: newMediaReference,
                threadId: threadId,
                replyToMessageId: replyToMessageId,
                replyToStoryId: replyToStoryId,
                localGroupingKey: localGroupingKey,
                correlationId: correlationId,
                bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
            )
        case .forward:
            return message
        }
    }
}

// MARK: - Forward With Edit Store (Feature 12)

public final class FullGramForwardEditorStore: @unchecked Sendable {
    public static let shared = FullGramForwardEditorStore()
    private let lock = NSLock()
    private var editedTextsByRawId: [Int32: String] = [:]
    private var excludedRawIds: Set<Int32> = []

    private init() {}

    public func setEditedText(_ text: String?, forRawMessageId id: Int32) {
        self.lock.lock()
        if let text {
            self.editedTextsByRawId[id] = text
        } else {
            self.editedTextsByRawId.removeValue(forKey: id)
        }
        self.lock.unlock()
    }

    public func consumeEditedText(forRawMessageId id: Int32) -> String? {
        self.lock.lock()
        let val = self.editedTextsByRawId.removeValue(forKey: id)
        self.lock.unlock()
        return val
    }

    public func setExcluded(_ excluded: Bool, rawMessageId id: Int32) {
        self.lock.lock()
        if excluded {
            self.excludedRawIds.insert(id)
        } else {
            self.excludedRawIds.remove(id)
        }
        self.lock.unlock()
    }

    public func isExcluded(rawMessageId id: Int32) -> Bool {
        self.lock.lock()
        let res = self.excludedRawIds.contains(id)
        self.lock.unlock()
        return res
    }

    public func clearAll() {
        self.lock.lock()
        self.editedTextsByRawId.removeAll()
        self.excludedRawIds.removeAll()
        self.lock.unlock()
    }
}

// MARK: - Smart Transfer Queue & Cache Optimizer (Features 9 & 13)

public final class FullGramTransferQueue: @unchecked Sendable {
    public struct TransferItem: Identifiable, Sendable {
        public enum Direction: String, Sendable {
            case upload
            case download
        }
        public enum Status: String, Sendable {
            case queued
            case active
            case pausedByNetwork
            case completed
            case failed
        }
        public let id: String
        public let title: String
        public let byteCount: Int64
        public let direction: Direction
        public var status: Status
        public var updatedAt: Date
    }

    public static let shared = FullGramTransferQueue()
    public static let didChangeNotification = Notification.Name("FullGram.TransferQueueDidChange")

    private let lock = NSLock()
    private let monitorQueue = DispatchQueue(label: "com.fullgram.transfer-monitor")
    private let pathMonitor = NWPathMonitor()
    private var items: [TransferItem] = []
    private var retryCallbacks: [String: @Sendable () -> Void] = [:]
    private var connected: Bool = true
    private var networkLabel: String = "Wi-Fi / Cellular"
    private var memoryObserver: NSObjectProtocol?

    private init() {
        self.pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let nowConnected = (path.status == .satisfied)
            let kind: String
            if !nowConnected {
                kind = "Нет сети"
            } else if path.usesInterfaceType(.wifi) {
                kind = "Wi-Fi"
            } else if path.usesInterfaceType(.cellular) {
                kind = "Сотовая сеть"
            } else {
                kind = "Подключено"
            }
            var callbacksToRun: [@Sendable () -> Void] = []
            self.lock.lock()
            let becameConnected = !self.connected && nowConnected
            self.connected = nowConnected
            self.networkLabel = kind
            if nowConnected && (becameConnected || !self.retryCallbacks.isEmpty),
               FullGramExtras.shared.smartTransferQueue && FullGramExtras.shared.autoResumeDownloadsOnReconnect {
                for i in self.items.indices {
                    if self.items[i].status == .pausedByNetwork || self.items[i].status == .queued || self.items[i].status == .failed {
                        self.items[i].status = .active
                        self.items[i].updatedAt = Date()
                        if let cb = self.retryCallbacks[self.items[i].id] {
                            callbacksToRun.append(cb)
                        }
                    }
                }
            } else if !nowConnected {
                for i in self.items.indices where self.items[i].status == .active {
                    self.items[i].status = .pausedByNetwork
                    self.items[i].updatedAt = Date()
                }
            }
            self.lock.unlock()
            let pendingCallbacks = callbacksToRun
            DispatchQueue.main.async {
                for cb in pendingCallbacks { cb() }
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
        self.pathMonitor.start(queue: self.monitorQueue)
        self.memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if FullGramExtras.shared.autoCleanTempCaches {
                let _ = self?.purgeStaleTemporaryFiles()
            }
        }
    }

    deinit {
        self.pathMonitor.cancel()
        if let observer = self.memoryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public var isConnected: Bool {
        self.lock.lock()
        let v = self.connected
        self.lock.unlock()
        return v
    }

    public var connectionKind: String {
        self.lock.lock()
        let v = self.networkLabel
        self.lock.unlock()
        return v
    }

    public func currentItems() -> [TransferItem] {
        self.lock.lock()
        let v = self.items
        self.lock.unlock()
        return v
    }

    public func register(
        id: String,
        title: String,
        byteCount: Int64,
        direction: TransferItem.Direction,
        resumeAction: (@Sendable () -> Void)? = nil
    ) {
        self.lock.lock()
        let initialStatus: TransferItem.Status = self.connected ? .active : .pausedByNetwork
        if let idx = self.items.firstIndex(where: { $0.id == id }) {
            self.items[idx].status = initialStatus
            self.items[idx].updatedAt = Date()
        } else {
            self.items.insert(TransferItem(
                id: id,
                title: title,
                byteCount: byteCount,
                direction: direction,
                status: initialStatus,
                updatedAt: Date()
            ), at: 0)
            if self.items.count > 40 {
                let evicted = self.items.dropFirst(40)
                for item in evicted {
                    self.retryCallbacks.removeValue(forKey: item.id)
                }
                self.items = Array(self.items.prefix(40))
            }
        }
        if let resumeAction {
            self.retryCallbacks[id] = resumeAction
        }
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public func markCompleted(id: String) {
        self.lock.lock()
        if let idx = self.items.firstIndex(where: { $0.id == id }) {
            self.items[idx].status = .completed
            self.items[idx].updatedAt = Date()
        }
        self.retryCallbacks.removeValue(forKey: id)
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public func resumeAllNow() {
        var callbacks: [@Sendable () -> Void] = []
        self.lock.lock()
        for i in self.items.indices where self.items[i].status != .completed {
            self.items[i].status = .active
            self.items[i].updatedAt = Date()
            if let cb = self.retryCallbacks[self.items[i].id] {
                callbacks.append(cb)
            }
        }
        self.lock.unlock()
        let pendingCallbacks = callbacks
        DispatchQueue.main.async {
            for cb in pendingCallbacks { cb() }
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public func clearCompleted() {
        self.lock.lock()
        self.items.removeAll { $0.status == .completed }
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    @discardableResult
    public func purgeStaleTemporaryFiles(olderThan age: TimeInterval = 300.0) -> Int64 {
        let prefixes = ["fg-clean-", "fullgram_stt_", "fullgram_sub_", "fullgram_bleep_", "fg_archive_", "fg_audio_"]
        let tmp = FileManager.default.temporaryDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        let now = Date()
        var freed: Int64 = 0
        for url in urls {
            let name = url.lastPathComponent
            guard prefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            if age > 0, let mdate = values?.contentModificationDate, now.timeIntervalSince(mdate) < age {
                continue
            }
            freed += Int64(values?.fileSize ?? 0)
            try? FileManager.default.removeItem(at: url)
        }
        return freed
    }
}

// MARK: - Feature Flags (Phase 0 kill-switches, remote + local overrides)

public enum FullGramFeatureFlag: String, CaseIterable, Sendable {
    case classicDesign
    case cloudCosmetics
    case avatarFrames
    case nicknameStyles
    case adminPanel
    case screenCapturePrivacy
    case chatFaceIdLock
    case pluginsEngine
    case aiAssistant
    case paperDeleteAnimation

    public var defaultValue: Bool {
        switch self {
        case .classicDesign,
             .cloudCosmetics,
             .avatarFrames,
             .nicknameStyles,
             .adminPanel,
             .screenCapturePrivacy,
             .chatFaceIdLock,
             .pluginsEngine,
             .aiAssistant,
             .paperDeleteAnimation:
            return true
        }
    }
}

private struct FullGramRemoteFlagsPayload: Codable {
    var version: Int?
    var flags: [String: Bool]
}

public final class FullGramFeatureFlags: @unchecked Sendable {
    public static let shared = FullGramFeatureFlags()
    public static let didChangeNotification = Notification.Name("FullGram.FeatureFlagsDidChange")

    private static let remoteURL = "https://fullgram.korsakovx.workers.dev/config.json"
    private static let remoteCacheKey = "fullgram.flags.remoteCache"
    private static let localOverridePrefix = "fullgram.flags.override."
    private static let lastSyncKey = "fullgram.flags.lastSync"

    private let lock = NSRecursiveLock()
    private var remoteFlags: [String: Bool] = [:]
    private var localOverrides: [String: Bool] = [:]
    private var isRefreshing = false
    private var pendingCompletions: [(Bool) -> Void] = []

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8.0
        cfg.timeoutIntervalForResource = 12.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private init() {
        self.loadFromDefaults()
    }

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        var remote: [String: Bool] = [:]
        if let data = defaults.data(forKey: Self.remoteCacheKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            remote = decoded
        }
        var overrides: [String: Bool] = [:]
        for flag in FullGramFeatureFlag.allCases {
            let key = Self.localOverridePrefix + flag.rawValue
            if defaults.object(forKey: key) != nil {
                overrides[flag.rawValue] = defaults.bool(forKey: key)
            }
        }
        self.lock.lock()
        self.remoteFlags = remote
        self.localOverrides = overrides
        self.lock.unlock()
    }

    public static func isEnabled(_ flag: FullGramFeatureFlag) -> Bool {
        return self.shared.value(for: flag)
    }

    public func value(for flag: FullGramFeatureFlag) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let local = self.localOverrides[flag.rawValue] {
            return local
        }
        if let remote = self.remoteFlags[flag.rawValue] {
            return remote
        }
        return flag.defaultValue
    }

    public func setLocalOverride(_ flag: FullGramFeatureFlag, value: Bool?) {
        let key = Self.localOverridePrefix + flag.rawValue
        self.lock.lock()
        if let value {
            self.localOverrides[flag.rawValue] = value
            UserDefaults.standard.set(value, forKey: key)
        } else {
            self.localOverrides.removeValue(forKey: flag.rawValue)
            UserDefaults.standard.removeObject(forKey: key)
        }
        self.lock.unlock()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: flag.rawValue)
        NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: flag.rawValue)
    }

    public func refreshFromRemoteIfNeeded(maxAge: TimeInterval = 300.0) {
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if Date().timeIntervalSince1970 - last < maxAge {
            return
        }
        self.refreshFromRemote(completion: nil)
    }

    public func refreshFromRemote(completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: Self.remoteURL) else {
            completion?(false)
            return
        }
        self.lock.lock()
        if let completion {
            self.pendingCompletions.append(completion)
        }
        if self.isRefreshing {
            self.lock.unlock()
            return
        }
        self.isRefreshing = true
        self.lock.unlock()

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Self.session.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let drainCompletions: (Bool) -> Void = { ok in
                self.lock.lock()
                self.isRefreshing = false
                let completions = self.pendingCompletions
                self.pendingCompletions.removeAll()
                self.lock.unlock()
                DispatchQueue.main.async {
                    if ok {
                        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                        NotificationCenter.default.post(name: FullGramExtras.didChangeNotification, object: "featureFlags")
                    }
                    for cb in completions { cb(ok) }
                }
            }
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let data,
                  data.count <= 65_536,
                  let payload = try? JSONDecoder().decode(FullGramRemoteFlagsPayload.self, from: data) else {
                drainCompletions(false)
                return
            }

            if let encoded = try? JSONEncoder().encode(payload.flags) {
                UserDefaults.standard.set(encoded, forKey: Self.remoteCacheKey)
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)

            self.lock.lock()
            self.remoteFlags = payload.flags
            self.lock.unlock()

            drainCompletions(true)
        }.resume()
    }
}

// MARK: - Classic Design Auto-Rollback Watchdog (Phase 1.2)

public enum FullGramDesignWatchdog {
    private static let pendingKey = "fullgram.watchdog.classicDesignPending"
    private static let launchStreakKey = "fullgram.watchdog.classicDesignLaunchStreak"
    private static let rolledBackKey = "fullgram.watchdog.classicDesignRolledBack"
    private static let lock = NSLock()

    public static func armPendingClassicDesign() {
        self.lock.lock()
        defer { self.lock.unlock() }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: self.pendingKey)
        defaults.set(0, forKey: self.launchStreakKey)
        defaults.set(false, forKey: self.rolledBackKey)
    }

    public static func clearPendingClassicDesign() {
        self.lock.lock()
        defer { self.lock.unlock() }
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: self.pendingKey)
        defaults.set(0, forKey: self.launchStreakKey)
    }

    /// Call on app launch before applying `classicDesign` to Glass/TabBar.
    /// If classic design failed to reach a verified settings/UI open on the previous session,
    /// automatically rolls back `classicDesign` to `false` so the user is never locked out of settings.
    @discardableResult
    public static func checkOnLaunch() -> Bool {
        var didRollback = false
        self.lock.lock()
        let defaults = UserDefaults.standard
        let classicRawKey = "fullgram.extras.classicDesign"
        if !defaults.bool(forKey: classicRawKey) {
            defaults.set(false, forKey: self.pendingKey)
            defaults.set(0, forKey: self.launchStreakKey)
        } else {
            let pending = defaults.bool(forKey: self.pendingKey)
            let streak = defaults.integer(forKey: self.launchStreakKey) + 1
            defaults.set(streak, forKey: self.launchStreakKey)

            if pending && streak >= 2 {
                defaults.set(false, forKey: classicRawKey)
                defaults.set(false, forKey: self.pendingKey)
                defaults.set(0, forKey: self.launchStreakKey)
                defaults.set(true, forKey: self.rolledBackKey)
                didRollback = true
            }
        }
        self.lock.unlock()
        // Call outside lock so classicDesign setter -> clearPendingClassicDesign() cannot deadlock.
        if didRollback {
            FullGramExtras.shared.classicDesign = false
        }
        return didRollback
    }

    /// Call when Settings / FullGram Settings successfully renders.
    public static func markUIVerified() {
        self.lock.lock()
        defer { self.lock.unlock() }
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: self.pendingKey) || defaults.integer(forKey: self.launchStreakKey) > 0 {
            defaults.set(false, forKey: self.pendingKey)
            defaults.set(0, forKey: self.launchStreakKey)
        }
    }

    public static var didAutoRollback: Bool {
        return UserDefaults.standard.bool(forKey: self.rolledBackKey)
    }

    public static func clearRollbackNotice() {
        UserDefaults.standard.set(false, forKey: self.rolledBackKey)
    }
}

public enum FullGramCacheCleaner {
    @discardableResult
    public static func runIfNeeded(force: Bool = false) -> Int64 {
        let extras = FullGramExtras.shared
        let intervalDays = extras.autoCleanCacheIntervalDays
        let maxMB = extras.autoCleanCacheMaxMB
        if !force {
            if intervalDays <= 0 && maxMB <= 0 {
                return 0
            }
            let now = Date().timeIntervalSince1970
            let minElapsed: TimeInterval = intervalDays > 0 ? TimeInterval(intervalDays) * 86400.0 : 3600.0
            if extras.lastAutoCacheCleanTimestamp > 0 && (now - extras.lastAutoCacheCleanTimestamp) < minElapsed {
                return 0
            }
        }
        extras.lastAutoCacheCleanTimestamp = Date().timeIntervalSince1970

        var freedBytes: Int64 = 0
        let fm = FileManager.default
        let cutoff = intervalDays > 0 ? Date().addingTimeInterval(-TimeInterval(intervalDays) * 86400.0) : Date.distantPast
        let minTempSafetyCutoff = Date().addingTimeInterval(-300.0)

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        if let tmpItems = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: []) {
            for url in tmpItems {
                let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let modDate = vals?.contentModificationDate ?? .distantPast
                let isOlderThanSafety = modDate < minTempSafetyCutoff
                let ageOk = force || (isOlderThanSafety && (modDate < cutoff || url.lastPathComponent.hasPrefix("fg_")))
                if ageOk {
                    freedBytes += Int64(vals?.fileSize ?? 0)
                    try? fm.removeItem(at: url)
                }
            }
        }

        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            var candidates: [(url: URL, size: Int64, date: Date)] = []
            var totalBytes: Int64 = 0
            if let enumerator = fm.enumerator(at: cachesDir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator {
                    let name = url.lastPathComponent
                    if name.hasPrefix("fullgram_") || name.hasSuffix(".sqlite") || name.hasSuffix(".db") {
                        continue
                    }
                    guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                          vals.isRegularFile == true else { continue }
                    let sz = Int64(vals.fileSize ?? 0)
                    let mod = vals.contentModificationDate ?? .distantPast
                    totalBytes += sz
                    candidates.append((url, sz, mod))
                }
            }
            if force || (intervalDays > 0) {
                for item in candidates where force || item.date < cutoff {
                    freedBytes += item.size
                    totalBytes = max(0, totalBytes - item.size)
                    try? fm.removeItem(at: item.url)
                }
            }
            if !force && maxMB > 0 {
                let limitBytes = Int64(maxMB) * 1024 * 1024
                if totalBytes > limitBytes {
                    for item in candidates.sorted(by: { $0.date < $1.date }) {
                        if totalBytes <= limitBytes { break }
                        if fm.fileExists(atPath: item.url.path) {
                            freedBytes += item.size
                            totalBytes = max(0, totalBytes - item.size)
                            try? fm.removeItem(at: item.url)
                        }
                    }
                }
            }
        }
        return freedBytes
    }
}

public struct FullGramContactNote: Codable, Equatable, Sendable {
    public var text: String
    public var tags: [String]
    public var updatedAt: Int32

    public init(text: String, tags: [String], updatedAt: Int32) {
        self.text = text
        self.tags = tags
        self.updatedAt = updatedAt
    }
}

public final class FullGramContactNotesStore: @unchecked Sendable {
    public static let shared = FullGramContactNotesStore()
    public static let didChangeNotification = Notification.Name("FullGram.ContactNotesChanged")

    private let lock = NSLock()
    private var notes: [String: FullGramContactNote] = [:]

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FullGram", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("contact_notes_v1.json")
    }

    private init() {
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([String: FullGramContactNote].self, from: data) {
            self.notes = decoded
        }
    }

    public func note(forPeerId peerId: Int64) -> FullGramContactNote? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.notes[String(peerId)]
    }

    public func setNote(forPeerId peerId: Int64, text: String, tags: [String]) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        self.lock.lock()
        if cleanText.isEmpty && cleanTags.isEmpty {
            self.notes.removeValue(forKey: String(peerId))
        } else {
            self.notes[String(peerId)] = FullGramContactNote(text: cleanText, tags: cleanTags, updatedAt: Int32(Date().timeIntervalSince1970))
        }
        if let encoded = try? JSONEncoder().encode(self.notes) {
            try? encoded.write(to: self.fileURL, options: .atomic)
        }
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}

public final class FullGramLocalBusinessStore: @unchecked Sendable {
    public static let shared = FullGramLocalBusinessStore()

    private let lock = NSLock()
    private let defaults = UserDefaults.standard

    private init() {}

    public func saveLocation(accountPeerId: Int64, location: TelegramBusinessLocation?) {
        let key = "fullgram.localBusiness.location.\(accountPeerId)"
        self.lock.lock()
        defer { self.lock.unlock() }
        if let location {
            var dict: [String: Any] = ["address": location.address]
            if let coords = location.coordinates {
                dict["lat"] = coords.latitude
                dict["lon"] = coords.longitude
            }
            self.defaults.set(dict, forKey: key)
        } else {
            self.defaults.removeObject(forKey: key)
        }
    }

    public func storedLocation(accountPeerId: Int64) -> TelegramBusinessLocation? {
        let key = "fullgram.localBusiness.location.\(accountPeerId)"
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let dict = self.defaults.dictionary(forKey: key),
              let address = dict["address"] as? String else {
            return nil
        }
        var coords: TelegramBusinessLocation.Coordinates?
        if let lat = dict["lat"] as? Double, let lon = dict["lon"] as? Double {
            coords = TelegramBusinessLocation.Coordinates(latitude: lat, longitude: lon)
        }
        return TelegramBusinessLocation(address: address, coordinates: coords)
    }

    public func saveHours(accountPeerId: Int64, hours: TelegramBusinessHours?) {
        let key = "fullgram.localBusiness.hours.\(accountPeerId)"
        self.lock.lock()
        defer { self.lock.unlock() }
        if let hours, let encoded = try? JSONEncoder().encode(hours) {
            self.defaults.set(encoded, forKey: key)
        } else {
            self.defaults.removeObject(forKey: key)
        }
    }

    public func storedHours(accountPeerId: Int64) -> TelegramBusinessHours? {
        let key = "fullgram.localBusiness.hours.\(accountPeerId)"
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let data = self.defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(TelegramBusinessHours.self, from: data) else {
            return nil
        }
        return decoded
    }
}


