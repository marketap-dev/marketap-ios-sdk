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

/// 경과 시간 측정용 단조 시계. 벽시계(Date)는 NTP 보정이나 사용자의 시간 변경으로
/// 앞뒤로 튈 수 있어서, 뒤로 튀면 예산이 사실상 무한이 되고 앞으로 튀면 즉시 끊긴다.
/// 기간을 재는 데는 절대 시각이 아니라 단조 증가 값을 쓴다. (web SDK 의 performance.now 와 같은 이유)
private func inAppMonotonicNow() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}

/// 표시 상태(isModalShown / didFinishLoad / pendingCampaign)를 지키는 락.
///
/// 이 셋은 원래 메인큐(present 완료 콜백, webView didFinish)와 호출 스레드에서 동시에
/// 읽고 쓰였다. 폴스루가 들어오면서 후보마다 present 를 시도할 수 있게 됐고(이벤트당 1회 →
/// 최대 6회), 그것도 코어 시리얼큐·URLSession 델리게이트큐·타임아웃 글로벌큐 세 군데서
/// 들어온다. "이미 떠 있나?" 를 보고 나중에 present 하는 검사-후-사용 구조라 두 후보가
/// 동시에 통과할 수 있었다. 검사와 선점을 한 번에 처리한다.
private let inAppDisplayLock = NSLock()

extension InAppMessageService: InAppMessageWebViewControllerDelegate {

    func isCampaignHiden(campaign: InAppCampaign) -> Bool {
        if defaults.double(forKey: "hide_campaign_\(campaign.id)") > Date().timeIntervalSince1970 {
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
        releaseDisplay()
        if until > 0 {
            defaults.set(Date().timeIntervalSince1970 + until, forKey: "hide_campaign_\(campaignId)")
        }
    }

    func canShowCampaign(campaignId: String, frequencyCap: FrequencyCap) -> Bool {
        let key = "impression_\(campaignId)"
        let now = Date().timeIntervalSince1970

        let timestamps = defaults.object(forKey: key) as? [TimeInterval] ?? []
        let validTimestamps = timestamps.filter { now - $0 <= TimeInterval(frequencyCap.durationMinutes * 60) }

        return validTimestamps.count < frequencyCap.limit
    }

    func logImpression(campaignId: String) {
        let key = "impression_\(campaignId)"
        let now = Date().timeIntervalSince1970

        var timestamps = defaults.object(forKey: key) as? [TimeInterval] ?? []
        timestamps.append(now)

        defaults.set(Array(timestamps.suffix(100)), forKey: key)
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
        inAppDisplayLock.lock()
        let alreadyShown = isModalShown
        inAppDisplayLock.unlock()
        if alreadyShown { return }
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

        // html 이 이미 있으면(정적 렌더) 서버를 안 타고 바로 노출. fetch 예산 안 깎음.
        if campaign.html != nil {
            show(campaign: campaign, fromWebBridge: fromWebBridge)
            return
        }

        // 상세 fetch 가 필요한 후보. 요청 예산·시간 예산을 넘기면 멈춘다.
        if fetches >= inAppMaxFallthroughFetches {
            MarketapLogger.verbose("reached fetch budget (\(inAppMaxFallthroughFetches)), stopping fallthrough")
            return
        }
        if inAppMonotonicNow() >= deadline {
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
                self.show(campaign: fetchedCampaign, fromWebBridge: fromWebBridge)
            } else {
                MarketapLogger.warn("failed to fetch campaign html: \(campaign.id), trying next")
                self.tryShowCampaigns(
                    candidates: candidates, index: index + 1, fetches: fetches + 1, deadline: deadline,
                    eventName: eventName, eventProperties: eventProperties, fromWebBridge: fromWebBridge
                )
            }
        }
    }

    /// 확정된 캠페인을 노출한다(웹브릿지 위임 또는 모달 present).
    ///
    /// 웹브릿지 여부는 **여기서** 판단한다. 예전엔 fetch 를 걸기 전에 스냅샷을 떠서 콜백까지
    /// 들고 갔는데, 그 사이(최대 1초)에 브릿지가 떨어지면 사라진 웹뷰로 보내고 끝났다.
    private func show(campaign: InAppCampaign, fromWebBridge: Bool) {
        if fromWebBridge && MarketapWebBridge.hasActiveWebBridge() {
            // 웹으로 전달하는 순간 소진된 것으로 본다(이후 노출/클릭 이벤트는 웹이 보낸다).
            logImpression(campaignId: campaign.id)
            let messageId = UUID().uuidString
            MarketapWebBridge.sendCampaignToActiveWeb(campaign: campaign, messageId: messageId)
        } else {
            presentCampaignModal(campaign: campaign)
        }
    }

    /// 이 캠페인을 띄울 권리를 원자적으로 선점한다. true 를 받은 쪽만 present 로 간다.
    ///
    /// 아직 웹뷰 로딩 전이면 pendingCampaign 에 적재하고 false 를 준다(로딩이 끝나면
    /// webView(_:didFinish:) 가 다시 이 경로로 태운다).
    private func claimDisplay(campaign: InAppCampaign) -> Bool {
        inAppDisplayLock.lock()
        defer { inAppDisplayLock.unlock() }

        if isModalShown { return false }
        guard didFinishLoad else {
            MarketapLogger.verbose("loading campaign: \(campaign.id)")
            pendingCampaign = campaign
            return false
        }
        isModalShown = true
        return true
    }

    /// 선점했다가 실제로 못 띄웠을 때 되돌린다.
    private func releaseDisplay() {
        inAppDisplayLock.lock()
        isModalShown = false
        inAppDisplayLock.unlock()
    }

    private func presentCampaignModal(campaign: InAppCampaign) {
        guard claimDisplay(campaign: campaign) else { return }

        // 띄우기로 확정된 뒤에 기록한다. 예전엔 present 성공 여부와 무관하게 먼저 찍어서,
        // topViewController 를 못 찾거나 UIKit 이 중복 present 를 거절하면 사용자는 아무것도
        // 못 봤는데 빈도수만 소진됐다(그 캠페인이 이후로 막힘).
        logImpression(campaignId: campaign.id)

        DispatchQueue.main.async {
            self.campaignViewController.campaign = campaign
            if let topViewController = self.getTopViewController() {
                MarketapLogger.verbose("presenting campaign: \(campaign.id)")
                topViewController.present(self.campaignViewController, animated: false) {
                    MarketapLogger.verbose("presented campaign: \(campaign.id)")
                }
            } else {
                MarketapLogger.warn("failed to find topViewController: \(campaign.id)")
                self.releaseDisplay()
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
                    deadline: inAppMonotonicNow() + inAppFallthroughBudgetSeconds,
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
        inAppDisplayLock.lock()
        didFinishLoad = true
        let drained = pendingCampaign
        pendingCampaign = nil
        inAppDisplayLock.unlock()

        if let drained = drained {
            presentCampaignModal(campaign: drained)
        }
    }
}
