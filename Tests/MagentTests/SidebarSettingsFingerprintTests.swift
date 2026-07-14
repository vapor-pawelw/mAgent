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
    func changingActivityIndicatorStyleRequiresSidebarRefresh() {
        let circle = AppSettings(threadActivityIndicatorStyle: .circle)
        let text = AppSettings(threadActivityIndicatorStyle: .text)

        #expect(SidebarSettingsFingerprint(settings: circle) != SidebarSettingsFingerprint(settings: text))
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
