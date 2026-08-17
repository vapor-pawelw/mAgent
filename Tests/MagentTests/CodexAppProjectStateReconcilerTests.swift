import Foundation
import MagentCore
import Testing

@Suite("Codex App project state reconciliation")
struct CodexAppProjectStateReconcilerTests {
    @Test("Adds Magent projects without disturbing Codex project order or unknown state")
    func addsProjectsAndPreservesState() throws {
        let original: [String: Any] = [
            "electron-saved-workspace-roots": ["/repos/existing"],
            "project-order": ["/repos/existing"],
            "unrelated-setting": ["enabled": true],
        ]

        let result = CodexAppProjectStateReconciler.reconcile(
            state: original,
            magentProjectPaths: ["/repos/new", "/repos/existing/../existing"],
            assignments: []
        )

        #expect(result.state["electron-saved-workspace-roots"] as? [String] == [
            "/repos/existing",
            "/repos/new",
        ])
        #expect(result.state["project-order"] as? [String] == [
            "/repos/existing",
            "/repos/new",
        ])
        #expect((result.state["unrelated-setting"] as? [String: Bool])?["enabled"] == true)
        #expect(result.importedRepositoryPaths.isEmpty)
        #expect(result.didChange)
    }

    @Test("Assigns Codex threads to their main repository and removes them from General")
    func assignsThreadsToProjects() throws {
        let original: [String: Any] = [
            "electron-saved-workspace-roots": ["/repos/magent"],
            "project-order": ["/repos/magent"],
            "thread-workspace-root-hints": ["other-thread": "/repos/other"],
            "projectless-thread-ids": ["codex-thread", "other-thread"],
        ]

        let result = CodexAppProjectStateReconciler.reconcile(
            state: original,
            magentProjectPaths: ["/repos/magent"],
            assignments: [
                CodexAppThreadProjectAssignment(
                    threadID: "codex-thread",
                    projectPath: "/repos/magent-worktrees/../magent"
                ),
            ]
        )

        let hints = try #require(result.state["thread-workspace-root-hints"] as? [String: String])
        #expect(hints == [
            "codex-thread": "/repos/magent",
            "other-thread": "/repos/other",
        ])
        #expect(result.state["projectless-thread-ids"] as? [String] == ["other-thread"])
    }

    @Test("Returns Codex repositories that Magent has not registered")
    func findsProjectsForImport() {
        let original: [String: Any] = [
            "electron-saved-workspace-roots": [
                "/repos/magent",
                "/repos/import-me",
                "/repos/import-me/.",
            ],
        ]

        let result = CodexAppProjectStateReconciler.reconcile(
            state: original,
            magentProjectPaths: ["/repos/magent"],
            assignments: []
        )

        #expect(result.importedRepositoryPaths == ["/repos/import-me"])
    }

    @Test("Preserves existing Codex entries byte-for-byte while comparing normalized paths")
    func preservesExistingPathEntries() {
        let originalRoots = ["relative-project", "/repos/magent/../magent", ""]
        let original: [String: Any] = [
            "electron-saved-workspace-roots": originalRoots,
            "project-order": ["relative-project"],
        ]

        let result = CodexAppProjectStateReconciler.reconcile(
            state: original,
            magentProjectPaths: ["/repos/magent", "/repos/new"],
            assignments: []
        )

        #expect(result.state["electron-saved-workspace-roots"] as? [String] == originalRoots + ["/repos/new"])
        #expect(result.state["project-order"] as? [String] == [
            "relative-project",
            "/repos/magent",
            "/repos/new",
        ])
    }

    @Test("A reconciled state is stable on the next pass")
    func isIdempotent() {
        let original: [String: Any] = [
            "electron-saved-workspace-roots": ["/repos/magent"],
            "project-order": ["/repos/magent"],
            "thread-workspace-root-hints": ["codex-thread": "/repos/magent"],
            "projectless-thread-ids": ["other-thread"],
        ]
        let assignment = CodexAppThreadProjectAssignment(
            threadID: "codex-thread",
            projectPath: "/repos/magent"
        )

        let result = CodexAppProjectStateReconciler.reconcile(
            state: original,
            magentProjectPaths: ["/repos/magent"],
            assignments: [assignment]
        )

        #expect(!result.didChange)
    }

    @Test("Rejects a changed Codex project-state schema instead of overwriting it")
    func rejectsUnknownStateShape() {
        let state: [String: Any] = [
            "electron-saved-workspace-roots": [["path": "/repos/magent"]],
        ]

        #expect(!CodexAppProjectStateReconciler.hasSupportedShape(state))
    }

    @Test("Writes the merged Codex state while preserving unrelated values")
    func writesMergedState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-project-sync-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        let original: [String: Any] = [
            "electron-saved-workspace-roots": ["/repos/existing"],
            "project-order": ["/repos/existing"],
            "unrelated-setting": "keep-me",
        ]
        try JSONSerialization.data(withJSONObject: original).write(to: stateURL)
        let service = CodexAppProjectSyncService(stateFileURL: stateURL)

        let importedPaths = try service.synchronize(
            projects: [
                Project(
                    name: "Magent",
                    repoPath: "/repos/magent",
                    worktreesBasePath: "/worktrees/magent"
                ),
            ],
            assignments: [
                CodexAppThreadProjectAssignment(threadID: "thread-id", projectPath: "/repos/magent"),
            ]
        )

        let writtenData = try Data(contentsOf: stateURL)
        let written = try #require(JSONSerialization.jsonObject(with: writtenData) as? [String: Any])
        #expect(written["electron-saved-workspace-roots"] as? [String] == [
            "/repos/existing",
            "/repos/magent",
        ])
        #expect((written["thread-workspace-root-hints"] as? [String: String])?["thread-id"] == "/repos/magent")
        #expect(written["unrelated-setting"] as? String == "keep-me")
        #expect(importedPaths == ["/repos/existing"])
    }
}
