//
//  MarketapClickEvent.swift
//  MarketapSDK
//
//  Created by 이동현 on 6/19/25.
//

import Foundation

public enum MarketapCampaignType {
    case push
    case inAppMessage
}

public struct MarketapClickEvent {
    public let campaignType: MarketapCampaignType
    public let campaignId: String
    public let url: String?

    init(campaignType: MarketapCampaignType, campaignId: String, url: String?) {
        self.campaignType = campaignType
        self.campaignId = campaignId
        self.url = url
    }
}
