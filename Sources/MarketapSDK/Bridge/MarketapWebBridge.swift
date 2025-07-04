//
//  MarketapWebBridge.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/25/25.
//

import WebKit
import UIKit

@objc public class MarketapWebBridge: NSObject, WKScriptMessageHandler {
    public static let name = "marketap"

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.name,
              let body = message.body as? [String: Any],
              let typeString = body["type"] as? String,
              let eventType = MarketapBridgeEventType(rawValue: typeString) else {
            if message.name == Self.name {
                Logger.error("invalid body: \(message.body)")
            }
            return
        }

        let event = MarketapBridgeEvent(type: eventType, params: body["params"] as? [String: Any])
        handleEvent(event)
    }

    private func handleEvent(_ event: MarketapBridgeEvent) {
        switch event.type {
        case .track:
            handleTrackEvent(params: event.params)
        case .identify:
            handleIdentifyEvent(params: event.params)
        case .resetIdentity:
            Marketap.resetIdentity()
        }
    }

    private func handleTrackEvent(params: [String: Any]?) {
        guard let eventName = params?["eventName"] as? String else {
            return
        }
        let eventProperties = params?["eventProperties"] as? [String: Any]
        Marketap.track(eventName: eventName, eventProperties: eventProperties)
    }

    private func handleIdentifyEvent(params: [String: Any]?) {
        guard let userId = params?["userId"] as? String else {
            return
        }
        let userProperties = params?["userProperties"] as? [String: Any]
        Marketap.identify(userId: userId, userProperties: userProperties)
    }
}
