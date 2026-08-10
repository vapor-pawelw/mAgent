import Foundation
import UserNotifications

struct AgentAttentionDeliveryPlan: Equatable {
    let presentsSystemBanner: Bool
    let appSoundName: String?

    init(showSystemBanners: Bool, playSound: Bool, soundName: String) {
        presentsSystemBanner = showSystemBanners
        appSoundName = playSound ? soundName : nil
    }

    func makeSystemNotificationContent(
        title: String,
        body: String,
        userInfo: [AnyHashable: Any]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = userInfo
        return content
    }
}
