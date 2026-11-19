import Foundation
import UIKit

/// 이벤트 하나의 노출 흐름이 시작될 때의 세대. 흐름 도중 사용자 변경·취소 이벤트가 처리되면 낡은 흐름이 된다.
struct InAppEventFlow {
    let identityEpoch: Int
    let abortEpochs: [String: Int]

    func adopting(_ epochs: [String: Int]) -> InAppEventFlow {
        InAppEventFlow(identityEpoch: identityEpoch, abortEpochs: abortEpochs.merging(epochs) { $1 })
    }
}

enum InAppEventFlowValidity {
    case valid
    case campaignAborted
    case identityChanged
}

extension InAppMessageService {

    func bindDelayedInAppCoordinator() {
        let coordinator = delayedInAppCoordinator
        coordinator.isSlotOccupied = { [weak self] slot in
            self?.occupiedSlots().contains(slot) ?? false
        }
        coordinator.executor = { [weak self] ticket, completion in
            guard let self = self else { return completion(.finished) }
            self.executeDelayed(ticket, completion: completion)
        }
        workQueue.async { coordinator.rearm() }
    }

    func matchesAbortCondition(_ conditions: [Condition]?, event: IngestEventRequest) -> Bool {
        guard let conditions = conditions, !conditions.isEmpty else { return false }
        return conditions.contains { isConditionMatched($0, event: event) }
    }

    func currentEventFlow() -> InAppEventFlow {
        flowLock.lock()
        defer { flowLock.unlock() }
        return InAppEventFlow(identityEpoch: identityEpoch, abortEpochs: abortEpochs)
    }

    func validity(of flow: InAppEventFlow, campaignId: String) -> InAppEventFlowValidity {
        flowLock.lock()
        defer { flowLock.unlock() }
        if flow.identityEpoch != identityEpoch { return .identityChanged }
        if flow.abortEpochs[campaignId] != abortEpochs[campaignId] { return .campaignAborted }
        return .valid
    }

    /// 취소 이벤트에 맞는 캠페인의 누적 횟수를 지우고, 그 캠페인을 고르던 진행 중 흐름을 무효로 만든다.
    /// - Returns: 취소한 캠페인의 새 취소 세대.
    @discardableResult
    func abortMatching(campaigns: [InAppCampaign], event: IngestEventRequest) -> [String: Int] {
        let aborted = campaigns.filter { matchesAbortCondition($0.triggerEventCondition.abortConditions, event: event) }
        guard !aborted.isEmpty else { return [:] }
        flowLock.lock()
        var epochs: [String: Int] = [:]
        aborted.forEach {
            abortEpochs[$0.id, default: 0] &+= 1
            epochs[$0.id] = abortEpochs[$0.id]
        }
        flowLock.unlock()
        aborted.forEach { occurrenceEvaluator.reset(campaignId: $0.id) }
        return epochs
    }

    /// 이벤트로 노출 후보를 고른다. 웹 SDK `InAppService.onEvent`와 같은 순서로 거르고, 남은 후보만 횟수를 센다.
    ///
    /// - Parameters:
    ///   - flow: 이벤트 도착 시점에 캡처한 흐름.
    ///   - evaluatedOnArrival: 도착 시점에 이미 취소 조건을 판정한 캠페인 ID. 여기서는 나머지만 판정한다.
    /// - Returns: 도착 이후 사용자가 바뀌었으면 nil.
    func selectCandidates(
        campaigns: [InAppCampaign],
        event: IngestEventRequest,
        flow: InAppEventFlow,
        evaluatedOnArrival: Set<String>
    ) -> (candidates: [InAppCampaign], flow: InAppEventFlow)? {
        if isIdentityChanged(since: flow) { return nil }
        let unevaluated = campaigns.filter { !evaluatedOnArrival.contains($0.id) }
        let flow = flow.adopting(abortMatching(campaigns: unevaluated, event: event))

        let current = now()
        let caps = globalFrequencyCaps
        let countable = campaigns.filter { campaign in
            validity(of: flow, campaignId: campaign.id) == .valid
                && isEventTriggered(condition: campaign.triggerEventCondition, event: event)
                && windowChecker.check(campaign.triggerEventCondition.sendableTimeWindow, now: current)
                && !isCampaignHiden(campaign: campaign)
                && !isTimerExpired(campaign)
                && !delayedInAppCoordinator.isScheduled(campaignId: campaign.id)
                && !globalImpressionLog.isCapped(campaign: campaign, rules: caps, now: current)
        }

        let sessionId = event.properties?["mkt_session_id"]?.value as? String ?? sessionId
        let candidates = countable.filter {
            occurrenceEvaluator.recordAndEvaluate(campaign: $0, sessionId: sessionId)
        }
        return (candidates, flow)
    }

