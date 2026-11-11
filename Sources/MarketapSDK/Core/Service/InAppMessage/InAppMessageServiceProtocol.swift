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
    /// 출처 웹뷰가 다른 페이지로 이동했다. 그 출처에서 시작돼 이미 화면에 나타난 "이 페이지에서만" 플로팅과 팝업을 닫는다.
    func originDidLeavePage(_ originId: ObjectIdentifier)
    /// 출처 웹뷰가 사라졌다(창에서 떨어짐·브리지 해제). 그 출처에서 시작돼 이미 화면에 나타난 "이 페이지에서만" 플로팅과 팝업을 닫는다.
    func originDidDisappear(_ originId: ObjectIdentifier)
    /// 앱 화면이 바뀌었다. `signalTime` 은 앱이 신호를 보낸 시각(`ProcessInfo.systemUptime`).
    func screenChanged(at signalTime: TimeInterval)
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
