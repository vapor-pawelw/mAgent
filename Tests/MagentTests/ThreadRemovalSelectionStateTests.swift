import Foundation
import Testing

@Suite
struct ThreadRemovalSelectionStateTests {
    @Test
    func clearingSelectedRemovedThreadClearsDiffContext() {
        let removedID = UUID()
        var state = ThreadRemovalSelectionState(
            selectedThreadID: removedID,
            diffInspectionThreadID: removedID,
            isDiffInspectionPopoutContext: true
        )

        let didClear = state.clearRemovedThread(removedID)

        #expect(didClear)
        #expect(state.selectedThreadID == nil)
        #expect(state.diffInspectionThreadID == nil)
        #expect(state.isDiffInspectionPopoutContext == false)
    }

    @Test
    func clearingDiffOnlyRemovedThreadFallsBackToSelectedThread() {
        let selectedID = UUID()
        let removedID = UUID()
        var state = ThreadRemovalSelectionState(
            selectedThreadID: selectedID,
            diffInspectionThreadID: removedID,
            isDiffInspectionPopoutContext: true
        )

        let didClear = state.clearRemovedThread(removedID)

        #expect(didClear)
        #expect(state.selectedThreadID == selectedID)
        #expect(state.diffInspectionThreadID == selectedID)
        #expect(state.isDiffInspectionPopoutContext == false)
    }

    @Test
    func unrelatedRemovedThreadLeavesStateUnchanged() {
        let selectedID = UUID()
        let diffID = UUID()
        var state = ThreadRemovalSelectionState(
            selectedThreadID: selectedID,
            diffInspectionThreadID: diffID,
            isDiffInspectionPopoutContext: true
        )

        let didClear = state.clearRemovedThread(UUID())

        #expect(!didClear)
        #expect(state.selectedThreadID == selectedID)
        #expect(state.diffInspectionThreadID == diffID)
        #expect(state.isDiffInspectionPopoutContext == true)
    }
}
