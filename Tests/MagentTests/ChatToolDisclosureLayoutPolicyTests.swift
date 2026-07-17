import Testing
import MagentCore

@Suite("Chat tool disclosure layout")
struct ChatToolDisclosureLayoutPolicyTests {
    @Test("Activity summaries keep a readable transcript width")
    func activitySummariesUseMaximumWidth() {
        let width = ChatToolDisclosureLayoutPolicy.targetWidth(
            isActivitySummary: true,
            maximumWidth: 760,
            minimumWidth: 44,
            measuredLineWidth: 0,
            measuredHeaderWidth: 31,
            horizontalPadding: 0
        )

        #expect(width == 760)
    }

    @Test("Activity count stays on the disclosure headline")
    func activityCountStaysOnHeadline() {
        let title = ChatToolDisclosureLayoutPolicy.headerTitle(title: "Activity", detail: "3 actions")

        #expect(title == "Activity  ·  3 actions")
        #expect(!title.contains("\n"))
    }
}
