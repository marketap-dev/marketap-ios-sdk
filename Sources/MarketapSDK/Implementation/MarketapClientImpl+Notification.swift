//
//  MarketapClientImpl+Notification.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import UserNotifications
import UIKit

extension MarketapClientImpl {
    struct MarketapNotification {
        let deepLink: URL?
        
        init(deepLink: URL?) {
            self.deepLink = deepLink
        }
    }
    
    private func getMarketapNotification(request: UNNotificationRequest) -> MarketapNotification? {
        guard let info = request.content.userInfo["marketap"] as? [String: Any] else { return nil }
        
        return MarketapNotification(
            deepLink: (info["deepLink"] as? String).map { URL(string: $0) } ?? nil
        )
    }
    
    func setPushToken(token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        setDevice(additionalInfo: ["token": tokenString])
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
        completionHandler()
        
        return true
    }
}
