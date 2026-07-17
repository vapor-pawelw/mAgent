import MagentCore
import Testing

@Suite
struct SidebarSettingsFingerprintTests {
    @Test
    func hidingThreadIconsRequiresSidebarRefresh() {
        let visibleIcons = AppSettings(showThreadIcons: true)
        let hiddenIcons = AppSettings(showThreadIcons: false)

        #expect(SidebarSettingsFingerprint(settings: visibleIcons) != SidebarSettingsFingerprint(settings: hiddenIcons))
    }

    @Test
    func showingWorktreeNamesRequiresSidebarRefresh() {
        let hiddenNames = AppSettings(showWorktreeNames: false)
        let visibleNames = AppSettings(showWorktreeNames: true)

        #expect(SidebarSettingsFingerprint(settings: hiddenNames) != SidebarSettingsFingerprint(settings: visibleNames))
    }

    @Test
    func changingActivityIndicatorStyleRequiresSidebarRefresh() {
        let circle = AppSettings(threadActivityIndicatorStyle: .circle)
        let text = AppSettings(threadActivityIndicatorStyle: .text)

        #expect(SidebarSettingsFingerprint(settings: circle) != SidebarSettingsFingerprint(settings: text))
    }

    @Test
    func changingPrimaryColorRequiresSidebarRefresh() {
        let pink = AppSettings(appPrimaryColorHex: "#D12D82")
        let blue = AppSettings(appPrimaryColorHex: "#007AFF")

        #expect(SidebarSettingsFingerprint(settings: pink) != SidebarSettingsFingerprint(settings: blue))
    }

    @Test
    func changingAllowedJiraPrefixesRequiresSidebarRefresh() {
        let ipOnly = AppSettings(jiraTicketDetectionPrefixes: "IP")
        let multiplePrefixes = AppSettings(jiraTicketDetectionPrefixes: "IP, APPL")

        #expect(SidebarSettingsFingerprint(settings: ipOnly) != SidebarSettingsFingerprint(settings: multiplePrefixes))
    }

    @Test
    func equivalentAllowedJiraPrefixesDoNotCauseAnotherSidebarRefresh() {
        var commaSeparated = AppSettings()
        commaSeparated.jiraTicketDetectionPrefixes = "IP, appl"
        var semicolonSeparated = commaSeparated
        semicolonSeparated.jiraTicketDetectionPrefixes = "APPL; IP"

        #expect(SidebarSettingsFingerprint(settings: commaSeparated) == SidebarSettingsFingerprint(settings: semicolonSeparated))
    }
}
