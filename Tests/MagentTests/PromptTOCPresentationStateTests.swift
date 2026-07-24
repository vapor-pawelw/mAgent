import Cocoa
import Testing

@Suite("Prompt TOC presentation")
struct PromptTOCPresentationStateTests {
    @Test("Floating TOC reveals pin control and full content only while hovered")
    func floatingPresentationFollowsHover() {
        var state = PromptTOCPresentationState(isPinned: false, isHovered: false)

        #expect(!state.isExpanded)
        #expect(!state.showsPinButton)
        #expect(!state.showsCornerResizeHandles)

        state.isHovered = true

        #expect(state.isExpanded)
        #expect(state.showsPinButton)
        #expect(state.showsCornerResizeHandles)
    }

    @Test("Pinned TOC stays expanded with its pin control and uses only the split divider")
    func pinnedPresentationStaysExpanded() {
        let state = PromptTOCPresentationState(isPinned: true, isHovered: false)

        #expect(state.isExpanded)
        #expect(state.showsPinButton)
        #expect(!state.showsCornerResizeHandles)
    }

    @Test("Pinned width preserves room for content and respects the TOC minimum")
    func pinnedWidthIsClampedToSplitBounds() {
        #expect(
            PromptTOCPresentationState.pinnedWidth(
                requestedWidth: 500,
                availableWidth: 900,
                minimumTOCWidth: 320,
                minimumContentWidth: 320
            ) == 500
        )
        #expect(
            PromptTOCPresentationState.pinnedWidth(
                requestedWidth: 800,
                availableWidth: 900,
                minimumTOCWidth: 320,
                minimumContentWidth: 320
            ) == 580
        )
        #expect(
            PromptTOCPresentationState.pinnedWidth(
                requestedWidth: 100,
                availableWidth: 900,
                minimumTOCWidth: 320,
                minimumContentWidth: 320
            ) == 320
        )
    }

    @Test("Pinned divider matches toolbar separators and uses the horizontal resize cursor")
    func pinnedDividerAppearanceAndCursor() {
        #expect(PromptTOCPinnedResizeStyle.dividerColor == NSColor.tertiaryLabelColor)
        #expect(PromptTOCPinnedResizeStyle.cursor === NSCursor.resizeLeftRight)
    }
}
