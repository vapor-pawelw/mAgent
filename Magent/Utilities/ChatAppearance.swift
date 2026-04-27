import Cocoa
import MagentCore

@MainActor
struct ChatAppearance {
    static let defaultUserBubbleColor = NSColor.controlAccentColor
    static let defaultUserTextColor = NSColor.white
    static let defaultAgentBubbleColor = NSColor(resource: .surface)
    static let defaultAgentTextColor = NSColor.labelColor

    let userBubbleColor: NSColor
    let userTextColor: NSColor
    let agentBubbleColor: NSColor
    let agentTextColor: NSColor

    static func resolve(from settings: AppSettings) -> ChatAppearance {
        ChatAppearance(
            userBubbleColor: NSColor(hex: settings.chatUserBubbleColorHex ?? "") ?? defaultUserBubbleColor,
            userTextColor: NSColor(hex: settings.chatUserTextColorHex ?? "") ?? defaultUserTextColor,
            agentBubbleColor: NSColor(hex: settings.chatAssistantBubbleColorHex ?? "") ?? defaultAgentBubbleColor,
            agentTextColor: NSColor(hex: settings.chatAssistantTextColorHex ?? "") ?? defaultAgentTextColor
        )
    }
}
