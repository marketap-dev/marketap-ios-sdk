//
//  MarketapState.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct MarketapState: Codable {
    var userId: String?
    var config: MarketapConfig
    var device: Device
    var storage: InternalStorage
}

struct InternalStorage: Codable {
    var sessionId: String
}
