import Foundation

struct ThreadCreationSourceDescriptor: Equatable {
    let threadID: UUID
    let branchName: String
    let displayName: String
    let isMainWorktree: Bool
}

enum ThreadCreationSourceSelection: Equatable {
    case thread(ThreadCreationSourceDescriptor)
    case branch(String)

    var sourceThreadID: UUID? {
        guard case .thread(let source) = self, !source.isMainWorktree else { return nil }
        return source.threadID
    }

    var baseBranch: String {
        switch self {
        case .thread(let source):
            return source.branchName
        case .branch(let branch):
            return branch
        }
    }

    var titleSourceName: String {
        switch self {
        case .thread(let source):
            return source.displayName
        case .branch(let branch):
            return branch
        }
    }

    var isCustomBranch: Bool {
        if case .branch = self {
            return true
        }
        return false
    }

    mutating func updateBaseBranch(_ input: String, defaultBranch: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBranch = trimmedInput.isEmpty ? defaultBranch : trimmedInput

        if case .thread(let source) = self,
           normalizedBranch(source.branchName) == normalizedBranch(resolvedBranch) {
            return
        }
        self = .branch(resolvedBranch)
    }

    private func normalizedBranch(_ branch: String) -> String {
        branch.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "origin/", with: "")
    }
}

enum ThreadCreationSourcePickerScrollGeometry {
    static func centeredOrigin(
        itemMidY: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        let maximumOrigin = max(contentHeight - viewportHeight, 0)
        return min(max(itemMidY - (viewportHeight / 2), 0), maximumOrigin)
    }
}
