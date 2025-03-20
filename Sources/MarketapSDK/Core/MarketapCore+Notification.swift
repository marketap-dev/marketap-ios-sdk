//
//  MarketapCore+Notification.swift
//  MarketapSDK
//
//  Created by 이동현 on 3/20/25.
//

import UserNotifications
import UIKit

extension MarketapCore {
    struct MarketapNotification {
        let deepLink: URL?
        let campaignId: String?

        init(deepLink: URL?, campaignId: String?) {
            self.deepLink = deepLink
            self.campaignId = campaignId
        }
    }

    private func getMarketapNotification(request: UNNotificationRequest) -> MarketapNotification? {
        guard let info = request.content.userInfo["marketap"] as? [String: Any] else { return nil }

        return MarketapNotification(
            deepLink: (info["deepLink"] as? String).map { URL(string: $0) } ?? nil,
            campaignId: info["campaignId"] as? String
        )
    }

    func setPushToken(token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        setPushToken(token: tokenString)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool {

        if getMarketapNotification(request: notification.request) == nil {
            return false
        }

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }

        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        guard let notification = getMarketapNotification(request: response.notification.request) else {
            return false
        }

        if let deepLink = notification.deepLink {
            UIApplication.shared.open(deepLink, options: [:], completionHandler: nil)
        }

        if let campaignId = notification.campaignId {
            track(
                eventName: "mkt_click_message",
                eventProperties: [
                    "mkt_campaign_id": campaignId,
                    "mkt_campaign_category": "OFF_SITE",
                    "mkt_channel_type": "PUSH",
                    "mkt_sub_channel_type": "IOS",
                    "mkt_result_status": 200,
                    "mkt_result_message": "SUCCESS",
                    "mkt_location_id": "push",
                    "mkt_is_success": true,
                    "mkt_message_id": UUID().uuidString
                ],
                id: nil,
                timestamp: nil
            )
        }
        completionHandler()

        return true
    }
}
