import MagentCore
import Testing

@Suite("Prompt input surface style")
struct PromptInputSurfaceStyleTests {
    @Test("Chat and launch prompts share compact rounded input metrics")
    func sharedPromptMetrics() {
        #expect(PromptInputSurfaceStyle.cornerRadius == 10)
        #expect(PromptInputSurfaceStyle.borderOpacity == 0.2)
        #expect(PromptInputSurfaceStyle.horizontalTextInset == 8)
        #expect(PromptInputSurfaceStyle.verticalTextInset == 8)
    }
}
