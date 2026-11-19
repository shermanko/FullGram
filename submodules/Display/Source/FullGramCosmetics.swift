import Foundation
import UIKit

// MARK: - Облачная синхронизация косметики по ID аккаунта (как в Discord)

public struct FullGramUserCosmetics: Codable, Equatable, Sendable {
    public var frameId: String?
    public var nickColor: String?
    public var nickGlow: Bool

    public init(frameId: String? = nil, nickColor: String? = nil, nickGlow: Bool = false) {
        self.frameId = frameId
        self.nickColor = nickColor
        self.nickGlow = nickGlow
    }

    public var isEmpty: Bool {
        return (self.frameId == nil || self.frameId?.isEmpty == true)
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

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: self.cacheFileURL),
              let payload = try? JSONDecoder().decode(FullGramCosmeticsPayload.self, from: data) else {
            return
        }
        var mapped: [Int64: FullGramUserCosmetics] = [:]
        for (k, v) in payload.users {
            if let id = Int64(k), !v.isEmpty {
                mapped[id] = v
            }
        }
        self.lock.lock()
        self.remoteUsers = mapped
        self.lock.unlock()
    }

    public func setActiveSelfPeerId(_ peerId: Int64) {
        self.lock.lock()
        self.activeSelfPeerId = peerId
        self.lock.unlock()
    }

    public var currentSelfPeerId: Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.activeSelfPeerId
    }

    public func localCosmetics(forPeerId peerId: Int64) -> FullGramUserCosmetics? {
        self.lock.lock()
        if let cached = self.localCache[peerId] {
            self.lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        self.lock.unlock()

        if let data = UserDefaults.standard.data(forKey: Self.localPrefix + "\(peerId)"),
           let decoded = try? JSONDecoder().decode(FullGramUserCosmetics.self, from: data) {
            self.lock.lock()
            self.localCache[peerId] = decoded
            self.lock.unlock()
            return decoded.isEmpty ? nil : decoded
        }

        // Fall back to remote entry if user logged into the same account on a fresh device
        self.lock.lock()
        let remote = self.remoteUsers[peerId]
        self.lock.unlock()
        return remote
    }

    public func cosmetics(forPeerId peerId: Int64?, selfPeerId: Int64?) -> FullGramUserCosmetics? {
        guard let peerId, peerId != 0 else { return nil }
        let effectiveSelfId = selfPeerId ?? self.currentSelfPeerId
        if let effectiveSelfId, peerId == effectiveSelfId {
            return self.localCosmetics(forPeerId: peerId)
        }
        self.lock.lock()
        let remote = self.remoteUsers[peerId]
        self.lock.unlock()
        return remote
    }

    public func setFrame(forPeerId peerId: Int64, frameId: String?) {
        self.setActiveSelfPeerId(peerId)
        var entry = self.localCosmetics(forPeerId: peerId) ?? FullGramUserCosmetics()
        let cleaned = frameId?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.frameId = (cleaned?.isEmpty == false) ? cleaned : nil
        self.saveLocal(entry, forPeerId: peerId)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramAvatarFrames.didChangeNotification, object: nil)
        self.pushToCloud(peerId: peerId, entry: entry)
    }

    public func setNickStyle(forPeerId peerId: Int64, colorHex: String?, glowEnabled: Bool) {
        self.setActiveSelfPeerId(peerId)
        var entry = self.localCosmetics(forPeerId: peerId) ?? FullGramUserCosmetics()
        let cleaned = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        entry.nickColor = (cleaned?.isEmpty == false) ? cleaned : nil
        entry.nickGlow = entry.nickColor != nil ? glowEnabled : false
        self.saveLocal(entry, forPeerId: peerId)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        NotificationCenter.default.post(name: FullGramNicknameStyle.didChangeNotification, object: nil)
        self.pushToCloud(peerId: peerId, entry: entry)
    }

    private func saveLocal(_ entry: FullGramUserCosmetics, forPeerId peerId: Int64) {
        self.lock.lock()
        self.localCache[peerId] = entry
        if entry.isEmpty {
            self.remoteUsers.removeValue(forKey: peerId)
        } else {
            self.remoteUsers[peerId] = entry
        }
        self.lock.unlock()

        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: Self.localPrefix + "\(peerId)")
        }
    }

    private func pushToCloud(peerId: Int64, entry: FullGramUserCosmetics) {
        guard let url = URL(string: Self.updateEndpointURL) else { return }
        var body: [String: Any] = [
            "peerId": String(peerId),
            "frameId": entry.frameId as Any? ?? NSNull(),
            "nickColor": entry.nickColor as Any? ?? NSNull(),
            "nickGlow": entry.nickGlow
        ]
        if entry.frameId == nil { body["frameId"] = "" }
        if entry.nickColor == nil { body["nickColor"] = "" }

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        Self.session.dataTask(with: req) { [weak self] _, response, _ in
            if let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) {
                UserDefaults.standard.set(0.0, forKey: Self.lastSyncKey)
                self?.refreshNow(completion: nil)
            }
        }.resume()
    }

    public func refreshIfNeeded(maxAge: TimeInterval = 90.0) {
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
            defer {
                self.lock.lock()
                self.isRefreshing = false
                self.lock.unlock()
            }
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let data,
                  data.count <= 1_000_000,
                  let payload = try? JSONDecoder().decode(FullGramCosmeticsPayload.self, from: data) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            try? data.write(to: self.cacheFileURL, options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)

            var mapped: [Int64: FullGramUserCosmetics] = [:]
            for (k, v) in payload.users {
                if let id = Int64(k), !v.isEmpty {
                    mapped[id] = v
                }
            }
            self.lock.lock()
            self.remoteUsers = mapped
            self.lock.unlock()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
                NotificationCenter.default.post(name: FullGramAvatarFrames.didChangeNotification, object: nil)
                NotificationCenter.default.post(name: FullGramNicknameStyle.didChangeNotification, object: nil)
                completion?(true)
            }
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
            shadow.shadowColor = style.color.withAlphaComponent(0.75)
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 7.0
            attrs[.shadow] = shadow
        }
        return NSAttributedString(string: text, attributes: attrs)
    }
}

