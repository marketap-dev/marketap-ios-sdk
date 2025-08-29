//
//  ColdStartHandler.swift
//  MarketapSDK
//
//  Created by 이동현 on 5/22/25.
//

import UIKit

/// MarketapClient 가 initialize 되기 이전에 발생한 노티피케이션 관련 액션을 관리합니다.
final class ColdStartNotificationHandler: MarketapNotificationClientProtocol {
    var token: Data?
    var notification: MarketapNotification?

    func setPushToken(token: Data) {
        MarketapLogger.verbose("store token")
        self.token = token
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        let info = response.notification.request.content.userInfo["marketap"] as? [String: Any]
        guard let notification = MarketapNotification(info: info) else {
            MarketapLogger.verbose("invalid info")
            return false
        }
        MarketapLogger.verbose("store didReceive event")

        self.notification = notification
        completionHandler()

        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?
    ) {
        guard let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
              let info = remoteNotification["marketap"] as? [String: Any],
              let notification = MarketapNotification(info: info) else {
            MarketapLogger.verbose("invalid info")
            return
        }
        MarketapLogger.verbose("store didFinishLaunchingWithOptions event")

        self.notification = notification
    }


    func didInitializeClient(client: MarketapNotificationClientProtocol & MarketapNotificationHandlerProtocol) {
        MarketapLogger.verbose("didInitializeClient")
        if let token = token {
            client.setPushToken(token: token)
            self.token = nil
        }

        if let notification = notification {
            client.handleNotification(notification)
            self.notification = nil
        }
    }
}
