import Cocoa
import MagentCore
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

    @Test("TOC header reserves enough badge width for the full prompt count")
    func headerCountBadgeWidth() {
        let singleDigitWidth = PromptTOCHeaderLayout.countBadgeWidth(for: "9")
        let multiDigitText = "12345"
        let multiDigitWidth = PromptTOCHeaderLayout.countBadgeWidth(for: multiDigitText)
        let renderedTextWidth = (multiDigitText as NSString).size(
            withAttributes: [.font: PromptTOCHeaderLayout.countFont]
        ).width

        #expect(singleDigitWidth >= PromptTOCHeaderLayout.countBadgeMinimumWidth)
        #expect(
            multiDigitWidth >= ceil(renderedTextWidth) +
                (2 * PromptTOCHeaderLayout.countLabelHorizontalInset)
        )
        #expect(multiDigitWidth > singleDigitWidth)
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

    @Test("Navigation resolves the selected prompt against fresh line coordinates")
    func navigationTargetUsesFreshCoordinates() {
        let original = [
            PromptTOCEntry(lineIndex: 120, displayText: "First", fullText: "First"),
            PromptTOCEntry(lineIndex: 840, displayText: "Second", fullText: "Second"),
        ]
        let target = PromptTOCNavigationTarget(entryIndex: 1, entries: original)
        let refreshed = [
            PromptTOCEntry(lineIndex: 40, displayText: "First", fullText: "First"),
            PromptTOCEntry(lineIndex: 760, displayText: "Second", fullText: "Second"),
        ]

        #expect(target?.resolve(in: refreshed)?.lineIndex == 760)
    }

    @Test("Navigation distinguishes repeated prompts from newest to oldest")
    func navigationTargetDistinguishesDuplicatePrompts() {
        let original = [
            PromptTOCEntry(lineIndex: 100, displayText: "Continue", fullText: "Continue"),
            PromptTOCEntry(lineIndex: 200, displayText: "Other", fullText: "Other"),
            PromptTOCEntry(lineIndex: 300, displayText: "Continue", fullText: "Continue"),
        ]
        let olderTarget = PromptTOCNavigationTarget(entryIndex: 0, entries: original)
        let newerTarget = PromptTOCNavigationTarget(entryIndex: 2, entries: original)
        let refreshed = [
            PromptTOCEntry(lineIndex: 25, displayText: "Continue", fullText: "Continue"),
            PromptTOCEntry(lineIndex: 125, displayText: "Other", fullText: "Other"),
            PromptTOCEntry(lineIndex: 225, displayText: "Continue", fullText: "Continue"),
        ]

        #expect(olderTarget?.resolve(in: refreshed)?.lineIndex == 25)
        #expect(newerTarget?.resolve(in: refreshed)?.lineIndex == 225)
    }

    @Test("Known prompt history makes an empty pane capture transient")
    func emptyCaptureRetryPolicy() {
        #expect(PromptTOCRefreshPolicy.shouldRetryEmptyEntries(knownPromptCount: 1))
        #expect(!PromptTOCRefreshPolicy.shouldRetryEmptyEntries(knownPromptCount: 0))
        #expect(PromptTOCRefreshPolicy.periodicInterval == 3)
        #expect(PromptTOCRefreshPolicy.emptyCaptureRetryDelays == [0, 0.2, 0.5, 1])
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

    @Test("TOC timing follows matching prompt occurrences and leaves unknown history unchanged")
    func timingResolutionMatchesPromptOccurrences() {
        let firstSentAt = Date(timeIntervalSince1970: 100)
        let secondSentAt = Date(timeIntervalSince1970: 200)
        let completedAt = Date(timeIntervalSince1970: 260)
        let entries = [
            PromptTOCEntry(lineIndex: 10, displayText: "First prompt", fullText: "First\nprompt"),
            PromptTOCEntry(lineIndex: 20, displayText: "Historical prompt", fullText: "Historical prompt"),
            PromptTOCEntry(lineIndex: 30, displayText: "First prompt", fullText: "First prompt"),
        ]
        let timings = [
            SubmittedPromptTiming(text: "First prompt", sentAt: firstSentAt, completedAt: completedAt),
            SubmittedPromptTiming(text: "First prompt", sentAt: secondSentAt),
        ]

        let resolved = PromptTOCTimingResolver.attaching(timings, to: entries)

        #expect(resolved[0].timing?.sentAt == firstSentAt)
        #expect(resolved[0].timing?.completedAt == completedAt)
        #expect(resolved[1].timing == nil)
        #expect(resolved[2].timing?.sentAt == secondSentAt)
    }

    @Test("A newly observed repeated prompt receives timing on its newest TOC occurrence")
    func timingResolutionPrefersNewestRepeatedPrompt() {
        let sentAt = Date(timeIntervalSince1970: 200)
        let entries = [
            PromptTOCEntry(lineIndex: 10, displayText: "Continue", fullText: "Continue"),
            PromptTOCEntry(lineIndex: 20, displayText: "Other", fullText: "Other"),
            PromptTOCEntry(lineIndex: 30, displayText: "Continue", fullText: "Continue"),
        ]

        let resolved = PromptTOCTimingResolver.attaching(
            [SubmittedPromptTiming(text: "Continue", sentAt: sentAt)],
            to: entries
        )

        #expect(resolved[0].timing == nil)
        #expect(resolved[2].timing?.sentAt == sentAt)
    }

    @Test("TOC footer distinguishes unfinished and completed prompt turns")
    func footerStateReflectsCompletion() {
        let sentAt = Date(timeIntervalSince1970: 100)
        let completedAt = Date(timeIntervalSince1970: 160)

        #expect(
            PromptTOCFooterState(
                timing: SubmittedPromptTiming(text: "Pending", sentAt: sentAt)
            ) == .inProgress(sentAt: sentAt)
        )
        #expect(
            PromptTOCFooterState(
                timing: SubmittedPromptTiming(
                    text: "Done",
                    sentAt: sentAt,
                    completedAt: completedAt
                )
            ) == .completed(sentAt: sentAt, completedAt: completedAt)
        )
        #expect(PromptTOCFooterState(timing: nil) == nil)
    }

    @Test("Agent completion closes every prompt submitted during the active turn")
    func completionClosesPendingPromptTimings() {
        let sessionName = "ma-project-thread"
        let firstSentAt = Date(timeIntervalSince1970: 100)
        let secondSentAt = Date(timeIntervalSince1970: 120)
        let completedAt = Date(timeIntervalSince1970: 180)
        let nextTurnSentAt = Date(timeIntervalSince1970: 200)
        var thread = MagentThread(
            projectId: UUID(),
            name: "thread",
            worktreePath: "/tmp/thread",
            branchName: "feature/thread",
            submittedPromptTimingsBySession: [
                sessionName: [
                    SubmittedPromptTiming(
                        text: "Already done",
                        sentAt: Date(timeIntervalSince1970: 20),
                        completedAt: Date(timeIntervalSince1970: 40)
                    ),
                    SubmittedPromptTiming(text: "First steering prompt", sentAt: firstSentAt),
                    SubmittedPromptTiming(text: "Second steering prompt", sentAt: secondSentAt),
                    SubmittedPromptTiming(text: "Next turn", sentAt: nextTurnSentAt),
                ],
            ]
        )

        let didComplete = thread.completePendingPromptTimings(for: sessionName, at: completedAt)
        #expect(didComplete)

        let timings = thread.submittedPromptTimingsBySession[sessionName]
        #expect(timings?[0].completedAt == Date(timeIntervalSince1970: 40))
        #expect(timings?[1].completedAt == completedAt)
        #expect(timings?[2].completedAt == completedAt)
        #expect(timings?[3].completedAt == nil)
        let didCompleteAgain = thread.completePendingPromptTimings(for: sessionName, at: completedAt)
        #expect(!didCompleteAgain)

        let restored = try? JSONDecoder().decode(
            MagentThread.self,
            from: JSONEncoder().encode(thread)
        )
        #expect(restored?.submittedPromptTimingsBySession[sessionName] == timings)
    }
}
