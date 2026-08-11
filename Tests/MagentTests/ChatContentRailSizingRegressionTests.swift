import MagentCore
import Testing

@Suite("Chat content rail sizing regressions")
struct ChatContentRailSizingRegressionTests {
    @Test(
        "Loading chat derives its rail from the existing container width",
        arguments: [640.0, 900.0, 1_440.0]
    )
    func loadingChatUsesExistingContainerWidth(_ containerWidth: Double) {
        let railWidth = ChatContentLayoutPolicy.railWidth(for: containerWidth)

        #expect(railWidth <= max(0, containerWidth - 28))
        #expect(railWidth <= ChatContentLayoutPolicy.maximumRailWidth)
    }
}
