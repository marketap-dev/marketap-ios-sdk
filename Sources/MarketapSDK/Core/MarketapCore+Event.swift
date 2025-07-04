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
            Logger.debug("setPushToken: \(token)")
            self.eventService.setPushToken(token: token)
        }
    }

    func login(userId: String, userProperties: [String : Any]?, eventProperties: [String : Any]?) {
        queue.async {
            Logger.debug("login: userProperties \(userProperties.prettyPrintedJSONString), eventProperties \(eventProperties.prettyPrintedJSONString)")
            self.eventService.login(userId: userId, userProperties: userProperties, eventProperties: eventProperties)
        }
    }

    func logout(eventProperties: [String : Any]?) {
        queue.async {
            Logger.debug("logout:\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.logout(eventProperties: eventProperties)
        }
    }

    func track(eventName: String, eventProperties: [String : Any]?, id: String?, timestamp: Date?) {
        queue.async {
            Logger.debug("track: \(eventName)\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: eventName, eventProperties: eventProperties, id: id, timestamp: timestamp)
        }
    }

    func trackPurchase(revenue: Double, eventProperties: [String : Any]?) {
        queue.async {
            var eventProperties = eventProperties ?? [:]
            eventProperties["mkt_revenue"] = revenue
            Logger.debug("trackPurchase:\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: MarketapEvent.purchase.rawValue, eventProperties: eventProperties)
        }
    }

    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String : Any]?) {
        queue.async {
            var eventProperties = eventProperties ?? [:]
            eventProperties["mkt_revenue"] = revenue
            Logger.debug("trackRevenue: \(revenue)\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: eventName, eventProperties: eventProperties)
        }
    }

    func trackPageView(eventProperties: [String : Any]?) {
        queue.async {
            Logger.debug("trackPageView:\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: MarketapEvent.view.rawValue, eventProperties: eventProperties)
        }
    }

    func identify(userId: String, userProperties: [String : Any]?) {
        queue.async {
            Logger.debug("identify: \(userId)\n\(userProperties.prettyPrintedJSONString)")
            self.eventService.identify(userId: userId, userProperties: userProperties)
        }
    }

    func resetIdentity() {
        queue.async {
            Logger.debug("resetIdentity")
            self.eventService.flushUser()
        }
    }
}
