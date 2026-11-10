import XCTest
import UIKit
@testable import MarketapSDK

private final class NoopAPI: MarketapAPIProtocol {
    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL, path: String, queryItems: [URLQueryItem]?,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {}

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {}

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    ) {
        completion?(.success(()))
    }
}

private final class RecordingClickHandler: MarketapCustomHandlerStoreProtocol {
    private(set) var clicked: [String?] = []
    func handleClick(_ event: MarketapClickEvent) { clicked.append(event.url) }
    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void) {}
}

private final class TrackedEvents: InAppMessageServiceDelegate {
    private let lock = NSLock()
    private var names: [String] = []
    var eventNames: [String] { lock.lock(); defer { lock.unlock() }; return names }
    func trackEvent(eventName: String, eventProperties: [String: Any]?) {
        lock.lock(); names.append(eventName); lock.unlock()
    }
    func setUserProperties(userProperties: [String: Any]) {}
}

private final class FakeOrigin: InAppWebOrigin {
    private let lock = NSLock()
    private var _opened: [String] = []
    private var _received = false
    private var _watching: [ObjectIdentifier] = []

    var visible = true
    var inWindow = true
    private(set) var onLeave: (() -> Void)?

    private func sync<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var opened: [String] { sync { _opened } }
    var watching: [ObjectIdentifier] { sync { _watching } }
    var received: Bool {
        get { sync { _received } }
        set { sync { _received = newValue } }
    }

    var isWebViewVisible: Bool { visible }
    var hasReceivedAddressChange: Bool { received }
    func openInWebView(url: String) { sync { _opened.append(url) } }

    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool {
        guard inWindow else { return false }
        sync { _watching.append(ObjectIdentifier(owner)) }
        self.onLeave = onLeave
        return true
    }

    func endWatchingWindow(owner: AnyObject) {
        sync { _watching.removeAll { $0 == ObjectIdentifier(owner) } }
    }
}

private func makeCampaign(_ id: String, slot: InAppDisplaySlot, scope: String? = nil) -> InAppCampaign {
    var campaign = InAppCampaign(
        id: id,
        layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
        triggerEventCondition: EventTriggerCondition(
            condition: Condition(eventFilter: EventFilter(eventName: "mkt_home_view"), propertyConditions: nil),
            frequencyCap: nil,
            delayMinutes: nil
        ),
        html: "<div>\(id)</div>",
        updatedAt: "t",
        displaySlot: slot
    )
    campaign.floatingScope = scope
    return campaign
}

final class InAppWebOriginPolicyTests: XCTestCase {

    func testREG25_ClickRoute() {
        let url = "https://shop.example.com/a"
        XCTAssertEqual(InAppClickRoute.of(url: url, customized: false, useWebClickRouting: true, originVisible: true), .webView)
        XCTAssertEqual(InAppClickRoute.of(url: url, customized: true, useWebClickRouting: true, originVisible: true), .app)
        XCTAssertEqual(InAppClickRoute.of(url: url, customized: false, useWebClickRouting: false, originVisible: true), .app)
        XCTAssertEqual(InAppClickRoute.of(url: url, customized: false, useWebClickRouting: true, originVisible: false), .app)
        XCTAssertEqual(InAppClickRoute.of(url: nil, customized: false, useWebClickRouting: true, originVisible: true), .app)
    }

    func testOnlyPageScopeWithOriginIsBound() {
        XCTAssertTrue(PageFloatingPolicy.isBoundToOrigin(floatingScope: "PAGE", hasOrigin: true))
        XCTAssertFalse(PageFloatingPolicy.isBoundToOrigin(floatingScope: "PAGE", hasOrigin: false))
        XCTAssertFalse(PageFloatingPolicy.isBoundToOrigin(floatingScope: "UNTIL_CLOSED", hasOrigin: true))
        XCTAssertFalse(PageFloatingPolicy.isBoundToOrigin(floatingScope: nil, hasOrigin: true))
    }

    func testREG28_ClosesOnlyBarOfLeavingOrigin() {
        let a = ObjectIdentifier(FakeOrigin.self)
        let b = ObjectIdentifier(NSObject.self)
        XCTAssertTrue(PageFloatingPolicy.closes(floatingScope: "PAGE", floatingOriginId: a, leavingOriginId: a))
        XCTAssertFalse(PageFloatingPolicy.closes(floatingScope: "PAGE", floatingOriginId: b, leavingOriginId: a))
        XCTAssertFalse(PageFloatingPolicy.closes(floatingScope: "UNTIL_CLOSED", floatingOriginId: a, leavingOriginId: a))
        XCTAssertFalse(PageFloatingPolicy.closes(floatingScope: nil, floatingOriginId: a, leavingOriginId: a))
        XCTAssertFalse(PageFloatingPolicy.closes(floatingScope: "PAGE", floatingOriginId: nil, leavingOriginId: a))
    }

