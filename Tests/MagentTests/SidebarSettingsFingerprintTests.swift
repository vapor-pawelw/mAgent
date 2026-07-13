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
}
