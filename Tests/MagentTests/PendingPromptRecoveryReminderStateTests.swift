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

    @Test
    func toolbarHintIsConsumedOnlyTheFirstTimeReminderAppears() {
        var state = PendingPromptRecoveryToolbarHintState()

        let hiddenResult = state.consumeHintIfNeeded(isReminderVisible: false)
        #expect(!hiddenResult)
        #expect(!state.hasShownHint)

        let firstVisibleResult = state.consumeHintIfNeeded(isReminderVisible: true)
        #expect(firstVisibleResult)
        #expect(state.hasShownHint)

        let secondVisibleResult = state.consumeHintIfNeeded(isReminderVisible: true)
        #expect(!secondVisibleResult)
    }

    @Test
    func toolbarHintStaysHiddenAfterEarlierPresentation() {
        var state = PendingPromptRecoveryToolbarHintState(hasShownHint: true)

        let result = state.consumeHintIfNeeded(isReminderVisible: true)
        #expect(!result)
        #expect(state.hasShownHint)
    }
}
