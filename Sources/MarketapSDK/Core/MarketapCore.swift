//
//  MarketapCore.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

class MarketapCore: MarketapClientProtocol {
    let eventService: EventServiceProtocol
    let inAppMessageService: InAppMessageServiceProtocol
    let queue = DispatchQueue(label: "com.marketap.core")

    init(eventService: EventServiceProtocol, inAppMessageService: InAppMessageServiceProtocol) {
        self.inAppMessageService = inAppMessageService
        self.eventService = eventService

        queue.async {
            self.eventService.updateDevice(pushToken: nil, removeUserId: false)
            if !UserDefaults.standard.bool(forKey: "first_visit") {
                UserDefaults.standard.set(true, forKey: "first_visit")
                self.eventService.trackEvent(eventName: "mkt_first_visit", eventProperties: nil)
            }
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
