//
//  InAppMessageService+View.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation
import UIKit
import WebKit

/// 상세 fetch 를 실제로 보내는 후보의 최대 개수. 서버가 노출을 확정 못 해 빈 응답을 주면
/// 다음 후보로 넘어가는데, 그때마다 요청이 나가므로 상한을 둔다. html 이 이미 있는 정적 렌더
/// 캠페인은 서버를 안 타므로 이 예산을 깎지 않는다. (web SDK 와 동일한 정책)
private let inAppMaxFallthroughFetches = 5

/// 폴스루 전체의 시간 예산(초). fetch 는 비동기라 스레드를 블록하지 않지만, 무한정 이어가면
/// 이벤트가 난 지 한참 뒤에 팝업이 튀어나온다. fetch 당 1초 타임아웃이라 이 값이면 약 2회에서 찬다.
private let inAppFallthroughBudgetSeconds: TimeInterval = 2

extension InAppMessageService: InAppMessageWebViewControllerDelegate {

    func isCampaignHiden(campaign: InAppCampaign) -> Bool {
        if UserDefaults.standard.double(forKey: "hide_campaign_\(campaign.id)") > Date().timeIntervalSince1970 {
            return true
        }

        if let frequencyCap = campaign.triggerEventCondition.frequencyCap {
            let canShow = canShowCampaign(campaignId: campaign.id, frequencyCap: frequencyCap)
            return !canShow
        }

        return false
    }

