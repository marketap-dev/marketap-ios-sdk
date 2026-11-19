import XCTest
import UIKit
import WebKit
@testable import MarketapSDK

final class ManualDelayScheduler: InAppDelayScheduler {
    final class Timer: InAppDelayTimer {
        let fireAt: TimeInterval
        let block: () -> Void
        var isCancelled = false
        init(fireAt: TimeInterval, block: @escaping () -> Void) {
            self.fireAt = fireAt
            self.block = block
        }
        func cancel() { isCancelled = true }
    }

    private let clock: TestClock
    private let lock = NSLock()
    private var timers: [Timer] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return timers.filter { !$0.isCancelled }.count
    }

    func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> InAppDelayTimer {
        let timer = Timer(fireAt: clock.now.timeIntervalSince1970 + max(seconds, 0), block: block)
        lock.lock(); timers.append(timer); lock.unlock()
        return timer
    }

    func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        let now = clock.now.timeIntervalSince1970
        lock.lock()
        let due = timers.filter { !$0.isCancelled && $0.fireAt <= now }
        timers.removeAll { timer in due.contains { $0 === timer } || timer.isCancelled }
        lock.unlock()
        due.forEach { $0.block() }
    }
}

final class DelayOrigin: InAppWebOrigin {
    private let lock = NSLock()
    private var _visibilityChecks = 0
    var visible = true

    var visibilityChecks: Int { lock.lock(); defer { lock.unlock() }; return _visibilityChecks }

    var isWebViewVisible: Bool {
        lock.lock(); _visibilityChecks += 1; lock.unlock()
        return visible
    }
    func openInWebView(url: String) {}
    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool { visible }
    func endWatchingWindow(owner: AnyObject) {}
}

extension InAppMessageService {
    var isFloatingClaimed: Bool {
        displayLock.lock()
        defer { displayLock.unlock() }
        return activeFloating != nil
    }
}

private func event(_ name: String, sessionId: String = "s1") -> IngestEventRequest {
    IngestEventRequest(
        id: nil, name: name, userId: nil,
        device: MockMarketapCache().device.makeRequest(),
        properties: ["mkt_session_id": AnyCodable(sessionId)],
        timestamp: Date()
    )
}

