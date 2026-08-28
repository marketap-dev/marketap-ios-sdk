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

    /// 네이티브 모달을 닫았을 때. 숨김 기록 + 표시 권리 반납.
    func hideCampaign(campaignId: String, until: TimeInterval) {
        MarketapLogger.debug("hide \(campaignId) until: \(until)")
        releaseDisplay()
        recordHidden(campaignId: campaignId, until: until)
    }

    /// 숨김 기록만 남긴다(표시 상태는 건드리지 않는다).
    ///
    /// 웹브릿지·플러그인 경로용. 거기서 닫힌 건 우리 네이티브 모달이 아니라 호스트 앱
    /// 웹뷰가 띄운 것이라, 여기서 표시 권리까지 반납하면 실제로 떠 있는 네이티브 모달 위에
    /// 다른 캠페인이 올라올 수 있다.
    func recordHidden(campaignId: String, until: TimeInterval) {
        guard until > 0 else { return }
        defaults.set(Date().timeIntervalSince1970 + until, forKey: "hide_campaign_\(campaignId)")
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
        displayLock.lock()
        let alreadyShown = isModalShown
        displayLock.unlock()
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
    /// 아직 웹뷰가 준비되기 전이면 pendingCampaign 에 적재하고 false 를 준다(준비되면
    /// `markWebViewReady()` 가 노출로 승격시킨다). **적재도 선점이다** — isModalShown 을
    /// 세워 뒤 이벤트가 앞 후보를 덮어쓰지 못하게 한다. 예전엔 적재 경로가 권리를 안 잡아서,
    /// 앱 시작 직후처럼 웹뷰 초기화가 느릴 때 뒤 이벤트마다 같은 분기를 타며 먼저 도착한
    /// (= 우선순위가 더 높은) 캠페인을 조용히 덮어썼다.
    ///
    /// 적재 선점은 `pendingClaimTimeoutSeconds` 시한을 함께 건다. 시한이 없으면 웹뷰가
    /// 영영 준비되지 않을 때 권리가 잠긴 채로 남아 인앱이 하나도 못 뜬다.
    private func claimDisplay(campaign: InAppCampaign) -> Bool {
        displayLock.lock()
        defer { displayLock.unlock() }

        if isModalShown { return false }

        // 아래 두 갈래 모두 "이 캠페인이 표시 권리를 가져갔다"는 뜻이다.
        isModalShown = true

        guard didFinishLoad else {
            MarketapLogger.verbose("webView not ready, claiming for pending campaign: \(campaign.id)")
            pendingCampaign = campaign
            pendingGeneration &+= 1
            schedulePendingExpiry(generation: pendingGeneration, campaignId: campaign.id)
            return false
        }
        return true
    }

    /// 적재 선점에 시한을 건다. 시한이 지나도 여전히 같은 적재가 남아 있으면 권리를 반납해
    /// 이후 이벤트가 다시 시도할 수 있게 한다(이벤트 하나는 잃지만 영구 무노출은 막는다).
    private func schedulePendingExpiry(generation: Int, campaignId: String) {
        let timeout = pendingClaimTimeoutSeconds
        // .userInitiated: 이 타이머가 늦으면 그동안 인앱이 하나도 안 뜬다.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self else { return }

            self.displayLock.lock()
            // 세대가 다르면 이미 승격됐거나 반납된 뒤다 — 남의 선점을 풀면 안 된다.
            guard self.pendingGeneration == generation, self.pendingCampaign != nil else {
                self.displayLock.unlock()
                return
            }
            self.pendingCampaign = nil
            self.isModalShown = false
            self.displayLock.unlock()

            // verbose 가 아니라 warn 이다. 이 상태는 웹뷰가 준비되지 않았다는 진단 신호다.
            MarketapLogger.warn(
                "webView not ready within \(timeout)s, dropping pending campaign: \(campaignId)"
            )
        }
    }

    /// 선점했다가 실제로 못 띄웠을 때 되돌린다.
    ///
    /// 적재도 같이 버린다. 불변식(`pendingCampaign != nil` → `isModalShown == true`)을 지키려면
    /// 권리를 놓는 순간 적재도 없어야 한다. 남겨두면 나중에 웹뷰가 준비됐을 때 이미 놓은
    /// 권리로 캠페인이 뜬다.
    private func releaseDisplay() {
        displayLock.lock()
        isModalShown = false
        pendingCampaign = nil
        pendingGeneration &+= 1
        displayLock.unlock()
    }

    private func presentCampaignModal(campaign: InAppCampaign) {
        guard claimDisplay(campaign: campaign) else { return }
        presentClaimed(campaign: campaign)
    }

    /// 이미 표시 권리를 쥔 상태에서 실제 present 를 수행한다. 선점 없이 호출하면 안 된다.
    private func presentClaimed(campaign: InAppCampaign) {
        DispatchQueue.main.async {
            self.campaignViewController.campaign = campaign
            guard let topViewController = self.getTopViewController() else {
                MarketapLogger.warn("failed to find topViewController: \(campaign.id)")
                self.releaseDisplay()
                return
            }

            MarketapLogger.verbose("presenting campaign: \(campaign.id)")
            topViewController.present(self.campaignViewController, animated: false) {
                MarketapLogger.verbose("presented campaign: \(campaign.id)")
                // 화면에 실제로 올라간 뒤에 기록한다. present 가 거절되면 이 블록은 안 불리고,
                // 그러면 빈도수도 소진되지 않아야 한다(안 본 캠페인이 막히면 안 된다).
                self.logImpression(campaignId: campaign.id)
            }

            // UIKit 은 present 를 조용히 거절할 수 있다(이미 present 중, 전환 중, 뷰가 아직
            // 윈도우에 없음). 그때는 completion 도 viewDidDisappear 도 안 불려서, 선점이
            // 영구히 남고 이후 인앱이 하나도 안 뜬다. 실제로 올라갔는지 확인해 되돌린다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.campaignViewController.presentingViewController == nil else { return }
                MarketapLogger.warn("presentation was refused: \(campaign.id)")
                self.releaseDisplay()
            }
        }
    }

    /// 모달이 내려갔다. hideCampaign(JS 의 "오늘 하루 보지 않기" 등)을 거치지 않고 닫히는
    /// 경로가 있어서 여기서도 표시 권리를 되돌린다. 중복 해제는 무해하다.
    func onDismissed() {
        releaseDisplay()
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
        markWebViewReady()
    }

    /// 초기 blank 로드가 서버에 닿기도 전에 실패한 경우.
    ///
    /// 예전엔 이 콜백이 없어서 `didFinishLoad` 가 영영 false 로 남았고, 그 뒤로 **어떤
    /// 인앱도 뜨지 못했다**. 초기 로드는 껍데기일 뿐이고 실제 노출은 새 loadHTMLString 을
    /// 걸기 때문에, 실패도 "웹뷰 준비 완료"로 처리해 적재된 후보를 그대로 승격시킨다.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MarketapLogger.warn("in-app webView provisional navigation failed: \(error.localizedDescription)")
        markWebViewReady()
    }

    /// 네비게이션이 시작된 뒤 실패한 경우. 처리는 didFailProvisionalNavigation 과 같다.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MarketapLogger.warn("in-app webView navigation failed: \(error.localizedDescription)")
        markWebViewReady()
    }

    /// 웹 콘텐츠 프로세스가 죽었다. 화면은 빈 껍데기가 되고 JS 도 안 돈다.
    ///
    /// 떠 있는 모달이 있으면 닫기 버튼조차 JS 라 사용자가 닫을 수단이 없다 — 표시 권리가
    /// 영구히 잠겨 이후 인앱이 하나도 안 뜬다. 내려서 권리를 반납하고(viewDidDisappear →
    /// onDismissed), 껍데기를 다시 올려 다음 노출에 쓸 수 있게 한다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MarketapLogger.warn("in-app webView content process terminated")

        DispatchQueue.main.async {
            if self.campaignViewController.presentingViewController != nil {
                self.campaignViewController.dismiss(animated: false)
            }
            self.campaignViewController.reloadShell()
        }

        markWebViewReady()
    }

    /// 웹뷰가 노출에 쓸 수 있는 상태가 됐다고 표시하고, 적재된 후보가 있으면 노출로 승격한다.
    ///
    /// 승격은 표시 권리를 **놓지 않고** 이어간다. 적재 시점에 이미 선점했으므로 여기서 다시
    /// claimDisplay 를 타면 자기 자신이 잡은 권리에 막혀 영영 못 뜬다.
    private func markWebViewReady() {
        displayLock.lock()
        didFinishLoad = true
        let drained = pendingCampaign
        pendingCampaign = nil
        if drained != nil {
            // 시한 타이머가 뒤늦게 떠서 승격된 권리를 풀어버리지 않도록 세대를 넘긴다.
            pendingGeneration &+= 1
        }
        displayLock.unlock()

        if let drained = drained {
            presentClaimed(campaign: drained)
        }
    }
}
