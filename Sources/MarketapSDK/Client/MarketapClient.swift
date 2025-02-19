//
//  MarketapClient.swift
//
//  Created by 이동현 on 2/11/25.
//

import WebKit

class MarketapClient: NSObject, MarketapClientProtocol {
    let core: MarketapCore

    init(projectId: String) {
        let config = MarketapConfig(projectId: projectId)
        let api = MarketapAPI()
        let cache = MarketapCache(config: config)
        let eventService = EventService(api: api, cache: cache)
        let inAppMessageService = InAppMessageService(api: api, cache: cache)
        let core = MarketapCore(eventService: eventService, inAppMessageService: inAppMessageService)
        eventService.delegate = core
        inAppMessageService.delegate = core
        self.core = core
        super.init()
    }
}
