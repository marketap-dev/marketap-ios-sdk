//
//  Untitled.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import Foundation
import UserNotifications

@objcMembers
public class MarketapNotificationServiceExtension: NSObject {
    public static var client: MarketapNotificationClient = MarketapNotificationClientImpl()

    private override init() {}
    
    @objc public static func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) -> Bool {
        client.didReceive(request, withContentHandler: contentHandler)
    }

    @objc public static func serviceExtensionTimeWillExpire() -> Bool {
        client.serviceExtensionTimeWillExpire()
    }
}
