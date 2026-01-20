//
//  MarketapNotificationService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import Foundation
import UserNotifications

@objcMembers
public class MarketapNotificationService: NSObject {
    public static var client: MarketapNotificationServiceClientProtocol = MarketapNotificationServiceClient()

    private override init() {}

    @objc public static func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) -> Bool {
        client.didReceive(request, withContentHandler: contentHandler)
    }

    @objc public static func serviceExtensionTimeWillExpire() -> Bool {
        client.serviceExtensionTimeWillExpire()
    }
}