    func hideCampaign(campaignId: String, until: TimeInterval) {
        MarketapLogger.debug("hide \(campaignId) until: \(until)")
        isModalShown = false
        if until > 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970 + until, forKey: "hide_campaign_\(campaignId)")
        }
    }

    func canShowCampaign(campaignId: String, frequencyCap: FrequencyCap) -> Bool {
        let key = "impression_\(campaignId)"
        let now = Date().timeIntervalSince1970

        let timestamps = UserDefaults.standard.object(forKey: key) as? [TimeInterval] ?? []
        let validTimestamps = timestamps.filter { now - $0 <= TimeInterval(frequencyCap.durationMinutes * 60) }

        return validTimestamps.count < frequencyCap.limit
    }

    func logImpression(campaignId: String) {
        let key = "impression_\(campaignId)"
        let now = Date().timeIntervalSince1970

        var timestamps = UserDefaults.standard.object(forKey: key) as? [TimeInterval] ?? []
        timestamps.append(now)

        UserDefaults.standard.set(Array(timestamps.suffix(100)), forKey: key)
    }

    /// 후보를 우선순위 순으로 **하나가 뜰 때까지** 시도한다.
    ///
    /// 예전에는 첫 후보 하나만 시도하고, 그 상세 fetch 가 빈 응답이면(쿠폰 발급 실패·타겟팅
    /// 탈락 등 서버가 노출을 확정 못 한 경우) 뒤에 뜰 수 있는 캠페인이 있어도 화면에
    /// 아무것도 안 떴다. web SDK 와 같은 증상·수정이다.
    ///
    /// fetch 는 비동기라(스레드를 블록하지 않는다) 실패 콜백에서 다음 후보로 이어간다.
    /// 무한정 이어가면 이벤트가 난 지 한참 뒤에 팝업이 튀어나오므로, 상세 fetch 횟수
    /// (`inAppMaxFallthroughFetches`)와 전체 시간(`inAppFallthroughBudgetSeconds`)으로 묶는다.
    func tryShowCampaigns(
        candidates: [InAppCampaign],
        index: Int,
        fetches: Int,
        deadline: TimeInterval,
        eventName: String,
        eventProperties: [String: Any]?,
        fromWebBridge: Bool
    ) {
        // 앞 후보가 떴거나 다른 경로가 이미 띄웠으면 멈춘다.
        if isModalShown { return }
        guard index < candidates.count else { return }

        let campaign = candidates[index]

        // 숨김·빈도수 미달 캠페인은 요청 없이 다음 후보로. (fetch 예산 안 깎음)
        if isCampaignHiden(campaign: campaign) {
            tryShowCampaigns(
                candidates: candidates, index: index + 1, fetches: fetches, deadline: deadline,
                eventName: eventName, eventProperties: eventProperties, fromWebBridge: fromWebBridge
            )
            return
        }

        // 웹브릿지에서 온 이벤트이고 활성 웹브릿지가 있으면 웹으로 캠페인 전달
        let shouldDelegateToWeb = fromWebBridge && MarketapWebBridge.hasActiveWebBridge()

        // html 이 이미 있으면(정적 렌더) 서버를 안 타고 바로 노출. fetch 예산 안 깎음.
        if campaign.html != nil {
            show(campaign: campaign, delegateToWeb: shouldDelegateToWeb)
            return
        }

        // 상세 fetch 가 필요한 후보. 요청 예산·시간 예산을 넘기면 멈춘다.
        if fetches >= inAppMaxFallthroughFetches {
            MarketapLogger.verbose("reached fetch budget (\(inAppMaxFallthroughFetches)), stopping fallthrough")
            return
        }
        if Date().timeIntervalSince1970 >= deadline {
            MarketapLogger.verbose("reached time budget, stopping fallthrough")
            return
        }

        MarketapLogger.verbose("fetching campaign html: \(campaign.id)")
        fetchCampaign(
            campaignId: campaign.id,
            eventName: eventName,
            eventProperties: eventProperties
        ) { [weak self] fetchedCampaign in
            guard let self = self else { return }
            if let fetchedCampaign = fetchedCampaign, fetchedCampaign.html != nil {
                self.show(campaign: fetchedCampaign, delegateToWeb: shouldDelegateToWeb)
            } else {
                MarketapLogger.warn("failed to fetch campaign html: \(campaign.id), trying next")
                self.tryShowCampaigns(
                    candidates: candidates, index: index + 1, fetches: fetches + 1, deadline: deadline,
                    eventName: eventName, eventProperties: eventProperties, fromWebBridge: fromWebBridge
                )
            }
        }
    }

    /// 확정된 캠페인을 노출한다(웹브릿지 위임 또는 모달 present). impression 도 여기서 기록.
    private func show(campaign: InAppCampaign, delegateToWeb: Bool) {
        logImpression(campaignId: campaign.id)
        if delegateToWeb {
            // 웹으로 캠페인 전달 (impression은 웹에서 처리)
            let messageId = UUID().uuidString
            MarketapWebBridge.sendCampaignToActiveWeb(campaign: campaign, messageId: messageId)
        } else {
            presentCampaignModal(campaign: campaign)
        }
    }

    private func presentCampaignModal(campaign: InAppCampaign) {

        guard didFinishLoad else {
            MarketapLogger.verbose("loading campaign: \(campaign.id)")
            pendingCampaign = campaign
            return
        }
        DispatchQueue.main.async {
            self.campaignViewController.campaign = campaign
            if let topViewController = self.getTopViewController() {
                MarketapLogger.verbose("presenting campaign: \(campaign.id)")
                topViewController.present(self.campaignViewController, animated: false) {
                    MarketapLogger.verbose("presented campaign: \(campaign.id)")
                    self.isModalShown = true
                }
            } else {
                MarketapLogger.warn("failed to find topViewController: \(campaign.id)")
            }
        }
    }

    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { [.foregroundActive, .foregroundInactive].contains($0.activationState) }) as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }

        var topController = keyWindow.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }

    func onEvent(eventRequest: IngestEventRequest, fromWebBridge: Bool) {
        let eventProperties = eventRequest.properties?.compactMapValues { $0.value }
        fetchCampaigns(inTimeout: { [weak self] campaigns in
                guard let self = self else { return }
                // 이벤트 조건을 만족하는 후보 전체를 우선순위 순으로 넘긴다.
                let candidates = campaigns.filter {
                    self.isEventTriggered(condition: $0.triggerEventCondition, event: eventRequest)
                }
                self.tryShowCampaigns(
                    candidates: candidates,
                    index: 0,
                    fetches: 0,
                    deadline: Date().timeIntervalSince1970 + inAppFallthroughBudgetSeconds,
                    eventName: eventRequest.name,
                    eventProperties: eventProperties,
                    fromWebBridge: fromWebBridge
                )
            })
    }

    func onImpression(campaign: InAppCampaign, messageId: String) {
        let props = InAppEventBuilder.impressionEventProperties(
            campaignId: campaign.id,
            messageId: messageId,
            layoutSubType: campaign.layout.layoutSubType
        )
        delegate?.trackEvent(eventName: "mkt_delivery_message", eventProperties: props)
    }

    func onClick(campaign: InAppCampaign, locationId: String, messageId: String, url: String?) {
        MarketapLogger.debug("onClick: \(url ?? "null")")
        customHandlerStore.handleClick(
            MarketapClickEvent(campaignType: .inAppMessage, campaignId: campaign.id, url: url)
        )

        let props = InAppEventBuilder.clickEventProperties(
            campaignId: campaign.id,
            messageId: messageId,
            locationId: locationId,
            url: url,
            layoutSubType: campaign.layout.layoutSubType
        )
        delegate?.trackEvent(eventName: "mkt_click_message", eventProperties: props)
    }

    func onTrack(campaign: InAppCampaign, eventName: String, properties: [String: Any]?) {
        delegate?.trackEvent(eventName: eventName, eventProperties: properties)
    }

    func onSetUserProperties(properties: [String: Any]) {
        delegate?.setUserProperties(userProperties: properties)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishLoad = true
        if let pendingCampaign = pendingCampaign {
            self.pendingCampaign = nil
            presentCampaignModal(campaign: pendingCampaign)
        }
    }
}
