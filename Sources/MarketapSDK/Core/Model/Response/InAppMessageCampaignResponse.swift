//
//  InAppMessageCampaignResponse.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/16/25.
//

import Foundation

struct InAppCampaignFetchResponse: Decodable, Equatable {
    let checksum: String
    let campaigns: [InAppCampaign]
}
