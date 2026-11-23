import Foundation
import UIKit

// MARK: - Облачная синхронизация косметики по ID аккаунта (как в Discord)

public struct FullGramUserCosmetics: Codable, Equatable, Sendable {
    public var frameId: String?
    public var customFrameUrl: String?
    public var profileEffectId: String?
    public var nickColor: String?
    public var nickGlow: Bool

    public init(
        frameId: String? = nil,
        customFrameUrl: String? = nil,
        profileEffectId: String? = nil,
        nickColor: String? = nil,
        nickGlow: Bool = false
    ) {
        self.frameId = frameId
        self.customFrameUrl = customFrameUrl
        self.profileEffectId = profileEffectId
        self.nickColor = nickColor
        self.nickGlow = nickGlow
    }

    private enum CodingKeys: String, CodingKey {
        case frameId
        case customFrameUrl
        case profileEffectId
        case nickColor
        case nickGlow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.frameId = try c.decodeIfPresent(String.self, forKey: .frameId)
        self.customFrameUrl = try c.decodeIfPresent(String.self, forKey: .customFrameUrl)
        self.profileEffectId = try c.decodeIfPresent(String.self, forKey: .profileEffectId)
        self.nickColor = try c.decodeIfPresent(String.self, forKey: .nickColor)
        self.nickGlow = try c.decodeIfPresent(Bool.self, forKey: .nickGlow) ?? false
    }

    public var isEmpty: Bool {
        return (self.frameId == nil || self.frameId?.isEmpty == true)
            && (self.customFrameUrl == nil || self.customFrameUrl?.isEmpty == true)
            && (self.profileEffectId == nil || self.profileEffectId?.isEmpty == true)
            && (self.nickColor == nil || self.nickColor?.isEmpty == true)
    }
}

private struct FullGramCosmeticsPayload: Codable {
    var version: Int?
    var users: [String: FullGramUserCosmetics]
}

public final class FullGramCloudCosmetics: @unchecked Sendable {
    public static let shared = FullGramCloudCosmetics()
    public static let didChangeNotification = Notification.Name("FullGram.CloudCosmeticsChanged")

    private static let cosmeticsURL = "https://fullgram.korsakovx.workers.dev/cosmetics.json"
    private static let updateEndpointURL = "https://fullgram.korsakovx.workers.dev/cosmetics"
    private static let localPrefix = "fullgram.cosmetics.user."
    private static let lastSyncKey = "fullgram.cosmetics.lastSync"

    private let lock = NSRecursiveLock()
    private var activeSelfPeerId: Int64?
    private var localCache: [Int64: FullGramUserCosmetics] = [:]
    private var remoteUsers: [Int64: FullGramUserCosmetics] = [:]
    private var isRefreshing = false
    private var pendingCompletions: [(Bool) -> Void] = []
    private var pushWorkItem: DispatchWorkItem?
    private var pushGeneration: Int = 0

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10.0
        cfg.timeoutIntervalForResource = 15.0
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    private init() {
        self.loadDiskCache()
    }

