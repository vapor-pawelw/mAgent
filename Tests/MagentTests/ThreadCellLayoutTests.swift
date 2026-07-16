import Testing

@Suite("Thread cell layout")
struct ThreadCellLayoutTests {
    @Test("Text and status rows use bottom-anchored vertical spacing")
    func verticalContentSpacing() {
        #expect(ThreadRowBadgeLayout.topContentPadding == 8)
        #expect(ThreadRowBadgeLayout.titleToSubtitleSpacing == 3)
        #expect(ThreadRowBadgeLayout.textToStatusRowSpacing == 8)
        #expect(ThreadRowBadgeLayout.bottomContentPadding == 8)
        #expect(ThreadRowBadgeLayout.statusRowHeight == 13)
    }

    @Test("Main worktree branch always reserves a subtitle row")
    func mainWorktreeSubtitle() {
        #expect(ThreadRowBadgeLayout.subtitleText(
            hasDescription: false,
            branchName: "develop",
            worktreeName: "magent",
            showWorktreeName: false,
            isMainWorktree: true
        ) == "develop")
    }

    @Test("Main worktree keeps its home icon inline after the title when leading icons are hidden")
    func mainWorktreeIconPlacement() {
        #expect(ThreadRowBadgeLayout.mainWorktreeIconPlacement(showThreadIcons: true) == .leading)
        #expect(ThreadRowBadgeLayout.mainWorktreeIconPlacement(showThreadIcons: false) == .inlineAfterTitle)
    }

    @Test("Inline Main worktree icon uses compact title-sized metrics")
    func mainWorktreeInlineIconMetrics() {
        #expect(ThreadRowBadgeLayout.inlineMainWorktreeIconSize == 11)
    }

    @Test("Thread signs prefix primary text with one space")
    func signPrefix() {
        #expect(ThreadRowBadgeLayout.primaryText("Fix sidebar layout", signEmoji: "⚠️") == "⚠️ Fix sidebar layout")
        #expect(ThreadRowBadgeLayout.primaryText("feature/sidebar", signEmoji: "✅") == "✅ feature/sidebar")
        #expect(ThreadRowBadgeLayout.primaryText("Fix sidebar layout", signEmoji: nil) == "Fix sidebar layout")
    }

    @Test("Archive marker centers on text rows instead of the status row")
    func archiveMarkerTextCentering() {
        #expect(ThreadRowBadgeLayout.trailingMarkerVerticalAnchor == .textRows)
    }

    @Test("Pinned and favorite icons are optically smaller than hidden")
    func leadingStatusIconSizes() {
        #expect(ThreadRowBadgeLayout.compactLeadingStatusIconSize == 11)
        #expect(ThreadRowBadgeLayout.standardStatusIconSize == 13)
    }

    @Test("Compact status labels share a readable font size")
    func compactStatusLabelFontSize() {
        #expect(ThreadRowBadgeLayout.compactTextFontSize == 9)
    }

    @Test("Worktree names are omitted from subtitles by default")
    func hiddenWorktreeNameSubtitle() {
        #expect(ThreadRowBadgeLayout.subtitleText(
            hasDescription: true,
            branchName: "feature/settings",
            worktreeName: "magent-worktrees-blue-sky",
            showWorktreeName: false
        ) == "feature/settings")
        #expect(ThreadRowBadgeLayout.subtitleText(
            hasDescription: false,
            branchName: "feature/settings",
            worktreeName: "magent-worktrees-blue-sky",
            showWorktreeName: false
        ) == nil)
    }

    @Test("Enabled worktree names appear on the second line")
    func visibleWorktreeNameSubtitle() {
        #expect(ThreadRowBadgeLayout.subtitleText(
            hasDescription: true,
            branchName: "feature/settings",
            worktreeName: "magent-worktrees-blue-sky",
            showWorktreeName: true
        ) == "feature/settings  ·  magent-worktrees-blue-sky")
        #expect(ThreadRowBadgeLayout.subtitleText(
            hasDescription: false,
            branchName: "feature/settings",
            worktreeName: "magent-worktrees-blue-sky",
            showWorktreeName: true
        ) == "magent-worktrees-blue-sky")
    }
}
