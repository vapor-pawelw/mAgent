import Foundation

public enum TerminalSurfaceCachePressure: Sendable {
    case warning
    case critical
}

public enum TerminalSurfaceCachePolicy {
    public static func retainedCount(
        currentCount: Int,
        pressure: TerminalSurfaceCachePressure
    ) -> Int {
        guard currentCount > 0 else { return 0 }
        switch pressure {
        case .warning:
            return min(2, currentCount)
        case .critical:
            return 0
        }
    }
}
