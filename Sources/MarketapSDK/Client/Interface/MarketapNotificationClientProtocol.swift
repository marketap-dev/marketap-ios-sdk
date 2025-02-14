//
//  MarketapNotificationClientProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import UserNotifications

public protocol MarketapNotificationClientProtocol {
    /// Registers the push token for the device.
    /// - Parameter token: The device's push notification token.
    func setPushToken(token: Data)
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool
}
