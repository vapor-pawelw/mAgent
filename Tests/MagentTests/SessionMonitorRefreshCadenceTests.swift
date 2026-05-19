import Testing
import MagentCore

@Suite
struct SessionMonitorRefreshCadenceTests {

    @Test
    func resetGitStateCounterRestartsPeriodicCadence() {
        var counter = SessionMonitorRefreshCadence.gitStateIntervalTicks - 1

        SessionMonitorRefreshCadence.resetGitStateCounter(&counter)

        #expect(counter == 0)
    }

    @Test
    func resetStatusSyncCountersRestartsPeriodicCadence() {
        var prCounter = SessionMonitorRefreshCadence.statusSyncIntervalTicks - 1
        var jiraCounter = SessionMonitorRefreshCadence.statusSyncIntervalTicks - 1

        SessionMonitorRefreshCadence.resetStatusSyncCounters(
            prCounter: &prCounter,
            jiraCounter: &jiraCounter
        )

        #expect(prCounter == 0)
        #expect(jiraCounter == 0)
    }
}
