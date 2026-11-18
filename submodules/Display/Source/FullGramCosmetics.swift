import Foundation
import UIKit

// MARK: - Кастомные стили ников

public struct FullGramNicknamePreset: Equatable {
    public let id: String
    public let title: String
    public let colors: [UIColor]
    public let glowColor: UIColor?
    public let isBold: Bool
    public let isMono: Bool
    public let isItalic: Bool
}

public enum FullGramNicknameStyle {
    public static let didChangeNotification = Notification.Name("FullGram.NicknameStyleChanged")

    private static let presetKey = "fullgram.nickname.presetId"
    private static let glowKey = "fullgram.nickname.glowEnabled"
    private static let applyOthersKey = "fullgram.nickname.applyOthers"

    private static let stateLock = NSLock()
    private static var cachedPresetId: String?
    private static var cachedGlow: Bool?
    private static var cachedApplyOthers: Bool?
    private static let gradientCache: NSCache<NSString, UIColor> = {
        let c = NSCache<NSString, UIColor>()
        c.countLimit = 48
        return c
    }()

    public static var selectedPresetId: String {
        get {
            self.stateLock.lock()
            if let v = self.cachedPresetId {
                self.stateLock.unlock()
                return v
            }
            let resolved = UserDefaults.standard.string(forKey: presetKey) ?? "none"
            self.cachedPresetId = resolved
            self.stateLock.unlock()
            return resolved
        }
        set {
            self.stateLock.lock()
            self.cachedPresetId = newValue
            self.stateLock.unlock()
            UserDefaults.standard.set(newValue, forKey: presetKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var glowEnabled: Bool {
        get {
            self.stateLock.lock()
            if let v = self.cachedGlow {
                self.stateLock.unlock()
                return v
            }
            let resolved = (UserDefaults.standard.object(forKey: glowKey) == nil)
                ? true
                : UserDefaults.standard.bool(forKey: glowKey)
            self.cachedGlow = resolved
            self.stateLock.unlock()
            return resolved
        }
        set {
            self.stateLock.lock()
            self.cachedGlow = newValue
            self.stateLock.unlock()
            UserDefaults.standard.set(newValue, forKey: glowKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var applyToChatTitles: Bool {
        get {
            self.stateLock.lock()
            if let v = self.cachedApplyOthers {
                self.stateLock.unlock()
                return v
            }
            let resolved = (UserDefaults.standard.object(forKey: applyOthersKey) == nil)
                ? true
                : UserDefaults.standard.bool(forKey: applyOthersKey)
            self.cachedApplyOthers = resolved
            self.stateLock.unlock()
            return resolved
        }
        set {
            self.stateLock.lock()
            self.cachedApplyOthers = newValue
            self.stateLock.unlock()
            UserDefaults.standard.set(newValue, forKey: applyOthersKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    private static let presetsById: [String: FullGramNicknamePreset] = Dictionary(
        uniqueKeysWithValues: presets.map { ($0.id, $0) }
    )

    public static var activePreset: FullGramNicknamePreset? {
        let id = self.selectedPresetId
        guard id != "none" else { return nil }
        return self.presetsById[id]
    }

    public static let presets: [FullGramNicknamePreset] = [
        FullGramNicknamePreset(
            id: "none",
            title: "Стандартный",
            colors: [],
            glowColor: nil,
            isBold: false,
            isMono: false,
            isItalic: false
        ),
        FullGramNicknamePreset(
            id: "neon_cyan_pink",
            title: "Неон (Бирюза → Розовый)",
            colors: [UIColor(rgb: 0x00F5D4), UIColor(rgb: 0xFF2A85)],
            glowColor: UIColor(rgb: 0xFF2A85),
            isBold: true,
            isMono: false,
            isItalic: false
        ),
        FullGramNicknamePreset(
            id: "cyberpunk",
            title: "Киберпанк (Пурпур → Жёлтый)",
            colors: [UIColor(rgb: 0xC026D3), UIColor(rgb: 0xFACC15)],
            glowColor: UIColor(rgb: 0xC026D3),
            isBold: true,
            isMono: true,
            isItalic: false
        ),
        FullGramNicknamePreset(
            id: "royal_gold",
            title: "Королевское золото",
            colors: [UIColor(rgb: 0xFFF3B0), UIColor(rgb: 0xF59E0B), UIColor(rgb: 0xB45309)],
            glowColor: UIColor(rgb: 0xF59E0B),
            isBold: true,
            isMono: false,
            isItalic: false
        ),
        FullGramNicknamePreset(
            id: "blood_fire",
            title: "Огненный закат",
            colors: [UIColor(rgb: 0xFF3B30), UIColor(rgb: 0xFF9500)],
            glowColor: UIColor(rgb: 0xFF453A),
            isBold: true,
            isMono: false,
            isItalic: false
        ),
        FullGramNicknamePreset(
            id: "matrix",
            title: "Матрица (Хакер)",
            colors: [UIColor(rgb: 0x00FF66), UIColor(rgb: 0x10B981)],
            glowColor: UIColor(rgb: 0x00FF66),
            isBold: true,
            isMono: true,
            isItalic: false
        ),
        FullGramNicknamePreset(
            id: "rainbow",
            title: "Радужный спектр",
            colors: [UIColor(rgb: 0xFF3B30), UIColor(rgb: 0xFFCC00), UIColor(rgb: 0x34C759), UIColor(rgb: 0x00C7BE), UIColor(rgb: 0xAF52DE)],
            glowColor: UIColor(rgb: 0xAF52DE),
            isBold: true,
            isMono: false,
            isItalic: false
        ),
        FullGramNicknamePreset(
            id: "ice_chrome",
            title: "Ледяной хром",
            colors: [UIColor(rgb: 0xE0F2FE), UIColor(rgb: 0x38BDF8), UIColor(rgb: 0x818CF8)],
            glowColor: UIColor(rgb: 0x38BDF8),
            isBold: false,
            isMono: false,
            isItalic: true
        ),
        FullGramNicknamePreset(
            id: "sakura",
            title: "Сакура",
            colors: [UIColor(rgb: 0xFFC1E3), UIColor(rgb: 0xF43F5E)],
            glowColor: UIColor(rgb: 0xFB7185),
            isBold: true,
            isMono: false,
            isItalic: true
        )
    ]

    public static func styledAttributedString(
        _ text: String,
        baseFont: UIFont,
        baseColor: UIColor
    ) -> NSAttributedString {
        guard let preset = self.activePreset, !text.isEmpty else {
            return NSAttributedString(string: text, attributes: [.font: baseFont, .foregroundColor: baseColor])
        }

        var font = baseFont
        if preset.isMono {
            font = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: preset.isBold ? .bold : .medium)
        } else if preset.isBold && preset.isItalic {
            if let desc = baseFont.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                font = UIFont(descriptor: desc, size: baseFont.pointSize)
            } else {
                font = UIFont.boldSystemFont(ofSize: baseFont.pointSize)
            }
        } else if preset.isBold {
            font = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
        } else if preset.isItalic {
            font = UIFont.italicSystemFont(ofSize: baseFont.pointSize)
        }

        let gradientColor = self.gradientPatternColor(presetId: preset.id, text: text, font: font, colors: preset.colors) ?? preset.colors.first ?? baseColor
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: gradientColor
        ]
        if self.glowEnabled, let glow = preset.glowColor {
            let shadow = NSShadow()
            shadow.shadowColor = glow.withAlphaComponent(0.65)
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 6.0
            attrs[.shadow] = shadow
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func gradientPatternColor(presetId: String, text: String, font: UIFont, colors: [UIColor]) -> UIColor? {
        guard colors.count >= 2 else { return colors.first }
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let bucketW = max(32, (Int(ceil(measured.width)) + 15) / 16 * 16)
        let bucketH = max(16, Int(ceil(measured.height)))
        let key = "\(presetId)_\(bucketW)_\(bucketH)" as NSString
        if let cached = self.gradientCache.object(forKey: key) {
            return cached
        }
        let size = CGSize(width: CGFloat(bucketW), height: CGFloat(bucketH))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { renderCtx in
            let cgColors = colors.map { $0.cgColor } as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) else {
                return
            }
            renderCtx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0.0, y: size.height * 0.5),
                end: CGPoint(x: size.width, y: size.height * 0.5),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        let pattern = UIColor(patternImage: img)
        self.gradientCache.setObject(pattern, forKey: key)
        return pattern
    }
}

// MARK: - Настройка пузырей сообщений

public enum FullGramBubbleCustomization {
    public static let didChangeNotification = Notification.Name("FullGram.BubbleCustomizationChanged")

    private static let radiusKey = "fullgram.bubbles.cornerRadius"
    private static let opacityKey = "fullgram.bubbles.opacity"
    private static let hideTailKey = "fullgram.bubbles.hideTail"
    private static let outlineEnabledKey = "fullgram.bubbles.outlineEnabled"
    private static let outlineColorKey = "fullgram.bubbles.outlineColorHex"

    private static let stateLock = NSLock()
    private static var cachedRadius: CGFloat?
    private static var cachedHasCustomRadius: Bool?
    private static var cachedOpacity: CGFloat?
    private static var cachedHideTail: Bool?
    private static var cachedOutlineEnabled: Bool?
    private static var cachedOutlineHex: String??
    private static var cachedOutlineColor: UIColor??

    public static var cornerRadius: CGFloat {
        get {
            self.stateLock.lock()
            if let v = self.cachedRadius {
                self.stateLock.unlock()
                return v
            }
            let resolved: CGFloat = (UserDefaults.standard.object(forKey: radiusKey) == nil)
                ? 17.0
                : CGFloat(max(4.0, min(24.0, UserDefaults.standard.double(forKey: radiusKey))))
            self.cachedRadius = resolved
            self.cachedHasCustomRadius = (UserDefaults.standard.object(forKey: radiusKey) != nil && abs(resolved - 17.0) > 0.25)
            self.stateLock.unlock()
            return resolved
        }
        set {
            let clamped = CGFloat(max(4.0, min(24.0, newValue)))
            self.stateLock.lock()
            self.cachedRadius = clamped
            self.cachedHasCustomRadius = abs(clamped - 17.0) > 0.25
            self.stateLock.unlock()
            UserDefaults.standard.set(Double(clamped), forKey: radiusKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var hasCustomCornerRadius: Bool {
        self.stateLock.lock()
        if let v = self.cachedHasCustomRadius {
            self.stateLock.unlock()
            return v
        }
        self.stateLock.unlock()
        _ = self.cornerRadius
        self.stateLock.lock()
        let result = self.cachedHasCustomRadius ?? false
        self.stateLock.unlock()
        return result
    }

    public static var opacity: CGFloat {
        get {
            self.stateLock.lock()
            if let v = self.cachedOpacity {
                self.stateLock.unlock()
                return v
            }
            let resolved: CGFloat = (UserDefaults.standard.object(forKey: opacityKey) == nil)
                ? 1.0
                : CGFloat(max(0.35, min(1.0, UserDefaults.standard.double(forKey: opacityKey))))
            self.cachedOpacity = resolved
            self.stateLock.unlock()
            return resolved
        }
        set {
            let clamped = CGFloat(max(0.35, min(1.0, newValue)))
            self.stateLock.lock()
            self.cachedOpacity = clamped
            self.stateLock.unlock()
            UserDefaults.standard.set(Double(clamped), forKey: opacityKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var hideTail: Bool {
        get {
            self.stateLock.lock()
            if let v = self.cachedHideTail {
                self.stateLock.unlock()
                return v
            }
            let resolved = UserDefaults.standard.bool(forKey: hideTailKey)
            self.cachedHideTail = resolved
            self.stateLock.unlock()
            return resolved
        }
        set {
            self.stateLock.lock()
            self.cachedHideTail = newValue
            self.stateLock.unlock()
            UserDefaults.standard.set(newValue, forKey: hideTailKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var outlineEnabled: Bool {
        get {
            self.stateLock.lock()
            if let v = self.cachedOutlineEnabled {
                self.stateLock.unlock()
                return v
            }
            let resolved = UserDefaults.standard.bool(forKey: outlineEnabledKey)
            self.cachedOutlineEnabled = resolved
            self.stateLock.unlock()
            return resolved
        }
        set {
            self.stateLock.lock()
            self.cachedOutlineEnabled = newValue
            self.stateLock.unlock()
            UserDefaults.standard.set(newValue, forKey: outlineEnabledKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var outlineColorHex: String? {
        get {
            self.stateLock.lock()
            if let v = self.cachedOutlineHex {
                self.stateLock.unlock()
                return v
            }
            let v = UserDefaults.standard.string(forKey: outlineColorKey) ?? ""
            let resolved: String? = v.isEmpty ? nil : v
            self.cachedOutlineHex = .some(resolved)
            self.cachedOutlineColor = .some(resolved.flatMap { FullGramThemeColors.parse($0) }.map { UIColor(rgb: $0).withAlphaComponent(0.85) })
            self.stateLock.unlock()
            return resolved
        }
        set {
            let cleaned: String? = (newValue?.isEmpty == false) ? newValue : nil
            let parsedColor = cleaned.flatMap { FullGramThemeColors.parse($0) }.map { UIColor(rgb: $0).withAlphaComponent(0.85) }
            self.stateLock.lock()
            self.cachedOutlineHex = .some(cleaned)
            self.cachedOutlineColor = .some(parsedColor)
            self.stateLock.unlock()
            if let cleaned {
                UserDefaults.standard.set(cleaned, forKey: outlineColorKey)
            } else {
                UserDefaults.standard.removeObject(forKey: outlineColorKey)
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static var resolvedOutlineColor: UIColor {
        self.stateLock.lock()
        if let v = self.cachedOutlineColor {
            self.stateLock.unlock()
            return v ?? UIColor.white.withAlphaComponent(0.35)
        }
        self.stateLock.unlock()
        _ = self.outlineColorHex
        self.stateLock.lock()
        let resolved = (self.cachedOutlineColor ?? nil) ?? UIColor.white.withAlphaComponent(0.35)
        self.stateLock.unlock()
        return resolved
    }

    public static func reset() {
        self.stateLock.lock()
        self.cachedRadius = 17.0
        self.cachedHasCustomRadius = false
        self.cachedOpacity = 1.0
        self.cachedHideTail = false
        self.cachedOutlineEnabled = false
        self.cachedOutlineHex = .some(nil)
        self.cachedOutlineColor = .some(nil)
        self.stateLock.unlock()
        UserDefaults.standard.removeObject(forKey: radiusKey)
        UserDefaults.standard.removeObject(forKey: opacityKey)
        UserDefaults.standard.removeObject(forKey: hideTailKey)
        UserDefaults.standard.removeObject(forKey: outlineEnabledKey)
        UserDefaults.standard.removeObject(forKey: outlineColorKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

// MARK: - Скины раскраски (полные цветовые пресеты)

public struct FullGramColorSkin: Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let themePreset: FullGramThemeColors.Preset
    public let recommendedNicknameId: String
    public let recommendedCornerRadius: CGFloat
    public let recommendedOutlineHex: String?
}

public enum FullGramColorSkins {
    private static let selectedKey = "fullgram.skins.selectedId"

    public static var selectedSkinId: String? {
        get { UserDefaults.standard.string(forKey: selectedKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: selectedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedKey)
            }
        }
    }

    public static let skins: [FullGramColorSkin] = [
        FullGramColorSkin(
            id: "cyberpunk_2077",
            title: "⚡ Cyberpunk Neon",
            subtitle: "Неоновый розовый, тёмный индиго и кибер-пузыри",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_cyberpunk_2077",
                title: "Cyberpunk Neon",
                colors: [
                    .accent: "#FF2A85",
                    .outgoingBubble: "#7B1FA2",
                    .outgoingText: "#FFFFFF",
                    .incomingBubble: "#16122B",
                    .incomingText: "#E2E8F0",
                    .wallpaper: "#090714",
                    .wallpaperSecond: "#1E0B36",
                    .listBackground: "#090714",
                    .chatTitle: "#00F5D4"
                ]
            ),
            recommendedNicknameId: "cyberpunk",
            recommendedCornerRadius: 10.0,
            recommendedOutlineHex: "#FF2A85"
        ),
        FullGramColorSkin(
            id: "sakura_bloom",
            title: "🌸 Sakura Bloom",
            subtitle: "Нежно-розовая сакура и мягкие округлые пузыри",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_sakura_bloom",
                title: "Sakura Bloom",
                colors: [
                    .accent: "#F43F5E",
                    .outgoingBubble: "#BE185D",
                    .outgoingText: "#FFFFFF",
                    .incomingBubble: "#2D1221",
                    .incomingText: "#FFE4E6",
                    .wallpaper: "#180A12",
                    .wallpaperSecond: "#3B1228",
                    .listBackground: "#14080F",
                    .chatTitle: "#FDA4AF"
                ]
            ),
            recommendedNicknameId: "sakura",
            recommendedCornerRadius: 20.0,
            recommendedOutlineHex: "#FB7185"
        ),
        FullGramColorSkin(
            id: "toxic_matrix",
            title: "🟢 Toxic Matrix",
            subtitle: "Кислотно-зелёный терминал на глубоком чёрном",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_toxic_matrix",
                title: "Toxic Matrix",
                colors: [
                    .accent: "#00FF66",
                    .outgoingBubble: "#064E3B",
                    .outgoingText: "#6EE7B7",
                    .incomingBubble: "#0A1410",
                    .incomingText: "#A7F3D0",
                    .wallpaper: "#020503",
                    .wallpaperSecond: "#052014",
                    .listBackground: "#020503",
                    .chatTitle: "#00FF66"
                ]
            ),
            recommendedNicknameId: "matrix",
            recommendedCornerRadius: 8.0,
            recommendedOutlineHex: "#00FF66"
        ),
        FullGramColorSkin(
            id: "blood_moon",
            title: "🩸 Blood Moon",
            subtitle: "Багровый неон и тёмный кармин",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_blood_moon",
                title: "Blood Moon",
                colors: [
                    .accent: "#FF3B30",
                    .outgoingBubble: "#991B1B",
                    .outgoingText: "#FFFFFF",
                    .incomingBubble: "#220D0D",
                    .incomingText: "#FECACA",
                    .wallpaper: "#0D0404",
                    .wallpaperSecond: "#2B0909",
                    .listBackground: "#0D0404",
                    .chatTitle: "#FCA5A5"
                ]
            ),
            recommendedNicknameId: "blood_fire",
            recommendedCornerRadius: 14.0,
            recommendedOutlineHex: "#EF4444"
        ),
        FullGramColorSkin(
            id: "arctic_frost",
            title: "❄️ Arctic Frost",
            subtitle: "Холодный ледяной синий и воздушный контраст",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_arctic_frost",
                title: "Arctic Frost",
                colors: [
                    .accent: "#38BDF8",
                    .outgoingBubble: "#0284C7",
                    .outgoingText: "#FFFFFF",
                    .incomingBubble: "#0F172A",
                    .incomingText: "#E0F2FE",
                    .wallpaper: "#060D1A",
                    .wallpaperSecond: "#0C2340",
                    .listBackground: "#060D1A",
                    .chatTitle: "#7DD3FC"
                ]
            ),
            recommendedNicknameId: "ice_chrome",
            recommendedCornerRadius: 18.0,
            recommendedOutlineHex: "#38BDF8"
        ),
        FullGramColorSkin(
            id: "royal_gold",
            title: "👑 Royal Gold",
            subtitle: "Премиальный чёрно-золотой люкс",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_royal_gold",
                title: "Royal Gold",
                colors: [
                    .accent: "#F59E0B",
                    .outgoingBubble: "#92400E",
                    .outgoingText: "#FEF3C7",
                    .incomingBubble: "#1C160C",
                    .incomingText: "#FDE68A",
                    .wallpaper: "#0B0804",
                    .wallpaperSecond: "#231907",
                    .listBackground: "#0B0804",
                    .chatTitle: "#FCD34D"
                ]
            ),
            recommendedNicknameId: "royal_gold",
            recommendedCornerRadius: 16.0,
            recommendedOutlineHex: "#F59E0B"
        ),
        FullGramColorSkin(
            id: "discord_nitro",
            title: "🎮 Discord Nitro",
            subtitle: "Фирменный Blurple и тёмный графит",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_discord_nitro",
                title: "Discord Nitro",
                colors: [
                    .accent: "#5865F2",
                    .outgoingBubble: "#5865F2",
                    .outgoingText: "#FFFFFF",
                    .incomingBubble: "#2B2D31",
                    .incomingText: "#F2F3F5",
                    .wallpaper: "#1E1F22",
                    .wallpaperSecond: "#2B2D31",
                    .listBackground: "#1E1F22",
                    .chatTitle: "#FFFFFF"
                ]
            ),
            recommendedNicknameId: "neon_cyan_pink",
            recommendedCornerRadius: 17.0,
            recommendedOutlineHex: "#5865F2"
        ),
        FullGramColorSkin(
            id: "vaporwave",
            title: "🌆 Vaporwave 1984",
            subtitle: "Ретро-волна: бирюза, фиолетовый и закат",
            themePreset: FullGramThemeColors.Preset(
                id: "skin_vaporwave",
                title: "Vaporwave 1984",
                colors: [
                    .accent: "#00E5FF",
                    .outgoingBubble: "#6D28D9",
                    .outgoingText: "#FFFFFF",
                    .incomingBubble: "#1F1638",
                    .incomingText: "#DDD6FE",
                    .wallpaper: "#110B22",
                    .wallpaperSecond: "#3B1347",
                    .listBackground: "#110B22",
                    .chatTitle: "#F472B6"
                ]
            ),
            recommendedNicknameId: "rainbow",
            recommendedCornerRadius: 12.0,
            recommendedOutlineHex: "#00E5FF"
        )
    ]

    public static func apply(_ skin: FullGramColorSkin) {
        self.selectedSkinId = skin.id
        FullGramThemeColors.apply(skin.themePreset)
        FullGramNicknameStyle.selectedPresetId = skin.recommendedNicknameId
        FullGramBubbleCustomization.cornerRadius = skin.recommendedCornerRadius
        if let outline = skin.recommendedOutlineHex {
            FullGramBubbleCustomization.outlineEnabled = true
            FullGramBubbleCustomization.outlineColorHex = outline
        } else {
            FullGramBubbleCustomization.outlineEnabled = false
        }
    }

    public static func resetAll() {
        self.selectedSkinId = nil
        FullGramThemeColors.reset()
        FullGramNicknameStyle.selectedPresetId = "none"
        FullGramBubbleCustomization.reset()
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