final class DelayedInAppCoordinatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: TestClock!
    private var scheduler: ManualDelayScheduler!
    private var coordinator: DelayedInAppCoordinator!
    private var executed: [String] = []
    private var outcome: DelayedInAppOutcome = .finished
    private var occupied: Set<InAppDisplaySlot> = []
    private var holdExecution = false
    private var held: [(DelayedInAppTicket, (DelayedInAppOutcome) -> Void)] = []

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults(self)
        clock = TestClock()
        scheduler = ManualDelayScheduler(clock: clock)
        coordinator = makeCoordinator(foreground: true)
    }

    private func makeCoordinator(foreground: Bool) -> DelayedInAppCoordinator {
        let clock = self.clock!
        let coordinator = DelayedInAppCoordinator(
            defaults: defaults, now: { clock.now }, scheduler: scheduler, isForeground: foreground
        )
        coordinator.executor = { [unowned self] ticket, completion in
            self.executed.append(ticket.reservation.campaignId)
            if self.holdExecution {
                self.held.append((ticket, completion))
            } else {
                completion(self.outcome)
            }
        }
        coordinator.isSlotOccupied = { [unowned self] in self.occupied.contains($0) }
        return coordinator
    }

    private func schedule(_ campaign: InAppCampaign) -> Bool {
        coordinator.schedule(campaign: campaign, eventName: "mkt_home_view", eventProperties: nil)
    }

    func testFiresAtDueTimeInForeground() {
        XCTAssertTrue(schedule(triggerCampaign("a", delaySeconds: 30)))
        scheduler.advance(29)
        XCTAssertEqual(executed, [])
        scheduler.advance(1)
        XCTAssertEqual(executed, ["a"])
        XCTAssertTrue(coordinator.reservations.isEmpty)
    }

    func testOneReservationPerCampaign() {
        XCTAssertTrue(schedule(triggerCampaign("a", delaySeconds: 30)))
        XCTAssertFalse(schedule(triggerCampaign("a", delaySeconds: 30)))
        XCTAssertFalse(schedule(triggerCampaign("b")))
        XCTAssertEqual(coordinator.reservations.map(\.campaignId), ["a"])
    }

    func testBackgroundHoldsUntilForeground() {
        _ = schedule(triggerCampaign("a", delaySeconds: 30))
        coordinator.setForeground(false)
        scheduler.advance(60)
        XCTAssertEqual(executed, [])
        XCTAssertTrue(coordinator.isScheduled(campaignId: "a"))

        coordinator.setForeground(true)
        scheduler.advance(0)
        XCTAssertEqual(executed, ["a"])
    }

    func testExpiredReservationIsDroppedOnReturn() {
        _ = schedule(triggerCampaign("a", delaySeconds: 30))
        coordinator.setForeground(false)
        scheduler.advance(30 + DelayedInAppCoordinator.reservationTTL)
        coordinator.setForeground(true)
        scheduler.advance(0)
        XCTAssertEqual(executed, [])
        XCTAssertTrue(coordinator.reservations.isEmpty)
    }

    func testRestoresAfterRestart() {
        _ = schedule(triggerCampaign("a", delaySeconds: 30))
        coordinator = nil
        scheduler = ManualDelayScheduler(clock: clock)
        clock.advance(120)

        coordinator = makeCoordinator(foreground: false)
        coordinator.rearm()
        coordinator.setForeground(true)
        scheduler.advance(0)
        XCTAssertEqual(executed, ["a"])
    }

    func testOriginIsKeptInMemoryOnly() {
        let origin = DelayOrigin()
        holdExecution = true
        _ = coordinator.schedule(
            campaign: triggerCampaign("a", delaySeconds: 30), eventName: "mkt_home_view", eventProperties: nil, origin: origin
        )
        scheduler.advance(30)
        XCTAssertTrue(held.first.flatMap { coordinator.origin(of: $0.0) } === origin)

        held = []
        coordinator = makeCoordinator(foreground: true)
        coordinator.rearm()
        scheduler.advance(0)
        XCTAssertEqual(held.count, 1)
        XCTAssertNil(held.first.flatMap { coordinator.origin(of: $0.0) }, "다시 시작해 복원한 예약에는 출처가 없다")
    }

    func testReleasedOriginIsNotRetained() {
        var origin: DelayOrigin? = DelayOrigin()
        holdExecution = true
        _ = coordinator.schedule(
            campaign: triggerCampaign("a", delaySeconds: 30), eventName: "mkt_home_view", eventProperties: nil, origin: origin
        )
        weak var released = origin
        origin = nil
        XCTAssertNil(released)
        scheduler.advance(30)
        XCTAssertNil(held.first.flatMap { coordinator.origin(of: $0.0) })
    }

    func testAbortSnapshotCancelsWithoutCampaignList() {
        _ = schedule(triggerCampaign("a", delaySeconds: 30, abort: ["mkt_purchase"]))
        _ = schedule(triggerCampaign("b", delaySeconds: 30))
        coordinator.cancelMatching { conditions in conditions.contains { $0.eventFilter.eventName == "mkt_purchase" } }
        XCTAssertEqual(coordinator.reservations.map(\.campaignId), ["b"])
        scheduler.advance(30)
        XCTAssertEqual(executed, ["b"])
    }

    func testSameSlotOccupiedDropsButOtherSlotRuns() {
        _ = schedule(triggerCampaign("popup", delaySeconds: 30))
        _ = schedule(triggerCampaign("floating", delaySeconds: 30, slot: .floating))
        occupied = [.popup]
        scheduler.advance(30)
        XCTAssertEqual(executed, ["floating"])
        XCTAssertTrue(coordinator.reservations.isEmpty)
    }

    func testRetryLaterKeepsReservationUntilExpiry() {
        outcome = .retryLater
        _ = schedule(triggerCampaign("a", delaySeconds: 30))
        scheduler.advance(30)
        XCTAssertEqual(executed, ["a"])
        XCTAssertTrue(coordinator.isScheduled(campaignId: "a"))

        scheduler.advance(DelayedInAppCoordinator.retryInterval)
        XCTAssertEqual(executed, ["a", "a"])

        scheduler.advance(DelayedInAppCoordinator.reservationTTL)
        XCTAssertFalse(coordinator.isScheduled(campaignId: "a"))
    }

    func testRemoveAllCancelsTimers() {
        _ = schedule(triggerCampaign("a", delaySeconds: 30))
        coordinator.removeAll()
        scheduler.advance(30)
        XCTAssertEqual(executed, [])
        XCTAssertTrue(coordinator.reservations.isEmpty)
    }
}

