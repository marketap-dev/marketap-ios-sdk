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
