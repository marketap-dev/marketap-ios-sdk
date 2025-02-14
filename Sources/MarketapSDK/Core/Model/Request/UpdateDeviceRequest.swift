//
//  UpdateDeviceRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct UpdateDeviceRequest: Encodable {
    let deviceId: String
    let cookieId: String?
    let idfa: String?
    let idfv: String?
    let gaid: String?
    let appSetId: String?
    let appLocalId: String?
    let platform: String
    let token: String?
    let properties: [String: AnyEncodable]?
    let removeUserId: Bool
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case cookieId = "cookie_id"
        case idfa
        case idfv
        case gaid
        case appSetId = "app_set_id"
        case appLocalId = "app_local_id"
        case platform
        case token
        case properties
        case removeUserId = "remove_user_id"
    }
}
