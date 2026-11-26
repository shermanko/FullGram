import Foundation
import Security

public enum FullGramVersion {
    public static let shortVersion = "1.7.0"
    public static let isBeta = true

    public static func displayString(russian: Bool) -> String {
        return russian ? "\(self.shortVersion) · Бета-тест" : "\(self.shortVersion) · Beta Test"
    }
}

public final class FullGramAdmin: @unchecked Sendable {
    public static let shared = FullGramAdmin()
    /// UI-only hint for showing the entry point to the admin panel before server verification.
    /// Actual authorization is enforced strictly on Cloudflare Worker via Telegram-signed auth.
    public static let ownerUserId: Int64 = 8899688273
    public static let workerBaseURL = "https://fullgram.korsakovx.workers.dev"

    private let keychainService = "FullGram.Admin.Token"
    private let keychainAccount = "owner_token"
    private let initDataAccount = "telegram_init_data"
    private let clientSessionTokenAccount = "client_session_token"
    private let clientSessionUidAccount = "client_session_uid"
    private let deviceSecretAccount = "device_secret"
    private let lock = NSLock()
    private var verifiedAdminUserId: Int64?
    private var verifiedAuthMethod: String?
    private var pendingSessionCompletions: [Int64: [@Sendable (Result<String, Error>) -> Void]] = [:]

    private init() {}

    public static func isOwnerUserId(_ userId: Int64) -> Bool {
        if let verified = self.shared.serverVerifiedAdminUserId {
            return verified == userId
        }
        return userId == self.ownerUserId
    }

