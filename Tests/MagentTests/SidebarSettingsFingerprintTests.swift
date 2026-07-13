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
}
