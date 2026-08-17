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

@Suite("Magent project repository deduplication")
struct MagentProjectDeduplicatorTests {
    @Test("Projects for the same Git repository collapse without losing project configuration")
    func collapsesRepositoryAliases() throws {
        let canonicalID = UUID()
        let duplicateID = UUID()
        let unrelatedID = UUID()
        let canonical = Project(
            id: canonicalID,
            name: "Canonical",
            repoPath: "/repos/repo-link",
            worktreesBasePath: "/custom/worktrees",
            localFileSyncEntries: [LocalFileSyncEntry(path: ".env")]
        )
        let duplicate = Project(
            id: duplicateID,
            name: "Duplicate",
            repoPath: "/repos/repo-worktree",
            worktreesBasePath: "/other/worktrees",
            isPinned: true,
            localFileSyncEntries: [LocalFileSyncEntry(path: "Config/local.json")]
        )
        let unrelated = Project(
            id: unrelatedID,
            name: "Unrelated",
            repoPath: "/repos/unrelated",
            worktreesBasePath: "/repos/unrelated-worktrees"
        )

        let plan = MagentProjectDeduplicator.plan(
            projects: [canonical, duplicate, unrelated],
            resolutions: [
                MagentProjectRepositoryResolution(
                    projectID: canonicalID,
                    repositoryIdentity: "/repos/repo/.git",
                    canonicalProjectPath: "/repos/repo"
                ),
                MagentProjectRepositoryResolution(
                    projectID: duplicateID,
                    repositoryIdentity: "/repos/repo/.git",
                    canonicalProjectPath: "/repos/repo"
                ),
            ]
        )

        #expect(plan.projects.map(\.id) == [canonicalID, unrelatedID])
        #expect(plan.projectIDReplacements == [duplicateID: canonicalID])
        let merged = try #require(plan.projects.first)
        #expect(merged.repoPath == "/repos/repo")
        #expect(merged.worktreesBasePath == "/custom/worktrees")
        #expect(merged.isPinned)
        #expect(Set(merged.localFileSyncEntries.map(\.path)) == [".env", "Config/local.json"])
    }

    @Test("Different subprojects in one repository remain separate")
    func preservesDistinctSubprojects() {
        let frontendID = UUID()
        let backendID = UUID()
        let frontend = Project(
            id: frontendID,
            name: "Frontend",
            repoPath: "/repos/monorepo/frontend",
            worktreesBasePath: "/worktrees/frontend"
        )
        let backend = Project(
            id: backendID,
            name: "Backend",
            repoPath: "/repos/monorepo/backend",
            worktreesBasePath: "/worktrees/backend"
        )

        let plan = MagentProjectDeduplicator.plan(
            projects: [frontend, backend],
            resolutions: [
                MagentProjectRepositoryResolution(
                    projectID: frontendID,
                    repositoryIdentity: "/repos/monorepo/.git\u{0}frontend",
                    canonicalProjectPath: "/repos/monorepo/frontend"
                ),
                MagentProjectRepositoryResolution(
                    projectID: backendID,
                    repositoryIdentity: "/repos/monorepo/.git\u{0}backend",
                    canonicalProjectPath: "/repos/monorepo/backend"
                ),
            ]
        )

        #expect(plan.projects.map(\.id) == [frontendID, backendID])
        #expect(plan.projectIDReplacements.isEmpty)
    }

    @Test("A lone linked-worktree project keeps its configured checkout")
    func preservesIntentionalLinkedWorktreeProjectPath() throws {
        let projectID = UUID()
        let project = Project(
            id: projectID,
            name: "Feature checkout",
            repoPath: "/worktrees/feature",
            worktreesBasePath: "/worktrees"
        )

        let plan = MagentProjectDeduplicator.plan(
            projects: [project],
            resolutions: [
                MagentProjectRepositoryResolution(
                    projectID: projectID,
                    repositoryIdentity: "/repos/repo/.git",
                    canonicalProjectPath: "/repos/repo"
                ),
            ]
        )

        #expect(try #require(plan.projects.first).repoPath == project.repoPath)
        #expect(plan.canonicalProjectPathsByProjectID[projectID] == project.repoPath)
    }

