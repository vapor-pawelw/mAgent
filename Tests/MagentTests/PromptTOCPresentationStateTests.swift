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

    @Test("Pinned divider sits on the TOC leading edge while its resize target stays wide")
    func pinnedDividerUsesLeadingEdge() {
        let handleBounds = CGRect(x: 0, y: 0, width: 8, height: 500)

        #expect(
            PromptTOCPinnedResizeStyle.dividerRect(in: handleBounds)
                == CGRect(x: 0, y: 0, width: 1, height: 500)
        )
    }

    @Test("TOC row keeps its ordinal separate and expands its pinned preview")
    func rowPresentationAdaptsToPinnedMode() {
        let floating = PromptTOCRowPresentation(
            entryIndex: 1,
            promptText: "Explain this change",
            isPinned: false
        )
        let pinned = PromptTOCRowPresentation(
            entryIndex: 1,
            promptText: "Explain this change",
            isPinned: true
        )

        #expect(floating.ordinalText == "2")
        #expect(floating.promptText == "Explain this change")
        #expect(floating.promptFontSize == 11)
        #expect(floating.maximumPromptLines == 3)
        #expect(floating.ordinalBadgeWidth == 20)
        #expect(pinned.promptFontSize == 12)
        #expect(pinned.maximumPromptLines == 5)

        let threeDigitOrdinal = PromptTOCRowPresentation(
            entryIndex: 99,
            promptText: "One hundredth prompt",
            isPinned: true
        )
        #expect(threeDigitOrdinal.ordinalText == "100")
        #expect(threeDigitOrdinal.ordinalBadgeWidth > 20)
    }
}
