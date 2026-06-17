import Foundation
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

    @Test
    func statusSyncCadenceIsFiveMinutes() {
        #expect(SessionMonitorRefreshCadence.statusSyncIntervalSeconds == 5 * 60)
    }

    @Test
    func jiraTicketRefreshReasonsThatRepresentExternalSignalsBypassCache() {
        #expect(JiraTicketRefreshReason.appLaunch.bypassesCache)
        #expect(JiraTicketRefreshReason.displayedStatusSync.bypassesCache)
        #expect(JiraTicketRefreshReason.agentCompletion.bypassesCache)
        #expect(JiraTicketRefreshReason.manual.bypassesCache)
        #expect(!JiraTicketRefreshReason.detectedTicketChange.bypassesCache)
        #expect(!JiraTicketRefreshReason.settingsEnabled.bypassesCache)
    }

    @Test
    func jiraTicketRefreshPolicyVerifiesMissingOrStaleCacheEntries() {
        let now = Date(timeIntervalSince1970: 1_000)
        let fresh = now.addingTimeInterval(-60)
        let stale = now.addingTimeInterval(-(JiraTicketRefreshPolicy.displayedTicketCacheTTL + 1))

        #expect(JiraTicketRefreshPolicy.needsVerification(
            cachedVerifiedAt: nil,
            now: now,
            reason: .detectedTicketChange
        ))
        #expect(!JiraTicketRefreshPolicy.needsVerification(
            cachedVerifiedAt: fresh,
            now: now,
            reason: .detectedTicketChange
        ))
        #expect(JiraTicketRefreshPolicy.needsVerification(
            cachedVerifiedAt: stale,
            now: now,
            reason: .detectedTicketChange
        ))
    }

    @Test
    func jiraTicketRefreshPolicyBypassesFreshCacheForPeriodicSyncAndAgentCompletion() {
        let now = Date(timeIntervalSince1970: 1_000)
        let fresh = now.addingTimeInterval(-60)

        #expect(JiraTicketRefreshPolicy.needsVerification(
            cachedVerifiedAt: fresh,
            now: now,
            reason: .displayedStatusSync
        ))
        #expect(JiraTicketRefreshPolicy.needsVerification(
            cachedVerifiedAt: fresh,
            now: now,
            reason: .agentCompletion
        ))
        #expect(JiraTicketRefreshPolicy.needsVerification(
            cachedVerifiedAt: fresh,
            now: now,
            reason: .manual
        ))
    }
}
