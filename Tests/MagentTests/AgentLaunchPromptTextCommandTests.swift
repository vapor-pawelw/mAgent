import AppKit
import Testing

@Suite("Agent launch prompt keyboard commands")
struct AgentLaunchPromptTextCommandTests {
    @Test("Escape cancels the launch prompt")
    func escapeCancelsPrompt() {
        let command = AgentLaunchPromptTextCommand(
            selector: #selector(NSResponder.cancelOperation(_:))
        )
        var cancellationCount = 0
        var submissionCount = 0

        let consumed = command?.perform(
            isShiftReturn: false,
            actions: AgentLaunchPromptTextCommandActions(
                submit: { submissionCount += 1 },
                cancel: { cancellationCount += 1 },
                selectNextField: {},
                selectPreviousField: {},
                undo: {},
                redo: {}
            )
        )

        #expect(command == .cancel)
        #expect(consumed == true)
        #expect(cancellationCount == 1)
        #expect(submissionCount == 0)
    }
}
