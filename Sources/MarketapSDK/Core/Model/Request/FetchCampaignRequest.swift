//
//  FetchCampaignRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct FetchCampaignRequest: Encodable {
    let projectId: String
    let userId: String?
    let device: UpdateDeviceRequest
    
    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case userId = "user_id"
        case device
    }
}