    private var cacheFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("fullgram_cosmetics.json")
    }

    public static func normalizedPeerId(_ raw: Int64) -> Int64 {
        let u = UInt64(bitPattern: raw)
        if raw > 0 && u >= (1 << 35) {
            let low = u & 0xffffffff
            let high = u >> 35
            return Int64(bitPattern: (high << 32) | low)
        }
        return raw < 0 ? abs(raw) : raw
    }

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: self.cacheFileURL),
              let payload = try? JSONDecoder().decode(FullGramCosmeticsPayload.self, from: data) else {
            return
        }
        var mapped: [Int64: FullGramUserCosmetics] = [:]
        for (k, v) in payload.users {
            if let id = Int64(k), !v.isEmpty {
                mapped[Self.normalizedPeerId(id)] = v
            }
        }
        self.lock.lock()
        self.remoteUsers = mapped
        self.lock.unlock()
    }

    public func setActiveSelfPeerId(_ peerId: Int64) {
        let norm = Self.normalizedPeerId(peerId)
        self.lock.lock()
        self.activeSelfPeerId = norm
        self.lock.unlock()
    }

    public var currentSelfPeerId: Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.activeSelfPeerId
    }

    public func localCosmetics(forPeerId peerId: Int64) -> FullGramUserCosmetics? {
        let norm = Self.normalizedPeerId(peerId)
        self.lock.lock()
        if let cached = self.localCache[norm] {
            self.lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        self.lock.unlock()

        let keysToCheck: [String] = norm == peerId
            ? [Self.localPrefix + "\(norm)"]
            : [Self.localPrefix + "\(norm)", Self.localPrefix + "\(peerId)"]
        for key in keysToCheck {
            if let data = UserDefaults.standard.data(forKey: key),
               let decoded = try? JSONDecoder().decode(FullGramUserCosmetics.self, from: data) {
                self.lock.lock()
                self.localCache[norm] = decoded
                self.lock.unlock()
                return decoded.isEmpty ? nil : decoded
            }
        }

        // Fall back to remote entry if user logged into the same account on a fresh device
        self.lock.lock()
        let remote = self.remoteUsers[norm]
        self.lock.unlock()
        return remote
    }

    public func cosmetics(forPeerId peerId: Int64?, selfPeerId: Int64?) -> FullGramUserCosmetics? {
        guard let peerId, peerId != 0 else { return nil }
        let normPeer = Self.normalizedPeerId(peerId)
        let effectiveSelfId = selfPeerId.map { Self.normalizedPeerId($0) } ?? self.currentSelfPeerId
        if let effectiveSelfId, normPeer == effectiveSelfId {
            return self.localCosmetics(forPeerId: normPeer)
        }
        self.lock.lock()
        let remote = self.remoteUsers[normPeer]
        self.lock.unlock()
        return remote
    }

    public func setFrame(forPeerId peerId: Int64, frameId: String?, customFrameUrl: String? = nil) {
        let norm = Self.normalizedPeerId(peerId)
        self.setActiveSelfPeerId(norm)
        var entry = self.localCosmetics(forPeerId: norm) ?? FullGramUserCosmetics()
        let cleaned = frameId?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.frameId = (cleaned?.isEmpty == false) ? cleaned : nil
        let cleanedUrl = customFrameUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.customFrameUrl = (cleanedUrl?.isEmpty == false) ? cleanedUrl : nil
        self.saveLocal(entry, forPeerId: norm)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramAvatarFrames.didChangeNotification, object: nil)
        self.pushToCloud(peerId: norm, entry: entry)
    }

    public func setProfileEffect(forPeerId peerId: Int64, effectId: String?) {
        let norm = Self.normalizedPeerId(peerId)
        self.setActiveSelfPeerId(norm)
        var entry = self.localCosmetics(forPeerId: norm) ?? FullGramUserCosmetics()
        let cleaned = effectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.profileEffectId = (cleaned?.isEmpty == false) ? cleaned : nil
        self.saveLocal(entry, forPeerId: norm)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramProfileEffects.didChangeNotification, object: nil)
        self.pushToCloud(peerId: norm, entry: entry)
    }

    public func setNickStyle(forPeerId peerId: Int64, colorHex: String?, glowEnabled: Bool) {
        let norm = Self.normalizedPeerId(peerId)
        self.setActiveSelfPeerId(norm)
        var entry = self.localCosmetics(forPeerId: norm) ?? FullGramUserCosmetics()
        let cleaned = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        entry.nickColor = (cleaned?.isEmpty == false) ? cleaned : nil
        entry.nickGlow = entry.nickColor != nil ? glowEnabled : false
        self.saveLocal(entry, forPeerId: norm)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramNicknameStyle.didChangeNotification, object: nil)
        self.pushToCloud(peerId: norm, entry: entry)
    }

    private func saveLocal(_ entry: FullGramUserCosmetics, forPeerId peerId: Int64) {
        let norm = Self.normalizedPeerId(peerId)
        self.lock.lock()
        self.localCache[norm] = entry
        if entry.isEmpty {
            self.remoteUsers.removeValue(forKey: norm)
        } else {
            self.remoteUsers[norm] = entry
        }
        self.lock.unlock()

        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: Self.localPrefix + "\(norm)")
        }
    }

    private func pushToCloud(peerId: Int64, entry: FullGramUserCosmetics) {
        let norm = Self.normalizedPeerId(peerId)
        self.lock.lock()
        self.pushWorkItem?.cancel()
        self.pushGeneration &+= 1
        let gen = self.pushGeneration
        let item = DispatchWorkItem { [weak self] in
            self?.performPushToCloud(peerId: norm, entry: entry, generation: gen)
        }
        self.pushWorkItem = item
        self.lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.65, execute: item)
    }

    private func performPushToCloud(peerId norm: Int64, entry: FullGramUserCosmetics, generation: Int, didRetry: Bool = false) {
        self.lock.lock()
        let isLatest = (self.pushGeneration == generation)
        self.lock.unlock()
        guard isLatest, let url = URL(string: Self.updateEndpointURL) else { return }

        let cloudFrameId = (entry.frameId == "custom_local") ? "" : (entry.frameId ?? "")
        let body: [String: Any] = [
            "peerId": String(norm),
            "frameId": cloudFrameId,
            "customFrameUrl": entry.customFrameUrl ?? "",
            "profileEffectId": entry.profileEffectId ?? "",
            "nickColor": entry.nickColor ?? "",
            "nickGlow": entry.nickGlow
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { return }

        FullGramAdmin.shared.ensureClientSession(peerId: norm, forceRefresh: didRetry) { [weak self] sessionResult in
            guard let self else { return }
            self.lock.lock()
            let stillLatest = (self.pushGeneration == generation)
            self.lock.unlock()
            guard stillLatest else { return }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 15.0
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let clientToken = (try? sessionResult.get())
            guard FullGramAdmin.shared.applyClientOrAdminAuthHeaders(to: &req, preferredClientToken: clientToken) else {
                return
            }
            req.httpBody = data
            Self.session.dataTask(with: req) { [weak self] _, response, _ in
                guard let self else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 && !didRetry {
                    FullGramAdmin.shared.clearClientSession()
                    self.performPushToCloud(peerId: norm, entry: entry, generation: generation, didRetry: true)
                    return
                }
                if (200 ..< 300).contains(status) {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)
                }
            }.resume()
        }
    }

    public func uploadCustomFrame(
        peerId: Int64,
        data: Data,
        isGif: Bool = false,
        didRetry: Bool = false,
        completion: (@Sendable (Result<String, Error>) -> Void)? = nil
    ) {
        let norm = Self.normalizedPeerId(peerId)
        guard norm > 0, !data.isEmpty else {
            completion?(.failure(NSError(domain: "FullGramCloudCosmetics", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid frame data"])))
            return
        }
        var preparedData = data
        if !isGif, preparedData.count > 1_200_000, let uiImg = UIImage(data: preparedData) {
            let targetSize = CGSize(width: 320.0, height: 320.0)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let resized = renderer.image { _ in
                uiImg.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            if let png = resized.pngData(), !png.isEmpty {
                preparedData = png
            }
        }
        let finalPayloadData = preparedData
        guard let uploadURL = URL(string: FullGramAdmin.workerBaseURL + "/cosmetics/upload-frame") else {
            completion?(.failure(NSError(domain: "FullGramCloudCosmetics", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        FullGramAdmin.shared.ensureClientSession(peerId: norm, forceRefresh: didRetry) { [weak self] sessionResult in
            guard let self else { return }
            switch sessionResult {
            case let .failure(err):
                DispatchQueue.main.async { completion?(.failure(err)) }
            case let .success(token):
                let payload: [String: Any] = [
                    "peerId": String(norm),
                    "imageBase64": finalPayloadData.base64EncodedString(),
                    "ext": isGif ? "gif" : "png"
                ]
                guard let bodyData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
                    DispatchQueue.main.async {
                        completion?(.failure(NSError(domain: "FullGramCloudCosmetics", code: 400, userInfo: [NSLocalizedDescriptionKey: "Encoding error"])))
                    }
                    return
                }
                var req = URLRequest(url: uploadURL)
                req.httpMethod = "POST"
                req.timeoutInterval = 25.0
                req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                _ = FullGramAdmin.shared.applyClientOrAdminAuthHeaders(to: &req, preferredClientToken: token)
                req.httpBody = bodyData

                Self.session.dataTask(with: req) { [weak self] respData, response, error in
                    guard let self else { return }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status == 401 && !didRetry {
                        FullGramAdmin.shared.clearClientSession()
                        self.uploadCustomFrame(peerId: norm, data: data, isGif: isGif, didRetry: true, completion: completion)
                        return
                    }
                    if let error {
                        DispatchQueue.main.async { completion?(.failure(error)) }
                        return
                    }
                    let json = respData.flatMap { try? JSONSerialization.jsonObject(with: $0, options: []) as? [String: Any] } ?? [:]
                    if (200 ..< 300).contains(status), let remoteUrl = json["url"] as? String, !remoteUrl.isEmpty {
                        self.setFrame(forPeerId: norm, frameId: "custom", customFrameUrl: remoteUrl)
                        DispatchQueue.main.async { completion?(.success(remoteUrl)) }
                    } else {
                        let msg = (json["error"] as? String) ?? "HTTP \(status)"
                        DispatchQueue.main.async {
                            completion?(.failure(NSError(domain: "FullGramCloudCosmetics", code: status, userInfo: [NSLocalizedDescriptionKey: msg])))
                        }
                    }
                }.resume()
            }
        }
    }

    public func refreshIfNeeded(maxAge: TimeInterval = 25.0) {
        let last = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if Date().timeIntervalSince1970 - last < maxAge {
            return
        }
        self.refreshNow(completion: nil)
    }

    public func refreshNow(completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: Self.cosmeticsURL) else {
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
                        NotificationCenter.default.post(name: FullGramAvatarFrames.didChangeNotification, object: nil)
                        NotificationCenter.default.post(name: FullGramProfileEffects.didChangeNotification, object: nil)
                        NotificationCenter.default.post(name: FullGramNicknameStyle.didChangeNotification, object: nil)
                    }
                    for cb in completions { cb(ok) }
                }
            }
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let data,
                  data.count <= 1_000_000,
                  let payload = try? JSONDecoder().decode(FullGramCosmeticsPayload.self, from: data) else {
                drainCompletions(false)
                return
            }

            try? data.write(to: self.cacheFileURL, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)

            var mapped: [Int64: FullGramUserCosmetics] = [:]
            for (k, v) in payload.users {
                if let id = Int64(k), !v.isEmpty {
                    mapped[Self.normalizedPeerId(id)] = v
                }
            }
            self.lock.lock()
            self.remoteUsers = mapped
            self.lock.unlock()

            drainCompletions(true)
        }.resume()
    }
}

// MARK: - Кастомные стили ников (палитра цветов + неоновое свечение на профиль)

public struct FullGramNicknameColorOption: Equatable, Sendable {
    public let id: String
    public let title: String
    public let hex: String
}

public enum FullGramNicknameStyle {
    public static let didChangeNotification = Notification.Name("FullGram.NicknameStyleChanged")

    public static let palette: [FullGramNicknameColorOption] = [
        FullGramNicknameColorOption(id: "cyan", title: "Неоновый бирюзовый", hex: "#00F5D4"),
        FullGramNicknameColorOption(id: "pink", title: "Неоновый розовый", hex: "#FF2A85"),
        FullGramNicknameColorOption(id: "blue", title: "Электрик синий", hex: "#0A84FF"),
        FullGramNicknameColorOption(id: "purple", title: "Фиолетовый неон", hex: "#BF5AF2"),
        FullGramNicknameColorOption(id: "gold", title: "Золотой", hex: "#FFD60A"),
        FullGramNicknameColorOption(id: "orange", title: "Огненный оранжевый", hex: "#FF9500"),
        FullGramNicknameColorOption(id: "red", title: "Неоновый алый", hex: "#FF3B30"),
        FullGramNicknameColorOption(id: "green", title: "Матричный зелёный", hex: "#00FF66"),
        FullGramNicknameColorOption(id: "emerald", title: "Изумрудный", hex: "#30D158"),
        FullGramNicknameColorOption(id: "ice", title: "Ледяной голубой", hex: "#64D2FF"),
        FullGramNicknameColorOption(id: "lavender", title: "Лавандовый", hex: "#A78BFA"),
        FullGramNicknameColorOption(id: "sakura", title: "Сакура", hex: "#FF85B3"),
        FullGramNicknameColorOption(id: "lime", title: "Кислотный лайм", hex: "#A3E635"),
        FullGramNicknameColorOption(id: "indigo", title: "Индиго", hex: "#5E5CE6"),
        FullGramNicknameColorOption(id: "coral", title: "Коралловый", hex: "#FB7185"),
        FullGramNicknameColorOption(id: "silver", title: "Белый хром", hex: "#F8FAFC")
    ]

    public static func colorHex(forPeerId peerId: Int64?, selfPeerId: Int64?) -> String? {
        guard let cosmetics = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId),
              let hex = cosmetics.nickColor,
              !hex.isEmpty else {
            return nil
        }
        return hex
    }

    public static func glowEnabled(forPeerId peerId: Int64?, selfPeerId: Int64?) -> Bool {
        guard let cosmetics = FullGramCloudCosmetics.shared.cosmetics(forPeerId: peerId, selfPeerId: selfPeerId) else {
            return false
        }
        return cosmetics.nickGlow
    }

    public static func style(forPeerId peerId: Int64?, selfPeerId: Int64?) -> (color: UIColor, glowEnabled: Bool)? {
        guard let hex = self.colorHex(forPeerId: peerId, selfPeerId: selfPeerId),
              let rgb = FullGramThemeColors.parse(hex) else {
            return nil
        }
        let glow = self.glowEnabled(forPeerId: peerId, selfPeerId: selfPeerId)
        return (UIColor(rgb: rgb), glow)
    }

    public static func setOwnStyle(peerId: Int64, colorHex: String?, glowEnabled: Bool) {
        FullGramCloudCosmetics.shared.setNickStyle(forPeerId: peerId, colorHex: colorHex, glowEnabled: glowEnabled)
    }

    public static func statusSummary(forPeerId peerId: Int64, selfPeerId: Int64?) -> String {
        guard let hex = self.colorHex(forPeerId: peerId, selfPeerId: selfPeerId) else {
            return "Стандартный"
        }
        let option = self.palette.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame })?.title ?? hex
        let glow = self.glowEnabled(forPeerId: peerId, selfPeerId: selfPeerId)
        return glow ? "\(option) · Неон" : option
    }

    public static func styledAttributedString(
        _ text: String,
        baseFont: UIFont,
        baseColor: UIColor,
        peerId: Int64?,
        selfPeerId: Int64?
    ) -> NSAttributedString {
        guard !text.isEmpty, let style = self.style(forPeerId: peerId, selfPeerId: selfPeerId) else {
            return NSAttributedString(string: text, attributes: [.font: baseFont, .foregroundColor: baseColor])
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: style.color
        ]
        if style.glowEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = style.color.withAlphaComponent(0.90)
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 9.0
            attrs[.shadow] = shadow
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    public static func applyGlow(to layer: CALayer, style: (color: UIColor, glowEnabled: Bool)?, radius: CGFloat = 9.0) {
        if let style, style.glowEnabled {
            layer.shadowColor = style.color.cgColor
            layer.shadowRadius = radius
            layer.shadowOpacity = 1.0
            layer.shadowOffset = .zero
            layer.masksToBounds = false
        } else if layer.shadowOpacity != 0.0 {
            layer.shadowColor = nil
            layer.shadowRadius = 0.0
            layer.shadowOpacity = 0.0
        }
    }
}

