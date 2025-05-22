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
    /// UNUserNotificationCenterDelegate 함수에 추가해주세요.
    ///
    /// - Returns: Marketap SDK가 해당 알림을 처리했으면 `true`, 그렇지 않으면 `false`
    @objc public static func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) -> Bool {
        guard let client else { return false }
        return client.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }

    /// UNUserNotificationCenterDelegate 함수에 추가해주세요.
    ///
    /// - Returns: Marketap SDK가 해당 알림을 처리했으면 `true`, 그렇지 않으면 `false`
    @objc public static func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        guard let client else { return false }
        return client.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }

    /// 콜드스타트시 필요한 정보를 처리합니다.
    @objc public static func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?) {
        guard let client else { return }
        client.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
