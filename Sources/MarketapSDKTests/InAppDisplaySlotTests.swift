import XCTest
import UIKit
@testable import MarketapSDK

private final class SlotAPI: MarketapAPIProtocol {
    var singleResponses: [String: InAppCampaign] = [:]
    private let lock = NSLock()
    private var paths: [String] = []

    var fetchedCampaignIds: [String] {
        lock.lock(); defer { lock.unlock() }
        return paths.compactMap { $0.hasPrefix("/api/v2/campaigns/") ? $0.components(separatedBy: "/").last : nil }
    }

    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL, path: String, queryItems: [URLQueryItem]?,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {}

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {
        lock.lock(); paths.append(path); lock.unlock()
        if T.self == InAppCampaignSingleFetchResponse.self {
            let id = path.components(separatedBy: "/").last ?? ""
            if let typed = InAppCampaignSingleFetchResponse(campaign: singleResponses[id]) as? T {
                completion?(.success(typed))
            }
        }
    }

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    ) {
        completion?(.success(()))
    }
}

private final class TrackedEvents: InAppMessageServiceDelegate {
    private let lock = NSLock()
    private var storage: [(String, [String: Any]?)] = []

    var events: [(String, [String: Any]?)] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func trackEvent(eventName: String, eventProperties: [String: Any]?) {
        lock.lock(); storage.append((eventName, eventProperties)); lock.unlock()
    }

    func setUserProperties(userProperties: [String: Any]) {}
}

final class InAppDisplaySlotTests: XCTestCase {
    private var service: InAppMessageService!
    private var api: SlotAPI!
    private var defaults: UserDefaults!
    private var tracked: TrackedEvents!