    public var serverVerifiedAdminUserId: Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.verifiedAdminUserId
    }

    public var serverVerifiedMethod: String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.verifiedAuthMethod
    }

    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let keychainLock = NSLock()

    private func writeKeychain(_ rawValue: String, account: String) {
        self.keychainLock.lock()
        defer { self.keychainLock.unlock() }
        self.writeKeychainUnlocked(rawValue, account: account)
    }

    private func writeKeychainUnlocked(_ rawValue: String, account: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deleteKeychainUnlocked(account: account)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return
        }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: self.keychainService,
                kSecAttrAccount as String: account
            ]
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    private func deleteKeychain(account: String) {
        self.keychainLock.lock()
        defer { self.keychainLock.unlock() }
        self.deleteKeychainUnlocked(account: account)
    }

    private func deleteKeychainUnlocked(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain Token & Telegram InitData Storage

    public var hasToken: Bool {
        if let token = self.getToken(), !token.isEmpty { return true }
        if let initData = self.getTelegramInitData(), !initData.isEmpty { return true }
        return false
    }

    public func getToken() -> String? {
        return self.readKeychain(account: self.keychainAccount)
    }

    public func getTelegramInitData() -> String? {
        return self.readKeychain(account: self.initDataAccount)
    }

    /// Accepts either a server-issued signed session token (`fg1.*`) or Telegram WebApp `initData` (`user=...&hash=...`).
    public func setToken(_ rawToken: String) {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lock.lock()
        self.verifiedAdminUserId = nil
        self.verifiedAuthMethod = nil
        self.lock.unlock()
        if trimmed.contains("hash=") && (trimmed.contains("auth_date=") || trimmed.contains("user=")) {
            self.writeKeychain(trimmed, account: self.initDataAccount)
            self.deleteKeychain(account: self.keychainAccount)
        } else {
            self.writeKeychain(trimmed, account: self.keychainAccount)
            self.deleteKeychain(account: self.initDataAccount)
        }
    }

    public func clearToken() {
        self.lock.lock()
        self.verifiedAdminUserId = nil
        self.verifiedAuthMethod = nil
        self.lock.unlock()
        self.deleteKeychain(account: self.keychainAccount)
        self.deleteKeychain(account: self.initDataAccount)
    }

    @discardableResult
    public func applyAuthHeaders(to request: inout URLRequest) -> Bool {
        var applied = false
        if let initData = self.getTelegramInitData(), !initData.isEmpty {
            request.setValue(initData, forHTTPHeaderField: "X-Telegram-Init-Data")
            applied = true
        }
        if let token = self.getToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            applied = true
        }
        return applied
    }

    @discardableResult
    public func applyClientOrAdminAuthHeaders(to request: inout URLRequest, preferredClientToken: String? = nil) -> Bool {
        if let preferredClientToken, !preferredClientToken.isEmpty {
            request.setValue("Bearer \(preferredClientToken)", forHTTPHeaderField: "Authorization")
            return true
        }
        if self.applyAuthHeaders(to: &request) {
            return true
        }
        if let storedClient = self.readKeychain(account: self.clientSessionTokenAccount), !storedClient.isEmpty {
            request.setValue("Bearer \(storedClient)", forHTTPHeaderField: "Authorization")
            return true
        }
        return false
    }

    public func deviceSecretValue() -> String {
        return self.getOrCreateDeviceSecret()
    }

    private func getOrCreateDeviceSecret() -> String {
        self.keychainLock.lock()
        defer { self.keychainLock.unlock() }
        if let existing = self.readKeychain(account: self.deviceSecretAccount), existing.count >= 16 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let secret: String
        if status == errSecSuccess {
            secret = bytes.map { String(format: "%02x", $0) }.joined()
        } else {
            secret = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        self.writeKeychainUnlocked(secret, account: self.deviceSecretAccount)
        return secret
    }

    public func clearClientSession() {
        self.deleteKeychain(account: self.clientSessionTokenAccount)
        self.deleteKeychain(account: self.clientSessionUidAccount)
    }

    public func ensureClientSession(
        peerId: Int64,
        forceRefresh: Bool = false,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        let normId = FullGramCloudCosmetics.normalizedPeerId(peerId)
        guard normId > 0 else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramAdmin", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный ID пользователя."])))
            }
            return
        }
        if !forceRefresh,
           let token = self.readKeychain(account: self.clientSessionTokenAccount),
           !token.isEmpty,
           let uid = self.readKeychain(account: self.clientSessionUidAccount),
           uid == String(normId) {
            completion(.success(token))
            return
        }

        self.lock.lock()
        if var list = self.pendingSessionCompletions[normId] {
            list.append(completion)
            self.pendingSessionCompletions[normId] = list
            self.lock.unlock()
            return
        }
        self.pendingSessionCompletions[normId] = [completion]
        self.lock.unlock()

        let finish: @Sendable (Result<String, Error>) -> Void = { result in
            self.lock.lock()
            let callbacks = self.pendingSessionCompletions.removeValue(forKey: normId) ?? []
            self.lock.unlock()
            for cb in callbacks {
                cb(result)
            }
        }

        guard let url = URL(string: Self.workerBaseURL + "/auth/session") else {
            finish(.failure(NSError(domain: "FullGramAdmin", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес сервера."])))
            return
        }
        let secret = self.getOrCreateDeviceSecret()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "peerId": String(normId),
            "deviceSecret": secret
        ], options: [])

        self.sendJSONRequest(request) { [weak self] result in
            switch result {
            case let .success(json):
                if let token = json["token"] as? String, !token.isEmpty {
                    self?.writeKeychain(token, account: self?.clientSessionTokenAccount ?? "client_session_token")
                    self?.writeKeychain(String(normId), account: self?.clientSessionUidAccount ?? "client_session_uid")
                    finish(.success(token))
                } else {
                    finish(.failure(NSError(domain: "FullGramAdmin", code: 500, userInfo: [NSLocalizedDescriptionKey: "Сервер не выдал токен сессии."])))
                }
            case let .failure(error):
                finish(.failure(error))
            }
        }
    }

    // MARK: - Server-Side Verification & Telegram Auth Exchange

    public func exchangeTelegramInitData(
        _ initData: String,
        completion: @escaping (Result<(userId: Int64, isAdmin: Bool), Error>) -> Void
    ) {
        let trimmed = initData.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: Self.workerBaseURL + "/auth/telegram") else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramAdmin", code: 400, userInfo: [NSLocalizedDescriptionKey: "Пустые данные авторизации Telegram."])))
            }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmed, forHTTPHeaderField: "X-Telegram-Init-Data")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["initData": trimmed], options: [])

        self.sendJSONRequest(request) { [weak self] result in
            switch result {
            case let .success(json):
                let uid = (json["userId"] as? String).flatMap { Int64($0) } ?? 0
                let isAdmin = (json["isAdmin"] as? Bool) ?? false
                if let token = json["token"] as? String, !token.isEmpty {
                    self?.writeKeychain(token, account: self?.keychainAccount ?? "owner_token")
                }
                self?.lock.lock()
                self?.verifiedAdminUserId = isAdmin ? uid : nil
                self?.verifiedAuthMethod = "telegram_init_data"
                self?.lock.unlock()
                completion(.success((uid, isAdmin)))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func verifySession(completion: @escaping (Result<(userId: Int64?, isAdmin: Bool, method: String), Error>) -> Void) {
        guard let url = URL(string: Self.workerBaseURL + "/auth/me") else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramAdmin", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес сервера FullGram."])))
            }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        _ = self.applyAuthHeaders(to: &request)

        self.sendJSONRequest(request) { [weak self] result in
            switch result {
            case let .success(json):
                let uid = (json["userId"] as? String).flatMap { Int64($0) }
                let isAdmin = (json["isAdmin"] as? Bool) ?? false
                let method = (json["method"] as? String) ?? "none"
                self?.lock.lock()
                self?.verifiedAdminUserId = isAdmin ? uid : nil
                self?.verifiedAuthMethod = isAdmin ? method : nil
                self?.lock.unlock()
                completion(.success((uid, isAdmin, method)))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Admin Requests

    private func makeAdminRequest(path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: Self.workerBaseURL + path) else {
            throw NSError(
                domain: "FullGramAdmin",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Некорректный адрес сервера FullGram."]
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard self.applyAuthHeaders(to: &request) else {
            throw NSError(
                domain: "FullGramAdmin",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Требуется подписанный токен (/auth в боте) или Telegram initData."]
            )
        }
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        return request
    }

    private func sendJSONRequest(_ request: URLRequest, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any] } ?? [:]
            guard (200 ..< 300).contains(status), (parsed["ok"] as? Bool ?? true) else {
                let message = (parsed["error"] as? String) ?? "HTTP \(status)"
                let err = NSError(domain: "FullGramAdmin", code: status, userInfo: [NSLocalizedDescriptionKey: message])
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            DispatchQueue.main.async { completion(.success(parsed)) }
        }.resume()
    }

    public func updateBadge(
        peerId: Int64?,
        username: String?,
        enabled: Bool,
        roleId: String?,
        customEmojiId: Int64?,
        emoji: String?,
        label: String?,
        shortLabel: String?,
        color: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var payload: [String: Any] = ["enabled": enabled]
        if let peerId {
            let normId = FullGramCloudCosmetics.normalizedPeerId(peerId)
            payload["peerId"] = String(normId)
        }
        if let username, !username.isEmpty {
            payload["username"] = username
        }
        if let roleId, !roleId.isEmpty {
            payload["roleId"] = roleId
        }
        if let customEmojiId {
            payload["customEmojiId"] = String(customEmojiId)
        }
        if let emoji, !emoji.isEmpty {
            payload["emoji"] = emoji
        }
        if let label, !label.isEmpty {
            payload["label"] = label
        }
        if let shortLabel, !shortLabel.isEmpty {
            payload["shortLabel"] = shortLabel
        }
        if let color, !color.isEmpty {
            payload["color"] = color
        }

        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/badge", method: "POST", body: payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        self.sendJSONRequest(request) { result in
            switch result {
            case .success:
                FullGramBadges.shared.refreshNow { _ in
                    completion(.success(()))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func publishPlugin(
        id: String?,
        name: String,
        language: FullGramPluginLanguage,
        version: String,
        author: String,
        description: String,
        code: String,
        completion: @escaping (Result<FullGramRemotePluginItem, Error>) -> Void
    ) {
        var payload: [String: Any] = [
            "name": name,
            "language": language.rawValue,
            "version": version,
            "author": author,
            "description": description,
            "code": code
        ]
        if let id, !id.isEmpty {
            payload["id"] = id
        }

        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/plugin", method: "POST", body: payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        self.sendJSONRequest(request) { result in
            switch result {
            case let .success(json):
                if let pluginDict = json["plugin"] as? [String: Any],
                   let data = try? JSONSerialization.data(withJSONObject: pluginDict, options: []),
                   let item = try? JSONDecoder().decode(FullGramRemotePluginItem.self, from: data) {
                    completion(.success(item))
                } else {
                    completion(.failure(NSError(domain: "FullGramAdmin", code: 500, userInfo: [NSLocalizedDescriptionKey: "Некорректный ответ сервера."])))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func deleteMarketPlugin(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/plugin/delete", method: "POST", body: ["id": id])
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        self.sendJSONRequest(request) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func setupTelegramWebhook(completion: @escaping (Result<String, Error>) -> Void) {
        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/setup-webhook", method: "POST", body: [:])
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        self.sendJSONRequest(request) { result in
            switch result {
            case let .success(json):
                let url = (json["webhookUrl"] as? String) ?? "\(Self.workerBaseURL)/telegram-webhook"
                completion(.success(url))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func updateRemoteCosmetics(
        peerId: Int64,
        frameId: String?,
        nickColor: String?,
        nickGlow: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let payload: [String: Any] = [
            "peerId": String(FullGramCloudCosmetics.normalizedPeerId(peerId)),
            "frameId": frameId ?? "",
            "nickColor": nickColor ?? "",
            "nickGlow": nickGlow
        ]
        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/cosmetics", method: "POST", body: payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        self.sendJSONRequest(request) { result in
            switch result {
            case .success:
                FullGramCloudCosmetics.shared.refreshNow { _ in
                    completion(.success(()))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func updateFeatureFlag(
        key: String,
        enabled: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/flags", method: "POST", body: ["flags": [key: enabled]])
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        self.sendJSONRequest(request) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func grantNFT(
        peerId: Int64,
        giftId: Int64,
        title: String,
        modelName: String,
        backdropName: String,
        backdropId: Int32?,
        patternName: String,
        number: Int32,
        note: String = "",
        pinned: Bool = true,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var payload: [String: Any] = [
            "enabled": true,
            "peerId": String(FullGramCloudCosmetics.normalizedPeerId(peerId)),
            "giftId": String(giftId),
            "title": title,
            "modelName": modelName,
            "backdropName": backdropName,
            "patternName": patternName,
            "number": Int(max(1, number)),
            "note": note,
            "pinned": pinned
        ]
        if let backdropId {
            payload["backdropId"] = Int(backdropId)
        }
        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/nft", method: "POST", body: payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        self.sendJSONRequest(request) { result in
            switch result {
            case let .success(json):
                let id = (json["id"] as? String) ?? ""
                completion(.success(id))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func revokeNFT(
        peerId: Int64,
        entryId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let payload: [String: Any] = [
            "enabled": false,
            "peerId": String(FullGramCloudCosmetics.normalizedPeerId(peerId)),
            "id": entryId
        ]
        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/nft", method: "POST", body: payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        self.sendJSONRequest(request) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Sponsors API (Owner & Sponsor Self-Service)

    public func setSponsor(
        peerId: Int64?,
        username: String?,
        enabled: Bool,
        tier: FullGramSponsorTier = .sponsor,
        completion: @escaping @Sendable (Result<Int64, Error>) -> Void
    ) {
        let effectiveTier: FullGramSponsorTier = enabled ? (tier == .none ? .sponsor : tier) : .none
        var payload: [String: Any] = [
            "enabled": enabled,
            "tier": effectiveTier.workerValue
        ]
        if let peerId {
            payload["peerId"] = String(FullGramCloudCosmetics.normalizedPeerId(peerId))
        }
        if let username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["username"] = username.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let request: URLRequest
        do {
            request = try self.makeAdminRequest(path: "/admin/sponsor", method: "POST", body: payload)
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }
        self.sendJSONRequest(request) { result in
            switch result {
            case let .success(json):
                let resolvedId = (json["peerId"] as? String).flatMap { Int64($0) }
                    ?? peerId.map { FullGramCloudCosmetics.normalizedPeerId($0) }
                    ?? 0
                if resolvedId != 0 {
                    FullGramSponsors.shared.setLocalSponsor(peerId: resolvedId, enabled: enabled, tier: effectiveTier)
                }
                FullGramSponsors.shared.refreshNow { _ in }
                FullGramBadges.shared.refreshNow { _ in }
                completion(.success(resolvedId))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func updateSponsorBadge(
        actorPeerId: Int64,
        targetPeerId: Int64,
        enabled: Bool,
        roleId: String?,
        customEmojiId: Int64?,
        emoji: String?,
        label: String?,
        shortLabel: String?,
        color: String?,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let normActorId = FullGramCloudCosmetics.normalizedPeerId(actorPeerId)
        let normTargetId = FullGramCloudCosmetics.normalizedPeerId(targetPeerId)
        var payload: [String: Any] = [
            "enabled": enabled,
            "peerId": String(normTargetId)
        ]
        if let roleId, !roleId.isEmpty {
            payload["roleId"] = roleId
        }
        if let customEmojiId {
            payload["customEmojiId"] = String(customEmojiId)
        }
        if let emoji, !emoji.isEmpty {
            payload["emoji"] = emoji
        }
        if let label, !label.isEmpty {
            payload["label"] = label
        }
        if let shortLabel, !shortLabel.isEmpty {
            payload["shortLabel"] = shortLabel
        }
        if let color, !color.isEmpty {
            payload["color"] = color
        }

        self.sendClientSessionJSONRequest(path: "/sponsor/badge", peerId: normActorId, payload: payload, didRetry: false) { result in
            switch result {
            case .success:
                FullGramBadges.shared.refreshNow { _ in
                    completion(.success(()))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func updateSponsorSelfBadge(
        peerId: Int64,
        enabled: Bool,
        roleId: String?,
        customEmojiId: Int64?,
        emoji: String?,
        label: String?,
        shortLabel: String?,
        color: String?,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.updateSponsorBadge(
            actorPeerId: peerId,
            targetPeerId: peerId,
            enabled: enabled,
            roleId: roleId,
            customEmojiId: customEmojiId,
            emoji: emoji,
            label: label,
            shortLabel: shortLabel,
            color: color,
            completion: completion
        )
    }

    public func grantSponsorNFT(
        actorPeerId: Int64,
        targetPeerId: Int64,
        giftId: Int64,
        title: String,
        modelName: String,
        backdropName: String,
        backdropId: Int32?,
        patternName: String,
        number: Int32,
        note: String = "",
        pinned: Bool = true,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        let normActorId = FullGramCloudCosmetics.normalizedPeerId(actorPeerId)
        let normTargetId = FullGramCloudCosmetics.normalizedPeerId(targetPeerId)
        var payload: [String: Any] = [
            "enabled": true,
            "peerId": String(normTargetId),
            "giftId": String(giftId),
            "title": title,
            "modelName": modelName,
            "backdropName": backdropName,
            "patternName": patternName,
            "number": Int(max(1, number)),
            "note": note,
            "pinned": pinned
        ]
        if let backdropId {
            payload["backdropId"] = Int(backdropId)
        }
        self.sendClientSessionJSONRequest(path: "/sponsor/nft", peerId: normActorId, payload: payload, didRetry: false) { result in
            switch result {
            case let .success(json):
                completion(.success((json["id"] as? String) ?? ""))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func grantSponsorSelfNFT(
        peerId: Int64,
        giftId: Int64,
        title: String,
        modelName: String,
        backdropName: String,
        backdropId: Int32?,
        patternName: String,
        number: Int32,
        note: String = "",
        pinned: Bool = true,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        self.grantSponsorNFT(
            actorPeerId: peerId,
            targetPeerId: peerId,
            giftId: giftId,
            title: title,
            modelName: modelName,
            backdropName: backdropName,
            backdropId: backdropId,
            patternName: patternName,
            number: number,
            note: note,
            pinned: pinned,
            completion: completion
        )
    }

    public func revokeSponsorNFT(
        actorPeerId: Int64,
        targetPeerId: Int64,
        entryId: String,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let normActorId = FullGramCloudCosmetics.normalizedPeerId(actorPeerId)
        let normTargetId = FullGramCloudCosmetics.normalizedPeerId(targetPeerId)
        let payload: [String: Any] = [
            "enabled": false,
            "peerId": String(normTargetId),
            "id": entryId
        ]
        self.sendClientSessionJSONRequest(path: "/sponsor/nft", peerId: normActorId, payload: payload, didRetry: false) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func revokeSponsorSelfNFT(
        peerId: Int64,
        entryId: String,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.revokeSponsorNFT(actorPeerId: peerId, targetPeerId: peerId, entryId: entryId, completion: completion)
    }

    public func performNFTAction(
        actorPeerId: Int64,
        targetPeerId: Int64,
        toPeerId: Int64? = nil,
        entryId: String? = nil,
        slug: String? = nil,
        action: String,
        modelName: String? = nil,
        backdropName: String? = nil,
        backdropId: Int32? = nil,
        patternName: String? = nil,
        number: Int32? = nil,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let normActor = FullGramCloudCosmetics.normalizedPeerId(actorPeerId)
        let normTarget = FullGramCloudCosmetics.normalizedPeerId(targetPeerId)
        var payload: [String: Any] = [
            "action": action,
            "peerId": String(normTarget)
        ]
        if let entryId, !entryId.isEmpty { payload["id"] = entryId }
        if let slug, !slug.isEmpty { payload["slug"] = slug }
        if let toPeerId { payload["toPeerId"] = String(FullGramCloudCosmetics.normalizedPeerId(toPeerId)) }
        if let modelName, !modelName.isEmpty { payload["modelName"] = modelName }
        if let backdropName, !backdropName.isEmpty { payload["backdropName"] = backdropName }
        if let backdropId { payload["backdropId"] = Int(backdropId) }
        if let patternName, !patternName.isEmpty { payload["patternName"] = patternName }
        if let number, number >= 1 { payload["number"] = Int(number) }

        self.sendClientSessionJSONRequest(path: "/nft/action", peerId: normActor, payload: payload, didRetry: false) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func performEconomyAction(
        actorPeerId: Int64,
        targetPeerId: Int64? = nil,
        toPeerId: Int64? = nil,
        action: String,
        amount: Double? = nil,
        username: String? = nil,
        number: String? = nil,
        entryId: String? = nil,
        isActive: Bool? = nil,
        isPrimary: Bool? = nil,
        completion: (@Sendable (Result<Void, Error>) -> Void)? = nil
    ) {
        let normActor = FullGramCloudCosmetics.normalizedPeerId(actorPeerId)
        let normTarget = FullGramCloudCosmetics.normalizedPeerId(targetPeerId ?? actorPeerId)
        var payload: [String: Any] = [
            "action": action,
            "peerId": String(normTarget)
        ]
        if let toPeerId { payload["toPeerId"] = String(FullGramCloudCosmetics.normalizedPeerId(toPeerId)) }
        if let amount { payload["amount"] = amount }
        if let username, !username.isEmpty { payload["username"] = username }
        if let number, !number.isEmpty { payload["number"] = number }
        if let entryId, !entryId.isEmpty { payload["id"] = entryId }
        if let isActive { payload["isActive"] = isActive }
        if let isPrimary { payload["isPrimary"] = isPrimary }

        self.sendClientSessionJSONRequest(path: "/economy/action", peerId: normActor, payload: payload, didRetry: false) { result in
            switch result {
            case .success:
                completion?(.success(()))
            case let .failure(err):
                completion?(.failure(err))
            }
        }
    }

    public func grantEconomy(
        actorPeerId: Int64,
        targetPeerId: Int64,
        useAdminEndpoint: Bool,
        action: String,
        amount: Double? = nil,
        username: String? = nil,
        number: String? = nil,
        priceTon: Double? = nil,
        isPrimary: Bool = true,
        entryId: String? = nil,
        completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void
    ) {
        let normActor = FullGramCloudCosmetics.normalizedPeerId(actorPeerId)
        let normTarget = FullGramCloudCosmetics.normalizedPeerId(targetPeerId)
        var payload: [String: Any] = [
            "action": action,
            "peerId": String(normTarget),
            "isPrimary": isPrimary
        ]
        if let amount { payload["amount"] = amount }
        if let username, !username.isEmpty { payload["username"] = username }
        if let number, !number.isEmpty { payload["number"] = number }
        if let priceTon { payload["priceTon"] = priceTon }
        if let entryId, !entryId.isEmpty { payload["id"] = entryId }

        if useAdminEndpoint && self.hasToken {
            do {
                let req = try self.makeAdminRequest(path: "/admin/economy", method: "POST", body: payload)
                self.sendJSONRequest(req, completion: completion)
                return
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
        }
        self.sendClientSessionJSONRequest(path: "/sponsor/economy", peerId: normActor, payload: payload, didRetry: false, completion: completion)
    }

    private func sendClientSessionJSONRequest(
        path: String,
        peerId: Int64,
        payload: [String: Any],
        didRetry: Bool,
        completion: @escaping @Sendable (Result<[String: Any], Error>) -> Void
    ) {
        self.ensureClientSession(peerId: peerId, forceRefresh: didRetry) { [weak self] sessionResult in
            guard let self else { return }
            switch sessionResult {
            case let .failure(err):
                DispatchQueue.main.async { completion(.failure(err)) }
            case let .success(token):
                guard let url = URL(string: Self.workerBaseURL + path),
                      let bodyData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "FullGramAdmin", code: 400, userInfo: [NSLocalizedDescriptionKey: "Ошибка формирования запроса."])))
                    }
                    return
                }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 15.0
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.httpBody = bodyData

                URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 401 && !didRetry {
                        self?.clearClientSession()
                        self?.sendClientSessionJSONRequest(path: path, peerId: peerId, payload: payload, didRetry: true, completion: completion)
                        return
                    }
                    if let error {
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }
                    let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any] } ?? [:]
                    guard (200 ..< 300).contains(status), (parsed["ok"] as? Bool ?? true) else {
                        let msg = (parsed["error"] as? String) ?? "HTTP \(status)"
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "FullGramAdmin", code: status, userInfo: [NSLocalizedDescriptionKey: msg])))
                        }
                        return
                    }
                    DispatchQueue.main.async { completion(.success(parsed)) }
                }.resume()
            }
        }
    }
}

public enum FullGramSponsorTier: String, Sendable, Equatable {
    case none
    case sponsor
    case sponsorPlus

    public var workerValue: String {
        switch self {
        case .sponsorPlus: return "plus"
        case .sponsor, .none: return "standard"
        }
    }
}

public final class FullGramSponsors: @unchecked Sendable {
    public static let shared = FullGramSponsors()
    public static let didChangeNotification = Notification.Name("FullGram.SponsorsDidChange")

    private static let sponsorsURL = FullGramAdmin.workerBaseURL + "/sponsors.json"
    private static let lastSyncKey = "fullgram_sponsors_last_sync"

    private let lock = NSLock()
    private var sponsorTiers: [Int64: FullGramSponsorTier] = [:]
    private var isRefreshing = false
    private var pendingCompletions: [@Sendable (Bool) -> Void] = []

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_sponsors.json")
    }

    private init() {
        self.loadCache()
    }

    private static func parseTiers(from sponsors: [String: Any]) -> [Int64: FullGramSponsorTier] {
        var tiers: [Int64: FullGramSponsorTier] = [:]
        for (key, value) in sponsors {
            guard let parsed = Int64(key), parsed != 0 else { continue }
            let norm = FullGramCloudCosmetics.normalizedPeerId(parsed)
            var resolvedTier: FullGramSponsorTier = .sponsor
            if let dict = value as? [String: Any], let rawTier = dict["tier"] as? String {
                let lowered = rawTier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lowered == "plus" || lowered == "sponsor_plus" || lowered == "sponsor+" || lowered == "+" {
                    resolvedTier = .sponsorPlus
                }
            }
            tiers[norm] = resolvedTier
        }
        return tiers
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: self.cacheFileURL),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let sponsors = json["sponsors"] as? [String: Any] else {
            return
        }
        let parsedTiers = Self.parseTiers(from: sponsors)
        self.lock.lock()
        self.sponsorTiers = parsedTiers
        self.lock.unlock()
    }

    public func tier(forPeerId peerId: Int64) -> FullGramSponsorTier {
        let norm = FullGramCloudCosmetics.normalizedPeerId(peerId)
        self.lock.lock()
        let result = self.sponsorTiers[norm] ?? .none
        self.lock.unlock()
        return result
    }

    public func isSponsor(peerId: Int64) -> Bool {
        return self.tier(forPeerId: peerId) != .none
    }

    public func isSponsorPlus(peerId: Int64) -> Bool {
        return self.tier(forPeerId: peerId) == .sponsorPlus
    }

    public func setLocalSponsor(peerId: Int64, enabled: Bool, tier: FullGramSponsorTier = .sponsor) {
        let norm = FullGramCloudCosmetics.normalizedPeerId(peerId)
        self.lock.lock()
        if enabled {
            self.sponsorTiers[norm] = (tier == .none ? .sponsor : tier)
        } else {
            self.sponsorTiers.removeValue(forKey: norm)
        }
        self.lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    public func refreshIfNeeded(maxAge: TimeInterval = 45.0) {
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if Date().timeIntervalSince1970 - last < maxAge {
            return
        }
        self.refreshNow(completion: nil)
    }

    public func refreshNow(completion: (@Sendable (Bool) -> Void)? = nil) {
        guard let url = URL(string: Self.sponsorsURL) else {
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
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            let finish: @Sendable (Bool) -> Void = { ok in
                self.lock.lock()
                self.isRefreshing = false
                let callbacks = self.pendingCompletions
                self.pendingCompletions.removeAll()
                self.lock.unlock()
                DispatchQueue.main.async {
                    if ok {
                        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                    }
                    for cb in callbacks {
                        cb(ok)
                    }
                }
            }

            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let sponsors = json["sponsors"] as? [String: Any] else {
                finish(false)
                return
            }

            try? data.write(to: self.cacheFileURL, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)

            let parsedTiers = Self.parseTiers(from: sponsors)
            self.lock.lock()
            self.sponsorTiers = parsedTiers
            self.lock.unlock()
            finish(true)
        }.resume()
    }
}

public final class FullGramBetaAccess: @unchecked Sendable {
    public static let shared = FullGramBetaAccess()
    public static let didChangeNotification = Notification.Name("FullGram.BetaAccessDidChange")

    private let keychainService = "FullGram.Beta.Access"
    private let receiptAccount = "beta_receipt_v1"
    private let peerIdAccount = "beta_peer_v1"
    private let pendingCodeDefaultsKey = "FullGram.Beta.PendingCode"
    private let lock = NSLock()
    private var cachedActivated: Bool?
    private var cachedPeerId: String?
    private var lastServerCheck: TimeInterval = 0

    private init() {}

    private func readKeychain(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeKeychain(_ value: String, account: String) {
        self.deleteKeychain(account)
        guard let data = value.data(using: .utf8), !value.isEmpty else { return }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func deleteKeychain(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    public func storePendingCode(_ code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: self.pendingCodeDefaultsKey)
    }

    public func consumePendingCode() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: self.pendingCodeDefaultsKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: self.pendingCodeDefaultsKey)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var isActivated: Bool {
        self.lock.lock()
        if let cached = self.cachedActivated {
            self.lock.unlock()
            return cached
        }
        let receipt = self.readKeychain(self.receiptAccount)
        let peerId = self.readKeychain(self.peerIdAccount)
        let valid = Self.isStructurallyValidReceipt(receipt)
        self.cachedActivated = valid
        self.cachedPeerId = peerId
        self.lock.unlock()
        return valid
    }

    public func isUnlocked(forPeerId peerId: Int64?) -> Bool {
        let normId = peerId.map { FullGramCloudCosmetics.normalizedPeerId($0) } ?? 0
        if normId == FullGramAdmin.ownerUserId {
            return true
        }
        if self.isActivated {
            self.lock.lock()
            let storedPeer = self.cachedPeerId ?? self.readKeychain(self.peerIdAccount)
            self.cachedPeerId = storedPeer
            self.lock.unlock()
            guard let storedPeer, !storedPeer.isEmpty, normId > 0 else {
                return false
            }
            return storedPeer == String(normId)
        }
        return false
    }

    private static func isStructurallyValidReceipt(_ receipt: String?) -> Bool {
        guard let receipt, receipt.hasPrefix("fgba1.") else { return false }
        let parts = receipt.split(separator: ".")
        return parts.count == 3 && parts[1].count >= 12 && parts[2].count >= 16
    }

    public func clearActivation() {
        self.lock.lock()
        let wasActive = self.cachedActivated == true || self.readKeychain(self.receiptAccount) != nil
        self.cachedActivated = false
        self.cachedPeerId = nil
        self.lastServerCheck = 0
        self.lock.unlock()
        self.deleteKeychain(self.receiptAccount)
        self.deleteKeychain(self.peerIdAccount)
        if wasActive {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            }
        }
    }

    public static func extractBetaCode(from url: URL) -> String? {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        if scheme == "fullgram" && (host == "beta" || host == "activate" || url.path.lowercased().hasPrefix("/beta")) {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = comps.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !code.isEmpty {
                return code
            }
            let parts = url.pathComponents.filter { $0 != "/" }
            if (host == "beta" || host == "activate"), let first = parts.first, !first.isEmpty {
                return first.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if parts.count >= 2 && parts[0].lowercased() == "beta" {
                let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty { return code }
            }
        }
        if scheme == "tg" && host == "fullgram" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.isEmpty || parts[0].lowercased() == "beta" {
                if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = comps.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !code.isEmpty {
                    return code
                }
                if parts.count >= 2 && parts[0].lowercased() == "beta" {
                    let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !code.isEmpty { return code }
                }
            }
        }
        if (scheme == "https" || scheme == "http") && host.contains("fullgram") {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 && parts[0].lowercased() == "beta" {
                let code = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    return code
                }
            }
            if parts.first?.lowercased() == "beta",
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = comps.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !code.isEmpty {
                return code
            }
        }
        return nil
    }

    public static func extractBetaCode(fromRawInput raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed) {
            if let extracted = self.extractBetaCode(from: url) {
                return extracted
            }
            let host = url.host?.lowercased() ?? ""
            if (host == "t.me" || host == "telegram.me" || host == "telegram.dog"),
               let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let start = comps.queryItems?.first(where: { $0.name.lowercased() == "start" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !start.isEmpty {
                if start.lowercased().hasPrefix("beta_") || start.lowercased().hasPrefix("beta-") {
                    let code = String(start.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !code.isEmpty { return code }
                }
                return start
            }
        }
        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            return trimmed
        }
        return nil
    }

    public static func isBetaSyncURL(_ url: URL) -> Bool {
        guard self.extractBetaCode(from: url) == nil else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        if scheme == "fullgram" && (host == "beta" || url.path.lowercased().hasPrefix("/beta")) {
            return true
        }
        if scheme == "tg" && host == "fullgram" {
            let path = url.path.lowercased()
            return path == "/beta" || path == "beta"
        }
        return false
    }

    public func activate(
        code: String,
        peerId: Int64,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let normId = FullGramCloudCosmetics.normalizedPeerId(peerId)
        guard !cleanCode.isEmpty, normId > 0,
              let url = URL(string: FullGramAdmin.workerBaseURL + "/beta/activate") else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "FullGramBeta", code: 400, userInfo: [NSLocalizedDescriptionKey: "Некорректный код приглашения или аккаунт."])))
            }
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "code": cleanCode,
            "peerId": String(normId),
            "deviceSecret": FullGramAdmin.shared.deviceSecretValue()
        ], options: [])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any] } ?? [:]
            guard (200 ..< 300).contains(status),
                  (parsed["ok"] as? Bool) == true,
                  let receipt = parsed["receipt"] as? String,
                  Self.isStructurallyValidReceipt(receipt) else {
                let msg = (parsed["error"] as? String) ?? "Активация отклонена (HTTP \(status))"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "FullGramBeta", code: status, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
                return
            }
            self?.writeKeychain(receipt, account: self?.receiptAccount ?? "beta_receipt_v1")
            self?.writeKeychain(String(normId), account: self?.peerIdAccount ?? "beta_peer_v1")
            self?.lock.lock()
            self?.cachedActivated = true
            self?.cachedPeerId = String(normId)
            self?.lastServerCheck = Date().timeIntervalSince1970
            self?.lock.unlock()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                completion(.success(()))
            }
        }.resume()
    }

    public func syncWithServer(
        peerId: Int64,
        force: Bool = false,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        let normId = FullGramCloudCosmetics.normalizedPeerId(peerId)
        guard normId > 0 else {
            if let completion {
                DispatchQueue.main.async { completion(false) }
            }
            return
        }
        if normId == FullGramAdmin.ownerUserId {
            if let completion {
                DispatchQueue.main.async { completion(true) }
            }
            return
        }

        self.lock.lock()
        let now = Date().timeIntervalSince1970
        let existingReceipt = self.readKeychain(self.receiptAccount)
        let existingPeer = self.readKeychain(self.peerIdAccount)
        let currentlyActivated = Self.isStructurallyValidReceipt(existingReceipt) && existingPeer == String(normId)
        let minInterval: TimeInterval = currentlyActivated ? 120.0 : 15.0
        let shouldCheck = force || (now - self.lastServerCheck) >= minInterval
        if shouldCheck {
            self.lastServerCheck = now
        }
        self.lock.unlock()

        guard shouldCheck, let url = URL(string: FullGramAdmin.workerBaseURL + "/beta/check") else {
            if let completion {
                let unlocked = self.isUnlocked(forPeerId: normId)
                DispatchQueue.main.async { completion(unlocked) }
            }
            return
        }

        var payload: [String: Any] = [
            "peerId": String(normId),
            "deviceSecret": FullGramAdmin.shared.deviceSecretValue()
        ]
        if let existingReceipt, !existingReceipt.isEmpty {
            payload["receipt"] = existingReceipt
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12.0
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self else { return }
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let data,
                  let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  (parsed["ok"] as? Bool) == true,
                  let active = parsed["active"] as? Bool else {
                if let completion {
                    let unlocked = self.isUnlocked(forPeerId: normId)
                    DispatchQueue.main.async { completion(unlocked) }
                }
                return
            }

            if active {
                if let receipt = parsed["receipt"] as? String, Self.isStructurallyValidReceipt(receipt) {
                    self.writeKeychain(receipt, account: self.receiptAccount)
                    self.writeKeychain(String(normId), account: self.peerIdAccount)
                    self.lock.lock()
                    let changed = self.cachedActivated != true || self.cachedPeerId != String(normId)
                    self.cachedActivated = true
                    self.cachedPeerId = String(normId)
                    self.lock.unlock()
                    if changed {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                        }
                    }
                }
                if let completion {
                    DispatchQueue.main.async { completion(true) }
                }
            } else {
                self.clearActivation()
                if let completion {
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }.resume()
    }

    public func verifyWithServerIfNeeded(peerId: Int64) {
        self.syncWithServer(peerId: peerId, force: false, completion: nil)
    }
}