    func isIdentityChanged(since flow: InAppEventFlow) -> Bool {
        flowLock.lock()
        defer { flowLock.unlock() }
        return flow.identityEpoch != identityEpoch
    }

    /// - Parameter origin: 예약을 만든 이벤트의 출처 웹뷰. 실행할 때 아직 살아 있으면 그 출처를 붙여 띄운다.
    /// - Returns: 예약했으면 true. 이미 예약된 캠페인이면 false.
    func scheduleDelayed(
        campaign: InAppCampaign,
        eventName: String,
        eventProperties: [String: Any]?,
        origin: InAppWebOrigin? = nil
    ) -> Bool {
        let scheduled = delayedInAppCoordinator.schedule(
            campaign: campaign,
            eventName: eventName,
            eventProperties: eventProperties?.toAnyCodable(),
            origin: origin
        )
        if scheduled {
            occurrenceEvaluator.reset(campaignId: campaign.id)
        }
        return scheduled
    }

    /// 노출로 기록한다: 캠페인 빈도·전체 빈도 기록, 누적 횟수 초기화.
    func recordExposure(campaign: InAppCampaign, at date: Date = Date()) {
        logImpression(campaignId: campaign.id, at: date)
        let longestRule = globalFrequencyCaps.map { TimeInterval($0.durationMinutes * 60) }.max() ?? 0
        globalImpressionLog.record(
            tagIds: campaign.tagIds ?? [],
            at: date,
            retention: max(longestRule, GlobalImpressionLog.minimumRetention)
        )
        occurrenceEvaluator.reset(campaignId: campaign.id)
    }

    func isTimerExpired(_ campaign: InAppCampaign) -> Bool {
        timerStore.isExpired(campaign: campaign, now: now())
    }

    /// 템플릿에 넘길 타이머 시작 시각. 이미 기록된 시작 시각이 있으면 그것, 없으면 `mountAt`. 타이머가 없으면 nil.
    func timerStart(for campaign: InAppCampaign, mountAt: Date) -> Date? {
        guard let timer = campaign.timer else { return nil }
        guard campaign.isTest != true,
              let start = timerStore.startMillis(campaignId: campaign.id, revision: timer.revision) else { return mountAt }
        return Date(timeIntervalSince1970: start / 1000)
    }

    /// 화면에 붙은 시각을 타이머 시작 시각으로 기록한다. 이미 있으면 두고, 테스트 캠페인은 기록하지 않는다.
    func recordTimerStart(_ campaign: InAppCampaign, at mountAt: Date) {
        guard let timer = campaign.timer, campaign.isTest != true else { return }
        timerStore.recordStartIfAbsent(
            campaignId: campaign.id, revision: timer.revision, nowMillis: mountAt.timeIntervalSince1970 * 1000
        )
    }

    func discardDelayedState() {
        flowLock.lock()
        identityEpoch &+= 1
        flowLock.unlock()
        delayedInAppCoordinator.removeAll()
        occurrenceEvaluator.resetAll()
    }

    /// 예약이 아직 유효한지 보고, 유효하지 않으면 어떻게 끝낼지 알려 준다.
    private func ticketOutcomeIfStale(_ ticket: DelayedInAppTicket) -> DelayedInAppOutcome? {
        switch delayedInAppCoordinator.state(of: ticket) {
        case .valid: return nil
        case .background: return .retryLater
        case .invalidated: return .finished
        }
    }

