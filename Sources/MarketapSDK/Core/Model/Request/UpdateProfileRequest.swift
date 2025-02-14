//
//  UpdateProfileRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct UpdateProfileRequest: Encodable {
    let userId: String
    let properties: [String: AnyEncodable]?
    let device: UpdateDeviceRequest?

    init(userId: String, properties: [String: AnyEncodable]?, device: UpdateDeviceRequest?) {
        self.userId = userId
        self.properties = properties
        self.device = device
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case properties
        case device
    }
}
