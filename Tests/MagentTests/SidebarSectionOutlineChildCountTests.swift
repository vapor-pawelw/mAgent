import Foundation
import Testing
import MagentCore

@Suite
struct SidebarSectionOutlineChildCountTests {
    @Test
    func hiddenThreadsAreCollapsedBehindAGroupToggleByDefault() {
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
        #expect(renderedItems.count == section.threads.count + 2)
        #expect(renderedItems.contains { $0 is SidebarHiddenThreadsToggle })
        #expect(!renderedItems.contains { ($0 as? MagentThread)?.id == hidden.id })
        #expect(renderedItems[renderedItems.count - 2] is SidebarHiddenThreadsToggle)
        #expect((renderedItems.last as? SidebarGroupSeparator)?.height == SidebarGroupSeparator.standardHeight)
    }

    @Test
    func expandedHiddenGroupRendersItsThreadsWithoutChangingTheirOrder() {
        let projectId = UUID()
        let first = makeThread(projectId: projectId, name: "first", isSidebarHidden: true)
        let second = makeThread(projectId: projectId, name: "second", isSidebarHidden: true)
        let section = SidebarSection(
            projectId: projectId,
            sectionId: UUID(),
            name: "Work",
            color: .systemBlue,
            threads: [first, second],
            areHiddenThreadsExpanded: true
        )

        let renderedThreads = section.items.compactMap { $0 as? MagentThread }
        #expect(renderedThreads.map(\.id) == [first.id, second.id])
        #expect(section.items.first is SidebarHiddenThreadsToggle)
    }

    @Test
    func expandedHiddenGroupAddsNoSpacingBeforeDisclosure() {
        let projectId = UUID()
        let section = SidebarSection(
            projectId: projectId,
            sectionId: UUID(),
            name: "Work",
            color: .systemBlue,
            threads: [
                makeThread(projectId: projectId, name: "visible"),
                makeThread(projectId: projectId, name: "hidden", isSidebarHidden: true),
            ],
            areHiddenThreadsExpanded: true
        )

        #expect(section.items[0] is MagentThread)
        #expect(section.items[1] is SidebarHiddenThreadsToggle)
        #expect(section.items[2] is MagentThread)
        #expect(!section.items.contains { $0 is SidebarGroupSeparator })
    }

    @Test
    func collapsedHiddenGroupAddsNoSpacingBeforeDisclosureAndStandardSpacingAfterIt() {
        let projectId = UUID()
        let section = SidebarSection(
            projectId: projectId,
            sectionId: UUID(),
            name: "Work",
            color: .systemBlue,
            threads: [
                makeThread(projectId: projectId, name: "visible"),
                makeThread(projectId: projectId, name: "hidden", isSidebarHidden: true),
            ]
        )

        #expect(section.items[0] is MagentThread)
        #expect(section.items[1] is SidebarHiddenThreadsToggle)
        #expect((section.items[2] as? SidebarGroupSeparator)?.height == SidebarGroupSeparator.standardHeight)
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

    @Test
    func inlineRenameFocusRetriesWhileEditorIsNotMaterialized() {
        #expect(SidebarInlineRenameFocusPolicy.shouldRetry(editorIsAvailable: false, attempt: 0))
        #expect(SidebarInlineRenameFocusPolicy.shouldRetry(editorIsAvailable: false, attempt: 2))
    }

    @Test
    func inlineRenameFocusStopsWhenEditorExistsOrRetryLimitIsReached() {
        #expect(!SidebarInlineRenameFocusPolicy.shouldRetry(editorIsAvailable: true, attempt: 0))
        #expect(!SidebarInlineRenameFocusPolicy.shouldRetry(editorIsAvailable: false, attempt: 3))
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