// MARK: - Анимация удаления сообщения (скомканный лист бумаги -> в мусорку)

public enum FullGramPaperTrashAnimator {
    @MainActor
    public static func animateDelete(snapshots: [(view: UIView, frameInHost: CGRect)], in hostView: UIView) {
        guard !snapshots.isEmpty else { return }

        let binSize = CGSize(width: 64.0, height: 74.0)
        let safeBottom = hostView.safeAreaInsets.bottom
        let binCenter = CGPoint(
            x: hostView.bounds.midX,
            y: hostView.bounds.height - safeBottom - 86.0
        )

        let binView = FullGramTrashBinView(frame: CGRect(
            x: binCenter.x - binSize.width * 0.5,
            y: binCenter.y - binSize.height * 0.5,
            width: binSize.width,
            height: binSize.height
        ))
        binView.alpha = 0.0
        binView.transform = CGAffineTransform(translationX: 0.0, y: 28.0).scaledBy(x: 0.72, y: 0.72)
        hostView.addSubview(binView)

        UIView.animate(withDuration: 0.24, delay: 0.0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.5, options: [.allowUserInteraction]) {
            binView.alpha = 1.0
            binView.transform = .identity
        }
        binView.setLidOpen(true, delay: 0.06)

        for (idx, item) in snapshots.prefix(4).enumerated() {
            let delay = Double(idx) * 0.06
            let snapshot = item.view
            snapshot.frame = item.frameInHost
            snapshot.layer.cornerRadius = 14.0
            snapshot.clipsToBounds = true
            hostView.addSubview(snapshot)

            let paperBall = FullGramCrumpledPaperBallView(frame: CGRect(x: 0.0, y: 0.0, width: 32.0, height: 32.0))
            paperBall.center = CGPoint(x: item.frameInHost.midX, y: item.frameInHost.midY)
            paperBall.alpha = 0.0
            paperBall.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            hostView.addSubview(paperBall)

            // Phase 1: Crumple snapshot into paper ball
            UIView.animate(withDuration: 0.22, delay: delay, options: [.curveEaseIn]) {
                snapshot.transform = CGAffineTransform(scaleX: 0.18, y: 0.16).rotated(by: idx % 2 == 0 ? 0.35 : -0.35)
                snapshot.alpha = 0.0
                paperBall.alpha = 1.0
                paperBall.transform = CGAffineTransform(rotationAngle: 0.5)
            } completion: { _ in
                snapshot.removeFromSuperview()
            }

            // Phase 2: Parabolic throw of crumpled paper ball into open trash bin
            let startPt = paperBall.center
            let endPt = CGPoint(x: binCenter.x, y: binCenter.y - 6.0)
            let ctrlPt = CGPoint(
                x: (startPt.x + endPt.x) * 0.5 + (idx % 2 == 0 ? 28.0 : -28.0),
                y: min(startPt.y, endPt.y) - 90.0
            )
            let arcPath = UIBezierPath()
            arcPath.move(to: startPt)
            arcPath.addQuadCurve(to: endPt, controlPoint: ctrlPt)

            let posAnim = CAKeyframeAnimation(keyPath: "position")
            posAnim.path = arcPath.cgPath
            posAnim.duration = 0.36
            posAnim.beginTime = CACurrentMediaTime() + delay + 0.18
            posAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            posAnim.fillMode = .forwards
            posAnim.isRemovedOnCompletion = false
            paperBall.layer.add(posAnim, forKey: "fg.throw")

            let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
            rotAnim.fromValue = 0.5
            rotAnim.toValue = Double.pi * (idx % 2 == 0 ? 3.2 : -3.2)
            rotAnim.duration = 0.36
            rotAnim.beginTime = CACurrentMediaTime() + delay + 0.18
            paperBall.layer.add(rotAnim, forKey: "fg.spin")

            UIView.animate(withDuration: 0.14, delay: delay + 0.44, options: [.curveEaseIn]) {
                paperBall.transform = CGAffineTransform(scaleX: 0.45, y: 0.45)
                paperBall.alpha = 0.0
            } completion: { _ in
                paperBall.removeFromSuperview()
            }
        }

        let finishDelay = Double(min(snapshots.count, 4)) * 0.06 + 0.56
        binView.setLidOpen(false, delay: finishDelay - 0.10)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((finishDelay + 0.06) * 1_000_000_000))
            UIView.animate(withDuration: 0.16, animations: {
                binView.transform = CGAffineTransform(scaleX: 1.08, y: 0.92)
            }, completion: { _ in
                UIView.animate(withDuration: 0.22, delay: 0.12, animations: {
                    binView.alpha = 0.0
                    binView.transform = CGAffineTransform(translationX: 0.0, y: 24.0).scaledBy(x: 0.8, y: 0.8)
                }, completion: { _ in
                    binView.removeFromSuperview()
                })
            })
        }
    }
}