    func testREG30_PageViewLeavesPageOnlyBeforeFirstAddressChange() {
        XCTAssertTrue(PageFloatingPolicy.eventLeavesPage(eventName: "mkt_page_view", originReceivedAddressChange: false))
        XCTAssertFalse(PageFloatingPolicy.eventLeavesPage(eventName: "mkt_page_view", originReceivedAddressChange: true))
        XCTAssertFalse(PageFloatingPolicy.eventLeavesPage(eventName: "mkt_home_view", originReceivedAddressChange: false))
    }

    func testExternalOriginIsConsumedOnce() {
        MarketapWebBridge.setExternalWebBridgeActive(false)
        XCTAssertNil(MarketapWebBridge.consumeExternalOrigin())

        MarketapWebBridge.setExternalWebBridgeActive(true)
        XCTAssertTrue(MarketapWebBridge.consumeExternalOrigin() === ExternalWebViewHost.shared)
        XCTAssertNil(MarketapWebBridge.consumeExternalOrigin(), "다음 이벤트까지 출처가 남으면 안 된다")
    }

    func testJavaScriptStringLiteral() {
        XCTAssertEqual(JavaScriptLiteral.string("a\"b"), "\"a\\\"b\"")
        XCTAssertEqual(JavaScriptLiteral.string("x\u{2028}y"), "\"x\\u2028y\"")
    }
}

