//
//  EventServiceProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol EventServiceProtocol {
    var delegate: EventServiceDelegate? { get set }

    func setPushToken(token: String)
    func setDeviceOptIn(optIn: Bool)
    func identify(userId: String, userProperties: [String: Any]?)
    func setUserProperties(userProperties: [String: Any], userId: String?)
    func flushUser()
    func trackEvent(eventName: String, eventProperties: [String: Any]?, userId: String?, id: String?, timestamp: Date?, fromWebBridge: Bool)
    func updateDevice(pushToken: String?, optIn: Bool?, removeUserId: Bool)
}

extension EventServiceProtocol {
    func trackEvent(eventName: String, eventProperties: [String: Any]?, userId: String? = nil) {
        trackEvent(eventName: eventName, eventProperties: eventProperties, userId: userId, id: nil, timestamp: nil, fromWebBridge: false)
    }

    func trackEvent(eventName: String, eventProperties: [String: Any]?, id: String?, timestamp: Date?) {
        trackEvent(eventName: eventName, eventProperties: eventProperties, userId: nil, id: id, timestamp: timestamp, fromWebBridge: false)
    }

    func trackEvent(eventName: String, eventProperties: [String: Any]?, fromWebBridge: Bool) {
        trackEvent(eventName: eventName, eventProperties: eventProperties, userId: nil, id: nil, timestamp: nil, fromWebBridge: fromWebBridge)
    }
}
