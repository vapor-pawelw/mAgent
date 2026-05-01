import Foundation
import MagentModels

/// Incremental render plan for chat message arrays.
///
/// The planner intentionally supports only prefix-stable changes:
/// - content edits on existing message IDs
/// - trailing removals
/// - trailing appends
///
/// Any non-tail insertion/removal/reorder falls back to `.fullReload`.
public enum ChatMessageRenderPlan: Equatable, Sendable {
    case fullReload
    case incremental(
        removeTailCount: Int,
        appendRange: Range<Int>,
        changedIndices: [Int]
    )

    public var hasChanges: Bool {
        switch self {
        case .fullReload:
            return true
        case .incremental(let removeTailCount, let appendRange, let changedIndices):
            return removeTailCount > 0 || !appendRange.isEmpty || !changedIndices.isEmpty
        }
    }
}

public enum ChatMessageRenderPlanner {

    /// Builds an incremental render plan from `previous` to `next`.
    /// Returns `.fullReload` when IDs diverge before the tail.
    public static func plan(
        previous: [PersistedChatMessage],
        next: [PersistedChatMessage]
    ) -> ChatMessageRenderPlan {
        let sharedCount = min(previous.count, next.count)
        var sharedPrefixCount = 0

        while sharedPrefixCount < sharedCount,
              previous[sharedPrefixCount].id == next[sharedPrefixCount].id {
            sharedPrefixCount += 1
        }

        // ID mismatch before one array ends means insertion/removal/reorder in the middle.
        // Rebuilding the stack is simpler and safer than trying to patch interior diffs.
        if sharedPrefixCount < sharedCount {
            return .fullReload
        }

        let removeTailCount = max(0, previous.count - sharedPrefixCount)
        let appendRange = sharedPrefixCount..<next.count

        var changedIndices: [Int] = []
        if sharedPrefixCount > 0 {
            changedIndices.reserveCapacity(sharedPrefixCount)
            for index in 0..<sharedPrefixCount where previous[index] != next[index] {
                changedIndices.append(index)
            }
        }

        return .incremental(
            removeTailCount: removeTailCount,
            appendRange: appendRange,
            changedIndices: changedIndices
        )
    }
}

