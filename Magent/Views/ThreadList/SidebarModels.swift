import Cocoa
import MagentCore

class SidebarProject {
    let projectId: UUID
    let name: String
    let isPinned: Bool
    let isMissing: Bool
    var children: [Any] // Mix of MagentThread (main) and SidebarSection

    init(projectId: UUID, name: String, isPinned: Bool, isMissing: Bool = false, children: [Any]) {
        self.projectId = projectId
        self.name = name
        self.isPinned = isPinned
        self.isMissing = isMissing
        self.children = children
    }
}

class SidebarSection {
    let projectId: UUID
    let sectionId: UUID
    let name: String
    let color: NSColor
    var isKeepAlive: Bool
    var threads: [MagentThread]
    var areHiddenThreadsExpanded: Bool

    init(projectId: UUID, sectionId: UUID, name: String, color: NSColor, isKeepAlive: Bool = false, threads: [MagentThread], areHiddenThreadsExpanded: Bool = false) {
        self.projectId = projectId
        self.sectionId = sectionId
        self.name = name
        self.color = color
        self.isKeepAlive = isKeepAlive
        self.threads = threads
        self.areHiddenThreadsExpanded = areHiddenThreadsExpanded
    }

    /// Thread items interleaved with `SidebarGroupSeparator` spacers at pinned→normal
    /// and normal→hidden transitions. Used for datasource rendering only —
    /// all drag-drop / count / filter logic reads `threads` directly.
    var items: [Any] {
        var result: [Any] = []
        var lastState: ThreadSidebarListState? = nil
        for thread in threads where !thread.isSidebarHidden {
            if let last = lastState, thread.sidebarListState != last {
                result.append(SidebarGroupSeparator())
            }
            result.append(thread)
            lastState = thread.sidebarListState
        }
        let hiddenThreads = threads.filter(\.isSidebarHidden)
        if !hiddenThreads.isEmpty {
            result.append(SidebarHiddenThreadsToggle(
                projectId: projectId,
                sectionId: sectionId,
                threads: hiddenThreads,
                isExpanded: areHiddenThreadsExpanded
            ))
            if areHiddenThreadsExpanded {
                result.append(contentsOf: hiddenThreads)
            } else {
                result.append(SidebarGroupSeparator())
            }
        }
        return result
    }

    var outlineChildCount: Int {
        items.count
    }

    var hasArchivableThreads: Bool {
        !threads.isEmpty
    }
}

enum SidebarInlineRenameFocusPolicy {
    static let maxDeferredFocusAttempts = 3

    static func shouldRetry(editorIsAvailable: Bool, attempt: Int) -> Bool {
        !editorIsAvailable && attempt < maxDeferredFocusAttempts
    }
}

final class SidebarSpacer {}
final class SidebarProjectMainSpacer {}
final class SidebarMissingProjectRow {
    let projectId: UUID
    let projectName: String
    let repoPath: String

    init(projectId: UUID, projectName: String, repoPath: String) {
        self.projectId = projectId
        self.projectName = projectName
        self.repoPath = repoPath
    }
}
/// Blank spacing between thread groups or after a final collapsed disclosure row.
final class SidebarGroupSeparator {
    static let standardHeight: CGFloat = 12

    let height: CGFloat

    init(height: CGFloat = standardHeight) {
        self.height = height
    }
}
final class SidebarHiddenThreadsToggle {
    let projectId: UUID
    let sectionId: UUID?
    var threads: [MagentThread]
    let isExpanded: Bool

    init(projectId: UUID, sectionId: UUID?, threads: [MagentThread], isExpanded: Bool) {
        self.projectId = projectId
        self.sectionId = sectionId
        self.threads = threads
        self.isExpanded = isExpanded
    }

    var count: Int { threads.count }
}
final class HiddenThreadsDisclosureButton: NSButton {
    var storageKey: String?
}
final class SidebarBottomPadding {
    let height: CGFloat

    init(height: CGFloat) {
        self.height = height
    }
}
