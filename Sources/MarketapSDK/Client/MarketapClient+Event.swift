//
//  MarketapClient+Event.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import Foundation

extension MarketapClient {
    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?) {
        core.login(userId: userId, userProperties: userProperties, eventProperties: eventProperties)
    }

    func logout(eventProperties: [String: Any]?) {
        core.logout(eventProperties: eventProperties)
    }

    func track(eventName: String, eventProperties: [String: Any]?, id: String?, timestamp: Date?) {
        core.track(eventName: eventName, eventProperties: eventProperties, id: id, timestamp: timestamp)
    }

    func trackPurchase(revenue: Double, eventProperties: [String: Any]?) {
        core.trackPurchase(revenue: revenue, eventProperties: eventProperties)
    }

    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String: Any]?) {
        core.trackRevenue(eventName: eventName, revenue: revenue, eventProperties: eventProperties)
    }

    func trackPageView(eventProperties: [String: Any]?) {
        core.trackPageView(eventProperties: eventProperties)
    }

    func identify(userId: String, userProperties: [String: Any]?) {
        core.identify(userId: userId, userProperties: userProperties)
    }

    func resetIdentity() {
        core.resetIdentity()
    }
}
