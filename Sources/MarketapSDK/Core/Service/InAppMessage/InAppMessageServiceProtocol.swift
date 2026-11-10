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
    func onEvent(eventRequest: IngestEventRequest, origin: InAppWebOrigin?)
    func recordHidden(campaignId: String, until: TimeInterval)
    /// 신원이 바뀌면 이전 신원으로 고른 적재 후보를 버린다.
    func discardPendingCampaign()
    /// 출처 웹뷰가 페이지를 벗어났다(주소 변경·창에서 떨어짐·브리지 해제). 그 출처에 묶인 플로팅만 닫는다.
    func originDidLeavePage(_ originId: ObjectIdentifier)
}

extension InAppMessageServiceProtocol {
    func fetchCampaigns(force: Bool = false) {
        fetchCampaigns(force: force, inTimeout: nil, completion: nil)
    }

    func fetchCampaigns(force: Bool = false, completion: (([InAppCampaign]) -> Void)?) {
        fetchCampaigns(force: force, inTimeout: nil, completion: completion)
    }

    func onEvent(eventRequest: IngestEventRequest) {
        onEvent(eventRequest: eventRequest, origin: nil)
    }
}