extension DelayedInAppCoordinatorTests {
    func testCancelDuringExecutionInvalidatesTicket() {
        holdExecution = true
        _ = schedule(triggerCampaign("a", delaySeconds: 30, abort: ["mkt_purchase"]))
        scheduler.advance(30)
        let (ticket, completion) = held[0]
        XCTAssertEqual(coordinator.state(of: ticket), .valid)

        coordinator.cancelMatching { $0.contains { $0.eventFilter.eventName == "mkt_purchase" } }
        XCTAssertEqual(coordinator.state(of: ticket), .invalidated)
        completion(.retryLater)
        XCTAssertTrue(coordinator.reservations.isEmpty)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testRemoveAllInvalidatesRunningTicket() {
        holdExecution = true
        _ = schedule(triggerCampaign("a", delaySeconds: 30))
        scheduler.advance(30)
        coordinator.removeAll()
        XCTAssertEqual(coordinator.state(of: held[0].0), .invalidated)
    }

    func testBackgroundDuringExecutionKeepsReservationAndRerunsOnReturn() {
        holdExecution = true
        _ = schedule(triggerCampaign("a", delaySeconds: 30))
        scheduler.advance(30)
        let (ticket, completion) = held[0]

        coordinator.setForeground(false)
        XCTAssertEqual(coordinator.state(of: ticket), .background)
        completion(.retryLater)
        XCTAssertTrue(coordinator.isScheduled(campaignId: "a"))

        coordinator.setForeground(true)
        scheduler.advance(0)
        XCTAssertEqual(executed, ["a", "a"])
        XCTAssertEqual(coordinator.state(of: ticket), .invalidated)
        XCTAssertEqual(coordinator.state(of: held[1].0), .valid)
        held[1].1(.finished)
        XCTAssertTrue(coordinator.reservations.isEmpty)
    }
}

final class InAppTriggerFlowTests: XCTestCase {
    private var service: InAppMessageService!
    private var api: NoopAPIForTriggerFlow!
    private var defaults: UserDefaults!
    private var clock: TestClock!
    private var scheduler: ManualDelayScheduler!
    private var canAttachFloating = true

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults(self)
        clock = TestClock(Date())
        scheduler = ManualDelayScheduler(clock: clock)
        let clock = self.clock!
        api = NoopAPIForTriggerFlow()
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: api,
            cache: MockMarketapCache(), defaults: defaults,
            now: { clock.now }, delayScheduler: scheduler, observesAppLifecycle: false
        )
        service.pendingClaimTimeoutSeconds = 600
        service.delayedInAppCoordinator.setForeground(true)
        service.isAppActiveOnMain = { true }
        service.floatingPresenter = FloatingPresenter(makeWindow: { [weak self] container in
            guard self?.canAttachFloating == true else { return nil }
            return FloatingWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844), container: container)
        })
    }

    override func tearDown() {
        if let popup = service.popupPresentation {
            service.finishPopup(claim: popup.claim)
        }
        service.floatingPresenter.dismiss()
        service = nil
        defaults = nil
        scheduler = nil
        clock = nil
        super.tearDown()
    }

    private func setCampaigns(_ campaigns: [InAppCampaign]) {
        service.lastFetch = Date()
        service.campaigns = campaigns
    }

    private func send(_ name: String = "mkt_home_view", sessionId: String = "s1", origin: InAppWebOrigin? = nil) {
        service.onEvent(eventRequest: event(name, sessionId: sessionId), origin: origin)
        service.workQueue.sync {}
    }

    func testREG10_CampaignWithoutConditionsShowsImmediately() {
        setCampaigns([triggerCampaign("a")])
        send()
        XCTAssertTrue(service.isModalShown)
    }

    func testOccurrenceCountGatesShow() {
        setCampaigns([triggerCampaign("a", occurrence: OccurrenceCondition(count: 2))])
        send()
        XCTAssertFalse(service.isModalShown)
        send()
        XCTAssertTrue(service.isModalShown)
    }

    func testD10_HiddenCampaignDoesNotAccumulateCount() {
        setCampaigns([triggerCampaign("a", occurrence: OccurrenceCondition(count: 2))])
        service.recordHidden(campaignId: "a", until: 3600)
        send()
        send()
        defaults.removeObject(forKey: "hide_campaign_a")
        send()
        XCTAssertFalse(service.isModalShown)
    }

    func testD10_FrequencyCappedCampaignDoesNotAccumulateCount() {
        setCampaigns([
            triggerCampaign("a", occurrence: OccurrenceCondition(count: 2), frequencyCap: FrequencyCap(limit: 1, durationMinutes: 1))
        ])
        service.logImpression(campaignId: "a", at: Date())
        send()
        send()
        defaults.removeObject(forKey: "impression_a")
        send()
        XCTAssertFalse(service.isModalShown)
    }

    func testOrConditionsCountTogetherTowardOccurrence() {
        setCampaigns([
            triggerCampaign("a", eventName: "mkt_cart", occurrence: OccurrenceCondition(count: 2), orEventNames: ["mkt_cart", "mkt_wish"])
        ])
        send("mkt_cart")
        XCTAssertFalse(service.isModalShown)
        send("mkt_other")
        XCTAssertFalse(service.isModalShown, "어느 조건에도 맞지 않는 이벤트는 세지 않는다")
        send("mkt_wish")
        XCTAssertTrue(service.isModalShown, "서로 다른 조건의 이벤트도 함께 센다")
    }

    func testOrConditionWhileDelayedDoesNotReserveTwice() {
        setCampaigns([
            triggerCampaign("a", eventName: "mkt_cart", delaySeconds: 30, orEventNames: ["mkt_cart", "mkt_wish"])
        ])
        send("mkt_cart")
        let first = service.delayedInAppCoordinator.reservations
        XCTAssertEqual(first.count, 1)

        send("mkt_wish")
        XCTAssertEqual(service.delayedInAppCoordinator.reservations, first, "지연 예약 중에는 다른 조건 이벤트로 다시 예약하지 않는다")
        XCTAssertNil(defaults.data(forKey: OccurrenceConditionEvaluator.nonWindowedKeyPrefix + "a"))
    }

    func testShutdownStopsReservationsButKeepsThemForNextInstance() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        service.shutdown()
        scheduler.advance(30)
        drain()
        XCTAssertFalse(service.isModalShown)
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))
        XCTAssertFalse(service.delayedInAppCoordinator.schedule(
            campaign: triggerCampaign("b", delaySeconds: 30), eventName: "mkt_home_view", eventProperties: nil
        ))
    }

    func testDelayedCandidateIsReservedNotShownAndCountReset() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30, occurrence: OccurrenceCondition(count: 1))])
        send()
        XCTAssertFalse(service.isModalShown)
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))
        XCTAssertNil(defaults.data(forKey: OccurrenceConditionEvaluator.nonWindowedKeyPrefix + "a"))

        send()
        XCTAssertEqual(service.delayedInAppCoordinator.reservations.count, 1)
    }

    func testD14_4_DelayedPopupDoesNotBlockFloatingOrBlocksLowerPopup() {
        setCampaigns([
            triggerCampaign("delayed", delaySeconds: 30),
            triggerCampaign("popup"),
            triggerCampaign("floating", slot: .floating)
        ])
        send()
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "delayed"))
        XCTAssertFalse(service.isModalShown)
        XCTAssertTrue(service.isFloatingClaimed)
    }

    func testDelayedReservationShowsAtDueTime() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }
        XCTAssertEqual(service.delayedInAppCoordinator.reservations.count, 1)

        service.makePopupTarget = makeTestPopupTarget
        promotePending()
        XCTAssertEqual(service.popupPresentation?.campaignId, "a", "즉시 노출과 같은 팝업 창으로 띄운다")
        waitUntil(self, "띄우면 예약을 끝낸다") { [service] in service!.delayedInAppCoordinator.reservations.isEmpty }
        XCTAssertEqual((defaults.object(forKey: "impression_a") as? [TimeInterval])?.count, 1)
    }

    func testPopupWindowFailureKeepsReservationForRetry() {
        service.makePopupTarget = { nil }
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }

        promotePending()
        waitUntil(self, "팝업 창을 못 띄우면 예약을 남겨 재시도한다") { [service, scheduler] in
            !service!.isModalShown && scheduler!.pendingCount == 1
        }
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))
        XCTAssertNil(defaults.object(forKey: "impression_a"))
    }

    func testDelayedPopupCarriesOriginIntoPresentVisibilityCheck() {
        let origin = DelayOrigin()
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send(origin: origin)
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }
        XCTAssertTrue(service.displayOrigin === origin, "예약을 만든 이벤트의 출처로 표시 권리를 잡는다")

        service.makePopupTarget = makeTestPopupTarget
        promotePending()
        XCTAssertEqual(origin.visibilityChecks, 1, "즉시 노출과 같은 표시 직전 보임 판정을 거친다")
        XCTAssertEqual(service.popupPresentation?.campaignId, "a")
        XCTAssertTrue(service.displayOrigin === origin, "보이는 출처는 그대로 붙인다")
    }

    func testDelayedPopupDropsOriginThatIsNoLongerVisible() {
        let origin = DelayOrigin()
        service.makePopupTarget = makeTestPopupTarget
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send(origin: origin)
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }

        origin.visible = false
        promotePending()
        XCTAssertEqual(service.popupPresentation?.campaignId, "a", "앱에서 뜬 메시지로 띄운다")
        XCTAssertNil(service.displayOrigin)
    }

    func testDelayedPopupWithReleasedOriginShowsWithoutOrigin() {
        var origin: DelayOrigin? = DelayOrigin()
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send(origin: origin)
        weak var released = origin
        origin = nil
        XCTAssertNil(released)

        scheduler.advance(30)
        waitUntil(self, "출처 없이 적재된다") { [service] in service!.pendingCampaign?.id == "a" }
        XCTAssertNil(service.displayOrigin)
    }

    func testDelayedFloatingCarriesOrigin() {
        let origin = DelayOrigin()
        setCampaigns([triggerCampaign("f", delaySeconds: 30, slot: .floating)])
        send(origin: origin)
        scheduler.advance(30)
        waitUntil(self, "플로팅이 붙는다") { [service] in service!.activeFloating?.campaign.id == "f" }
        XCTAssertTrue(service.activeFloating?.origin === origin)
    }

    func testScreenAndOriginSignalsKeepWaitingReservation() {
        let origin = DelayOrigin()
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send(origin: origin)

        service.monotonicNow = { ProcessInfo.processInfo.systemUptime + 1 }
        service.screenChanged()
        service.originDidLeavePage(ObjectIdentifier(origin))
        service.originDidDisappear(ObjectIdentifier(origin))
        send("mkt_page_view", origin: origin)
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))

        scheduler.advance(30)
        waitUntil(self, "예약 시각에 띄운다") { [service] in service!.pendingCampaign?.id == "a" }
    }

    func testDelayedReservationHeldInBackgroundThenShownOnReturn() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        service.delayedInAppCoordinator.setForeground(false)
        scheduler.advance(60)
        service.workQueue.sync {}
        XCTAssertFalse(service.isModalShown)

        service.delayedInAppCoordinator.setForeground(true)
        scheduler.advance(0)
        waitUntil(self, "복귀하면 띄운다") { [service] in service!.isModalShown }
    }

    func testReservationDroppedWhenCampaignLeftTheList() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        setCampaigns([])
        scheduler.advance(30)
        waitUntil(self, "목록에 없으면 버린다") { [service] in service!.delayedInAppCoordinator.reservations.isEmpty }
        XCTAssertFalse(service.isModalShown)
    }

    func testReservationDroppedWhenSamePopupSlotIsShowing() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30), triggerCampaign("b", eventName: "mkt_other")])
        send()
        send("mkt_other")
        XCTAssertTrue(service.isModalShown)
        service.displayLock.lock()
        let pending = service.pendingCampaign
        service.pendingCampaign = nil
        service.displayLock.unlock()
        XCTAssertEqual(pending?.id, "b")

        scheduler.advance(30)
        XCTAssertTrue(service.delayedInAppCoordinator.reservations.isEmpty)
    }

    func testAbortEventCancelsReservationAndResetsCount() {
        setCampaigns([
            triggerCampaign("delayed", delaySeconds: 30, abort: ["mkt_purchase"]),
            triggerCampaign("counted", eventName: "mkt_cart", occurrence: OccurrenceCondition(count: 2), abort: ["mkt_purchase"])
        ])
        send()
        send("mkt_cart")
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "delayed"))

        send("mkt_purchase")
        XCTAssertFalse(service.delayedInAppCoordinator.isScheduled(campaignId: "delayed"))
        send("mkt_cart")
        XCTAssertFalse(service.isModalShown)
    }

    func testD11_DiscardDelayedStateClearsReservationsAndCounts() {
        setCampaigns([
            triggerCampaign("delayed", delaySeconds: 30),
            triggerCampaign("counted", eventName: "mkt_cart", occurrence: OccurrenceCondition(count: 2))
        ])
        send()
        send("mkt_cart")
        service.discardDelayedState()
        XCTAssertTrue(service.delayedInAppCoordinator.reservations.isEmpty)
        send("mkt_cart")
        XCTAssertFalse(service.isModalShown)
    }

    func testD12_TimeWindowExcludesCandidate() {
        let closed = SendableTimeWindow(weeklyTimeRules: [])
        setCampaigns([triggerCampaign("a", occurrence: OccurrenceCondition(count: 1), window: closed)])
        send()
        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(defaults.data(forKey: OccurrenceConditionEvaluator.nonWindowedKeyPrefix + "a"))
    }

    func testD12_GlobalFrequencyCapExcludesCandidateAndExposureIsRecorded() {
        let cache = MockMarketapCache()
        let clock = self.clock!
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: NoopAPIForTriggerFlow(),
            cache: cache, defaults: defaults, now: { clock.now }, delayScheduler: scheduler, observesAppLifecycle: false
        )
        cache.saveCodableObject(
            [GlobalFrequencyCapRule(limit: 1, durationMinutes: 60, tagIds: [])],
            key: InAppMessageService.globalFrequencyCapsKey
        )
        setCampaigns([triggerCampaign("a"), triggerCampaign("b", eventName: "mkt_other")])
        send()
        XCTAssertTrue(service.isModalShown)

        service.recordExposure(campaign: triggerCampaign("a"), at: clock.now)
        service.displayLock.lock()
        service.isModalShown = false
        service.pendingCampaign = nil
        service.displayLock.unlock()
        send("mkt_other")
        XCTAssertFalse(service.isModalShown)
    }
}

