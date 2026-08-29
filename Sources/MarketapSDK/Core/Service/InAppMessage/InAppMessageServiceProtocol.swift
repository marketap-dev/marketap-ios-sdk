//
//  InAppMessageServiceProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol InAppMessageServiceProtocol {
    func fetchCampaigns(
        force: Bool,
        inTimeout: (([InAppCampaign]) -> Void)?,
        completion: (([InAppCampaign]) -> Void)?,
    )
    func onEvent(eventRequest: IngestEventRequest, fromWebBridge: Bool)
    func recordHidden(campaignId: String, until: TimeInterval)
    /// 신원이 바뀌면 이전 신원으로 고른 적재 후보를 버린다.
    func discardPendingCampaign()
}

extension InAppMessageServiceProtocol {
    func fetchCampaigns(force: Bool = false) {
        fetchCampaigns(force: force, inTimeout: nil, completion: nil)
    }

    func fetchCampaigns(force: Bool = false, completion: (([InAppCampaign]) -> Void)?) {
        fetchCampaigns(force: force, inTimeout: nil, completion: completion)
    }

    func onEvent(eventRequest: IngestEventRequest) {
        onEvent(eventRequest: eventRequest, fromWebBridge: false)
    }
}
