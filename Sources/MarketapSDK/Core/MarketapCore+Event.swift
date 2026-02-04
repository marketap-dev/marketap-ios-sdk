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
            MarketapLogger.debug("setPushToken: \(token)")
            self.eventService.setPushToken(token: token)
        }
    }

    func setDeviceOptIn(optIn: Bool?) {
        queue.async {
            MarketapLogger.debug("setDeviceOptIn: \(String(describing: optIn))")
            self.eventService.setDeviceOptIn(optIn: optIn)
        }
    }

    func signup(
        userId: String,
        userProperties: [String: Any]? = nil,
        eventProperties: [String: Any]? = nil,
        persistUser: Bool = true
    ) {
        queue.async {
            MarketapLogger.debug("signup: userProperties \(userProperties.prettyPrintedJSONString), eventProperties \(eventProperties.prettyPrintedJSONString), persistUser: \(persistUser)")
            self.eventService.identify(userId: userId, userProperties: userProperties)
            self.eventService.trackEvent(eventName: MarketapEvent.signup.rawValue, eventProperties: eventProperties, userId: userId)
            if !persistUser {
                self.eventService.flushUser()
            }
        }
    }

    func login(userId: String, userProperties: [String : Any]?, eventProperties: [String : Any]?) {
        queue.async {
            MarketapLogger.debug("login: userProperties \(userProperties.prettyPrintedJSONString), eventProperties \(eventProperties.prettyPrintedJSONString)")
            self.eventService.identify(userId: userId, userProperties: userProperties)
            self.eventService.trackEvent(eventName: MarketapEvent.login.rawValue, eventProperties: eventProperties, userId: userId)
        }
    }

    func logout(eventProperties: [String : Any]?) {
        queue.async {
            MarketapLogger.debug("logout: \(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: MarketapEvent.logout.rawValue, eventProperties: eventProperties)
            self.eventService.flushUser()
        }
    }

    func track(eventName: String, eventProperties: [String : Any]?, id: String?, timestamp: Date?) {
        queue.async {
            MarketapLogger.debug("track: \(eventName)\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: eventName, eventProperties: eventProperties, id: id, timestamp: timestamp)
        }
    }

    func trackFromWebBridge(eventName: String, eventProperties: [String : Any]?) {
        queue.async {
            MarketapLogger.debug("trackFromWebBridge: \(eventName)\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: eventName, eventProperties: eventProperties, fromWebBridge: true)
        }
    }

    func trackPurchase(revenue: Double, eventProperties: [String : Any]?) {
        queue.async {
            var eventProperties = eventProperties ?? [:]
            eventProperties["mkt_revenue"] = revenue
            MarketapLogger.debug("trackPurchase:\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: MarketapEvent.purchase.rawValue, eventProperties: eventProperties)
        }
    }

    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String : Any]?) {
        queue.async {
            var eventProperties = eventProperties ?? [:]
            eventProperties["mkt_revenue"] = revenue
            MarketapLogger.debug("trackRevenue: \(revenue)\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: eventName, eventProperties: eventProperties)
        }
    }

    func trackPageView(eventProperties: [String : Any]?) {
        queue.async {
            MarketapLogger.debug("trackPageView:\n\(eventProperties.prettyPrintedJSONString)")
            self.eventService.trackEvent(eventName: MarketapEvent.view.rawValue, eventProperties: eventProperties)
        }
    }

    func identify(userId: String, userProperties: [String : Any]?) {
        queue.async {
            MarketapLogger.debug("identify: \(userId)\n\(userProperties.prettyPrintedJSONString)")
            self.eventService.identify(userId: userId, userProperties: userProperties)
        }
    }

    func resetIdentity() {
        queue.async {
            MarketapLogger.debug("resetIdentity")
            self.eventService.flushUser()
        }
    }
}