    override func setUp() {
        super.setUp()
        api = SlotAPI()
        defaults = makeIsolatedDefaults(self)
        tracked = TrackedEvents()
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: api,
            cache: MockMarketapCache(), defaults: defaults
        )
        service.pendingClaimTimeoutSeconds = 600
        service.delegate = tracked
        service.floatingPresenter = FloatingPresenter(makeWindow: { container in
            FloatingWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844), container: container)
        })
    }

    override func tearDown() {
        service.floatingPresenter.dismiss()
        service = nil
        api = nil
        defaults = nil
        tracked = nil
        super.tearDown()
    }

    private func campaign(
        _ id: String,
        html: String? = nil,
        slot: InAppDisplaySlot? = nil
    ) -> InAppCampaign {
        InAppCampaign(
            id: id,
            layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
            triggerEventCondition: EventTriggerCondition(
                condition: Condition(eventFilter: EventFilter(eventName: "mkt_home_view"), propertyConditions: nil),
                frequencyCap: nil,
                delayMinutes: nil
            ),
            html: html,
            updatedAt: "\(Date())",
            displaySlot: slot
        )
    }

    private func floating(_ id: String, html: String? = "<div></div>") -> InAppCampaign {
        campaign(id, html: html, slot: .floating)
    }

    private func run(_ candidates: [InAppCampaign]) {
        service.tryShowCampaigns(
            candidates: candidates, index: 0, fetches: 0,
            deadline: ProcessInfo.processInfo.systemUptime + 30,
            eventName: "mkt_home_view", eventProperties: nil, origin: nil
        )
    }

    private func waitForFloating(_ id: String) {
        let service = self.service!
        waitUntil(self, "플로팅 \(id) 이 붙는다") {
            service.activeFloating?.campaign.id == id && service.floatingPresenter.isShowing
        }
    }

    private func drainMain() {
        let done = expectation(description: "main drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func decode(_ json: String) throws -> InAppCampaign {
        try JSONDecoder().decode(InAppCampaign.self, from: Data(json.utf8))
    }

    private let baseJSON = """
    "id":"c","layout":{"layoutType":"MODAL","layoutSubType":"CENTER","orientations":[]},
    "triggerEventCondition":{"condition":{"eventFilter":{"eventName":"e"}}},"updatedAt":"t"
    """

    func testDecodesDisplaySlot() throws {
        XCTAssertEqual(try decode("{\(baseJSON)}").slot, .popup)
        XCTAssertEqual(try decode("{\(baseJSON),\"displaySlot\":\"POPUP\"}").slot, .popup)
        XCTAssertEqual(try decode("{\(baseJSON),\"displaySlot\":\"SOMETHING\"}").slot, .popup)
        let pageScoped = try decode("{\(baseJSON),\"displaySlot\":\"FLOATING\",\"floatingScope\":\"PAGE\"}")
        XCTAssertEqual(pageScoped.slot, .floating)
        let reEncoded = String(data: try JSONEncoder().encode(pageScoped), encoding: .utf8) ?? ""
        XCTAssertTrue(reEncoded.contains("\"floatingScope\":\"PAGE\""), "웹 화면 위임 시 그대로 넘긴다")
    }

    func testREG1_PopupOnlyCampaignsShowOnlyOne() {
        api.singleResponses = ["b": campaign("b", html: "<div>b</div>")]
        run([campaign("a", html: "<div>a</div>"), campaign("b"), campaign("c", html: "<div>c</div>")])

        XCTAssertEqual(service.pendingCampaign?.id, "a")
        XCTAssertEqual(api.fetchedCampaignIds, [])
        XCTAssertNil(service.activeFloating)
    }

    func testREG2_PresentingPopupBlocksSecondPopup() {
        service.isModalShown = true
        api.singleResponses = ["late": campaign("late", html: "<div>late</div>")]

        run([campaign("late"), campaign("static", html: "<div>s</div>")])

        XCTAssertEqual(api.fetchedCampaignIds, [])
        XCTAssertNil(service.pendingCampaign)
    }

    func testREG3_PendingPopupDoesNotFreezeEvaluation() {
        run([campaign("first", html: "<div>1</div>")])
        XCTAssertEqual(service.pendingCampaign?.id, "first")

        api.singleResponses = ["f": floating("f")]
        run([campaign("late"), floating("f", html: nil)])

        XCTAssertEqual(api.fetchedCampaignIds, ["late", "f"])
        XCTAssertEqual(service.pendingCampaign?.id, "first")
        waitForFloating("f")
    }

    func testPopupAndFloatingShowTogether() {
        run([
            campaign("p1", html: "<div>p1</div>"),
            floating("f1"),
            campaign("p2", html: "<div>p2</div>"),
            floating("f2"),
        ])

        XCTAssertEqual(service.pendingCampaign?.id, "p1")
        waitForFloating("f1")
        drainMain()
        XCTAssertEqual(service.activeFloating?.campaign.id, "f1")
    }

    func testFloatingFallsThroughEmptyFetchWithoutBlockingPopup() {
        api.singleResponses = ["f2": floating("f2")]
        run([floating("f1", html: nil), floating("f2", html: nil), campaign("p", html: "<div>p</div>")])

        XCTAssertEqual(api.fetchedCampaignIds, ["f1", "f2"])
        XCTAssertEqual(service.pendingCampaign?.id, "p")
        waitForFloating("f2")
    }

    func testPresentingPopupStillLetsFloatingShow() {
        service.isModalShown = true
        run([campaign("p", html: "<div>p</div>"), floating("f")])

        XCTAssertNil(service.pendingCampaign)
        waitForFloating("f")
    }

    func testShownFloatingBlocksSecondFloatingOnly() {
        run([floating("f1")])
        waitForFloating("f1")

        run([floating("f2"), campaign("p", html: "<div>p</div>")])
        drainMain()

        XCTAssertEqual(service.activeFloating?.campaign.id, "f1")
        XCTAssertEqual(service.pendingCampaign?.id, "p")
    }

    func testFetchedCampaignWithoutSlotKeepsListedSlot() {
        api.singleResponses = ["f": campaign("f", html: "<div>f</div>")]
        run([floating("f", html: nil)])

        XCTAssertNil(service.pendingCampaign)
        waitForFloating("f")
    }

    func testFloatingWithoutWindowReleasesClaim() {
        service.floatingPresenter = FloatingPresenter(makeWindow: { _ in nil })
        run([floating("f")])
        XCTAssertNotNil(service.activeFloating)

        drainMain()

        XCTAssertNil(service.activeFloating)
        XCTAssertNil(defaults.object(forKey: "impression_f"), "못 붙였으면 빈도수를 소진하지 않는다")
        XCTAssertFalse(tracked.events.contains { $0.0 == "mkt_delivery_message" })
    }

    func testImpressionAndClickCarrySessionMessageId() {
        run([floating("f")])
        waitForFloating("f")
        let session = service.activeFloating!

        XCTAssertEqual((defaults.object(forKey: "impression_f") as? [TimeInterval])?.count, 1)
        session.floatingDidClick(locationId: "loc", url: "https://example.com")

        let impression = tracked.events.first { $0.0 == "mkt_delivery_message" }
        let click = tracked.events.first { $0.0 == "mkt_click_message" }
        XCTAssertEqual(impression?.1?["mkt_message_id"] as? String, session.messageId)
        XCTAssertEqual(click?.1?["mkt_message_id"] as? String, session.messageId)
        XCTAssertEqual(click?.1?["mkt_location_id"] as? String, "loc")
    }

    func testHiddenCloseRecordsHideAndReleasesClaim() {
        run([floating("f")])
        waitForFloating("f")

        service.floatingPresenter.session?.close(reason: .hidden(until: 3600))

        XCTAssertNil(service.activeFloating)
        XCTAssertFalse(service.floatingPresenter.isShowing)
        XCTAssertTrue(service.isCampaignHiden(campaign: floating("f")))

        run([floating("f"), floating("g")])
        waitForFloating("g")
    }

    func testOtherCloseReasonsReleaseClaim() {
        for reason in [FloatingCloseReason.dismissed, .webContentTerminated, .hidden(until: 0)] {
            run([floating("f")])
            waitForFloating("f")

            service.floatingPresenter.session?.close(reason: reason)

            XCTAssertNil(service.activeFloating, "\(reason)")
            XCTAssertFalse(service.isCampaignHiden(campaign: floating("f")), "\(reason)")
        }
    }

    private func appEvent(_ name: String) -> IngestEventRequest {
        IngestEventRequest(
            id: "e1", name: name, userId: "u",
            device: MockMarketapCache().device.makeRequest(), properties: nil, timestamp: Date()
        )
    }

    private func scopedFloating(_ scope: String) -> InAppCampaign {
        try! JSONDecoder().decode(
            InAppCampaign.self,
            from: Data("{\(baseJSON),\"html\":\"<div></div>\",\"displaySlot\":\"FLOATING\",\"floatingScope\":\"\(scope)\"}".utf8)
        )
    }

    private func passScreenChangeGrace() {
        service.monotonicNow = { ProcessInfo.processInfo.systemUptime + 1 }
    }

    private func showFloating(scope: String) {
        run([scopedFloating(scope)])
        waitForFloating("c")
        service.lastFetch = Date()
        service.campaigns = []
    }

    func testREG5_ScreenChangedClosesPageScopedFloating() {
        showFloating(scope: "PAGE")

        passScreenChangeGrace()
        service.screenChanged()
        drainMain()

        XCTAssertNil(service.activeFloating)
        XCTAssertFalse(service.floatingPresenter.isShowing)
    }

    func testREG5_ScreenChangedKeepsUntilClosedFloating() {
        showFloating(scope: "UNTIL_CLOSED")

        passScreenChangeGrace()
        service.screenChanged()
        drainMain()

        XCTAssertEqual(service.activeFloating?.campaign.id, "c")
        XCTAssertTrue(service.floatingPresenter.isShowing)
    }

    func testREG6_PageViewAndOtherEventsDoNotClosePageFloating() {
        showFloating(scope: "PAGE")

        for name in ["mkt_page_view", "screen_view", "mkt_purchase"] {
            service.onEvent(eventRequest: appEvent(name), origin: nil)
        }
        drainMain()

        XCTAssertEqual(service.activeFloating?.campaign.id, "c")
        XCTAssertTrue(service.floatingPresenter.isShowing)
    }

    func testREG7_PageFloatingNotShownYetSurvivesScreenChange() {
        XCTAssertTrue(service.presentFloating(campaign: scopedFloating("PAGE")))
        passScreenChangeGrace()

        service.screenChanged()

        waitForFloating("c")
    }

    func testREG7_PageFloatingShownWithinGraceSurvivesScreenChange() {
        XCTAssertTrue(service.presentFloating(campaign: scopedFloating("PAGE")))
        waitForFloating("c")
        let shownAt = service.activeFloating?.shownAt ?? 0
        service.monotonicNow = { shownAt + 0.05 }

        service.screenChanged()
        drainMain()

        XCTAssertEqual(service.activeFloating?.campaign.id, "c")
    }

    func testREG7_FloatingShownAfterSignalSurvivesLateEvaluation() {
        XCTAssertTrue(service.presentFloating(campaign: scopedFloating("PAGE")))
        waitForFloating("c")
        let shownAt = service.activeFloating?.shownAt ?? 0
        service.monotonicNow = { shownAt + 5 }

        service.screenChanged(at: shownAt - 1)
        drainMain()

        XCTAssertEqual(service.activeFloating?.campaign.id, "c")
    }

    func testREG7_PopupNotShownYetSurvivesScreenChange() {
        service.tryShowCampaigns(
            candidates: [campaign("p", html: "<div>p</div>")], index: 0, fetches: 0,
            deadline: ProcessInfo.processInfo.systemUptime + 30,
            eventName: "mkt_home_view", eventProperties: nil, origin: nil
        )
        passScreenChangeGrace()

        service.screenChanged()

        XCTAssertEqual(service.pendingCampaign?.id, "p")
        XCTAssertTrue(service.isModalShown)
    }

    func testREG9_PageFloatingIsReplacedByFloatingOfNextScreen() {
        showFloating(scope: "PAGE")
        let next = try! JSONDecoder().decode(
            InAppCampaign.self,
            from: Data(("{\"id\":\"b\",\"layout\":{\"layoutType\":\"MODAL\",\"layoutSubType\":\"CENTER\",\"orientations\":[]},"
                + "\"triggerEventCondition\":{\"condition\":{\"eventFilter\":{\"eventName\":\"mkt_page_view\"}}},\"updatedAt\":\"t\","
                + "\"html\":\"<div></div>\",\"displaySlot\":\"FLOATING\",\"floatingScope\":\"PAGE\"}").utf8)
        )
        service.campaigns = [next]

        passScreenChangeGrace()
        service.screenChanged()
        service.onEvent(eventRequest: appEvent("mkt_page_view"), origin: nil)

        waitForFloating("b")
    }
}
