import Foundation
import Testing

@Suite
struct StickyHeaderBehaviorTests {
    @Test
    func overlayHeightMatchesOnlyTheVisibleHeaderRows() {
        let topPadding = SidebarTopPadding()

        #expect(topPadding.height == 6)
        #expect(topPadding.height == StickyHeaderLayout.topInset)
        #expect(
            StickyHeaderLayout.overlayHeight(
                showsProject: true,
                showsSection: false,
                projectRowHeight: 36,
                sectionRowHeight: 28
            ) == 42
        )
        #expect(
            StickyHeaderLayout.overlayHeight(
                showsProject: true,
                showsSection: true,
                projectRowHeight: 36,
                sectionRowHeight: 28
            ) == 70
        )
        #expect(
            StickyHeaderLayout.overlayHeight(
                showsProject: false,
                showsSection: false,
                projectRowHeight: 36,
                sectionRowHeight: 28
            ) == 0
        )
    }

    @Test
    func stickyProjectContinuesThroughGapsUntilNextProjectCrossesTop() {
        let candidates = [
            StickyHeaderProjectCandidate(project: "First", rowMinY: 0),
            StickyHeaderProjectCandidate(project: "Second", rowMinY: 420),
        ]

        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 390) == "First")
        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 433) == "Second")
    }

    @Test
    func stickyProjectStaysHiddenAtTopUntilActivationOffsetIsPassed() {
        let candidates = [StickyHeaderProjectCandidate(project: "First", rowMinY: 0)]

        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 0) == nil)
        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 12) == nil)
        #expect(StickyHeaderProjectResolver.stickyProject(from: candidates, visibleTop: 13) == "First")
    }
}
