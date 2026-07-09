import Testing
import MagentCore

@Suite("Chat timestamp presentation")
struct ChatTimestampPresentationTests {
    @Test("Tooltip contains exact time without optional model metadata")
    func exactTimeOnly() {
        let text = ChatTimestampPresentation.metadataTooltip(
            exactText: "May 1, 2026 at 11:45:10 AM",
            metadataText: nil
        )
        #expect(text == "May 1, 2026 at 11:45:10 AM")
    }

    @Test("Tooltip progressively discloses model metadata below exact time")
    func exactTimeWithMetadata() {
        let text = ChatTimestampPresentation.metadataTooltip(
            exactText: "May 1, 2026 at 11:45:10 AM",
            metadataText: "GPT 5.3 · high"
        )
        #expect(text == "May 1, 2026 at 11:45:10 AM\nGPT 5.3 · high")
    }
}
