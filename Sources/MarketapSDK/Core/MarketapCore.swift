//
//  MarketapCore.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

class MarketapCore: MarketapCoreProtocol {
    private let eventService: EventService
    private let inAppMessageService: InAppMessageService

    init(config: MarketapConfig) {
        let api = MarketapAPI()
        let cache = MarketapCache(config: config)
        let inAppMessageService = InAppMessageService(api: api, cache: cache)
        self.inAppMessageService = inAppMessageService
        self.eventService = EventService(api: api, cache: cache, inAppMessageService: inAppMessageService)

        self.eventService.updateDevice()
    }

    func login(userId: String, userProperties: [String : Any]?, eventProperties: [String : Any]?) {
        eventService.login(userId: userId, userProperties: userProperties, eventProperties: eventProperties)
    }
    
    func logout(eventProperties: [String : Any]?) {
        eventService.logout(eventProperties: eventProperties)
    }
    
    func track(eventName: String, eventProperties: [String : Any]?, id: String?, timestamp: Date?) {
        eventService.trackEvent(eventName: eventName, eventProperties: eventProperties, id: id, timestamp: timestamp)
    }
    
    func trackPurchase(revenue: Double, eventProperties: [String : Any]?) {
        var eventProperties = eventProperties ?? [:]
        eventProperties["mkt_revenue"] = revenue
        eventService.trackEvent(eventName: MarketapEvent.purchase.rawValue, eventProperties: eventProperties)
    }
    
    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String : Any]?) {
        var eventProperties = eventProperties ?? [:]
        eventProperties["mkt_revenue"] = revenue
        eventService.trackEvent(eventName: eventName, eventProperties: eventProperties)
    }
    
    func trackPageView(eventProperties: [String : Any]?) {
        eventService.trackEvent(eventName: MarketapEvent.view.rawValue, eventProperties: eventProperties)
    }
    
    func identify(userId: String, userProperties: [String : Any]?) {
        eventService.identify(userId: userId, userProperties: userProperties)
    }
    
    func resetIdentity() {
        eventService.flushUser()
    }
}
