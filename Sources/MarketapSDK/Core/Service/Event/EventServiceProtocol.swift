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
    func identify(userId: String, userProperties: [String: Any]?)
    func flushUser()
    func trackEvent(eventName: String, eventProperties: [String: Any]?, userId: String?, id: String?, timestamp: Date?)
    func updateDevice(pushToken: String?, removeUserId: Bool)
}

extension EventServiceProtocol {
    func trackEvent(eventName: String, eventProperties: [String: Any]?, userId: String? = nil) {
        trackEvent(eventName: eventName, eventProperties: eventProperties, userId: userId, id: nil, timestamp: nil)
    }

    func trackEvent(eventName: String, eventProperties: [String: Any]?, id: String?, timestamp: Date?) {
        trackEvent(eventName: eventName, eventProperties: eventProperties, userId: nil, id: id, timestamp: timestamp)
    }
}
