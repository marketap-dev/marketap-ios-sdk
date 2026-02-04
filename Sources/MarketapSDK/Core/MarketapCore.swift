//
//  MarketapCore.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

final class MarketapCore: MarketapClientProtocol, MarketapNotificationHandlerProtocol {
    let customHandlerStore: MarketapCustomHandlerStoreProtocol
    let eventService: EventServiceProtocol
    let inAppMessageService: InAppMessageServiceProtocol
    let queue = DispatchQueue(label: "com.marketap.core")

    init(
        customHandlerStore: MarketapCustomHandlerStoreProtocol,
        eventService: EventServiceProtocol,
        inAppMessageService: InAppMessageServiceProtocol
    ) {
        self.customHandlerStore = customHandlerStore
        self.inAppMessageService = inAppMessageService
        self.eventService = eventService

        queue.async {
            self.eventService.updateDevice(pushToken: nil, optIn: nil, removeUserId: false, clearOptIn: false)
            if !UserDefaults.standard.bool(forKey: "first_visit") {
                UserDefaults.standard.set(true, forKey: "first_visit")
                self.eventService.trackEvent(eventName: "mkt_first_visit", eventProperties: nil)
            }
        }
    }

    deinit {
        MarketapLogger.verbose("client has been deallocated: \(ObjectIdentifier(self).hashValue)")
    }
}


extension MarketapCore: EventServiceDelegate {
    func handleUserIdChanged() {
        queue.async {
            self.inAppMessageService.fetchCampaigns(force: true)
        }
    }

    func onEvent(eventRequest: IngestEventRequest, device: Device, fromWebBridge: Bool) {
        queue.async {
            if !["mkt_delivery_message", "mkt_click_message"].contains(eventRequest.name) {
                self.inAppMessageService.onEvent(eventRequest: eventRequest, fromWebBridge: fromWebBridge)
            }
        }
    }
}

extension MarketapCore: InAppMessageServiceDelegate {
    func trackEvent(eventName: String, eventProperties: [String : Any]?) {
        track(eventName: eventName, eventProperties: eventProperties, id: nil, timestamp: nil)
    }
    
    func setUserProperties(userProperties: [String : Any]) {
        queue.async {
            MarketapLogger.debug("setUserProperties:\n\(userProperties.prettyPrintedJSONString)")
            self.eventService.setUserProperties(userProperties: userProperties, userId: nil)
        }
    }
}
