//
//  MarketapCore+Event.swift
//  MarketapSDK
//
//  Created by 이동현 on 3/20/25.
//

import Foundation

extension MarketapCore {
    func setPushToken(token: String) {
        queue.async {
            self.eventService.setPushToken(token: token)
        }
    }

    func login(userId: String, userProperties: [String : Any]?, eventProperties: [String : Any]?) {
        queue.async {
            self.eventService.login(userId: userId, userProperties: userProperties, eventProperties: eventProperties)
        }
    }

    func logout(eventProperties: [String : Any]?) {
        queue.async {
            self.eventService.logout(eventProperties: eventProperties)
        }
    }

    func track(eventName: String, eventProperties: [String : Any]?, id: String?, timestamp: Date?) {
        queue.async {
            self.eventService.trackEvent(eventName: eventName, eventProperties: eventProperties, id: id, timestamp: timestamp)
        }
    }

    func trackPurchase(revenue: Double, eventProperties: [String : Any]?) {
        queue.async {
            var eventProperties = eventProperties ?? [:]
            eventProperties["mkt_revenue"] = revenue
            self.eventService.trackEvent(eventName: MarketapEvent.purchase.rawValue, eventProperties: eventProperties)
        }
    }

    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String : Any]?) {
        queue.async {
            var eventProperties = eventProperties ?? [:]
            eventProperties["mkt_revenue"] = revenue
            self.eventService.trackEvent(eventName: eventName, eventProperties: eventProperties)
        }
    }

    func trackPageView(eventProperties: [String : Any]?) {
        queue.async {
            self.eventService.trackEvent(eventName: MarketapEvent.view.rawValue, eventProperties: eventProperties)
        }
    }

    func identify(userId: String, userProperties: [String : Any]?) {
        queue.async {
            self.eventService.identify(userId: userId, userProperties: userProperties)
        }
    }

    func resetIdentity() {
        queue.async {
            self.eventService.flushUser()
        }
    }
}
