//
//  MarketapBridgeEvent.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/25/25.
//

import Foundation

enum MarketapBridgeEventType: String {
    case track
    case identify
    case resetIdentity
}

struct MarketapBridgeEvent {
    let type: MarketapBridgeEventType
    let params: [String: Any]?
}
