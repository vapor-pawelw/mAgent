import Foundation

enum StickyHeaderLayout {
    static let topInset: CGFloat = 6

    static func overlayHeight(
        showsProject: Bool,
        showsSection: Bool,
        projectRowHeight: CGFloat,
        sectionRowHeight: CGFloat
    ) -> CGFloat {
        let rowHeight = (showsProject ? projectRowHeight : 0)
            + (showsSection ? sectionRowHeight : 0)
        return rowHeight > 0 ? topInset + rowHeight : 0
    }
}

struct StickyHeaderProjectCandidate<Project> {
    let project: Project
    let rowMinY: CGFloat
}

enum StickyHeaderProjectResolver {
    static func stickyProject<Project>(
        from candidates: [StickyHeaderProjectCandidate<Project>],
        visibleTop: CGFloat,
        activationOffset: CGFloat = 12
    ) -> Project? {
        candidates.last { candidate in
            candidate.rowMinY + activationOffset < visibleTop
        }?.project
    }
}