    @Test("Retargeting a thread preserves all persisted state")
    func retargetingPreservesAllPersistedState() throws {
        let originalProjectID = UUID()
        let replacementProjectID = UUID()
        var thread = MagentThread(
            projectId: originalProjectID,
            name: "Thread",
            worktreePath: "/repos/repo-worktrees/thread",
            branchName: "feature/thread",
            tmuxSessionNames: ["session"],
            agentTmuxSessions: ["session"],
            customTabNames: ["session": "My model"],
            manuallyRenamedTabs: ["session"]
        )
        thread.busySessions = ["session"]
        let originalData = try JSONEncoder().encode(thread)

        let retargeted = thread.withProjectId(replacementProjectID)
        let retargetedData = try JSONEncoder().encode(retargeted)
        var originalJSON = try #require(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        var retargetedJSON = try #require(JSONSerialization.jsonObject(with: retargetedData) as? [String: Any])
        originalJSON.removeValue(forKey: "projectId")
        retargetedJSON.removeValue(forKey: "projectId")

        #expect(retargeted.projectId == replacementProjectID)
        #expect(NSDictionary(dictionary: originalJSON).isEqual(to: retargetedJSON))
        #expect(retargeted.busySessions == ["session"])
    }

    @Test("A migrated main thread follows the surviving project's canonical path")
    func migratesMainThreadPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-project-thread-migration-\(UUID().uuidString)")
        let canonicalPath = root.appendingPathComponent("repo")
        let aliasPath = root.appendingPathComponent("repo-alias")
        try FileManager.default.createDirectory(at: canonicalPath, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasPath, withDestinationURL: canonicalPath)
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalID = UUID()
        let duplicateID = UUID()
        let canonical = Project(
            id: canonicalID,
            name: "Canonical",
            repoPath: canonicalPath.path,
            worktreesBasePath: "/worktrees/repo"
        )
        let duplicate = Project(
            id: duplicateID,
            name: "Alias",
            repoPath: aliasPath.path,
            worktreesBasePath: "/worktrees/alias"
        )
        let plan = MagentProjectDeduplicator.plan(
            projects: [canonical, duplicate],
            resolutions: [
                MagentProjectRepositoryResolution(
                    projectID: canonicalID,
                    repositoryIdentity: "/repos/repo/.git",
                    canonicalProjectPath: canonicalPath.path
                ),
                MagentProjectRepositoryResolution(
                    projectID: duplicateID,
                    repositoryIdentity: "/repos/repo/.git",
                    canonicalProjectPath: canonicalPath.path
                ),
            ]
        )
        let thread = MagentThread(
            projectId: duplicateID,
            name: "main",
            worktreePath: duplicate.repoPath,
            branchName: "main",
            isMain: true
        )

        let migrated = MagentProjectThreadMigrator.migrate(
            thread,
            projectsByID: [canonicalID: canonical, duplicateID: duplicate],
            plan: plan
        )

        #expect(migrated.projectId == canonicalID)
        #expect(migrated.worktreePath == canonical.repoPath)
        #expect(migrated.isMain)
    }

    @Test("A second bare-backed checkout becomes a regular thread instead of a second main")
    func demotesDistinctBareBackedMainThread() {
        let canonicalID = UUID()
        let duplicateID = UUID()
        let canonical = Project(
            id: canonicalID,
            name: "First",
            repoPath: "/worktrees/first",
            worktreesBasePath: "/worktrees"
        )
        let duplicate = Project(
            id: duplicateID,
            name: "Second",
            repoPath: "/worktrees/second",
            worktreesBasePath: "/worktrees"
        )
        let plan = MagentProjectDeduplicator.plan(
            projects: [canonical, duplicate],
            resolutions: [
                MagentProjectRepositoryResolution(
                    projectID: canonicalID,
                    repositoryIdentity: "/repos/bare.git",
                    canonicalProjectPath: canonical.repoPath
                ),
                MagentProjectRepositoryResolution(
                    projectID: duplicateID,
                    repositoryIdentity: "/repos/bare.git",
                    canonicalProjectPath: duplicate.repoPath
                ),
            ]
        )
        let thread = MagentThread(
            projectId: duplicateID,
            name: "main",
            worktreePath: duplicate.repoPath,
            branchName: "feature/second",
            isMain: true
        )

        let migrated = MagentProjectThreadMigrator.migrate(
            thread,
            projectsByID: [canonicalID: canonical, duplicateID: duplicate],
            plan: plan
        )

        #expect(migrated.projectId == canonicalID)
        #expect(migrated.worktreePath == duplicate.repoPath)
        #expect(!migrated.isMain)
    }
}
