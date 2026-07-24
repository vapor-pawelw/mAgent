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

    mutating func updateBaseBranch(
        _ input: String,
        defaultBranch: String,
        availableSources: [ThreadCreationSourceDescriptor] = []
    ) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBranch = trimmedInput.isEmpty ? defaultBranch : trimmedInput

        if !trimmedInput.isEmpty,
           let matchedSource = matchingSource(
               branch: trimmedInput,
               availableSources: availableSources
           ) {
            self = .thread(matchedSource)
            return
        }
        if availableSources.isEmpty,
           case .thread(let source) = self,
           normalizedBranch(source.branchName) == normalizedBranch(resolvedBranch) {
            return
        }
        self = .branch(resolvedBranch)
    }

    private func matchingSource(
        branch: String,
        availableSources: [ThreadCreationSourceDescriptor]
    ) -> ThreadCreationSourceDescriptor? {
        let exactMatches = availableSources.filter {
            $0.branchName.trimmingCharacters(in: .whitespacesAndNewlines) == branch
        }
        if exactMatches.count == 1 {
            return exactMatches[0]
        }
        guard exactMatches.isEmpty else { return nil }

        let normalizedInput = normalizedBranch(branch)
        let normalizedMatches = availableSources.filter {
            normalizedBranch($0.branchName) == normalizedInput
        }
        guard normalizedMatches.count == 1 else { return nil }
        return normalizedMatches[0]
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

enum ThreadCreationSourcePickerLayout {
    static let rowHeight: CGFloat = 42
    static let standardSpacing: CGFloat = 6
    static let contextualGroupSpacing: CGFloat = 24
    static let verticalInset: CGFloat = 10

    static func hasVisibleContextualSeparator(
        firstRemainingOptionIndex: Int?,
        visibleOptionCount: Int
    ) -> Bool {
        guard let firstRemainingOptionIndex else { return false }
        return firstRemainingOptionIndex > 0
            && firstRemainingOptionIndex < visibleOptionCount
    }

    static func contentHeight(optionCount: Int, hasContextualSeparator: Bool) -> CGFloat {
        guard optionCount > 0 else { return 0 }
        let rowHeights = CGFloat(optionCount) * rowHeight
        let standardGaps = CGFloat(max(optionCount - 1, 0)) * standardSpacing
        let contextualSpacing = hasContextualSeparator
            ? contextualGroupSpacing - standardSpacing
            : 0
        return rowHeights + standardGaps + contextualSpacing + (verticalInset * 2)
    }
}

enum ThreadCreationSourceCapsuleMode: Equatable {
    case collapsed
    case expanded(isSelected: Bool)

    var showsExpandedDetails: Bool {
        if case .expanded = self {
            return true
        }
        return false
    }

    var isSelected: Bool {
        if case .expanded(let isSelected) = self {
            return isSelected
        }
        return false
    }

    var rowHeight: CGFloat {
        showsExpandedDetails ? ThreadCreationSourcePickerLayout.rowHeight : 30
    }
}
