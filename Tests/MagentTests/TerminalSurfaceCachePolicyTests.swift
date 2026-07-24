import MagentCore
import Testing

@Suite
struct TerminalSurfaceCachePolicyTests {
    @Test(arguments: [
        (0, 0),
        (1, 1),
        (2, 2),
        (3, 2),
        (8, 2),
    ])
    func warningRetainsAtMostTwoMostRecentSurfaces(current: Int, expected: Int) {
        #expect(TerminalSurfaceCachePolicy.retainedCount(
            currentCount: current,
            pressure: .warning
        ) == expected)
    }

    @Test(arguments: [0, 1, 8])
    func criticalPressureReleasesEveryCachedSurface(current: Int) {
        #expect(TerminalSurfaceCachePolicy.retainedCount(
            currentCount: current,
            pressure: .critical
        ) == 0)
    }
}
