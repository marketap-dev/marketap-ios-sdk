//
//  UpdateDeviceRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct UpdateDeviceRequest: Codable, Equatable {
    let deviceId: String
    let idfa: String?
    let idfv: String?
    let platform: String
    let token: String?
    let properties: [String: AnyCodable]?
    let removeUserId: Bool
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case idfa
        case idfv
        case platform
        case token
        case properties
        case removeUserId = "remove_user_id"
    }
}
