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

    /// 팝업이 스스로 닫혔을 때. 숨김을 기록하고 그 권리 번호의 팝업을 내린다.
    func hideCampaign(campaignId: String, until: TimeInterval, claim: Int) {
        MarketapLogger.debug("hide \(campaignId) until: \(until)")
        recordHidden(campaignId: campaignId, until: until)
        finishPopup(claim: claim)
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

    func logImpression(campaignId: String, at date: Date = Date()) {
        let key = "impression_\(campaignId)"
        let now = date.timeIntervalSince1970

        var timestamps = defaults.object(forKey: key) as? [TimeInterval] ?? []
        timestamps.append(now)

        defaults.set(Array(timestamps.suffix(100)), forKey: key)
    }

    /// 후보를 우선순위 순으로 **자리(팝업·플로팅)마다 하나가 뜰 때까지** 시도한다.
    /// 자리가 찬 후보만 건너뛰고 계속 간다(web SDK `handleCampaigns` 와 같은 규칙).
    ///
    /// 상세 fetch 가 빈 응답이면(서버가 노출을 확정 못 한 경우) 다음 후보로 넘어간다.
    /// 상세 fetch 횟수(`inAppMaxFallthroughFetches`)와 전체 시간(`inAppFallthroughBudgetSeconds`)으로 묶는다.
    ///
    /// - Parameter filledSlots: 이 체인에서 이미 처리가 끝난 자리.
    func tryShowCampaigns(
        candidates: [InAppCampaign],
        index: Int,
        fetches: Int,
        deadline: TimeInterval,
        eventName: String,
        eventProperties: [String: Any]?,
        origin: InAppWebOrigin?,
        filledSlots: Set<InAppDisplaySlot> = []
    ) {
        let occupied = filledSlots.union(occupiedSlots())
        if occupied.isSuperset(of: [.popup, .floating]) { return }
        guard index < candidates.count else { return }

        let campaign = candidates[index]
        let next = { (fetches: Int, filled: Set<InAppDisplaySlot>) in
            self.tryShowCampaigns(
                candidates: candidates, index: index + 1, fetches: fetches, deadline: deadline,
                eventName: eventName, eventProperties: eventProperties, origin: origin,
                filledSlots: filled
            )
        }

        if occupied.contains(campaign.slot) || isCampaignHiden(campaign: campaign) {
            next(fetches, filledSlots)
            return
        }

        if campaign.html != nil {
            show(campaign: campaign, origin: origin)
            next(fetches, filledSlots.union([campaign.slot]))
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
            if let fetchedCampaign = fetchedCampaign?.inheritingSlot(from: campaign), fetchedCampaign.html != nil {
                self.show(campaign: fetchedCampaign, origin: origin)
                next(fetches + 1, filledSlots.union([fetchedCampaign.slot]))
            } else {
                MarketapLogger.warn("failed to fetch campaign html: \(campaign.id), trying next")
                next(fetches + 1, filledSlots)
            }
        }
    }

    /// 다른 체인이 이미 차지한 자리. 팝업은 실제로 표시 단계일 때만 찬 것으로 본다.
    /// 적재가 덮어써지지 않는 건 claimDisplay 가 지킨다.
    private func occupiedSlots() -> Set<InAppDisplaySlot> {
        displayLock.lock()
        defer { displayLock.unlock() }
        var slots: Set<InAppDisplaySlot> = []
        if isModalShown && pendingCampaign == nil { slots.insert(.popup) }
        if activeFloating != nil { slots.insert(.floating) }
        return slots
    }

    private func show(campaign: InAppCampaign, origin: InAppWebOrigin?) {
        switch campaign.slot {
        case .floating:
            _ = presentFloating(campaign: campaign, origin: origin)
        case .popup:
            presentCampaignModal(campaign: campaign, origin: origin)
        }
    }

    /// 이 캠페인을 띄울 권리를 원자적으로 선점한다. 권리 번호를 받은 쪽만 present 로 간다.
    ///
    /// 아직 웹뷰가 준비되기 전이면 pendingCampaign 에 적재하고 nil 을 준다(준비되면
    /// `markWebViewReady()` 가 노출로 승격시킨다). **적재도 선점이다** — isModalShown 을
    /// 세워 뒤 이벤트가 앞 후보를 덮어쓰지 못하게 한다. 예전엔 적재 경로가 권리를 안 잡아서,
    /// 앱 시작 직후처럼 웹뷰 초기화가 느릴 때 뒤 이벤트마다 같은 분기를 타며 먼저 도착한
    /// (= 우선순위가 더 높은) 캠페인을 조용히 덮어썼다.
    ///
    /// 적재 선점은 `pendingClaimTimeoutSeconds` 시한을 함께 건다. 시한이 없으면 웹뷰가
    /// 영영 준비되지 않을 때 권리가 잠긴 채로 남아 인앱이 하나도 못 뜬다.
    private func claimDisplay(campaign: InAppCampaign, origin: InAppWebOrigin?) -> Int? {
        displayLock.lock()
        defer { displayLock.unlock() }

        if isShutDown || isModalShown { return nil }

        // 아래 두 갈래 모두 "이 캠페인이 표시 권리를 가져갔다"는 뜻이다.
        isModalShown = true
        displayOrigin = origin
        popupShownAt = nil
        displayClaim &+= 1

        guard didFinishLoad else {
            MarketapLogger.verbose("webView not ready, claiming for pending campaign: \(campaign.id)")
            pendingCampaign = campaign
            pendingGeneration &+= 1
            schedulePendingExpiry(generation: pendingGeneration, campaignId: campaign.id)
            return nil
        }
        return displayClaim
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
            self.releaseDisplayLocked(claim: self.displayClaim)
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
    ///
    /// 같은 권리 번호를 쥔 쪽만 반납한다. 늦게 도착한 이전 팝업의 닫힘 신호가 그 뒤에 선점된 권리를 풀지 않게 한다.
    @discardableResult
    private func releaseDisplay(claim: Int) -> Bool {
        displayLock.lock()
        defer { displayLock.unlock() }
        return releaseDisplayLocked(claim: claim)
    }

    /// `displayLock` 을 쥔 상태에서만 부른다.
    @discardableResult
    private func releaseDisplayLocked(claim: Int) -> Bool {
        guard isModalShown, displayClaim == claim else { return false }
        isModalShown = false
        pendingCampaign = nil
        displayOrigin = nil
        popupShownAt = nil
        pendingGeneration &+= 1
        return true
    }

    /// 화면에 올린 팝업이 이 권리 번호의 것이면 표시 권리를 반납한다.
    @discardableResult
    private func releasePresentedDisplay(ifClaim expectedClaim: Int) -> Bool {
        displayLock.lock()
        defer { displayLock.unlock() }
        guard let claim = presentedClaim, expectedClaim == claim else { return false }
        presentedClaim = nil
        return releaseDisplayLocked(claim: claim)
    }

    private func presentCampaignModal(campaign: InAppCampaign, origin: InAppWebOrigin?) {
        guard let claim = claimDisplay(campaign: campaign, origin: origin) else { return }
        presentClaimed(campaign: campaign, claim: claim)
    }

    /// 표시 권리를 쥔 팝업이 조건에 맞으면 닫는다. 아직 화면에 나타나기 전이면 권리를 반납하고, 떠 있으면 내린다.
    ///
    /// - Parameter shouldClose: 출처 웹뷰와 팝업이 화면에 나타난 시각(나타나기 전이면 nil)을 받는다.
    func closePopup(because cause: String, if shouldClose: (InAppWebOrigin?, TimeInterval?) -> Bool) {
        displayLock.lock()
        guard isModalShown, shouldClose(displayOrigin, popupShownAt) else {
            displayLock.unlock()
            return
        }
        let claim = displayClaim
        if presentedClaim != claim {
            MarketapLogger.verbose("\(cause), dropping popup before it was presented")
            releaseDisplayLocked(claim: claim)
        }
        displayLock.unlock()
        DispatchQueue.main.async {
            guard let popup = self.popupPresentation, popup.claim == claim else { return }
            MarketapLogger.verbose("\(cause), closing popup: \(popup.campaignId)")
            self.finishPopup(claim: claim)
        }
    }

    /// 이미 표시 권리를 쥔 상태에서 팝업 창을 띄운다. 선점 없이 호출하면 안 된다.
    private func presentClaimed(campaign: InAppCampaign, claim: Int) {
        DispatchQueue.main.async {
            guard self.beginPresenting(claim: claim) else {
                MarketapLogger.verbose("display claim was released before popup was presented: \(campaign.id)")
                return
            }
            self.displayLock.lock()
            if let origin = self.displayOrigin, !origin.isWebViewVisible {
                MarketapLogger.verbose("origin web view left before popup was presented: \(campaign.id)")
                self.displayOrigin = nil
            }
            self.displayLock.unlock()

            guard let target = self.makePopupTarget() else {
                MarketapLogger.warn("failed to find app window: \(campaign.id)")
                self.releasePresentedDisplay(ifClaim: claim)
                return
            }

            let controller = self.campaignViewController
            controller.load(campaign: campaign, claim: claim, appWindow: target.appWindow)
            let popup = InAppPopupPresentation(
                claim: claim,
                campaignId: campaign.id,
                target: target,
                content: controller
            ) { [weak self] finished in
                guard let self = self else { return }
                if self.popupPresentation === finished {
                    self.popupPresentation = nil
                }
                self.releasePresentedDisplay(ifClaim: finished.claim)
            }
            self.popupPresentation = popup
            popup.show()
            MarketapLogger.verbose("presented campaign: \(campaign.id)")
            self.markPopupShown(claim: claim)
            self.logImpression(campaignId: campaign.id)
            self.onImpression(campaign: campaign, messageId: controller.messageId)
        }
    }

    /// 이 권리 번호의 팝업이 떠 있으면 내린다. 메인 스레드에서만 부른다.
    func finishPopup(claim: Int) {
        popupPresentation?.finish(claim: claim)
    }

    /// 서비스를 버리기 전에 떠 있는 팝업을 내리고, 아직 화면에 오르지 않은 팝업과 이후 표시 요청은 버린다. 어느 스레드에서 불러도 된다.
    func shutdown() {
        displayLock.lock()
        isShutDown = true
        if isModalShown, presentedClaim == nil {
            releaseDisplayLocked(claim: displayClaim)
        }
        displayLock.unlock()
        let finish = {
            guard let popup = self.popupPresentation else { return }
            self.finishPopup(claim: popup.claim)
        }
        if Thread.isMainThread {
            finish()
        } else {
            DispatchQueue.main.async(execute: finish)
        }
    }

    /// 표시 권리가 아직 이 번호의 것이면 화면에 올리는 중으로 표시한다.
    private func beginPresenting(claim: Int) -> Bool {
        displayLock.lock()
        defer { displayLock.unlock() }
        guard !isShutDown, isModalShown, displayClaim == claim else { return false }
        presentedClaim = claim
        return true
    }

    private func markPopupShown(claim: Int) {
        displayLock.lock()
        if isModalShown, displayClaim == claim {
            popupShownAt = monotonicNow()
        }
        displayLock.unlock()
    }

    func onEvent(eventRequest: IngestEventRequest, origin: InAppWebOrigin?) {
        if let origin = origin, PageFloatingPolicy.eventLeavesPage(eventName: eventRequest.name) {
            originDidLeavePage(ObjectIdentifier(origin))
        }
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
                    origin: origin
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

    func onClick(campaign: InAppCampaign, locationId: String, messageId: String, url: String?, claim: Int) {
        displayLock.lock()
        let origin = displayClaim == claim ? displayOrigin : nil
        displayLock.unlock()
        onClick(campaign: campaign, locationId: locationId, messageId: messageId, url: url, origin: origin, closingPopup: claim)
    }

    /// - Parameter closingPopup: 링크를 출처 웹뷰에서 열 때 먼저 내릴 팝업의 표시 권리 번호.
    func onClick(
        campaign: InAppCampaign,
        locationId: String,
        messageId: String,
        url: String?,
        origin: InAppWebOrigin?,
        closingPopup: Int?
    ) {
        MarketapLogger.debug("onClick: \(url ?? "null")")
        routeClick(MarketapClickEvent(campaignType: .inAppMessage, campaignId: campaign.id, url: url), origin: origin, closingPopup: closingPopup)

        let props = InAppEventBuilder.clickEventProperties(
            campaignId: campaign.id,
            messageId: messageId,
            locationId: locationId,
            url: url,
            layoutSubType: campaign.layout.layoutSubType
        )
        delegate?.trackEvent(eventName: "mkt_click_message", eventProperties: props)
    }

    /// 출처 웹뷰가 화면에 있고 웹 클릭 처리 설정이 켜져 있으면 링크를 그 웹뷰에서 연다. 팝업은 닫은 뒤 연다.
    func routeClick(_ event: MarketapClickEvent, origin: InAppWebOrigin?, closingPopup: Int?) {
        let route = {
            let settings = self.clickRoutingSettings()
            let decision = InAppClickRoute.of(
                url: event.url,
                customized: settings.customized,
                useWebClickRouting: settings.useWebClickRouting,
                originVisible: origin?.isWebViewVisible ?? false
            )
            guard decision == .webView, let origin = origin, let url = event.url else {
                self.customHandlerStore.handleClick(event)
                return
            }
            MarketapLogger.debug("opening in-app click in origin web view: \(url)")
            if let claim = closingPopup {
                self.finishPopup(claim: claim)
            }
            origin.openInWebView(url: url)
        }
        if Thread.isMainThread {
            route()
        } else {
            DispatchQueue.main.async(execute: route)
        }
    }

    func onTrack(campaign: InAppCampaign, eventName: String, properties: [String: Any]?) {
        delegate?.trackEvent(eventName: eventName, eventProperties: properties)
    }

    func onSetUserProperties(properties: [String: Any]) {
        delegate?.setUserProperties(userProperties: properties)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let controller = campaignViewController
        guard webView === controller.webView else { return }
        controller.documentDidCommit(navigation)
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

    /// 웹 콘텐츠 프로세스가 죽었다. 그 웹뷰에 문서가 올라가 있던 팝업은 JS 로 닫을 수 없으므로 내리고, 껍데기를 다시 올린다.
    /// 메인 스레드에서 불린다.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MarketapLogger.warn("in-app webView content process terminated")

        let controller = campaignViewController
        if let claim = controller.claim {
            finishPopup(claim: claim)
        }
        controller.reloadShell()

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
        let claim = displayClaim
        pendingCampaign = nil
        if drained != nil {
            // 시한 타이머가 뒤늦게 떠서 승격된 권리를 풀어버리지 않도록 세대를 넘긴다.
            pendingGeneration &+= 1
        }
        displayLock.unlock()

        guard let drained = drained else { return }

        // 적재와 승격 사이는 최대 pendingClaimTimeoutSeconds 다. 그 사이에 같은 캠페인이
        // 웹브릿지로 전달돼 빈도수를 채웠거나 사용자가 다른 경로에서 "하루 보지 않기" 로
        // 닫았을 수 있다. 적재 시점의 판정을 그대로 믿으면 방금 끈 팝업이 다시 뜬다.
        if isCampaignHiden(campaign: drained) {
            MarketapLogger.verbose("pending campaign became hidden before promotion: \(drained.id)")
            releaseDisplay(claim: claim)
            return
        }

        presentClaimed(campaign: drained, claim: claim)
    }

    /// 적재된 후보를 버리고 표시 권리를 반납한다.
    ///
    /// 신원(userId)이 바뀌면 이전 신원으로 고른 후보는 더 이상 맞지 않는다. 예전에는 적재가
    /// 권리를 안 잡아서 뒤 이벤트가 알아서 덮어썼지만, 이제는 적재가 권리를 쥐므로 명시적으로
    /// 버려주지 않으면 로그인 전 캠페인이 로그인 후에 뜨고 그동안 올바른 후보는 막힌다.
    func discardPendingCampaign() {
        displayLock.lock()
        let discarded = pendingCampaign
        if discarded != nil {
            releaseDisplayLocked(claim: displayClaim)
        }
        displayLock.unlock()

        guard let discarded = discarded else { return }
        MarketapLogger.verbose("discarding pending campaign after identity change: \(discarded.id)")
    }
}
