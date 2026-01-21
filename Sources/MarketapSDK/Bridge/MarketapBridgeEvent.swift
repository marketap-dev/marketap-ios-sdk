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
    case marketapBridgeCheck
    // Web → Native: 웹에서 인앱 메시지 이벤트 전달
    case inAppMessageImpression
    case inAppMessageClick
    case inAppMessageHide
    case inAppMessageTrack
    case inAppMessageSetUserProperties
}

struct MarketapBridgeEvent {
    let type: MarketapBridgeEventType
    let params: [String: Any]?
}
