import Foundation
import Security

public final class FullGramAdmin: @unchecked Sendable {
    public static let shared = FullGramAdmin()
    /// UI-only hint for showing the entry point to the admin panel before server verification.
    /// Actual authorization is enforced strictly on Cloudflare Worker via Telegram-signed auth.
    public static let ownerUserId: Int64 = 8899688273
    public static let workerBaseURL = "https://fullgram.korsakovx.workers.dev"

    private let keychainService = "FullGram.Admin.Token"
    private let keychainAccount = "owner_token"
    private let initDataAccount = "telegram_init_data"
    private let lock = NSLock()
    private var verifiedAdminUserId: Int64?
    private var verifiedAuthMethod: String?

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

    private func writeKeychain(_ rawValue: String, account: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deleteKeychain(account: account)
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
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func deleteKeychain(account: String) {
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
            if trimmed.isEmpty {
                self.deleteKeychain(account: self.initDataAccount)
            }
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
            payload["peerId"] = String(peerId)
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
            "peerId": String(peerId),
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
            "peerId": String(peerId),
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
            "peerId": String(peerId),
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
}
