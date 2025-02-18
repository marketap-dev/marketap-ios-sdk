//
//  NotificationService.swift
//  MarketapSDKExampleNotificationServiceExtension
//
//  Created by 이동현 on 2/16/25.
//

import UIKit
import MarketapSDKNotificationServiceExtension

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        _ = MarketapNotificationService.didReceive(request, withContentHandler: contentHandler)
    }

    override func serviceExtensionTimeWillExpire() {
        _ = MarketapNotificationService.serviceExtensionTimeWillExpire()
    }
}
