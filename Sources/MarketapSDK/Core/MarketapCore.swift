//
//  MarketapCore.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

class MarketapCore: MarketapCoreProtocol {
    private let eventService: EventServiceProtocol
    private let inAppMessageService: InAppMessageServiceProtocol
    private let queue = DispatchQueue(label: "com.marketap.core")

    init(eventService: EventServiceProtocol, inAppMessageService: InAppMessageServiceProtocol) {
        self.inAppMessageService = inAppMessageService
        self.eventService = eventService

        queue.async {
            self.eventService.updateDevice(pushToken: nil, removeUserId: false)
        }
    }

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


extension MarketapCore: EventServiceDelegate {
    func handleUserIdChanged() {
        queue.async {
            self.inAppMessageService.fetchCampaigns(force: true)
        }
    }

    func onEvent(eventRequest: IngestEventRequest, device: Device) {
        queue.async {
            if !["mkt_delivery_message", "mkt_click_message"].contains(eventRequest.name) {
                self.inAppMessageService.onEvent(eventRequest: eventRequest)
            }
        }
    }
}

extension MarketapCore: InAppMessageServiceDelegate {
    func trackEvent(eventName: String, eventProperties: [String : Any]?) {
        track(eventName: eventName, eventProperties: eventProperties, id: nil, timestamp: nil)
    }
}
