import Foundation
import MagentCore
import Testing

@Suite("ChatAttachmentDropPlanner")
struct ChatAttachmentDropPlannerTests {
    @Test("Uses file URLs only when a drop also advertises image data")
    func fileURLsSuppressSyntheticPasteImages() {
        let screenshot = URL(fileURLWithPath: "/tmp/Screenshot 2026-05-22 at 12.00.00.png")

        let plan = ChatAttachmentDropPlanner.plan(
            fileURLs: [screenshot],
            hasPasteboardImages: true
        )

        #expect(plan.fileURLs == [screenshot])
        #expect(!plan.shouldImportPasteboardImages)
    }

    @Test("Imports pasteboard images when no file URLs are present")
    func imageOnlyPayloadCreatesSyntheticAttachment() {
        let plan = ChatAttachmentDropPlanner.plan(
            fileURLs: [],
            hasPasteboardImages: true
        )

        #expect(plan.fileURLs.isEmpty)
        #expect(plan.shouldImportPasteboardImages)
    }
}
