import Foundation
import UIKit
import Display
import TelegramCore

private let fullGramThemeLock = NSLock()
private var fullGramCustomThemes: [(input: PresentationTheme, revision: Int, output: PresentationTheme)] = []

private func fullGramBubble(_ components: PresentationThemeBubbleColorComponents, fill: UIColor) -> PresentationThemeBubbleColorComponents {
    let isLightFill = fill.lightness > 0.65
    let inactiveBg = isLightFill ? UIColor(rgb: 0x000000, alpha: 0.08) : UIColor(rgb: 0xffffff, alpha: 0.12)
    let inactiveFg = isLightFill ? UIColor(rgb: 0x000000, alpha: 0.85) : UIColor(rgb: 0xffffff, alpha: 0.9)
    let activeBg = isLightFill ? UIColor(rgb: 0x000000) : UIColor(rgb: 0xffffff)
    let activeFg = isLightFill ? UIColor(rgb: 0xffffff) : UIColor(rgb: 0x000000)
    return PresentationThemeBubbleColorComponents(
        fill: [fill],
        highlightedFill: isLightFill ? fill.withMultipliedBrightnessBy(0.92) : fill.withMultipliedBrightnessBy(1.12),
        stroke: components.stroke,
        shadow: components.shadow,
        reactionInactiveBackground: inactiveBg,
        reactionInactiveForeground: inactiveFg,
        reactionActiveBackground: activeBg,
        reactionActiveForeground: activeFg,
        reactionStarsInactiveBackground: components.reactionStarsInactiveBackground,
        reactionStarsInactiveForeground: components.reactionStarsInactiveForeground,
        reactionStarsActiveBackground: components.reactionStarsActiveBackground,
        reactionStarsActiveForeground: components.reactionStarsActiveForeground,
        reactionInactiveMediaPlaceholder: components.reactionInactiveMediaPlaceholder,
        reactionActiveMediaPlaceholder: components.reactionActiveMediaPlaceholder
    )
}

private func fullGramContrastingLinkColor(fill: UIColor?, text: UIColor?, accent: UIColor?, fallback: UIColor) -> UIColor {
    let bgLightness = fill?.lightness ?? (text.map { $0.lightness > 0.5 ? 0.1 : 0.9 } ?? 0.5)
    let isLightBubble = bgLightness > 0.62
    let primary = text ?? (isLightBubble ? UIColor(rgb: 0x000000) : UIColor(rgb: 0xffffff))

    // If the theme accent is clearly distinct in lightness from the bubble fill, use it;
    // otherwise (e.g. white accent on white outgoing bubble in black-and-white theme),
    // fall back to a high-contrast ink so links/mentions/hashtags never blend into the bubble.
    if let accent {
        let (_, sat, _) = accent.hsb
        let accentContrast = abs(accent.lightness - bgLightness)
        if sat > 0.15 && accentContrast >= 0.28 {
            return accent
        }
        if sat > 0.15 {
            return isLightBubble
                ? accent.withMultiplied(hue: 1.0, saturation: 1.0, brightness: 0.45)
                : accent.withMultiplied(hue: 1.0, saturation: 0.75, brightness: 1.35)
        }
    }

    let fallbackContrast = abs(fallback.lightness - bgLightness)
    if fallbackContrast >= 0.35 {
        return fallback
    }
    return primary
}

private func fullGramParted(_ colors: PresentationThemePartedColors, fill: UIColor?, text: UIColor?, accent: UIColor?) -> PresentationThemePartedColors {
    var bubble: PresentationThemeBubbleColor?
    if let fill {
        bubble = colors.bubble.withUpdated(
            withWallpaper: fullGramBubble(colors.bubble.withWallpaper, fill: fill),
            withoutWallpaper: fullGramBubble(colors.bubble.withoutWallpaper, fill: fill)
        )
    }
    let effectiveFill = fill ?? colors.bubble.withWallpaper.fill.first
    let resolvedText: UIColor
    if let text {
        resolvedText = text
    } else if let effectiveFill {
        resolvedText = effectiveFill.lightness > 0.65 ? UIColor(rgb: 0x000000) : UIColor(rgb: 0xffffff)
    } else {
        resolvedText = colors.primaryTextColor
    }
    let resolvedSecondary = resolvedText.withAlphaComponent(0.6)
    let resolvedLink = fullGramContrastingLinkColor(fill: effectiveFill, text: resolvedText, accent: accent, fallback: colors.linkTextColor)
    let resolvedPolls = colors.polls.withUpdated(
        radioButton: resolvedSecondary,
        radioProgress: resolvedLink,
        highlight: resolvedLink.withAlphaComponent(0.14),
        separator: resolvedText.withAlphaComponent(0.25),
        bar: resolvedLink
    )
    return colors.withUpdated(
        bubble: bubble,
        primaryTextColor: resolvedText,
        secondaryTextColor: resolvedSecondary,
        linkTextColor: resolvedLink,
        linkHighlightColor: resolvedLink.withAlphaComponent(0.22),
        accentTextColor: resolvedLink,
        accentControlColor: resolvedLink,
        accentControlDisabledColor: resolvedText.withAlphaComponent(0.45),
        mediaActiveControlColor: resolvedLink,
        mediaInactiveControlColor: resolvedText.withAlphaComponent(0.4),
        mediaControlInnerBackgroundColor: effectiveFill,
        pendingActivityColor: resolvedSecondary,
        fileTitleColor: resolvedText,
        fileDescriptionColor: resolvedSecondary,
        fileDurationColor: resolvedSecondary,
        polls: resolvedPolls,
        textSelectionColor: resolvedLink.withAlphaComponent(0.22),
        textSelectionKnobColor: resolvedLink
    )
}