extension InAppTriggerFlowTests {
    private func drain() {
        for _ in 0..<5 { service.workQueue.sync {} }
    }

    func testPresentFailureKeepsReservationForRetry() {
        canAttachFloating = false
        setCampaigns([triggerCampaign("f", delaySeconds: 30, slot: .floating)])
        send()
        scheduler.advance(30)
        waitUntil(self, "플로팅을 붙이지 못하면 자리를 비운다") { [service] in
            service!.isFloatingClaimed == false && service!.delayedInAppCoordinator.reservations.count == 1
                && self.scheduler.pendingCount == 1
        }
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "f"))
    }

    func testInactiveAppOnMainKeepsReservation() {
        service.isAppActiveOnMain = { false }
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "비활성이면 재시도 타이머를 건다") { [scheduler] in scheduler!.pendingCount == 1 }
        XCTAssertFalse(service.isModalShown)
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))
    }

    func testUserChangeDuringDelayedDetailFetchDoesNotShow() {
        api.holdSingleFetch = true
        api.singleResponses = ["a": triggerCampaign("a", html: "<div></div>")]
        setCampaigns([triggerCampaign("a", html: nil, delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "상세 fetch 를 기다린다") { [api] in api!.heldCount == 1 }

        service.discardDelayedState()
        api.releaseHeld()
        drain()
        let main = expectation(description: "main")
        DispatchQueue.main.async { main.fulfill() }
        wait(for: [main], timeout: 2)
        XCTAssertFalse(service.isModalShown)
        XCTAssertTrue(service.delayedInAppCoordinator.reservations.isEmpty)
    }

    func testAbortDuringFallthroughFetchSkipsAbortedDelayedCandidate() {
        api.holdSingleFetch = true
        setCampaigns([
            triggerCampaign("slow", html: nil),
            triggerCampaign("delayed", delaySeconds: 30, abort: ["mkt_purchase"])
        ])
        send()
        waitUntil(self, "첫 후보 상세 fetch 를 기다린다") { [api] in api!.heldCount == 1 }

        send("mkt_purchase")
        api.releaseHeld()
        drain()
        XCTAssertFalse(service.delayedInAppCoordinator.isScheduled(campaignId: "delayed"))
    }

    func testUserChangeDuringFallthroughFetchStopsChain() {
        api.holdSingleFetch = true
        setCampaigns([triggerCampaign("slow", html: nil), triggerCampaign("next")])
        send()
        waitUntil(self, "첫 후보 상세 fetch 를 기다린다") { [api] in api!.heldCount == 1 }

        service.discardDelayedState()
        api.releaseHeld()
        drain()
        XCTAssertFalse(service.isModalShown)
    }

    func testFallthroughFetchCompletionReturnsToWorkQueue() {
        api.holdSingleFetch = true
        api.singleResponses = ["slow": triggerCampaign("slow", html: "<div></div>")]
        setCampaigns([triggerCampaign("slow", html: nil)])
        send()
        waitUntil(self, "상세 fetch 를 기다린다") { [api] in api!.heldCount == 1 }

        let entered = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        service.workQueue.async { entered.signal(); gate.wait() }
        entered.wait()
        api.releaseHeld()
        XCTAssertFalse(service.isModalShown, "코어 큐가 막혀 있으면 노출도 기다려야 한다")
        gate.signal()
        drain()
        XCTAssertTrue(service.isModalShown)
    }

    private func flushMain() {
        let main = expectation(description: "main")
        DispatchQueue.main.async { main.fulfill() }
        wait(for: [main], timeout: 2)
    }

    private func promotePending() {
        let ready = expectation(description: "ready")
        DispatchQueue.main.async {
            self.service.webView(WKWebView(), didFinish: nil)
            ready.fulfill()
        }
        wait(for: [ready], timeout: 2)
        flushMain()
    }

    private func useGlobalCap(limit: Int) {
        let cache = MockMarketapCache()
        let clock = self.clock!
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: api,
            cache: cache, defaults: defaults, now: { clock.now }, delayScheduler: scheduler, observesAppLifecycle: false
        )
        service.pendingClaimTimeoutSeconds = 600
        service.delayedInAppCoordinator.setForeground(true)
        service.isAppActiveOnMain = { true }
        cache.saveCodableObject(
            [GlobalFrequencyCapRule(limit: limit, durationMinutes: 60, tagIds: [])],
            key: InAppMessageService.globalFrequencyCapsKey
        )
    }

    func testUserChangeDuringCampaignListFetchDropsEvent() {
        api.holdListFetch = true
        api.listResponse = [triggerCampaign("a", occurrence: OccurrenceCondition(count: 1))]
        service.campaigns = api.listResponse
        service.lastFetch = nil
        send()
        waitUntil(self, "목록 요청을 기다린다") { [api] in api!.heldCount == 1 }

        service.discardDelayedState()
        api.releaseHeld()
        drain()
        flushMain()
        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(defaults.data(forKey: OccurrenceConditionEvaluator.nonWindowedKeyPrefix + "a"))
    }

    func testAbortArrivingDuringCampaignListFetchSkipsEarlierTrigger() {
        api.holdListFetch = true
        api.listResponse = [triggerCampaign("a", abort: ["mkt_purchase"])]
        service.campaigns = api.listResponse
        service.lastFetch = nil
        send()
        send("mkt_purchase")
        waitUntil(self, "두 이벤트의 목록 요청을 기다린다") { [api] in api!.heldCount == 2 }

        api.releaseHeld()
        drain()
        XCTAssertFalse(service.isModalShown)
    }

    func testSameEventAbortAndTriggerStillCountsWhenListArrivesLate() {
        api.holdListFetch = true
        api.listResponse = [triggerCampaign("a", abort: ["mkt_home_view"])]
        service.campaigns = nil
        service.lastFetch = nil
        send()
        waitUntil(self, "목록 요청을 기다린다") { [api] in api!.heldCount == 1 }

        api.releaseHeld()
        drain()
        XCTAssertTrue(service.isModalShown)
    }

    func testPendingDelayedPopupKeepsReservationAndAbortCancelsPromotion() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30, abort: ["mkt_purchase"])])
        send()
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }
        XCTAssertEqual(service.delayedInAppCoordinator.reservations.count, 1, "적재 중에는 예약을 지우지 않는다")

        send("mkt_purchase")
        XCTAssertTrue(service.delayedInAppCoordinator.reservations.isEmpty)

        promotePending()
        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(service.pendingCampaign)
        XCTAssertNil(defaults.object(forKey: "impression_a"))
    }

    func testPendingDelayedPopupIsNotPromotedAfterUserChange() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }

        service.discardDelayedState()
        promotePending()
        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(defaults.object(forKey: "impression_a"))
    }

    func testPendingDelayedPopupInBackgroundIsKeptForRetry() {
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }

        service.isAppActiveOnMain = { false }
        promotePending()
        XCTAssertFalse(service.isModalShown)
        waitUntil(self, "재시도 타이머를 건다") { [scheduler] in scheduler!.pendingCount == 1 }
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))
    }

    func testPendingExpiryKeepsDelayedReservationForRetry() {
        service.pendingClaimTimeoutSeconds = 0.1
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "적재 시한이 지나면 재시도 타이머를 건다") { [service, scheduler] in
            service!.pendingCampaign == nil && scheduler!.pendingCount == 1
        }
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))
    }

    func testOfflineColdStartUsesDiskCacheForDelayedReservation() {
        let cache = MockMarketapCache()
        let clock = self.clock!
        api.failListFetch = true
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: api,
            cache: cache, defaults: defaults, now: { clock.now }, delayScheduler: scheduler, observesAppLifecycle: false
        )
        service.pendingClaimTimeoutSeconds = 600
        service.delayedInAppCoordinator.setForeground(true)
        service.isAppActiveOnMain = { true }
        let campaign = triggerCampaign("a", delaySeconds: 30)
        cache.saveCodableObject([campaign], key: InAppMessageService.campaignCacheKey)
        service.campaigns = nil
        service.lastFetch = nil

        var received: [String]?
        service.fetchCampaigns(inTimeout: { received = $0.map(\.id) })
        XCTAssertEqual(received, ["a"])

        _ = service.delayedInAppCoordinator.schedule(campaign: campaign, eventName: "mkt_home_view", eventProperties: nil)
        scheduler.advance(30)
        waitUntil(self, "디스크 캐시로 예약을 실행한다") { [service] in service!.pendingCampaign?.id == "a" }
        XCTAssertEqual(service.delayedInAppCoordinator.reservations.count, 1)
    }

    func testGlobalCapReachedDuringDelayDiscardsReservation() {
        useGlobalCap(limit: 1)
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))

        service.recordExposure(campaign: triggerCampaign("b"), at: clock.now)
        scheduler.advance(30)
        waitUntil(self, "전체 빈도에 걸리면 예약을 버린다") { [service] in
            service!.delayedInAppCoordinator.reservations.isEmpty
        }
        flushMain()
        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(service.pendingCampaign)
    }

    func testGlobalCapReachedWhilePendingDiscardsOnPromotion() {
        useGlobalCap(limit: 1)
        setCampaigns([triggerCampaign("a", delaySeconds: 30)])
        send()
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }

        service.recordExposure(campaign: triggerCampaign("b"), at: clock.now)
        promotePending()
        XCTAssertFalse(service.isModalShown)
        waitUntil(self, "전체 빈도에 걸리면 예약을 버린다") { [service] in
            service!.delayedInAppCoordinator.reservations.isEmpty
        }
    }
}

