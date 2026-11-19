import XCTest
import WebKit
@testable import MarketapSDK

private func flowEvent(_ name: String, sessionId: String = "s1") -> IngestEventRequest {
    IngestEventRequest(
        id: nil, name: name, userId: nil,
        device: MockMarketapCache().device.makeRequest(),
        properties: ["mkt_session_id": AnyCodable(sessionId)],
        timestamp: Date()
    )
}

func flowCampaign(
    _ id: String,
    entry: [String] = ["signup"],
    withinSeconds: Int = 1800,
    arrival: String = "view_product",
    cancel: [String]? = ["purchase"],
    reentryBlockSeconds: Int? = nil,
    html: String? = "<div></div>",
    delaySeconds: Int? = nil,
    occurrence: OccurrenceCondition? = nil,
    version: String? = "v1"
) -> InAppCampaign {
    let base = triggerCampaign(
        id, eventName: arrival, html: html, delaySeconds: delaySeconds,
        occurrence: occurrence, abort: cancel, version: version
    )
    var trigger = base.triggerEventCondition
    trigger.flow = EventFlow(
        precedingSteps: [
            EventFlowStep(
                conditions: entry.map { Condition(eventFilter: EventFilter(eventName: $0), propertyConditions: nil) },
                withinSeconds: withinSeconds
            )
        ],
        reentryBlockSeconds: reentryBlockSeconds
    )
    var campaign = InAppCampaign(
        id: base.id, layout: base.layout, triggerEventCondition: trigger,
        html: base.html, updatedAt: base.updatedAt, displaySlot: base.displaySlot
    )
    campaign.triggerConditionVersion = version
    return campaign
}

final class EventFlowStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: TestClock!
    private var store: EventFlowStore!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults(self)
        clock = TestClock()
        let clock = self.clock!
        store = EventFlowStore(defaults: defaults, now: { clock.now })
    }

    private func evaluate(_ campaign: InAppCampaign, _ eventName: String) -> EventFlowEvaluation {
        store.evaluate(
            campaign: campaign,
            arrivalMatched: campaign.triggerEventCondition.effectiveConditions.contains { $0.eventFilter.eventName == eventName },
            occurredAt: clock.now,
            matches: { $0.eventFilter.eventName == eventName }
        )
    }

    func testCampaignWithoutFlowFollowsTriggerMatch() {
        let campaign = triggerCampaign("a")
        XCTAssertEqual(evaluate(campaign, "mkt_home_view"), EventFlowEvaluation(fired: true, restarted: false))
        XCTAssertTrue(store.canShow(campaign: campaign))
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
    }

    func testVersionChangeRequiresReentryButKeepsNewerProgress() {
        let v1 = flowCampaign("a", version: "v1")
        let v2 = flowCampaign("a", version: "v2")
        _ = evaluate(v2, "signup")
        XCTAssertFalse(store.canShow(campaign: v1))

        XCTAssertEqual(evaluate(v1, "view_product"), EventFlowEvaluation(fired: false, restarted: false))
        XCTAssertTrue(store.canShow(campaign: v2), "옛 설정으로 판정해도 새 설정의 진행을 지우지 않는다")
        XCTAssertEqual(evaluate(v2, "view_product").fired, true)
    }

    func testStatesOlderThan32DaysAreDroppedOnSave() {
        let old = flowCampaign("old", withinSeconds: 60)
        _ = evaluate(old, "signup")
        clock.advance(TimeInterval(33 * 24 * 60 * 60))
        _ = evaluate(flowCampaign("new"), "signup")
        XCTAssertFalse(store.canShow(campaign: old))
        XCTAssertTrue(store.canShow(campaign: flowCampaign("new")))
    }

    func testClearAndClearAll() {
        _ = evaluate(flowCampaign("a"), "signup")
        _ = evaluate(flowCampaign("b"), "signup")
        store.clear(campaignId: "a")
        XCTAssertFalse(store.canShow(campaign: flowCampaign("a")))
        XCTAssertTrue(store.canShow(campaign: flowCampaign("b")))
        store.clearAll()
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
    }
}

