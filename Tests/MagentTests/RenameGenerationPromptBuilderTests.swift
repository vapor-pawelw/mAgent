import Testing

@Suite("AI rename options")
struct AIRenameOptionsTests {
    @Test("Hides icon rename when automatic work-type icons are disabled")
    func hidesIconRenameWhenDisabled() {
        #expect(AIRenameTarget.availableTargets(allowsIconRename: false) == [.description, .branch])
    }

    @Test("Shows icon rename when automatic work-type icons are enabled")
    func showsIconRenameWhenEnabled() {
        #expect(AIRenameTarget.availableTargets(allowsIconRename: true) == [.icon, .description, .branch])
    }

    @Test("Ignores a remembered icon selection while automatic icons are disabled")
    func ignoresRememberedIconSelectionWhenDisabled() {
        #expect(!AIRenameTarget.shouldRenameIcon(allowsIconRename: false, isSelected: true))
        #expect(AIRenameTarget.shouldRenameIcon(allowsIconRename: true, isSelected: true))
    }
}

@Suite("AI rename generation prompts")
struct RenameGenerationPromptBuilderTests {
    @Test("Separates cached payloads by icon-classification mode")
    func cacheKeySeparatesIconMode() {
        let withIcon = RenameGenerationPromptBuilder.cacheKey(
            for: "  Fix   the rename flow  ",
            includeIcon: true
        )
        let withoutIcon = RenameGenerationPromptBuilder.cacheKey(
            for: "fix the rename flow",
            includeIcon: false
        )

        #expect(withIcon == "with-icon:fix the rename flow")
        #expect(withoutIcon == "without-icon:fix the rename flow")
        #expect(withIcon != withoutIcon)
    }

    @Test("Combined rename omits icon classification when disabled")
    func combinedRenameWithoutIcon() {
        let prompt = RenameGenerationPromptBuilder.combinedRename(
            task: "Fix the rename flow",
            slugInstruction: "Generate a slug.",
            includeIcon: false
        )

        #expect(prompt.contains("SLUG: <slug>"))
        #expect(prompt.contains("DESC: <description>"))
        #expect(!prompt.contains("Icon types:"))
        #expect(!prompt.contains("TYPE:"))
        #expect(prompt.contains("exactly two lines"))
    }

    @Test("Combined rename requests icon classification when enabled")
    func combinedRenameWithIcon() {
        let prompt = RenameGenerationPromptBuilder.combinedRename(
            task: "Fix the rename flow",
            slugInstruction: "Generate a slug.",
            includeIcon: true
        )

        #expect(prompt.contains("Icon types:"))
        #expect(prompt.contains("TYPE: <feature|fix|improvement|refactor|test|other>"))
        #expect(prompt.contains("exactly three lines"))
    }

    @Test("Task description omits icon classification when disabled")
    func taskDescriptionWithoutIcon() {
        let prompt = RenameGenerationPromptBuilder.taskDescription(
            task: "Improve prompt generation",
            includeIcon: false
        )

        #expect(prompt.contains("DESC: <description>"))
        #expect(!prompt.contains("Icon types:"))
        #expect(!prompt.contains("TYPE:"))
        #expect(prompt.contains("exactly one line"))
    }

    @Test("Task description requests icon classification when enabled")
    func taskDescriptionWithIcon() {
        let prompt = RenameGenerationPromptBuilder.taskDescription(
            task: "Improve prompt generation",
            includeIcon: true
        )

        #expect(prompt.contains("Icon types:"))
        #expect(prompt.contains("TYPE: <feature|fix|improvement|refactor|test|other>"))
        #expect(prompt.contains("exactly two lines"))
    }
}