final class InAppWebOriginServiceTests: XCTestCase {
    private var service: InAppMessageService!
    private var defaults: UserDefaults!
    private var clicks: RecordingClickHandler!
    private var tracked: TrackedEvents!
    private var origin: FakeOrigin!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults(self)
        clicks = RecordingClickHandler()
        tracked = TrackedEvents()
        origin = FakeOrigin()
        service = InAppMessageService(customHandlerStore: clicks, api: NoopAPI(), cache: MockMarketapCache(), defaults: defaults)
        service.pendingClaimTimeoutSeconds = 600
        service.delegate = tracked
        service.clickRoutingSettings = { (false, true) }
        service.floatingPresenter = FloatingPresenter(makeWindow: { container in
            FloatingWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844), container: container)
        })
    }

    override func tearDown() {
        service.floatingPresenter.dismiss()
        MarketapWebBridge.setExternalInAppMessageCallback(nil)
        MarketapWebBridge.setExternalWebBridgeActive(false)
        service = nil
        defaults = nil
        clicks = nil
        tracked = nil
        origin = nil
        super.tearDown()
    }

    private func run(_ candidates: [InAppCampaign], origin: InAppWebOrigin?) {
        service.tryShowCampaigns(
            candidates: candidates, index: 0, fetches: 0,
            deadline: ProcessInfo.processInfo.systemUptime + 30,
            eventName: "mkt_home_view", eventProperties: nil, origin: origin
        )
    }

    private func drainMain() {
        let done = expectation(description: "main drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func waitForFloating(_ id: String) {
        let service = self.service!
        waitUntil(self, "플로팅 \(id) 이 붙는다") {
            service.activeFloating?.campaign.id == id && service.floatingPresenter.isShowing
        }
    }

    private func pageView(origin: InAppWebOrigin?) {
        service.lastFetch = Date()
        service.campaigns = []
        service.onEvent(
            eventRequest: IngestEventRequest(
                id: "e", name: "mkt_page_view", userId: "u",
                device: MockMarketapCache().device.makeRequest(), properties: nil, timestamp: Date()
            ),
            origin: origin
        )
        drainMain()
    }

    private func impressionCount(_ id: String) -> Int {
        (defaults.object(forKey: "impression_\(id)") as? [TimeInterval])?.count ?? 0
    }

    // MARK: - 그리기

    func testREG24_WebViewPopupIsClaimedByAppAndNotSentToWeb() {
        var delivered: [String] = []
        MarketapWebBridge.setExternalInAppMessageCallback { campaign, _, _ in
            delivered.append(campaign["id"] as? String ?? "?")
        }
        MarketapWebBridge.setExternalWebBridgeActive(true)

        run([makeCampaign("p", slot: .popup)], origin: origin)

        XCTAssertEqual(service.pendingCampaign?.id, "p", "앱 팝업 표시 권리를 잡는다")
        XCTAssertTrue(service.displayOrigin === origin)
        XCTAssertEqual(delivered, [], "웹으로 캠페인을 넘기지 않는다")
    }

    func testREG24_WebViewPageFloatingIsDrawnByApp() {
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        waitForFloating("f")

        XCTAssertTrue(service.activeFloating?.origin === origin)
        XCTAssertEqual(origin.watching.count, 1, "출처 웹뷰의 창 감시를 건다")
    }

    func testPageFloatingIsNotShownWhenOriginAlreadyLeftWindow() {
        origin.inWindow = false
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        drainMain()

        XCTAssertNil(service.activeFloating)
        XCTAssertFalse(service.floatingPresenter.isShowing)
        XCTAssertEqual(impressionCount("f"), 0)
    }

    func testREG32_ImpressionIsRecordedOnceForWebViewFloating() {
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        waitForFloating("f")

        XCTAssertEqual(impressionCount("f"), 1)
        XCTAssertEqual(tracked.eventNames.filter { $0 == "mkt_delivery_message" }.count, 1)
    }

    // MARK: - 클릭

    private func floatingClick(origin: InAppWebOrigin?) {
        FloatingCampaignSession(campaign: makeCampaign("f", slot: .floating), service: service, origin: origin)
            .floatingDidClick(locationId: "loc", url: "https://shop.example.com/a")
    }

    private func popupClick(origin: InAppWebOrigin?) {
        run([makeCampaign("p", slot: .popup)], origin: origin)
        service.onClick(campaign: makeCampaign("p", slot: .popup), locationId: "loc", messageId: "m", url: "https://shop.example.com/a")
    }

    func testREG25_PopupFromWebViewOpensInOrigin() {
        popupClick(origin: origin)

        XCTAssertEqual(origin.opened, ["https://shop.example.com/a"])
        XCTAssertEqual(clicks.clicked, [])
        XCTAssertTrue(tracked.eventNames.contains("mkt_click_message"))
    }

    func testREG25_FloatingFromWebViewOpensInOrigin() {
        floatingClick(origin: origin)

        XCTAssertEqual(origin.opened, ["https://shop.example.com/a"])
        XCTAssertEqual(clicks.clicked, [])
    }

    func testREG25_RoutingOffOrCustomHandlerGoesToApp() {
        service.clickRoutingSettings = { (false, false) }
        floatingClick(origin: origin)
        service.clickRoutingSettings = { (true, true) }
        floatingClick(origin: origin)

        XCTAssertEqual(origin.opened, [])
        XCTAssertEqual(clicks.clicked.count, 2)
    }

    func testREG25_HiddenOriginGoesToApp() {
        origin.visible = false
        popupClick(origin: origin)

        XCTAssertEqual(origin.opened, [])
        XCTAssertEqual(clicks.clicked, ["https://shop.example.com/a"])
    }

    func testREG26_AppEventPopupAndFloatingClickGoToApp() {
        popupClick(origin: nil)
        floatingClick(origin: nil)

        XCTAssertEqual(origin.opened, [])
        XCTAssertEqual(clicks.clicked.count, 2)
    }

    func testExternalOriginOpensThroughCommand() {
        let external = ExternalWebViewHost.shared
        var commands: [(String, [String: Any])] = []
        external.command = { commands.append(($0, $1)) }
        external.attached = true
        defer {
            external.command = nil
            external.attached = false
        }

        floatingClick(origin: external)

        XCTAssertEqual(commands.map(\.0), ["openUrl"])
        XCTAssertEqual(commands.first?.1["url"] as? String, "https://shop.example.com/a")
        XCTAssertEqual(clicks.clicked, [])
    }

    // MARK: - "이 페이지에서만" 닫기

    func testREG28_AddressChangeClosesOnlyBarOfThatOrigin() {
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        waitForFloating("f")

        service.originDidLeavePage(ObjectIdentifier(FakeOrigin()))
        XCTAssertEqual(service.activeFloating?.campaign.id, "f", "다른 출처의 신호는 무시한다")

        service.originDidLeavePage(ObjectIdentifier(origin))
        XCTAssertNil(service.activeFloating)
        drainMain()
        XCTAssertFalse(service.floatingPresenter.isShowing)
        XCTAssertEqual(origin.watching, [], "닫히면 창 감시를 푼다")
    }

    func testREG28_UntilClosedBarFromSameOriginStays() {
        run([makeCampaign("f", slot: .floating, scope: "UNTIL_CLOSED")], origin: origin)
        waitForFloating("f")

        service.originDidLeavePage(ObjectIdentifier(origin))
        drainMain()

        XCTAssertEqual(service.activeFloating?.campaign.id, "f")
        XCTAssertTrue(service.floatingPresenter.isShowing)
        XCTAssertEqual(origin.watching, [], "유지 바는 창 감시를 걸지 않는다")
    }

    func testPageBarWithoutOriginStays() {
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: nil)
        waitForFloating("f")

        pageView(origin: nil)

        XCTAssertEqual(service.activeFloating?.campaign.id, "f")
    }

    func testWindowLeaveClosesPageBar() {
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        waitForFloating("f")

        origin.onLeave?()
        drainMain()

        XCTAssertNil(service.activeFloating)
        XCTAssertFalse(service.floatingPresenter.isShowing)
    }

    func testREG30_PageViewClosesBarBeforeFirstAddressChange() {
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        waitForFloating("f")

        pageView(origin: origin)

        XCTAssertNil(service.activeFloating)
        XCTAssertFalse(service.floatingPresenter.isShowing)
    }

    func testREG30_PageViewKeepsBarAfterAddressChangeWasReceived() {
        origin.received = true
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        waitForFloating("f")

        pageView(origin: origin)

        XCTAssertEqual(service.activeFloating?.campaign.id, "f")
    }

    func testREG30_PageViewFromOtherOriginKeepsBar() {
        run([makeCampaign("f", slot: .floating, scope: "PAGE")], origin: origin)
        waitForFloating("f")

        pageView(origin: FakeOrigin())

        XCTAssertEqual(service.activeFloating?.campaign.id, "f")
    }
}
