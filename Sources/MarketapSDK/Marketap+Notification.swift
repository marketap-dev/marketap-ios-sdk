//
//  Marketap+Notification.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import Foundation
import UserNotifications
import UIKit

@objc extension Marketap {
    @objc public static func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool {
        client.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
    
    @objc public static func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        client.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }

}
