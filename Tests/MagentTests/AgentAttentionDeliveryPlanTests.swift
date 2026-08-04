import Testing

@Suite
struct AgentAttentionDeliveryPlanTests {
    @Test
    func bannerAndSoundUseOneAppOwnedSound() {
        let plan = AgentAttentionDeliveryPlan(
            showSystemBanners: true,
            playSound: true,
            soundName: "Ping"
        )
        let content = plan.makeSystemNotificationContent(
            title: "Agent finished",
            body: "Project · Thread",
            userInfo: ["sessionName": "session"]
        )

        #expect(plan.presentsSystemBanner)
        #expect(plan.appSoundName == "Ping")
        #expect(content.sound == nil)
        #expect(content.title == "Agent finished")
        #expect(content.body == "Project · Thread")
        #expect(content.userInfo["sessionName"] as? String == "session")
    }

    @Test
    func soundRemainsAvailableWithoutSystemBanners() {
        let plan = AgentAttentionDeliveryPlan(
            showSystemBanners: false,
            playSound: true,
            soundName: "Ping"
        )

        #expect(!plan.presentsSystemBanner)
        #expect(plan.appSoundName == "Ping")
    }

    @Test
    func disabledSoundKeepsBannerSilent() {
        let plan = AgentAttentionDeliveryPlan(
            showSystemBanners: true,
            playSound: false,
            soundName: "Ping"
        )

        #expect(plan.presentsSystemBanner)
        #expect(plan.appSoundName == nil)
    }
}
