import Foundation

struct PendingPromptRecoveryReminderState: Equatable {
    private(set) var hasRecoverablePrompts = false
    private(set) var hasDismissedBanner = false

    var isReminderVisible: Bool {
        hasRecoverablePrompts && hasDismissedBanner
    }

    mutating func setRecoverablePromptsAvailable(_ available: Bool) {
        hasRecoverablePrompts = available
        if !available {
            hasDismissedBanner = false
        }
    }

    mutating func bannerBecameVisible(hasRecoverablePrompts: Bool = true) {
        self.hasRecoverablePrompts = hasRecoverablePrompts
        hasDismissedBanner = false
    }

    mutating func bannerDismissed(hasRecoverablePrompts: Bool = true) {
        self.hasRecoverablePrompts = hasRecoverablePrompts
        hasDismissedBanner = hasRecoverablePrompts
    }

    mutating func reminderActivated() {
        hasDismissedBanner = false
    }
}