final class EventFlowInAppTests: XCTestCase {
    private var service: InAppMessageService!
    private var api: NoopAPIForTriggerFlow!
    private var cache: MockMarketapCache!
    private var defaults: UserDefaults!
    private var clock: TestClock!
    private var scheduler: ManualDelayScheduler!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults(self)
        clock = TestClock(Date())
        scheduler = ManualDelayScheduler(clock: clock)
        let clock = self.clock!
        api = NoopAPIForTriggerFlow()
        cache = MockMarketapCache()
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: api,
            cache: cache, defaults: defaults,
            now: { clock.now }, delayScheduler: scheduler, observesAppLifecycle: false
        )
        service.pendingClaimTimeoutSeconds = 600
        service.delayedInAppCoordinator.setForeground(true)
        service.isAppActiveOnMain = { true }
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
        service.campaignsOwner = CampaignListOwner(userId: cache.userId)
    }

    private func send(_ name: String) {
        service.onEvent(eventRequest: flowEvent(name), origin: nil)
        service.workQueue.sync {}
    }

    private func flushMain() {
        let main = expectation(description: "main")
        DispatchQueue.main.async { main.fulfill() }
        wait(for: [main], timeout: 2)
    }

    private func canShow(_ campaign: InAppCampaign) -> Bool {
        service.eventFlowStore.canShow(campaign: campaign)
    }

    func testEntryThenArrivalShows() {
        setCampaigns([flowCampaign("a")])
        send("signup")
        XCTAssertFalse(service.isModalShown)
        send("view_product")
        XCTAssertTrue(service.isModalShown)
    }

    func testArrivalBeforeEntryDoesNotShow() {
        setCampaigns([flowCampaign("a")])
        send("view_product")
        send("signup")
        XCTAssertFalse(service.isModalShown)
    }

    func testArrivalAfterStepExpiryDoesNotShow() {
        setCampaigns([flowCampaign("a", withinSeconds: 1800)])
        send("signup")
        clock.advance(1801)
        send("view_product")
        XCTAssertFalse(service.isModalShown)
    }

    func testArrivalOnExpiryBoundaryShows() {
        setCampaigns([flowCampaign("a", withinSeconds: 1800)])
        send("signup")
        clock.advance(1800)
        send("view_product")
        XCTAssertTrue(service.isModalShown)
    }

    func testCancelDiscardsProgress() {
        setCampaigns([flowCampaign("a")])
        send("signup")
        send("purchase")
        send("view_product")
        XCTAssertFalse(service.isModalShown)
    }

    func testREG1_CampaignWithoutFlowStillTriggersOnArrival() {
        setCampaigns([triggerCampaign("plain", eventName: "view_product")])
        send("view_product")
        XCTAssertTrue(service.isModalShown)
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
    }

    func testReentryBlockAfterCancelWithProgress() {
        let campaign = flowCampaign("a", reentryBlockSeconds: 3600)
        setCampaigns([campaign])
        send("signup")
        send("purchase")

        clock.advance(1800)
        send("purchase")
        send("signup")
        send("view_product")
        XCTAssertFalse(service.isModalShown, "막힌 동안에는 진입하지 않는다")

        clock.advance(1800)
        send("signup")
        send("view_product")
        XCTAssertTrue(service.isModalShown, "막힌 중 취소는 막는 시간을 늘리지 않는다")
    }

    func testCancelWithoutProgressDoesNotBlock() {
        setCampaigns([flowCampaign("a", reentryBlockSeconds: 3600)])
        send("purchase")
        send("signup")
        send("view_product")
        XCTAssertTrue(service.isModalShown)
    }

    func testRestartResetsOccurrenceCount() {
        setCampaigns([flowCampaign("a", occurrence: OccurrenceCondition(count: 2))])
        send("signup")
        send("view_product")
        XCTAssertFalse(service.isModalShown)

        send("signup")
        send("view_product")
        XCTAssertFalse(service.isModalShown, "다시 진입하면 도달 횟수를 처음부터 센다")
        send("view_product")
        XCTAssertTrue(service.isModalShown)
    }

    func testREG3_CancelDuringDelayDoesNotShow() {
        let campaign = flowCampaign("a", reentryBlockSeconds: 3600, delaySeconds: 30)
        setCampaigns([campaign])
        send("signup")
        send("view_product")
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))

        send("purchase")
        XCTAssertFalse(canShow(campaign))
        scheduler.advance(30)
        drainWorkQueue(service)
        flushMain()
        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(service.pendingCampaign)
    }

    func testREG3_DelayedExecutionChecksFlowProgress() {
        let campaign = flowCampaign("a", delaySeconds: 30)
        setCampaigns([campaign])
        send("signup")
        send("view_product")
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "a"))

        service.eventFlowStore.clear(campaignId: "a")
        scheduler.advance(30)
        waitUntil(self, "진행이 없으면 예약을 끝낸다") { [service] in
            service!.delayedInAppCoordinator.reservations.isEmpty
        }
        flushMain()
        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(service.pendingCampaign)
    }

    func testDelayedFlowShowsWhenProgressIsKept() {
        setCampaigns([flowCampaign("a", delaySeconds: 30)])
        send("signup")
        send("view_product")
        scheduler.advance(30)
        waitUntil(self, "웹뷰 준비 대기로 적재된다") { [service] in service!.pendingCampaign?.id == "a" }
    }

    func testCancelDuringDetailFetchDoesNotShowAndKeepsBlock() {
        let campaign = flowCampaign("a", reentryBlockSeconds: 3600, html: nil)
        api.holdSingleFetch = true
        api.singleResponses = ["a": triggerCampaign("a", eventName: "view_product")]
        setCampaigns([campaign])
        send("signup")
        send("view_product")
        waitUntil(self, "상세 fetch 를 기다린다") { [api] in api!.heldCount == 1 }

        send("purchase")
        api.releaseHeld()
        drainWorkQueue(service)
        flushMain()
        XCTAssertFalse(service.isModalShown)
        XCTAssertFalse(canShow(campaign))
        XCTAssertNotNil(defaults.data(forKey: EventFlowStore.storageKey), "재진입 제한 상태는 남는다")
    }

    func testDetailFetchRechecksFlowBeforeShowing() {
        let campaign = flowCampaign("a", html: nil)
        api.holdSingleFetch = true
        api.singleResponses = ["a": triggerCampaign("a", eventName: "view_product")]
        setCampaigns([campaign])
        send("signup")
        send("view_product")
        waitUntil(self, "상세 fetch 를 기다린다") { [api] in api!.heldCount == 1 }

        service.eventFlowStore.clearAll()
        api.releaseHeld()
        drainWorkQueue(service)
        flushMain()
        XCTAssertFalse(service.isModalShown)
    }

    func testImpressionClearsProgress() {
        let campaign = flowCampaign("a")
        setCampaigns([campaign])
        service.makePopupTarget = makeTestPopupTarget
        service.didFinishLoad = true
        send("signup")
        send("view_product")
        waitUntil(self, "팝업이 뜬다") { [service] in service!.popupPresentation != nil }
        XCTAssertFalse(canShow(campaign), "노출되면 진입부터 다시 해야 한다")
    }

    func testREG4_GuestLoginKeepsProgress() {
        setCampaigns([flowCampaign("a")])
        send("signup")
        cache.userId = "A"
        send("view_product")
        XCTAssertTrue(service.isModalShown)
    }

    func testREG4_UserSwitchClearsProgressAndDelayedState() {
        setCampaigns([
            flowCampaign("a"),
            triggerCampaign("delayed", eventName: "view_product", delaySeconds: 30)
        ])
        cache.userId = "A"
        send("signup")
        cache.userId = "B"
        service.discardDelayedState()
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
        send("view_product")
        XCTAssertFalse(service.isModalShown)
        XCTAssertTrue(service.delayedInAppCoordinator.isScheduled(campaignId: "delayed"))
        service.discardDelayedState()
        XCTAssertTrue(service.delayedInAppCoordinator.reservations.isEmpty)
    }

    func testUserSwitchWhileListIsLoadingSkipsFlowAdvance() {
        api.holdListFetch = true
        api.listResponse = [flowCampaign("a")]
        service.campaigns = api.listResponse
        service.lastFetch = nil
        cache.userId = "A"
        send("signup")
        waitUntil(self, "목록 요청을 기다린다") { [api] in api!.heldCount == 1 }

        cache.userId = "B"
        api.releaseHeld()
        drainWorkQueue(service)
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
    }

    func testGuestEventPendingThroughLoginAndUserSwitchSkipsFlowAdvance() {
        api.holdListFetch = true
        api.listResponse = [flowCampaign("a")]
        service.campaigns = api.listResponse
        service.lastFetch = nil
        send("signup")
        waitUntil(self, "목록 요청을 기다린다") { [api] in api!.heldCount == 1 }

        cache.userId = "A"
        cache.userId = "B"
        service.discardDelayedState()
        api.releaseHeld()
        drainWorkQueue(service)
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
    }

    func testListFetchedForPreviousMemberDoesNotAdvanceFlow() {
        cache.userId = "A"
        setCampaigns([flowCampaign("a")])
        cache.userId = "B"
        service.discardDelayedState()

        send("signup")
        send("view_product")
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
        XCTAssertFalse(service.isModalShown)
    }

    func testListWithUnknownOwnerDoesNotAdvanceFlow() {
        setCampaigns([flowCampaign("a")])
        service.campaignsOwner = nil

        send("signup")
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
    }

    func testCachedListOfPreviousMemberIsRejectedAfterRestart() {
        cache.userId = "A"
        setCampaigns([flowCampaign("a")])
        cache.saveCodableObject(CampaignListOwner(userId: "A"), key: InAppMessageService.campaignsOwnerKey)
        cache.userId = "B"
        service.campaignsOwner = cache.loadCodableObject(forKey: InAppMessageService.campaignsOwnerKey)

        send("signup")
        XCTAssertNil(defaults.data(forKey: EventFlowStore.storageKey))
    }

    func testGuestListIsUsedAfterLogin() {
        setCampaigns([flowCampaign("a")])
        cache.userId = "A"

        send("signup")
        send("view_product")
        XCTAssertTrue(service.isModalShown)
    }

    func testFlowUsesEventTimeEvenWhenListArrivesLate() throws {
        api.holdListFetch = true
        api.listResponse = [flowCampaign("a", withinSeconds: 60)]
        service.campaigns = api.listResponse
        service.lastFetch = nil
        send("signup")
        waitUntil(self, "목록 요청을 기다린다") { [api] in api!.heldCount == 1 }
        let signupAt = EventFlowStore.millis(clock.now)

        clock.advance(120)
        api.releaseHeld()
        drainWorkQueue(service)
        let data = try XCTUnwrap(defaults.data(forKey: EventFlowStore.storageKey))
        let stored = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        XCTAssertEqual((stored?["a"]?["lastStepAt"] as? NSNumber)?.int64Value, signupAt)
    }
}
