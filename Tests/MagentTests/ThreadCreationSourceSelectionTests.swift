import Foundation
import Testing

@Suite
struct ThreadCreationSourceSelectionTests {
    private let source = ThreadCreationSourceDescriptor(
        threadID: UUID(),
        branchName: "feature/source",
        displayName: "Improve thread creation",
        isMainWorktree: false
    )

    @Test("Selecting a thread links its base branch and source identity")
    func selectingThreadLinksSource() {
        let selection = ThreadCreationSourceSelection.thread(source)

        #expect(selection.sourceThreadID == source.threadID)
        #expect(selection.baseBranch == "feature/source")
        #expect(selection.titleSourceName == "Improve thread creation")
        #expect(!selection.isCustomBranch)
    }

    @Test("Editing the base branch breaks source-thread inheritance")
    func customBaseBranchBreaksSourceLink() {
        var selection = ThreadCreationSourceSelection.thread(source)

        selection.updateBaseBranch("release/2.0", defaultBranch: "main")

        #expect(selection.sourceThreadID == nil)
        #expect(selection.baseBranch == "release/2.0")
        #expect(selection.isCustomBranch)
    }

    @Test("Equivalent remote branch spelling keeps the source linked")
    func equivalentRemoteBranchKeepsSourceLink() {
        let remoteSource = ThreadCreationSourceDescriptor(
            threadID: UUID(),
            branchName: "origin/feature/source",
            displayName: "Source",
            isMainWorktree: false
        )
        var selection = ThreadCreationSourceSelection.thread(remoteSource)

        selection.updateBaseBranch("feature/source", defaultBranch: "main")

        #expect(selection.sourceThreadID == remoteSource.threadID)
        #expect(!selection.isCustomBranch)
    }

    @Test("Clearing the base branch selects the project default as a custom branch")
    func emptyBaseBranchUsesDefault() {
        var selection = ThreadCreationSourceSelection.thread(source)

        selection.updateBaseBranch("", defaultBranch: "main")

        #expect(selection == .branch("main"))
    }

    @Test("Main worktree is a visual source without fork inheritance")
    func mainWorktreeActsAsDefaultSource() {
        let main = ThreadCreationSourceDescriptor(
            threadID: UUID(),
            branchName: "main",
            displayName: "Main worktree",
            isMainWorktree: true
        )
        let selection = ThreadCreationSourceSelection.thread(main)

        #expect(selection.sourceThreadID == nil)
        #expect(selection.baseBranch == "main")
        #expect(selection.titleSourceName == "Main worktree")
    }

    @Test("Picker scroll centers a selected row and clamps at both ends")
    func pickerScrollCentering() {
        #expect(ThreadCreationSourcePickerScrollGeometry.centeredOrigin(
            itemMidY: 240,
            viewportHeight: 200,
            contentHeight: 600
        ) == 140)
        #expect(ThreadCreationSourcePickerScrollGeometry.centeredOrigin(
            itemMidY: 30,
            viewportHeight: 200,
            contentHeight: 600
        ) == 0)
        #expect(ThreadCreationSourcePickerScrollGeometry.centeredOrigin(
            itemMidY: 580,
            viewportHeight: 200,
            contentHeight: 600
        ) == 400)
    }
}
