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
    func trackEvent(eventName: String, eventProperties: [String: Any]?, id: String?, timestamp: Date?)
    func updateDevice(pushToken: String?, removeUserId: Bool)
}

extension EventServiceProtocol {
    func trackEvent(eventName: String, eventProperties: [String: Any]?) {
        trackEvent(eventName: eventName, eventProperties: eventProperties, id: nil, timestamp: nil)
    }
}