// MARK: - Анимация удаления сообщения (скомканный лист бумаги -> в мусорку, редизайн v1.5.5)

public enum FullGramPaperTrashAnimator {
    @MainActor
    public static func animateDelete(snapshots: [(view: UIView, frameInHost: CGRect)], in hostView: UIView, styleRaw: Int = 1) {
        guard !snapshots.isEmpty, styleRaw != 0 else { return }

        if styleRaw == 2 {
            self.animateParticles(snapshots: snapshots, in: hostView)
            return
        }
        if styleRaw == 3 {
            self.animateBlackHole(snapshots: snapshots, in: hostView)
            return
        }
        if styleRaw == 4 {
            self.animateExplosion(snapshots: snapshots, in: hostView)
            return
        }

        let binSize = CGSize(width: 108.0, height: 122.0)
        let safeBottom = hostView.safeAreaInsets.bottom
        let binCenter = CGPoint(
            x: hostView.bounds.midX,
            y: hostView.bounds.height - safeBottom - 104.0
        )

        let binView = FullGramTrashBinView(frame: CGRect(
            x: binCenter.x - binSize.width * 0.5,
            y: binCenter.y - binSize.height * 0.5,
            width: binSize.width,
            height: binSize.height
        ))
        binView.alpha = 0.0
        binView.transform = CGAffineTransform(translationX: 0.0, y: 44.0).scaledBy(x: 0.65, y: 0.65)
        hostView.addSubview(binView)

        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.prepare()

        UIView.animate(withDuration: 0.28, delay: 0.0, usingSpringWithDamping: 0.68, initialSpringVelocity: 0.6, options: [.allowUserInteraction]) {
            binView.alpha = 1.0
            binView.transform = .identity
        }
        binView.setLidOpen(true, delay: 0.05)

        let batch = Array(snapshots.prefix(5))
        for (idx, item) in batch.enumerated() {
            let delay = Double(idx) * 0.065
            let snapshot = item.view
            snapshot.frame = item.frameInHost
            snapshot.layer.cornerRadius = 16.0
            snapshot.clipsToBounds = true
            hostView.addSubview(snapshot)

            let ballSide: CGFloat = 56.0
            let paperBall = FullGramCrumpledPaperBallView(frame: CGRect(x: 0.0, y: 0.0, width: ballSide, height: ballSide))
            paperBall.center = CGPoint(x: item.frameInHost.midX, y: item.frameInHost.midY)
            paperBall.alpha = 0.0
            paperBall.transform = CGAffineTransform(scaleX: 1.45, y: 1.45).rotated(by: idx % 2 == 0 ? -0.35 : 0.35)
            hostView.addSubview(paperBall)

            // Phase 1: Crumple message bubble into a large 3D-faceted paper ball
            UIView.animate(withDuration: 0.22, delay: delay, options: [.curveEaseInOut]) {
                snapshot.transform = CGAffineTransform(scaleX: 0.16, y: 0.14).rotated(by: idx % 2 == 0 ? 0.42 : -0.42)
                snapshot.alpha = 0.0
                paperBall.alpha = 1.0
                paperBall.transform = CGAffineTransform(scaleX: 1.08, y: 1.08).rotated(by: idx % 2 == 0 ? 0.45 : -0.45)
            } completion: { _ in
                snapshot.removeFromSuperview()
            }

            // Phase 2: High parabolic toss into the open trash bin mouth
            let startPt = paperBall.center
            let endPt = CGPoint(x: binCenter.x + CGFloat(idx % 3 - 1) * 4.0, y: binCenter.y - 12.0)
            let horizontalBias: CGFloat = (startPt.x < binCenter.x ? 34.0 : -34.0) + (idx % 2 == 0 ? 14.0 : -14.0)
            let arcHeight: CGFloat = max(110.0, min(180.0, abs(startPt.y - endPt.y) * 0.35 + 95.0))
            let ctrlPt = CGPoint(
                x: (startPt.x + endPt.x) * 0.5 + horizontalBias,
                y: min(startPt.y, endPt.y) - arcHeight
            )
            let arcPath = UIBezierPath()
            arcPath.move(to: startPt)
            arcPath.addQuadCurve(to: endPt, controlPoint: ctrlPt)

            let throwStart = CACurrentMediaTime() + delay + 0.19
            let throwDuration: Double = 0.42

            let posAnim = CAKeyframeAnimation(keyPath: "position")
            posAnim.path = arcPath.cgPath
            posAnim.duration = throwDuration
            posAnim.beginTime = throwStart
            posAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.08, 0.72, 1.0)
            posAnim.fillMode = .forwards
            posAnim.isRemovedOnCompletion = false
            paperBall.layer.add(posAnim, forKey: "fg.throw")

            let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
            rotAnim.fromValue = idx % 2 == 0 ? 0.45 : -0.45
            rotAnim.toValue = Double.pi * (idx % 2 == 0 ? 3.8 : -3.8)
            rotAnim.duration = throwDuration
            rotAnim.beginTime = throwStart
            paperBall.layer.add(rotAnim, forKey: "fg.spin")

            let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnim.values = [1.08, 1.24, 0.92, 0.48]
            scaleAnim.keyTimes = [0.0, 0.42, 0.82, 1.0]
            scaleAnim.duration = throwDuration
            scaleAnim.beginTime = throwStart
            scaleAnim.fillMode = .forwards
            scaleAnim.isRemovedOnCompletion = false
            paperBall.layer.add(scaleAnim, forKey: "fg.scale")

            UIView.animate(withDuration: 0.12, delay: delay + 0.19 + throwDuration - 0.10, options: [.curveEaseIn]) {
                paperBall.alpha = 0.0
            } completion: { _ in
                paperBall.removeFromSuperview()
            }

            // Impact squash & dust puff when each paper ball lands in the bin
            let impactDelay = delay + 0.19 + throwDuration - 0.04
            Task { @MainActor [weak binView] in
                try? await Task.sleep(nanoseconds: UInt64(impactDelay * 1_000_000_000))
                guard let binView else { return }
                if idx == 0 || idx == batch.count - 1 {
                    haptic.impactOccurred(intensity: 0.75)
                }
                binView.pulseImpact()
            }
        }

