import Foundation
import Testing
import MagentCore

@Suite
struct SidebarSectionOutlineChildCountTests {
    @Test
    func outlineChildCountMatchesRenderedSectionItems() {
        let projectId = UUID()
        let pinned = makeThread(projectId: projectId, name: "pinned", isPinned: true)
        let visible = makeThread(projectId: projectId, name: "visible")
        let hidden = makeThread(projectId: projectId, name: "hidden", isSidebarHidden: true)
        let section = SidebarSection(
            projectId: projectId,
            sectionId: UUID(),
            name: "Work",
            color: .systemBlue,
            threads: [pinned, visible, hidden]
        )
        let renderedItems = section.items

        #expect(section.outlineChildCount == renderedItems.count)
        #expect(renderedItems.count > section.threads.count)
    }

    @Test
    func archivableThreadAvailabilityMatchesSectionMembership() {
        let projectId = UUID()
        let emptySection = SidebarSection(
            projectId: projectId,
            sectionId: UUID(),
            name: "Empty",
            color: .systemBlue,
            threads: []
        )
        let populatedSection = SidebarSection(
            projectId: projectId,
            sectionId: UUID(),
            name: "Work",
            color: .systemBlue,
            threads: [makeThread(projectId: projectId, name: "work")]
        )

        #expect(!emptySection.hasArchivableThreads)
        #expect(populatedSection.hasArchivableThreads)
    }

    private func makeThread(
        projectId: UUID,
        name: String,
        isPinned: Bool = false,
        isSidebarHidden: Bool = false
    ) -> MagentThread {
        MagentThread(
            projectId: projectId,
            name: name,
            worktreePath: "/tmp/\(name)",
            branchName: name,
            isPinned: isPinned,
            isSidebarHidden: isSidebarHidden
        )
    }
}
