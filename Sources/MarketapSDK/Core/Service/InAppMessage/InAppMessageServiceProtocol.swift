//
//  InAppMessageServiceProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol InAppMessageServiceProtocol {
    func fetchCampaigns(force: Bool, completion: (([InAppCampaign]) -> Void)?)
    func onEvent(eventRequest: IngestEventRequest, device: Device)
}

extension InAppMessageServiceProtocol {
    func fetchCampaigns(force: Bool = false) {
        fetchCampaigns(force: force, completion: nil)
    }
}