        let finishDelay = Double(batch.count) * 0.065 + 0.64
        binView.setLidOpen(false, delay: finishDelay - 0.06)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((finishDelay + 0.16) * 1_000_000_000))
            UIView.animate(withDuration: 0.24, delay: 0.0, options: [.curveEaseIn]) {
                binView.alpha = 0.0
                binView.transform = CGAffineTransform(translationX: 0.0, y: 36.0).scaledBy(x: 0.76, y: 0.76)
            } completion: { _ in
                binView.removeFromSuperview()
            }
        }
    }

    @MainActor
    private static func makeParticleImage(color: UIColor, size: CGFloat = 10.0) -> CGImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            color.setFill()
            ctx.cgContext.fillEllipse(in: rect)
        }.cgImage
    }

    @MainActor
    private static func animateParticles(snapshots: [(view: UIView, frameInHost: CGRect)], in hostView: UIView) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.prepare()
        haptic.impactOccurred(intensity: 0.65)
        let particleCG = self.makeParticleImage(color: .white, size: 8.0)

        for (idx, item) in snapshots.prefix(6).enumerated() {
            let delay = Double(idx) * 0.04
            let snap = item.view
            snap.frame = item.frameInHost
            snap.layer.cornerRadius = 14.0
            snap.clipsToBounds = true
            hostView.addSubview(snap)

            let emitter = CAEmitterLayer()
            emitter.frame = item.frameInHost
            emitter.emitterPosition = CGPoint(x: item.frameInHost.width * 0.5, y: item.frameInHost.height * 0.5)
            emitter.emitterSize = item.frameInHost.size
            emitter.emitterShape = .rectangle
            emitter.emitterMode = .volume

            let cell1 = CAEmitterCell()
            cell1.contents = particleCG
            cell1.color = UIColor(rgb: 0x70D7FF).cgColor
            cell1.birthRate = 220
            cell1.lifetime = 0.65
            cell1.lifetimeRange = 0.25
            cell1.velocity = 75
            cell1.velocityRange = 45
            cell1.emissionRange = .pi * 2.0
            cell1.yAcceleration = -65
            cell1.scale = 0.55
            cell1.scaleRange = 0.35
            cell1.alphaSpeed = -1.5

            let cell2 = CAEmitterCell()
            cell2.contents = particleCG
            cell2.color = UIColor(rgb: 0xFFFFFF).cgColor
            cell2.birthRate = 140
            cell2.lifetime = 0.55
            cell2.velocity = 95
            cell2.velocityRange = 40
            cell2.emissionRange = .pi * 2.0
            cell2.yAcceleration = -40
            cell2.scale = 0.38
            cell2.alphaSpeed = -1.7

            emitter.emitterCells = [cell1, cell2]
            hostView.layer.addSublayer(emitter)

            UIView.animate(withDuration: 0.36, delay: delay, options: [.curveEaseIn]) {
                snap.alpha = 0.0
                snap.transform = CGAffineTransform(translationX: 0.0, y: -12.0).scaledBy(x: 0.92, y: 0.92)
            } completion: { _ in
                snap.removeFromSuperview()
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((delay + 0.14) * 1_000_000_000))
                emitter.birthRate = 0.0
                try? await Task.sleep(nanoseconds: 800_000_000)
                emitter.removeFromSuperlayer()
            }
        }
    }

    @MainActor
    private static func animateBlackHole(snapshots: [(view: UIView, frameInHost: CGRect)], in hostView: UIView) {
        let holeCenter = CGPoint(x: hostView.bounds.midX, y: hostView.bounds.midY)
        let holeSize: CGFloat = 112.0
        let holeView = UIView(frame: CGRect(x: holeCenter.x - holeSize * 0.5, y: holeCenter.y - holeSize * 0.5, width: holeSize, height: holeSize))
        holeView.isUserInteractionEnabled = false
        holeView.alpha = 0.0
        holeView.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)

        let halo = CAShapeLayer()
        halo.path = UIBezierPath(ovalIn: holeView.bounds.insetBy(dx: 8.0, dy: 8.0)).cgPath
        halo.fillColor = UIColor.black.cgColor
        halo.strokeColor = UIColor(rgb: 0x9D4EDD).cgColor
        halo.lineWidth = 4.5
        halo.shadowColor = UIColor(rgb: 0x7B2CBF).cgColor
        halo.shadowRadius = 16.0
        halo.shadowOpacity = 0.95
        halo.shadowOffset = .zero
        holeView.layer.addSublayer(halo)

        let innerRing = CAShapeLayer()
        innerRing.path = UIBezierPath(ovalIn: holeView.bounds.insetBy(dx: 16.0, dy: 16.0)).cgPath
        innerRing.fillColor = UIColor.clear.cgColor
        innerRing.strokeColor = UIColor(rgb: 0xE0AAFF).withAlphaComponent(0.75).cgColor
        innerRing.lineWidth = 2.0
        innerRing.lineDashPattern = [10, 6]
        holeView.layer.addSublayer(innerRing)
        hostView.addSubview(holeView)

        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.prepare()
        haptic.impactOccurred(intensity: 0.8)

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0.0
        spin.toValue = Double.pi * 4.0
        spin.duration = 0.9
        holeView.layer.add(spin, forKey: "fg.bh.spin")

        UIView.animate(withDuration: 0.22, delay: 0.0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.5) {
            holeView.alpha = 1.0
            holeView.transform = .identity
        }

        let batch = Array(snapshots.prefix(5))
        for (idx, item) in batch.enumerated() {
            let delay = 0.05 + Double(idx) * 0.05
            let snap = item.view
            snap.frame = item.frameInHost
            snap.layer.cornerRadius = 14.0
            snap.clipsToBounds = true
            hostView.addSubview(snap)

            UIView.animate(withDuration: 0.44, delay: delay, options: [.curveEaseIn]) {
                snap.center = holeCenter
                snap.transform = CGAffineTransform(rotationAngle: idx % 2 == 0 ? 2.6 : -2.6).scaledBy(x: 0.04, y: 0.04)
                snap.alpha = 0.0
            } completion: { _ in
                snap.removeFromSuperview()
            }
        }

        let total = 0.55 + Double(batch.count) * 0.05
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
            UIView.animate(withDuration: 0.2, animations: {
                holeView.transform = CGAffineTransform(scaleX: 0.05, y: 0.05)
                holeView.alpha = 0.0
            }, completion: { _ in
                holeView.removeFromSuperview()
            })
        }
    }

    @MainActor
    private static func animateExplosion(snapshots: [(view: UIView, frameInHost: CGRect)], in hostView: UIView) {
        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.prepare()
        haptic.impactOccurred(intensity: 0.95)
        let sparkCG = self.makeParticleImage(color: .white, size: 10.0)

        for (idx, item) in snapshots.prefix(5).enumerated() {
            let delay = Double(idx) * 0.04
            let snap = item.view
            snap.frame = item.frameInHost
            snap.layer.cornerRadius = 14.0
            snap.clipsToBounds = true
            hostView.addSubview(snap)

            let center = CGPoint(x: item.frameInHost.midX, y: item.frameInHost.midY)
            let shockwave = CAShapeLayer()
            shockwave.bounds = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 44.0)
            shockwave.position = center
            shockwave.path = UIBezierPath(ovalIn: shockwave.bounds).cgPath
            shockwave.fillColor = UIColor(rgb: 0xFF9F0A).withAlphaComponent(0.35).cgColor
            shockwave.strokeColor = UIColor(rgb: 0xFF453A).cgColor
            shockwave.lineWidth = 3.5
            hostView.layer.addSublayer(shockwave)

            let emitter = CAEmitterLayer()
            emitter.frame = hostView.bounds
            emitter.emitterPosition = center
            emitter.emitterSize = CGSize(width: 24.0, height: 24.0)
            emitter.emitterShape = .circle

            let ember = CAEmitterCell()
            ember.contents = sparkCG
            ember.color = UIColor(rgb: 0xFF6B00).cgColor
            ember.birthRate = 320
            ember.lifetime = 0.55
            ember.lifetimeRange = 0.2
            ember.velocity = 260
            ember.velocityRange = 120
            ember.emissionRange = .pi * 2.0
            ember.yAcceleration = 180
            ember.scale = 0.65
            ember.scaleRange = 0.4
            ember.alphaSpeed = -1.8

            emitter.emitterCells = [ember]
            hostView.layer.addSublayer(emitter)

            let expand = CABasicAnimation(keyPath: "transform.scale")
            expand.fromValue = 0.4
            expand.toValue = 4.2
            expand.duration = 0.36
            expand.beginTime = CACurrentMediaTime() + delay
            expand.fillMode = .forwards
            expand.isRemovedOnCompletion = false
            shockwave.add(expand, forKey: "fg.exp.scale")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = 0.36
            fade.beginTime = CACurrentMediaTime() + delay
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            shockwave.add(fade, forKey: "fg.exp.fade")

            UIView.animate(withDuration: 0.26, delay: delay, options: [.curveEaseOut]) {
                snap.transform = CGAffineTransform(scaleX: 1.28, y: 1.28).rotated(by: idx % 2 == 0 ? 0.14 : -0.14)
                snap.alpha = 0.0
            } completion: { _ in
                snap.removeFromSuperview()
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((delay + 0.09) * 1_000_000_000))
                emitter.birthRate = 0.0
                try? await Task.sleep(nanoseconds: 650_000_000)
                emitter.removeFromSuperlayer()
                shockwave.removeFromSuperlayer()
            }
        }
    }
}

