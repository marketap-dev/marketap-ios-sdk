//
//  FetchCampaignRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct FetchCampaignsRequest: Encodable {
    let projectId: String
    let userId: String?
    let device: UpdateDeviceRequest
    
    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case device
    }
}

struct FetchCampaignRequest: Encodable {
    let projectId: String
    let userId: String?
    let device: UpdateDeviceRequest
    let eventName: String?
    let eventProperties: [String: AnyCodable]?
    
    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case device
        case eventName = "event_name"
        case eventProperties = "event_properties"
    }
}
