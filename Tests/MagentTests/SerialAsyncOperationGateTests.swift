import Foundation
import Testing

@Suite
@MainActor
struct SerialAsyncOperationGateTests {

    @Test
    func exclusiveOperationsNeverOverlap() async {
        let gate = SerialAsyncOperationGate()
        var activeOperationCount = 0
        var maximumActiveOperationCount = 0
        var completedOperationCount = 0

        let tasks = (0..<6).map { _ in
            Task { @MainActor in
                await gate.withExclusiveAccess {
                    activeOperationCount += 1
                    maximumActiveOperationCount = max(maximumActiveOperationCount, activeOperationCount)
                    try? await Task.sleep(for: .milliseconds(20))
                    activeOperationCount -= 1
                    completedOperationCount += 1
                }
            }
        }

        for task in tasks {
            await task.value
        }

        #expect(maximumActiveOperationCount == 1)
        #expect(completedOperationCount == 6)
    }
}