private func fullGramApplyCustomization(_ theme: PresentationTheme) -> PresentationTheme {
    var result = theme
    let accent = FullGramThemeColors.color(.accent)
    if let accent {
        result = customizePresentationTheme(result, editing: false, accentColor: accent, outgoingAccentColor: nil, backgroundColors: [], bubbleColors: [], animateBubbleColors: nil)
    }
    let outgoingFill = FullGramThemeColors.color(.outgoingBubble)
    let outgoingText = FullGramThemeColors.color(.outgoingText)
    let incomingFill = FullGramThemeColors.color(.incomingBubble)
    let incomingText = FullGramThemeColors.color(.incomingText)
    if outgoingFill != nil || outgoingText != nil || incomingFill != nil || incomingText != nil {
        let message = result.chat.message
        let updatedOutgoing = (outgoingFill != nil || outgoingText != nil)
            ? fullGramParted(message.outgoing, fill: outgoingFill, text: outgoingText, accent: accent)
            : nil
        let updatedIncoming = (incomingFill != nil || incomingText != nil)
            ? fullGramParted(message.incoming, fill: incomingFill, text: incomingText, accent: accent)
            : nil
        let outgoingCheck: UIColor?
        if let updatedOutgoing {
            outgoingCheck = updatedOutgoing.primaryTextColor.withAlphaComponent(0.65)
        } else {
            outgoingCheck = nil
        }
        let updated = message.withUpdated(
            incoming: updatedIncoming,
            outgoing: updatedOutgoing,
            outgoingCheckColor: outgoingCheck
        )
        let chat = result.chat.withUpdated(message: updated)
        result = PresentationTheme(name: result.name, index: result.index, referenceTheme: result.referenceTheme, overallDarkAppearance: result.overallDarkAppearance, intro: result.intro, passcode: result.passcode, rootController: result.rootController, list: result.list, chatList: result.chatList, chat: chat, actionSheet: result.actionSheet, contextMenu: result.contextMenu, inAppNotification: result.inAppNotification, chart: result.chart, preview: result.preview)
    }
    let listBackground = FullGramThemeColors.color(.listBackground)
    let chatTitle = FullGramThemeColors.color(.chatTitle)
    if listBackground != nil || chatTitle != nil {
        let list = listBackground.map { result.list.withUpdated(blocksBackgroundColor: $0, plainBackgroundColor: $0) } ?? result.list
        let chatList = result.chatList.withUpdated(backgroundColor: listBackground, titleColor: chatTitle)
        result = PresentationTheme(name: result.name, index: result.index, referenceTheme: result.referenceTheme, overallDarkAppearance: result.overallDarkAppearance, intro: result.intro, passcode: result.passcode, rootController: result.rootController, list: list, chatList: chatList, chat: result.chat, actionSheet: result.actionSheet, contextMenu: result.contextMenu, inAppNotification: result.inAppNotification, chart: result.chart, preview: result.preview)
    }
    return result
}

func fullGramCustomizedTheme(_ theme: PresentationTheme) -> PresentationTheme {
    guard FullGramThemeColors.hasColors else {
        return theme
    }
    let revision = FullGramThemeColors.revision
    fullGramThemeLock.lock()
    defer { fullGramThemeLock.unlock() }
    if let cached = fullGramCustomThemes.first(where: { ($0.input === theme || $0.output === theme) && $0.revision == revision }) {
        return cached.output
    }
    let output = fullGramApplyCustomization(theme)
    fullGramCustomThemes.append((theme, revision, output))
    if fullGramCustomThemes.count > 6 {
        fullGramCustomThemes.removeFirst(fullGramCustomThemes.count - 6)
    }
    return output
}

func fullGramCustomWallpaper() -> TelegramWallpaper? {
    guard let first = FullGramThemeColors.rgb(.wallpaper) else {
        return nil
    }
    if let second = FullGramThemeColors.rgb(.wallpaperSecond) {
        return .gradient(TelegramWallpaper.Gradient(id: nil, colors: [first, second], settings: WallpaperSettings()))
    }
    return .color(first)
}
