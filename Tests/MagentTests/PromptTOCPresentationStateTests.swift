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
        #expect(floating.ordinalBadgeWidth == 16)
        #expect(pinned.promptFontSize == 12)
        #expect(pinned.maximumPromptLines == 5)

        let threeDigitOrdinal = PromptTOCRowPresentation(
            entryIndex: 99,
            promptText: "One hundredth prompt",
            isPinned: true
        )
        #expect(threeDigitOrdinal.ordinalText == "100")
        #expect(threeDigitOrdinal.ordinalBadgeWidth > 16)
        #expect(PromptTOCOrdinalBadgeStyle.numberColor(isDarkAppearance: true) == .white)
        #expect(PromptTOCOrdinalBadgeStyle.numberColor(isDarkAppearance: false) == .labelColor)
    }

    @Test("TOC displays newest prompts first and selects the newest prompt by default")
    func newestPromptPresentation() {
        #expect(PromptTOCListPresentation.displayEntryIndexes(entryCount: 4) == [3, 2, 1, 0])
        #expect(
            PromptTOCListPresentation.selectedEntryIndex(
                previousSelection: nil,
                entryCount: 4
            ) == 3
        )
        #expect(
            PromptTOCListPresentation.selectedEntryIndex(
                previousSelection: 1,
                entryCount: 4
            ) == 1
        )
        #expect(
            PromptTOCListPresentation.selectedEntryIndex(
                previousSelection: 1,
                entryCount: 5,
                didAppendNewestEntry: true
            ) == 4
        )
        #expect(
            PromptTOCListPresentation.selectedEntryIndex(
                previousSelection: 4,
                entryCount: 4
            ) == 3
        )
        #expect(
            PromptTOCListPresentation.didAppendNewestEntry(
                previousEntryCount: 4,
                currentEntryCount: 5,
                previousNewestEntryIndex: 3
            )
        )
        #expect(
            PromptTOCListPresentation.didAppendNewestEntry(
                previousEntryCount: 4,
                currentEntryCount: 4,
                previousNewestEntryIndex: 2
            )
        )
        #expect(
            !PromptTOCListPresentation.didAppendNewestEntry(
                previousEntryCount: 4,
                currentEntryCount: 4,
                previousNewestEntryIndex: nil
            )
        )
    }

    @Test("TOC keeps the newest edge visible only while the user remains near it")
    func newestEdgeScrollBehavior() {
        #expect(PromptTOCListPresentation.isAtNewestEdge(offsetY: 0, tolerance: 24))
        #expect(PromptTOCListPresentation.isAtNewestEdge(offsetY: 24, tolerance: 24))
        #expect(!PromptTOCListPresentation.isAtNewestEdge(offsetY: 25, tolerance: 24))
        #expect(
            PromptTOCListPresentation.preservedOlderOffset(
                previousOffsetY: 120,
                insertedContentHeight: 38
            ) == 158
        )
    }

    @Test("Only a visible pinned TOC reserves terminal width")
    func contentWidthMode() {
        #expect(
            PromptTOCContentWidthMode.resolve(isPinned: true, isTOCVisible: true)
                == .reservesTrailingTOC
        )
        #expect(
            PromptTOCContentWidthMode.resolve(isPinned: false, isTOCVisible: true)
                == .fullWidth
        )
        #expect(
            PromptTOCContentWidthMode.resolve(isPinned: true, isTOCVisible: false)
                == .fullWidth
        )
    }
}
