//
//  MarketapClickEventObjC.swift
//  MarketapSDK
//
//  Created by 이동현 on 8/29/25.
//

import Foundation

@objc public enum MarketapCampaignTypeObjC: Int {
    case push = 0
    case inAppMessage = 1
}

extension MarketapCampaignType {
    var objc: MarketapCampaignTypeObjC {
        switch self {
        case .push: return .push
        case .inAppMessage: return .inAppMessage
        }
    }
}

@objc(MarketapClickEventObjC)
public final class MarketapClickEventObjC: NSObject {
    @objc public let campaignType: MarketapCampaignTypeObjC
    @objc public let campaignId: NSString
    @objc public let url: NSString?

    @objc public init(campaignType: MarketapCampaignTypeObjC,
                      campaignId: String,
                      url: String?) {
        self.campaignType = campaignType
        self.campaignId = campaignId as NSString
        self.url = url as NSString?
        super.init()
    }

    @nonobjc
    public convenience init(from swift: MarketapClickEvent) {
        self.init(campaignType: swift.campaignType.objc,
                  campaignId: swift.campaignId,
                  url: swift.url)
    }
}