private final class NoopAPIForTriggerFlow: MarketapAPIProtocol {
    var singleResponses: [String: InAppCampaign] = [:]
    var holdSingleFetch = false
    var listResponse: [InAppCampaign]?
    var holdListFetch = false
    var failListFetch = false
    private let lock = NSLock()
    private var heldCompletions: [() -> Void] = []

    var heldCount: Int {
        lock.lock(); defer { lock.unlock() }
        return heldCompletions.count
    }

    func releaseHeld() {
        lock.lock()
        let completions = heldCompletions
        heldCompletions.removeAll()
        lock.unlock()
        completions.forEach { $0() }
    }

    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL, path: String, queryItems: [URLQueryItem]?,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {}

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {
        if T.self == InAppCampaignFetchResponse.self {
            if failListFetch {
                completion?(.failure(.serverError(statusCode: 503)))
                return
            }
            guard holdListFetch else { return }
            let respond = { [listResponse] in
                if let typed = InAppCampaignFetchResponse(checksum: "c", campaigns: listResponse) as? T {
                    completion?(.success(typed))
                }
            }
            lock.lock(); heldCompletions.append(respond); lock.unlock()
            return
        }
        guard T.self == InAppCampaignSingleFetchResponse.self else { return }
        let id = path.components(separatedBy: "/").last ?? ""
        let respond = { [singleResponses] in
            if let typed = InAppCampaignSingleFetchResponse(campaign: singleResponses[id]) as? T {
                completion?(.success(typed))
            }
        }
        if holdSingleFetch {
            lock.lock(); heldCompletions.append(respond); lock.unlock()
        } else {
            respond()
        }
    }

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    ) {
        completion?(.success(()))
    }
}

