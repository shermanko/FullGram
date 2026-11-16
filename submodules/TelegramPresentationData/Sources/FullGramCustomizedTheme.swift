import Foundation
import UIKit
import Display
import TelegramCore

private let fullGramThemeLock = NSLock()
private var fullGramCustomThemes: [(input: PresentationTheme, revision: Int, output: PresentationTheme)] = []

private func fullGramBubble(_ components: PresentationThemeBubbleColorComponents, fill: UIColor) -> PresentationThemeBubbleColorComponents {
    return PresentationThemeBubbleColorComponents(
        fill: [fill],
        highlightedFill: fill.withMultipliedBrightnessBy(0.9),
        stroke: components.stroke,
        shadow: components.shadow,
        reactionInactiveBackground: components.reactionInactiveBackground,
        reactionInactiveForeground: components.reactionInactiveForeground,
        reactionActiveBackground: components.reactionActiveBackground,
        reactionActiveForeground: components.reactionActiveForeground,
        reactionStarsInactiveBackground: components.reactionStarsInactiveBackground,
        reactionStarsInactiveForeground: components.reactionStarsInactiveForeground,
        reactionStarsActiveBackground: components.reactionStarsActiveBackground,
        reactionStarsActiveForeground: components.reactionStarsActiveForeground,
        reactionInactiveMediaPlaceholder: components.reactionInactiveMediaPlaceholder,
        reactionActiveMediaPlaceholder: components.reactionActiveMediaPlaceholder
    )
}

private func fullGramParted(_ colors: PresentationThemePartedColors, fill: UIColor?, text: UIColor?) -> PresentationThemePartedColors {
    var bubble: PresentationThemeBubbleColor?
    if let fill {
        bubble = colors.bubble.withUpdated(
            withWallpaper: fullGramBubble(colors.bubble.withWallpaper, fill: fill),
            withoutWallpaper: fullGramBubble(colors.bubble.withoutWallpaper, fill: fill)
        )
    }
    return colors.withUpdated(bubble: bubble, primaryTextColor: text, secondaryTextColor: text?.withAlphaComponent(0.6), linkTextColor: nil)
}

private func fullGramApplyCustomization(_ theme: PresentationTheme) -> PresentationTheme {
    var result = theme
    if let accent = FullGramThemeColors.color(.accent) {
        result = customizePresentationTheme(result, editing: false, accentColor: accent, outgoingAccentColor: nil, backgroundColors: [], bubbleColors: [], animateBubbleColors: nil)
    }
    let outgoingFill = FullGramThemeColors.color(.outgoingBubble)
    let outgoingText = FullGramThemeColors.color(.outgoingText)
    let incomingFill = FullGramThemeColors.color(.incomingBubble)
    let incomingText = FullGramThemeColors.color(.incomingText)
    if outgoingFill != nil || outgoingText != nil || incomingFill != nil || incomingText != nil {
        let message = result.chat.message
        let updated = message.withUpdated(
            incoming: (incomingFill != nil || incomingText != nil) ? fullGramParted(message.incoming, fill: incomingFill, text: incomingText) : nil,
            outgoing: (outgoingFill != nil || outgoingText != nil) ? fullGramParted(message.outgoing, fill: outgoingFill, text: outgoingText) : nil
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
