import Testing
@testable import UtilityCore

@Suite("Chat message context actions")
struct ChatMessageContextActionsTests {
    @Test("Text messages can be copied or used to rename their tab")
    func textMessageActions() {
        #expect(
            ChatMessageContextActions.availableActions(messageText: "Investigate the launch crash")
                == [.copy, .renameTabFromMessage]
        )
    }

    @Test("Attachment-only messages cannot generate an empty tab name")
    func emptyMessageActions() {
        #expect(ChatMessageContextActions.availableActions(messageText: "  \n") == [.copy])
    }
}