extension InAppTriggerFlowTests {
    private func timerCampaign(
        _ id: String,
        minutes: Int = 10,
        revision: String = "r1",
        isTest: Bool? = nil,
        delaySeconds: Int? = nil,
        slot: InAppDisplaySlot? = nil
    ) -> InAppCampaign {
        var campaign = triggerCampaign(id, delaySeconds: delaySeconds, slot: slot)
        campaign.timer = InAppCampaignTimer(minutes: minutes, revision: revision)
        campaign.isTest = isTest
        return campaign
    }

    private func millis(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    private func storedStart(_ id: String, _ revision: String = "r1") -> Double? {
        service.timerStore.startMillis(campaignId: id, revision: revision).map { $0.rounded() }
    }

    private func showPopupNow() {
        service.makePopupTarget = makeTestPopupTarget
        service.didFinishLoad = true
        send()
        waitUntil(self, "팝업이 뜬다") { [service] in service!.popupPresentation != nil }
    }

    private func closePopup() {
        guard let popup = service.popupPresentation else { return }
        service.finishPopup(claim: popup.claim)
        waitUntil(self, "팝업이 닫힌다") { [service] in !service!.isModalShown }
    }

    func testTimerStartIsRecordedOnFirstShowAndReusedOnReshow() {
        let firstShownAt = clock.now
        setCampaigns([timerCampaign("a")])
        showPopupNow()
        XCTAssertEqual(storedStart("a"), millis(firstShownAt))

        closePopup()
        clock.advance(120)
        XCTAssertEqual(service.timerStart(for: timerCampaign("a"), mountAt: clock.now).map(millis), millis(firstShownAt))
        showPopupNow()
        XCTAssertEqual(storedStart("a"), millis(firstShownAt), "다시 떠도 처음 시작 시각을 쓴다")
    }

    func testFloatingTimerStartIsRecordedOnAttach() {
        let shownAt = clock.now
        setCampaigns([timerCampaign("f", slot: .floating)])
        send()
        waitUntil(self, "플로팅이 붙는다") { [service] in service!.floatingPresenter.isShowing }
        XCTAssertEqual(storedStart("f"), millis(shownAt))
    }

    func testExpiredTimerExcludesCandidate() {
        service.timerStore.recordStartIfAbsent(
            campaignId: "a", revision: "r1", nowMillis: (clock.now.timeIntervalSince1970 - 10 * 60) * 1000
        )
        setCampaigns([timerCampaign("a")])
        send()
        XCTAssertFalse(service.isModalShown)
    }

    func testDelayedReservationDroppedWhenTimerExpiresBeforeRun() {
        service.timerStore.recordStartIfAbsent(
            campaignId: "a", revision: "r1", nowMillis: (clock.now.timeIntervalSince1970 - 10 * 60 + 10) * 1000
        )
        setCampaigns([timerCampaign("a", delaySeconds: 30)])
        send()
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))

