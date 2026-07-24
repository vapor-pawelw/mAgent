import Foundation

@MainActor
final class SerialAsyncOperationGate {
    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withExclusiveAccess<Result>(
        _ operation: () async throws -> Result
    ) async rethrows -> Result {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        guard isOccupied else {
            isOccupied = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        guard !waiters.isEmpty else {
            isOccupied = false
            return
        }

        waiters.removeFirst().resume()
    }
}
