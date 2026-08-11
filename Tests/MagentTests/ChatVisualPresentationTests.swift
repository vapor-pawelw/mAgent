import MagentCore
import Testing

struct ChatVisualPresentationTests {
    @Test
    func contentRailStaysReadableOnWideWindowsAndUsesAvailableSpaceOnNarrowWindows() {
        #expect(ChatContentLayoutPolicy.railWidth(for: 1_600) == 920)
        #expect(ChatContentLayoutPolicy.railWidth(for: 700) == 672)
        #expect(ChatContentLayoutPolicy.railWidth(for: 20) == 0)
    }

    @Test
    func composerActionCommunicatesWhetherPromptWillSendOrSteer() {
        #expect(
            ChatComposerPresentation(
                hasDraftText: false,
                attachmentCount: 0,
                isRunning: false,
                queuedPromptCount: 0
            ).primaryAction == .disabled
        )
        #expect(
            ChatComposerPresentation(
                hasDraftText: false,
                attachmentCount: 1,
                isRunning: false,
                queuedPromptCount: 0
            ).primaryAction == .send
        )
        let runningPresentation = ChatComposerPresentation(
            hasDraftText: true,
            attachmentCount: 0,
            isRunning: true,
            queuedPromptCount: 2
        )
        #expect(runningPresentation.primaryAction == .steer)
        #expect(runningPresentation.isRunning)
        #expect(runningPresentation.queuedPromptCount == 2)
    }

    @Test
    func contrastPolicyAcceptsReadablePairsAndRejectsLowContrastPairs() {
        #expect(
            ChatColorContrastPolicy.meetsAccessibleContrast(
                foregroundRed: 1,
                foregroundGreen: 1,
                foregroundBlue: 1,
                backgroundRed: 0,
                backgroundGreen: 0,
                backgroundBlue: 0
            )
        )
        #expect(
            !ChatColorContrastPolicy.meetsAccessibleContrast(
                foregroundRed: 0.55,
                foregroundGreen: 0.55,
                foregroundBlue: 0.55,
                backgroundRed: 0.65,
                backgroundGreen: 0.65,
                backgroundBlue: 0.65
            )
        )
    }
}
