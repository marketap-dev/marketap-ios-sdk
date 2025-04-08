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
        let messageId: String?
        let serverProperties: [String: String]?

        init(deepLink: URL?, campaignId: String?, messageId: String?, serverProperties: [String: String]?) {
            self.deepLink = deepLink
            self.campaignId = campaignId
            self.messageId = messageId
            self.serverProperties = serverProperties
        }
    }

    private func getMarketapNotification(request: UNNotificationRequest) -> MarketapNotification? {
        guard let info = request.content.userInfo["marketap"] as? [String: Any] else { return nil }

        let deepLink = (info["deepLink"] as? String).flatMap { URL(string: $0) }
        let campaignId = info["campaignId"] as? String
        let messageId = info["messageId"] as? String

        let serverProperties: [String: String]? = {
            guard let propertiesString = info["serverProperties"] as? String,
                  let data = propertiesString.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                  let dict = jsonObject as? [String: String] else {
                return nil
            }
            return dict
        }()

        return MarketapNotification(
            deepLink: deepLink,
            campaignId: campaignId,
            messageId: messageId,
            serverProperties: serverProperties
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

        if let campaignId = notification.campaignId, let messageId = notification.messageId, let serverProperties = notification.serverProperties {
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
                    "mkt_message_id": messageId
                ].merging(serverProperties) { (_, new) in new },
                id: nil,
                timestamp: nil
            )
        }
        completionHandler()

        return true
    }
}
