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

    @Test("Typing a source thread branch restores the linked source")
    func matchingBaseBranchRestoresSourceLink() {
        let otherSource = ThreadCreationSourceDescriptor(
            threadID: UUID(),
            branchName: "feature/other",
            displayName: "Other source",
            isMainWorktree: false
        )
        var selection = ThreadCreationSourceSelection.branch("feature/custom")

        selection.updateBaseBranch(
            " feature/other ",
            defaultBranch: "main",
            availableSources: [source, otherSource]
        )

        #expect(selection == .thread(otherSource))
        #expect(selection.sourceThreadID == otherSource.threadID)
        #expect(selection.titleSourceName == "Other source")
    }

    @Test("Remote branch spelling matches a source while partial input stays custom")
    func sourceMatchingRequiresCompleteNormalizedBranch() {
        let remoteSource = ThreadCreationSourceDescriptor(
            threadID: UUID(),
            branchName: "origin/feature/source",
            displayName: "Remote source",
            isMainWorktree: false
        )
        var selection = ThreadCreationSourceSelection.branch("feature/custom")

        selection.updateBaseBranch(
            "feature/sour",
            defaultBranch: "main",
            availableSources: [remoteSource]
        )
        #expect(selection == .branch("feature/sour"))

        selection.updateBaseBranch(
            "feature/source",
            defaultBranch: "main",
            availableSources: [remoteSource]
        )
        #expect(selection == .thread(remoteSource))
    }

    @Test("Exact branch spelling disambiguates normalized source collisions")
    func exactBranchSpellingWinsNormalizedCollision() {
        let localSource = ThreadCreationSourceDescriptor(
            threadID: UUID(),
            branchName: "feature/source",
            displayName: "Local source",
            isMainWorktree: false
        )
        let remoteSource = ThreadCreationSourceDescriptor(
            threadID: UUID(),
            branchName: "origin/feature/source",
            displayName: "Remote source",
            isMainWorktree: false
        )
        var selection = ThreadCreationSourceSelection.thread(source)

        selection.updateBaseBranch(
            "origin/feature/source",
            defaultBranch: "main",
            availableSources: [localSource, remoteSource]
        )

        #expect(selection == .thread(remoteSource))
    }

    @Test("Ambiguous duplicate branch sources stay custom")
    func ambiguousDuplicateBranchStaysCustom() {
        let duplicate = ThreadCreationSourceDescriptor(
            threadID: UUID(),
            branchName: source.branchName,
            displayName: "Duplicate source",
            isMainWorktree: false
        )
        var selection = ThreadCreationSourceSelection.thread(source)

        selection.updateBaseBranch(
            source.branchName,
            defaultBranch: "main",
            availableSources: [source, duplicate]
        )

        #expect(selection == .branch(source.branchName))
        #expect(selection.sourceThreadID == nil)
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

    @Test("Picker reserves spacing only between contextual and remaining sources")
    func pickerContextualGroupSpacing() {
        let withoutSeparator = ThreadCreationSourcePickerLayout.contentHeight(
            optionCount: 4,
            hasContextualSeparator: false
        )
        let withSeparator = ThreadCreationSourcePickerLayout.contentHeight(
            optionCount: 4,
            hasContextualSeparator: true
        )

        #expect(ThreadCreationSourcePickerLayout.verticalInset == 10)
        #expect(ThreadCreationSourcePickerLayout.contextualGroupSpacing == 24)
        #expect(ThreadCreationSourcePickerLayout.contextualGroupSpacing <= 32)
        #expect(
            withSeparator - withoutSeparator
                == ThreadCreationSourcePickerLayout.contextualGroupSpacing
                    - ThreadCreationSourcePickerLayout.standardSpacing
        )
        #expect(ThreadCreationSourcePickerLayout.hasVisibleContextualSeparator(
            firstRemainingOptionIndex: 2,
            visibleOptionCount: 7
        ))
        #expect(!ThreadCreationSourcePickerLayout.hasVisibleContextualSeparator(
            firstRemainingOptionIndex: 7,
            visibleOptionCount: 7
        ))
    }

    @Test("Collapsed picker is single-line while expanded options keep their details")
    func pickerCapsuleModes() {
        let collapsed = ThreadCreationSourceCapsuleMode.collapsed
        let expanded = ThreadCreationSourceCapsuleMode.expanded(isSelected: true)

        #expect(!collapsed.showsExpandedDetails)
        #expect(!collapsed.isSelected)
        #expect(collapsed.rowHeight == 30)
        #expect(expanded.showsExpandedDetails)
        #expect(expanded.isSelected)
        #expect(expanded.rowHeight == ThreadCreationSourcePickerLayout.rowHeight)
    }
}