private final class FullGramCrumpledPaperBallView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false

        let s = min(frame.width, frame.height) / 56.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: x * s, y: y * s)
        }

        // Outer irregular crumpled silhouette
        let outerPath = UIBezierPath()
        outerPath.move(to: pt(28, 3))
        outerPath.addLine(to: pt(41, 7))
        outerPath.addLine(to: pt(51, 17))
        outerPath.addLine(to: pt(53, 31))
        outerPath.addLine(to: pt(46, 44))
        outerPath.addLine(to: pt(34, 52))
        outerPath.addLine(to: pt(19, 51))
        outerPath.addLine(to: pt(8, 43))
        outerPath.addLine(to: pt(3, 29))
        outerPath.addLine(to: pt(8, 14))
        outerPath.addLine(to: pt(18, 6))
        outerPath.close()

        let baseLayer = CAShapeLayer()
        baseLayer.path = outerPath.cgPath
        baseLayer.fillColor = UIColor(rgb: 0xF5F6FA).cgColor
        baseLayer.strokeColor = UIColor(rgb: 0xB8C0CC).cgColor
        baseLayer.lineWidth = 1.5 * s
        baseLayer.lineJoin = .round
        baseLayer.shadowColor = UIColor.black.cgColor
        baseLayer.shadowOpacity = 0.32
        baseLayer.shadowRadius = 7.0 * s
        baseLayer.shadowOffset = CGSize(width: 0.0, height: 3.5 * s)
        self.layer.addSublayer(baseLayer)

        // Shaded origami facets for 3D crumpled paper depth
        func addFacet(_ points: [CGPoint], color: UIColor) {
            let p = UIBezierPath()
            guard let first = points.first else { return }
            p.move(to: first)
            for next in points.dropFirst() { p.addLine(to: next) }
            p.close()
            let layer = CAShapeLayer()
            layer.path = p.cgPath
            layer.fillColor = color.cgColor
            self.layer.addSublayer(layer)
        }

        // Bright top-left highlight facet
        addFacet([pt(28, 3), pt(41, 7), pt(31, 21), pt(18, 17), pt(18, 6)], color: UIColor(white: 1.0, alpha: 0.95))
        // Mid-tone right facet
        addFacet([pt(41, 7), pt(51, 17), pt(53, 31), pt(35, 30), pt(31, 21)], color: UIColor(rgb: 0xE6EAF2))
        // Deeper bottom-right shadow facet
        addFacet([pt(53, 31), pt(46, 44), pt(34, 52), pt(27, 37), pt(35, 30)], color: UIColor(rgb: 0xCFD6E2))
        // Lower-left shadow facet
        addFacet([pt(34, 52), pt(19, 51), pt(8, 43), pt(17, 32), pt(27, 37)], color: UIColor(rgb: 0xDCE1EB))
        // Left mid facet
        addFacet([pt(8, 43), pt(3, 29), pt(8, 14), pt(18, 17), pt(17, 32)], color: UIColor(rgb: 0xECEFF5))
        // Center crumpled pocket
        addFacet([pt(18, 17), pt(31, 21), pt(35, 30), pt(27, 37), pt(17, 32)], color: UIColor(rgb: 0xF9FAFC))

        // Crisp paper fold creases + tiny faux text scribbles
        let creases = CAShapeLayer()
        let cPath = UIBezierPath()
        cPath.move(to: pt(18, 6)); cPath.addLine(to: pt(18, 17)); cPath.addLine(to: pt(31, 21)); cPath.addLine(to: pt(41, 7))
        cPath.move(to: pt(8, 14)); cPath.addLine(to: pt(18, 17)); cPath.addLine(to: pt(17, 32)); cPath.addLine(to: pt(8, 43))
        cPath.move(to: pt(31, 21)); cPath.addLine(to: pt(35, 30)); cPath.addLine(to: pt(53, 31))
        cPath.move(to: pt(17, 32)); cPath.addLine(to: pt(27, 37)); cPath.addLine(to: pt(35, 30))
        cPath.move(to: pt(27, 37)); cPath.addLine(to: pt(34, 52))
        cPath.move(to: pt(18, 17)); cPath.addLine(to: pt(27, 37))
        creases.path = cPath.cgPath
        creases.fillColor = nil
        creases.strokeColor = UIColor(rgb: 0x9AA4B4, alpha: 0.85).cgColor
        creases.lineWidth = 1.25 * s
        creases.lineCap = .round
        creases.lineJoin = .round
        self.layer.addSublayer(creases)

        // Subtle ink lines hinting at deleted chat text on the paper
        let inkLines = CAShapeLayer()
        let iPath = UIBezierPath()
        iPath.move(to: pt(21, 23)); iPath.addLine(to: pt(29, 25))
        iPath.move(to: pt(20, 28)); iPath.addLine(to: pt(31, 30))
        inkLines.path = iPath.cgPath
        inkLines.strokeColor = UIColor(rgb: 0x6B778C, alpha: 0.45).cgColor
        inkLines.lineWidth = 1.4 * s
        inkLines.lineCap = .round
        self.layer.addSublayer(inkLines)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class FullGramTrashBinView: UIView {
    private let containerView = UIView()
    private let lidLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false

        let w = frame.width
        let h = frame.height
        self.containerView.frame = self.bounds
        self.containerView.isUserInteractionEnabled = false
        self.addSubview(self.containerView)

        // Frosted glass circular-squircle badge backdrop
        let cardRect = CGRect(x: 4.0, y: 12.0, width: w - 8.0, height: h - 12.0)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blur.frame = cardRect
        blur.layer.cornerRadius = 28.0
        blur.clipsToBounds = true
        blur.layer.borderWidth = 1.0
        blur.layer.borderColor = UIColor(white: 1.0, alpha: 0.18).cgColor
        self.containerView.addSubview(blur)

        // Soft outer shadow
        let shadowHost = UIView(frame: cardRect)
        shadowHost.backgroundColor = .clear
        shadowHost.layer.shadowColor = UIColor.black.cgColor
        shadowHost.layer.shadowOpacity = 0.42
        shadowHost.layer.shadowRadius = 18.0
        shadowHost.layer.shadowOffset = CGSize(width: 0.0, height: 8.0)
        shadowHost.layer.shadowPath = UIBezierPath(roundedRect: shadowHost.bounds, cornerRadius: 28.0).cgPath
        self.containerView.insertSubview(shadowHost, belowSubview: blur)

        // Subtle crimson ambient glow behind bin
        self.glowLayer.path = UIBezierPath(ovalIn: CGRect(x: w * 0.18, y: h * 0.28, width: w * 0.64, height: h * 0.56)).cgPath
        self.glowLayer.fillColor = UIColor(rgb: 0xFF3B30, alpha: 0.24).cgColor
        self.glowLayer.shadowColor = UIColor(rgb: 0xFF3B30).cgColor
        self.glowLayer.shadowRadius = 16.0
        self.glowLayer.shadowOpacity = 0.7
        self.glowLayer.shadowOffset = .zero
        self.containerView.layer.addSublayer(self.glowLayer)

        // Dark interior mouth (visible when lid opens)
        let mouthLayer = CAShapeLayer()
        mouthLayer.path = UIBezierPath(ovalIn: CGRect(x: w * 0.23, y: h * 0.34, width: w * 0.54, height: 12.0)).cgPath
        mouthLayer.fillColor = UIColor(rgb: 0x4A0E0C).cgColor
        self.containerView.layer.addSublayer(mouthLayer)

        // Tapered bin body with gradient fill
        let bodyPath = UIBezierPath()
        let topLeft = CGPoint(x: w * 0.22, y: h * 0.38)
        let topRight = CGPoint(x: w * 0.78, y: h * 0.38)
        let botRight = CGPoint(x: w * 0.71, y: h * 0.85)
        let botLeft = CGPoint(x: w * 0.29, y: h * 0.85)
        bodyPath.move(to: topLeft)
        bodyPath.addLine(to: topRight)
        bodyPath.addLine(to: CGPoint(x: botRight.x + 1.0, y: botRight.y - 6.0))
        bodyPath.addQuadCurve(to: CGPoint(x: botRight.x - 8.0, y: botRight.y + 2.0), controlPoint: CGPoint(x: botRight.x, y: botRight.y + 2.0))
        bodyPath.addLine(to: CGPoint(x: botLeft.x + 8.0, y: botLeft.y + 2.0))
        bodyPath.addQuadCurve(to: CGPoint(x: botLeft.x - 1.0, y: botLeft.y - 6.0), controlPoint: CGPoint(x: botLeft.x, y: botLeft.y + 2.0))
        bodyPath.close()

        let bodyMask = CAShapeLayer()
        bodyMask.path = bodyPath.cgPath
        let bodyGradient = CAGradientLayer()
        bodyGradient.frame = self.bounds
        bodyGradient.colors = [
            UIColor(rgb: 0xFF5247).cgColor,
            UIColor(rgb: 0xE52521).cgColor,
            UIColor(rgb: 0xB81818).cgColor
        ]
        bodyGradient.startPoint = CGPoint(x: 0.2, y: 0.35)
        bodyGradient.endPoint = CGPoint(x: 0.85, y: 0.90)
        bodyGradient.mask = bodyMask
        self.containerView.layer.addSublayer(bodyGradient)

        // Top metallic rim highlight on body
        let rimLayer = CAShapeLayer()
        let rimPath = UIBezierPath()
        rimPath.move(to: CGPoint(x: topLeft.x + 1.0, y: topLeft.y + 1.0))
        rimPath.addLine(to: CGPoint(x: topRight.x - 1.0, y: topRight.y + 1.0))
        rimLayer.path = rimPath.cgPath
        rimLayer.strokeColor = UIColor(white: 1.0, alpha: 0.42).cgColor
        rimLayer.lineWidth = 2.0
        rimLayer.lineCap = .round
        self.containerView.layer.addSublayer(rimLayer)

        // 3 sculpted vertical ribs (dark groove + bright edge)
        let ribShadow = CAShapeLayer()
        let ribLight = CAShapeLayer()
        let rsPath = UIBezierPath()
        let rlPath = UIBezierPath()
        let ribConfigs: [(CGFloat, CGFloat)] = [
            (w * 0.38, w * 0.40),
            (w * 0.50, w * 0.50),
            (w * 0.62, w * 0.60)
        ]
        for (topX, botX) in ribConfigs {
            rsPath.move(to: CGPoint(x: topX, y: h * 0.47))
            rsPath.addLine(to: CGPoint(x: botX, y: h * 0.78))
            rlPath.move(to: CGPoint(x: topX + 1.5, y: h * 0.47))
            rlPath.addLine(to: CGPoint(x: botX + 1.5, y: h * 0.78))
        }
        ribShadow.path = rsPath.cgPath
        ribShadow.strokeColor = UIColor(rgb: 0x7A0C0C, alpha: 0.55).cgColor
        ribShadow.lineWidth = 3.2
        ribShadow.lineCap = .round
        self.containerView.layer.addSublayer(ribShadow)

        ribLight.path = rlPath.cgPath
        ribLight.strokeColor = UIColor(white: 1.0, alpha: 0.50).cgColor
        ribLight.lineWidth = 2.0
        ribLight.lineCap = .round
        self.containerView.layer.addSublayer(ribLight)

        // Hinged 3D lid with arched handle
        let lidW = w * 0.64
        let lidH: CGFloat = 20.0
        let lidX = (w - lidW) * 0.5
        let lidY = h * 0.38 - lidH + 2.0
        self.lidLayer.frame = CGRect(x: lidX, y: lidY, width: lidW, height: lidH)
        self.lidLayer.anchorPoint = CGPoint(x: 0.08, y: 0.85)
        self.lidLayer.position = CGPoint(x: lidX + lidW * 0.08, y: lidY + lidH * 0.85)

        let lidPath = UIBezierPath(roundedRect: CGRect(x: 0.0, y: 9.0, width: lidW, height: 8.5), cornerRadius: 4.25)
        let handleW: CGFloat = 22.0
        let handleRect = CGRect(x: (lidW - handleW) * 0.5, y: 2.0, width: handleW, height: 8.0)
        lidPath.append(UIBezierPath(roundedRect: handleRect, cornerRadius: 4.0))
        self.lidLayer.path = lidPath.cgPath
        self.lidLayer.fillColor = UIColor(rgb: 0xFF6B63).cgColor
        self.lidLayer.strokeColor = UIColor(white: 1.0, alpha: 0.28).cgColor
        self.lidLayer.lineWidth = 1.0
        self.lidLayer.shadowColor = UIColor.black.cgColor
        self.lidLayer.shadowOpacity = 0.28
        self.lidLayer.shadowRadius = 4.0
        self.lidLayer.shadowOffset = CGSize(width: 0.0, height: 2.0)
        self.containerView.layer.addSublayer(self.lidLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLidOpen(_ open: Bool, delay: TimeInterval) {
        let angle: CGFloat = open ? -0.84 : 0.0
        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self else { return }
            let anim = CASpringAnimation(keyPath: "transform.rotation.z")
            anim.toValue = angle
            anim.damping = 9.5
            anim.stiffness = 190.0
            anim.duration = anim.settlingDuration
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            self.lidLayer.add(anim, forKey: "fg.lid")
        }
    }

    func pulseImpact() {
        UIView.animate(withDuration: 0.11, animations: {
            self.containerView.transform = CGAffineTransform(scaleX: 1.12, y: 0.88).translatedBy(x: 0.0, y: 4.0)
        }, completion: { _ in
            UIView.animate(withDuration: 0.24, delay: 0.0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, options: [.allowUserInteraction]) {
                self.containerView.transform = .identity
            }
        })

        // Emit subtle white paper-dust puffs from bin mouth
        let origin = CGPoint(x: self.bounds.midX, y: self.bounds.height * 0.36)
        for i in 0 ..< 5 {
            let puff = UIView(frame: CGRect(x: 0, y: 0, width: 7.0, height: 7.0))
            puff.center = origin
            puff.backgroundColor = UIColor(white: 1.0, alpha: 0.85)
            puff.layer.cornerRadius = 3.5
            puff.isUserInteractionEnabled = false
            self.addSubview(puff)
            let angle = -CGFloat.pi * (0.2 + CGFloat(i) * 0.15)
            let dist: CGFloat = 24.0 + CGFloat(i % 2) * 12.0
            UIView.animate(withDuration: 0.32, delay: 0.0, options: [.curveEaseOut]) {
                puff.center = CGPoint(x: origin.x + cos(angle) * dist, y: origin.y + sin(angle) * dist)
                puff.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)
                puff.alpha = 0.0
            } completion: { _ in
                puff.removeFromSuperview()
            }
        }
    }
}
