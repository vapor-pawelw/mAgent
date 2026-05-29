import Testing

@Suite
struct HomebrewUpdateScriptBuilderTests {

    @Test
    func upgradeFallbackSkipsReinstallWhenTargetVersionIsAlreadyInstalled() {
        #expect(!HomebrewUpgradeFallbackDecision.shouldReinstall(
            installedVersion: "1.2.3",
            targetVersion: "1.2.3"
        ))
    }

    @Test
    func upgradeFallbackReinstallsWhenTargetVersionIsNotInstalled() {
        #expect(HomebrewUpgradeFallbackDecision.shouldReinstall(
            installedVersion: "1.2.2",
            targetVersion: "1.2.3"
        ))
        #expect(HomebrewUpgradeFallbackDecision.shouldReinstall(
            installedVersion: nil,
            targetVersion: "1.2.3"
        ))
    }

    @Test
    func generatedScriptCarriesTargetVersionIntoFallbackCheck() {
        let script = HomebrewUpdateScriptBuilder.script(
            shouldRefreshTap: false,
            targetVersion: "1.2.3",
            messages: messages
        )

        #expect(script.contains(#"target_version='1.2.3'"#))
        #expect(script.contains(#"installed_version="$(installed_magent_version)""#))
        #expect(script.contains(#"if [[ "$installed_version" == "$target_version" ]]; then"#))
        #expect(script.contains("target version $target_version is already installed; skipping reinstall"))
        #expect(script.contains("brew reinstall --cask magent"))
    }

    @Test
    func refreshTapFlagControlsDetachedBrewUpdate() {
        let refreshScript = HomebrewUpdateScriptBuilder.script(
            shouldRefreshTap: true,
            targetVersion: "1.2.3",
            messages: messages
        )
        let skipScript = HomebrewUpdateScriptBuilder.script(
            shouldRefreshTap: false,
            targetVersion: "1.2.3",
            messages: messages
        )

        #expect(refreshScript.contains(#"should_refresh_tap="1""#))
        #expect(skipScript.contains(#"should_refresh_tap="0""#))
    }

    private var messages: HomebrewUpdateScriptMessages {
        HomebrewUpdateScriptMessages(
            waiting: "Waiting",
            refresh: "Refreshing",
            upgrade: "Upgrading",
            cleanup: "Cleaning",
            relaunch: "Relaunching"
        )
    }
}
