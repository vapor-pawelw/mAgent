import Foundation
import MagentCore
import os
import Testing

@Suite("Initial thread descriptions")
struct InitialThreadDescriptionTests {
    @Test("An explicit description remains authoritative")
    func explicitDescriptionWinsOverPrompt() {
        let result = InitialThreadDescription.resolve(
            explicitDescription: "  User description  ",
            prompt: "Prompt that should not be displayed",
            fallback: "Thread #7"
        )

        #expect(result == InitialThreadDescription(text: "User description", isProvisional: false))
    }

    @Test("A prompt becomes a single-line provisional description")
    func promptBecomesProvisionalDescription() {
        let result = InitialThreadDescription.resolve(
            explicitDescription: nil,
            prompt: "  Improve the sidebar\n\nwithout flashing\tworktree names  ",
            fallback: "Thread #7"
        )

        #expect(result.text == "Improve the sidebar without flashing worktree names")
        #expect(result.isProvisional)
    }

    @Test("Long prompt previews truncate at a word boundary")
    func longPromptTruncatesAtWordBoundary() {
        let prompt = Array(repeating: "description", count: 30).joined(separator: " ")

        let preview = InitialThreadDescription.promptPreview(prompt)

        #expect(preview.count <= InitialThreadDescription.promptPreviewMaximumLength)
        #expect(preview.hasSuffix("…"))
        #expect(preview.dropLast().split(separator: " ").last == "description")
    }

    @Test("A promptless thread receives a provisional numbered fallback")
    func emptyPromptUsesFallback() {
        let result = InitialThreadDescription.resolve(
            explicitDescription: nil,
            prompt: " \n ",
            fallback: "Thread #12"
        )

        #expect(result == InitialThreadDescription(text: "Thread #12", isProvisional: true))
    }

    @Test("Only absent or provisional descriptions allow automatic replacement")
    func automaticReplacementEligibility() {
        var thread = MagentThread(
            projectId: UUID(),
            name: "persian",
            worktreePath: "/tmp/persian",
            branchName: "persian"
        )
        #expect(thread.canReplaceTaskDescriptionAutomatically)

        thread.taskDescription = "Initial prompt preview"
        thread.taskDescriptionIsProvisional = true
        #expect(thread.canReplaceTaskDescriptionAutomatically)

        thread.taskDescriptionIsProvisional = false
        #expect(!thread.canReplaceTaskDescriptionAutomatically)
    }

    @Test("Provisional provenance survives persistence and defaults off for old data")
    func provisionalPersistence() throws {
        let original = MagentThread(
            projectId: UUID(),
            name: "persian",
            worktreePath: "/tmp/persian",
            branchName: "persian",
            taskDescription: "Initial prompt preview",
            taskDescriptionIsProvisional: true,
            threadDisplayNumber: 12
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MagentThread.self, from: encoded)
        #expect(decoded.taskDescriptionIsProvisional)
        #expect(decoded.threadDisplayNumber == 12)

        var oldPayload = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        oldPayload.removeValue(forKey: "taskDescriptionIsProvisional")
        let oldData = try JSONSerialization.data(withJSONObject: oldPayload)
        let oldDecoded = try JSONDecoder().decode(MagentThread.self, from: oldData)
        #expect(!oldDecoded.taskDescriptionIsProvisional)
    }

    @Test("Display numbers seed from existing threads and reserve concurrent allocations")
    func displayNumberAllocation() {
        let projectId = UUID()
        let allocator = ThreadDisplayNumberAllocator()
        let allocatedNumbers = OSAllocatedUnfairLock(initialState: [Int]())

        DispatchQueue.concurrentPerform(iterations: 50) { _ in
            let number = allocator.allocate(projectId: projectId, existingNumbers: [3, 12, 8])
            allocatedNumbers.withLock { $0.append(number) }
        }

        let numbers = allocatedNumbers.withLock { $0.sorted() }
        #expect(numbers == Array(13...62))
        #expect(allocator.allocate(projectId: UUID(), existingNumbers: []) == 1)
    }
}
