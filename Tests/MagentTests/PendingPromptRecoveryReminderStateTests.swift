import Testing

@Suite
struct PendingPromptRecoveryReminderStateTests {
    @Test
    func reminderAppearsOnlyAfterDismissalWithRecoverablePrompts() {
        var state = PendingPromptRecoveryReminderState()

        state.setRecoverablePromptsAvailable(true)
        #expect(!state.isReminderVisible)

        state.bannerDismissed(hasRecoverablePrompts: true)
        #expect(state.isReminderVisible)
    }

    @Test
    func reminderClearsWhenActivated() {
        var state = PendingPromptRecoveryReminderState()
        state.bannerDismissed(hasRecoverablePrompts: true)

        state.reminderActivated()

        #expect(!state.isReminderVisible)
        #expect(state.hasRecoverablePrompts)
    }

    @Test
    func reminderClearsWhenNoPromptsRemain() {
        var state = PendingPromptRecoveryReminderState()
        state.bannerDismissed(hasRecoverablePrompts: true)

        state.setRecoverablePromptsAvailable(false)

        #expect(!state.isReminderVisible)
        #expect(!state.hasRecoverablePrompts)
        #expect(!state.hasDismissedBanner)
    }

    @Test
    func visibleBannerKeepsReminderHidden() {
        var state = PendingPromptRecoveryReminderState()
        state.bannerDismissed(hasRecoverablePrompts: true)

        state.bannerBecameVisible(hasRecoverablePrompts: true)

        #expect(!state.isReminderVisible)
        #expect(state.hasRecoverablePrompts)
    }
}