private final class FullGramCrumpledPaperBallView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false

        let body = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 16, y: 2))
        path.addLine(to: CGPoint(x: 26, y: 6))
        path.addLine(to: CGPoint(x: 30, y: 15))
        path.addLine(to: CGPoint(x: 25, y: 26))
        path.addLine(to: CGPoint(x: 15, y: 30))
        path.addLine(to: CGPoint(x: 6, y: 26))
        path.addLine(to: CGPoint(x: 2, y: 16))
        path.addLine(to: CGPoint(x: 7, y: 6))
        path.close()
        body.path = path.cgPath
        body.fillColor = UIColor(white: 0.95, alpha: 1.0).cgColor
        body.strokeColor = UIColor(white: 0.72, alpha: 1.0).cgColor
        body.lineWidth = 1.2
        body.shadowColor = UIColor.black.cgColor
        body.shadowOpacity = 0.25
        body.shadowRadius = 4.0
        body.shadowOffset = CGSize(width: 0.0, height: 2.0)
        self.layer.addSublayer(body)

        let creases = CAShapeLayer()
        let cPath = UIBezierPath()
        cPath.move(to: CGPoint(x: 7, y: 6)); cPath.addLine(to: CGPoint(x: 17, y: 16)); cPath.addLine(to: CGPoint(x: 25, y: 26))
        cPath.move(to: CGPoint(x: 26, y: 6)); cPath.addLine(to: CGPoint(x: 14, y: 14)); cPath.addLine(to: CGPoint(x: 6, y: 26))
        cPath.move(to: CGPoint(x: 2, y: 16)); cPath.addLine(to: CGPoint(x: 18, y: 19)); cPath.addLine(to: CGPoint(x: 30, y: 15))
        creases.path = cPath.cgPath
        creases.fillColor = nil
        creases.strokeColor = UIColor(white: 0.62, alpha: 0.9).cgColor
        creases.lineWidth = 1.0
        creases.lineCap = .round
        creases.lineJoin = .round
        self.layer.addSublayer(creases)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class FullGramTrashBinView: UIView {
    private let lidLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false

        let backdrop = UIView(frame: CGRect(x: 2, y: 8, width: frame.width - 4, height: frame.height - 8))
        backdrop.backgroundColor = UIColor(white: 0.10, alpha: 0.82)
        backdrop.layer.cornerRadius = 18.0
        backdrop.layer.borderWidth = 0.5
        backdrop.layer.borderColor = UIColor(white: 1.0, alpha: 0.16).cgColor
        self.addSubview(backdrop)

        // Bin body
        let bodyLayer = CAShapeLayer()
        let bPath = UIBezierPath()
        bPath.move(to: CGPoint(x: 16, y: 27))
        bPath.addLine(to: CGPoint(x: 48, y: 27))
        bPath.addLine(to: CGPoint(x: 44, y: 62))
        bPath.addQuadCurve(to: CGPoint(x: 40, y: 65), controlPoint: CGPoint(x: 44, y: 65))
        bPath.addLine(to: CGPoint(x: 24, y: 65))
        bPath.addQuadCurve(to: CGPoint(x: 20, y: 62), controlPoint: CGPoint(x: 20, y: 65))
        bPath.close()
        bodyLayer.path = bPath.cgPath
        bodyLayer.fillColor = UIColor(rgb: 0xFF3B30).withAlphaComponent(0.92).cgColor
        self.layer.addSublayer(bodyLayer)

        // Vertical ribs
        let ribs = CAShapeLayer()
        let rPath = UIBezierPath()
        for x in [26.0, 32.0, 38.0] {
            rPath.move(to: CGPoint(x: x, y: 34))
            rPath.addLine(to: CGPoint(x: x, y: 58))
        }
        ribs.path = rPath.cgPath
        ribs.strokeColor = UIColor.white.withAlphaComponent(0.65).cgColor
        ribs.lineWidth = 2.0
        ribs.lineCap = .round
        self.layer.addSublayer(ribs)

        // Hinged lid
        self.lidLayer.frame = CGRect(x: 12, y: 15, width: 40, height: 12)
        self.lidLayer.anchorPoint = CGPoint(x: 0.08, y: 0.85)
        self.lidLayer.position = CGPoint(x: 12 + 40 * 0.08, y: 15 + 12 * 0.85)
        let lPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 5, width: 40, height: 5), cornerRadius: 2.5)
        lPath.append(UIBezierPath(roundedRect: CGRect(x: 14, y: 1, width: 12, height: 4), cornerRadius: 2.0))
        self.lidLayer.path = lPath.cgPath
        self.lidLayer.fillColor = UIColor(rgb: 0xFF6961).cgColor
        self.layer.addSublayer(self.lidLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLidOpen(_ open: Bool, delay: TimeInterval) {
        let angle: CGFloat = open ? -0.68 : 0.0
        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self else { return }
            let anim = CASpringAnimation(keyPath: "transform.rotation.z")
            anim.toValue = angle
            anim.damping = 10.0
            anim.stiffness = 180.0
            anim.duration = anim.settlingDuration
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            self.lidLayer.add(anim, forKey: "fg.lid")
        }
    }
}