        scheduler.advance(30)
        waitUntil(self, "실행 전에 만료되면 예약을 버린다") { [service] in
            service!.delayedInAppCoordinator.reservations.isEmpty
        }
        XCTAssertFalse(service.isModalShown)
    }

    func testRevisionChangeStartsTimerAnew() {
        let expiredStart = (clock.now.timeIntervalSince1970 - 60 * 60) * 1000
        service.timerStore.recordStartIfAbsent(campaignId: "a", revision: "r1", nowMillis: expiredStart)
        setCampaigns([timerCampaign("a", revision: "r2")])
        showPopupNow()
        XCTAssertEqual(storedStart("a", "r2"), millis(clock.now))
        XCTAssertEqual(storedStart("a", "r1"), expiredStart.rounded())
    }

    func testTestCampaignNeitherRecordsNorExpires() {
        let expiredStart = (clock.now.timeIntervalSince1970 - 60 * 60) * 1000
        service.timerStore.recordStartIfAbsent(campaignId: "a", revision: "r1", nowMillis: expiredStart)
        setCampaigns([timerCampaign("a", isTest: true)])
        showPopupNow()
        XCTAssertEqual(storedStart("a"), expiredStart.rounded(), "테스트 캠페인은 기록을 바꾸지 않는다")
        XCTAssertEqual(
            service.timerStart(for: timerCampaign("a", isTest: true), mountAt: clock.now).map(millis), millis(clock.now)
        )

        closePopup()
        setCampaigns([timerCampaign("b", isTest: true)])
        service.makePopupTarget = makeTestPopupTarget
        send()
        waitUntil(self, "팝업이 뜬다") { [service] in service!.popupPresentation != nil }
        XCTAssertNil(storedStart("b"), "테스트 캠페인은 새 기록을 만들지 않는다")
    }

    func testPopupDocumentCarriesTimerStartOnlyWhenGiven() {
        let start = Date(timeIntervalSince1970: 1_800_000_000.123)
        let withTimer = InAppMessageWebViewController.campaignDocument(campaignHTML: "<div></div>", safeArea: .zero, timerStartAt: start)
        XCTAssertTrue(withTimer.contains("timerStartAt: 1800000000123"))
        let withoutTimer = InAppMessageWebViewController.campaignDocument(campaignHTML: "<div></div>", safeArea: .zero, timerStartAt: nil)
        XCTAssertFalse(withoutTimer.contains("timerStartAt"))
    }
}
