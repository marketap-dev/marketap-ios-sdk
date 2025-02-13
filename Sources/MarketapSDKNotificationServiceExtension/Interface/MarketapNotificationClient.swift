//
//  MarketapNotificationClient.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

public protocol MarketapNotificationClient {
    func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) -> Bool
    func serviceExtensionTimeWillExpire() -> Bool
}