    /// 예약한 캠페인을 지금 띄우면 안 되는 이유. 예약이 무효이거나 숨김·캠페인 빈도·전체 빈도에 걸리면 결과를 준다.
    private func delayedOutcomeIfBlocked(
        _ ticket: DelayedInAppTicket,
        campaign: InAppCampaign
    ) -> DelayedInAppOutcome? {
        if let outcome = ticketOutcomeIfStale(ticket) { return outcome }
        if isCampaignHiden(campaign: campaign)
            || isTimerExpired(campaign)
            || globalImpressionLog.isCapped(campaign: campaign, rules: globalFrequencyCaps, now: now()) {
            return .finished
        }
        return nil
    }

    private func executeDelayed(
        _ ticket: DelayedInAppTicket,
        completion: @escaping (DelayedInAppOutcome) -> Void
    ) {
        let reservation = ticket.reservation
        fetchCampaigns(inTimeout: { [weak self] campaigns in
            guard let self = self else { return completion(.finished) }
            self.workQueue.async {
                if let outcome = self.ticketOutcomeIfStale(ticket) { return completion(outcome) }
                guard self.isInAppAllowed else { return completion(.finished) }
                guard let campaign = campaigns.first(where: { $0.id == reservation.campaignId }) else {
                    completion(self.hasKnownCampaignList ? .finished : .retryLater)
                    return
                }
                if let outcome = self.delayedOutcomeIfBlocked(ticket, campaign: campaign) {
                    return completion(outcome)
                }
                guard campaign.html == nil else {
                    self.presentDelayed(campaign: campaign, listed: campaign, ticket: ticket, completion: completion)
                    return
                }
                self.fetchCampaign(
                    campaignId: campaign.id,
                    eventName: reservation.triggerEventName,
                    eventProperties: reservation.triggerEventProperties?.compactMapValues { $0.value }
                ) { fetched in
                    self.workQueue.async {
                        if let outcome = self.delayedOutcomeIfBlocked(ticket, campaign: campaign) {
                            return completion(outcome)
                        }
                        guard let fetched = fetched?.inheritingSlot(from: campaign), fetched.html != nil else {
                            completion(.finished)
                            return
                        }
                        self.presentDelayed(campaign: fetched, listed: campaign, ticket: ticket, completion: completion)
                    }
                }
            }
        })
    }

    /// 앱이 띄운다. 예약을 만든 출처 웹뷰가 남아 있으면 즉시 노출과 같은 판정으로 출처를 붙인다.
    ///
    /// - Parameter listed: 목록에서 찾은 캠페인. 태그 등 전체 빈도 판정 정보는 이쪽에 있다.
    private func presentDelayed(
        campaign: InAppCampaign,
        listed: InAppCampaign,
        ticket: DelayedInAppTicket,
        completion: @escaping (DelayedInAppOutcome) -> Void
    ) {
        let hooks = InAppDisplayHooks(
            isStillValid: { [weak self] in
                guard let self = self else { return false }
                return self.delayedOutcomeIfBlocked(ticket, campaign: listed) == nil && self.isAppActiveOnMain()
            },
            onResult: { [weak self] shown in
                guard let self = self else { return completion(.finished) }
                completion(shown ? .finished : self.delayedOutcomeIfBlocked(ticket, campaign: listed) ?? .retryLater)
            }
        )
        let origin = delayedInAppCoordinator.origin(of: ticket)

        DispatchQueue.main.async {
            guard self.isAppActiveOnMain() else { return completion(.retryLater) }
            if let outcome = self.delayedOutcomeIfBlocked(ticket, campaign: listed) { return completion(outcome) }

            switch campaign.slot {
            case .floating:
                if !self.presentFloating(campaign: campaign, origin: origin, hooks: hooks) {
                    completion(.finished)
                }
            case .popup:
                switch self.presentCampaignModal(campaign: campaign, origin: origin, hooks: hooks) {
                case .presenting, .pending:
                    break
                case .occupied:
                    completion(.finished)
                }
            }
        }
    }
}
