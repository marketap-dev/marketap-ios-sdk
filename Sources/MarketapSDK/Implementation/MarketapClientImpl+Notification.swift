//
//  MarketapClientImpl+Notification.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import UserNotifications
import UIKit

extension MarketapClientImpl {
    struct MarketapNotificationInfo {
        let deepLink: URL?
        
        init(deepLink: URL?) {
            self.deepLink = deepLink
        }
    }
    
    private func getMarketapNotification(request: UNNotificationRequest) -> MarketapNotificationInfo? {
        guard let info = request.content.userInfo["marketap"] as? [String: Any] else { return nil }
        
        return MarketapNotificationInfo(
            deepLink: (info["deepLink"] as? String).map { URL(string: $0) } ?? nil
        )
    }
    
    func setPushToken(token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        setDevice(additionalInfo: ["token": tokenString])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool {
        print("📢 포어그라운드에서 푸시 수신: \(notification.request.content.userInfo)")
        
        if getMarketapNotification(request: notification.request) == nil {
            print("📢 마켓탭 푸시가 아님")
            return false
        }
        print("📢 마켓탭 푸시도착")
                
        completionHandler([.sound, .badge])
        
        return true
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        print("✅ 사용자가 푸시를 눌렀습니다")
        
        guard let info = getMarketapNotification(request: response.notification.request) else {
            print("📢 마켓탭 푸시가 아님")
            return false
        }
        
        if let deepLink = info.deepLink {
            print("📢 딥링크 오픈", deepLink.absoluteString)
            UIApplication.shared.open(deepLink, options: [:], completionHandler: nil)
        }
        completionHandler()
        
        return true
    }
}
