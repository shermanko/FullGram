import Foundation
import Security

public final class FullGramAdmin {
    public static let shared = FullGramAdmin()
    public static let ownerUserId: Int64 = 8899688273
    public static let workerBaseURL = "https://fullgram.korsakovx.workers.dev"

    private let keychainService = "FullGram.Admin.Token"
    private let keychainAccount = "owner_token"

    private init() {}

    public static func isOwnerUserId(_ userId: Int64) -> Bool {
        return userId == self.ownerUserId
    }

    // MARK: - Keychain Token Storage

    public var hasToken: Bool {
        guard let token = self.getToken() else { return false }
        return !token.isEmpty
    }

    public func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: self.keychainAccount,
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

    public func setToken(_ rawToken: String) {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clearToken()
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            return
        }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: self.keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    public func clearToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.keychainService,
            kSecAttrAccount as String: self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Admin Requests

    private func makeAdminRequest(path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        guard let token = self.getToken(), !token.isEmpty else {
            throw NSError(
                domain: "FullGramAdmin",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Токен администратора не задан."]
            )
        }
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
}
