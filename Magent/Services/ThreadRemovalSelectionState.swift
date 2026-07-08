import Foundation

struct ThreadRemovalSelectionState: Equatable {
    var selectedThreadID: UUID?
    var diffInspectionThreadID: UUID?
    var isDiffInspectionPopoutContext: Bool

    mutating func clearRemovedThread(_ threadID: UUID) -> Bool {
        let didMatchSelected = selectedThreadID == threadID
        let didMatchDiffInspection = diffInspectionThreadID == threadID
        guard didMatchSelected || didMatchDiffInspection else { return false }

        if didMatchSelected {
            selectedThreadID = nil
        }
        if didMatchDiffInspection {
            diffInspectionThreadID = selectedThreadID
            isDiffInspectionPopoutContext = false
        }
        return true
    }
}
