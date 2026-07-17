import Foundation
import MagentCore
import Testing

@Suite("Thread tab session rename detection")
struct ThreadTabSessionRenameDetectionTests {
    @Test("Recognizes a manual tab rename as an in-place update")
    func recognizesManualRename() {
        let oldName = "ma-repo-thread-codex"
        let newName = "ma-repo-thread-fix-tabs"
        let previous = makeThread(sessions: [oldName], pinnedSessions: [oldName])
        var updated = previous
        updated.tmuxSessionNames = [newName]
        updated.pinnedTmuxSessions = [newName]
        updated.sessionCreatedAts[newName] = updated.sessionCreatedAts.removeValue(forKey: oldName)
        updated.customTabNames[newName] = "Fix Tabs"
        updated.manuallyRenamedTabs.insert(newName)

        #expect(ThreadTabStructureFingerprint.isTabSessionRename(from: previous, to: updated))
    }

    @Test("Does not treat terminal tab reordering as a rename")
    func rejectsReordering() {
        let previous = makeThread(sessions: ["one", "two"])
        var updated = previous
        updated.tmuxSessionNames = ["two", "one"]
        updated.customTabNames["two"] = "Two"
        updated.customTabNames["one"] = "One"
        updated.manuallyRenamedTabs = ["one", "two"]

        #expect(!ThreadTabStructureFingerprint.isTabSessionRename(from: previous, to: updated))
    }

    @Test("Does not treat adding a terminal tab as a rename")
    func rejectsAddition() {
        let previous = makeThread(sessions: ["one"])
        var updated = previous
        updated.tmuxSessionNames.append("two")
        updated.customTabNames["two"] = "Two"
        updated.manuallyRenamedTabs.insert("two")

        #expect(!ThreadTabStructureFingerprint.isTabSessionRename(from: previous, to: updated))
    }

    @Test("Does not hide a pinning change inside a rename")
    func rejectsPinningChange() {
        let previous = makeThread(sessions: ["old"])
        var updated = previous
        updated.tmuxSessionNames = ["new"]
        updated.pinnedTmuxSessions = ["new"]
        updated.sessionCreatedAts["new"] = updated.sessionCreatedAts.removeValue(forKey: "old")
        updated.customTabNames["new"] = "New"
        updated.manuallyRenamedTabs.insert("new")

        #expect(!ThreadTabStructureFingerprint.isTabSessionRename(from: previous, to: updated))
    }

    @Test("Does not treat replacing a tab with a new session as a rename")
    func rejectsReplacement() {
        let previous = makeThread(sessions: ["old"])
        var updated = previous
        updated.tmuxSessionNames = ["new"]
        updated.sessionCreatedAts["new"] = Date(timeIntervalSince1970: 2)
        updated.customTabNames["new"] = "New"
        updated.manuallyRenamedTabs.insert("new")

        #expect(!ThreadTabStructureFingerprint.isTabSessionRename(from: previous, to: updated))
    }

    private func makeThread(sessions: [String], pinnedSessions: [String] = []) -> MagentThread {
        var thread = MagentThread(
            projectId: UUID(),
            name: "thread",
            worktreePath: "/tmp/thread",
            branchName: "thread",
            tmuxSessionNames: sessions,
            pinnedTmuxSessions: pinnedSessions
        )
        for (index, session) in sessions.enumerated() {
            thread.sessionCreatedAts[session] = Date(timeIntervalSince1970: TimeInterval(index + 1))
        }
        return thread
    }
}
