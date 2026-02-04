//
//  MarketapNotificationClientProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import UIKit
import UserNotifications

public protocol MarketapNotificationClientProtocol {
    // MARK: - Push Notification Management

    /// Registers the push notification token for the device.
    /// This method should be called after obtaining the device's push token from APNs.
    ///
    /// - Parameter token: The push notification token assigned to the device.
    func setPushToken(token: Data)

    /// 디바이스의 푸시 수신동의 여부를 설정합니다.
    /// - Parameter optIn: 수신동의 여부 (`true`, `false`, 또는 `nil`)
    func setDeviceOptIn(optIn: Bool?)

    // MARK: - Foreground Notification Handling

    /// Handles push notifications when the app is in the foreground.
    /// If the notification is related to Marketap, the SDK processes it and returns `true`.
    /// Otherwise, it returns `false` so the app can handle it separately.
    ///
    /// - Parameters:
    ///   - center: The notification center that triggered the event.
    ///   - notification: The received notification.
    ///   - completionHandler: A closure to execute with the desired presentation options.
    /// - Returns: `true` if the notification was handled by the SDK, otherwise `false`.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) -> Bool

    // MARK: - Background Notification Handling

    /// Handles push notifications when the user interacts with them.
    /// If the notification is related to Marketap, the SDK processes it and returns `true`.
    /// Otherwise, it returns `false` so the app can handle it separately.
    ///
    /// - Parameters:
    ///   - center: The notification center that triggered the event.
    ///   - response: The user’s response to the notification.
    ///   - completionHandler: A closure to execute after handling the response.
    /// - Returns: `true` if the notification was handled by the SDK, otherwise `false`.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?)
}

protocol MarketapNotificationHandlerProtocol {
    func handleNotification(_ notification: MarketapNotification)
}
