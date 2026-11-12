import XCTest
import UIKit
import WebKit
@testable import MarketapSDK

final class InAppPopupPresentationTests: XCTestCase {
    private struct FinishSnapshot {
        let claim: Int
        let windowHidden: Bool
        let hasRoot: Bool
        let appWindowAccessibilityHidden: Bool
        let state: InAppPopupPresentation.State
    }

    private var center: NotificationCenter!
    private var target: InAppPopupPresentation.Target!
    private var finishes: [FinishSnapshot] = []
    private var presentations: [InAppPopupPresentation] = []

    override func setUp() {
        super.setUp()
        center = NotificationCenter()
        target = makeTestPopupTarget()
        finishes = []
    }

    override func tearDown() {
        presentations.forEach { $0.finish(claim: $0.claim) }
        presentations = []
        center = nil
        target = nil
        super.tearDown()
    }

    private func make(claim: Int = 1, scene: AnyObject? = nil) -> InAppPopupPresentation {
        let pinned = InAppPopupPresentation.Target(appWindow: target.appWindow, scene: scene, window: target.window)
        let presentation = InAppPopupPresentation(
            claim: claim,
            campaignId: "c",
            target: pinned,
            content: sharedTestWebViewController,
            notificationCenter: center
        ) { [unowned self] finished in
            self.finishes.append(FinishSnapshot(
                claim: finished.claim,
                windowHidden: finished.window.isHidden,
                hasRoot: finished.window.rootViewController != nil,
                appWindowAccessibilityHidden: finished.appWindow.accessibilityElementsHidden,
                state: finished.state
            ))
        }
        presentations.append(presentation)
        return presentation
    }

    func testShowPutsContentOnVisibleWindowAboveApp() {
        let presentation = make()
        presentation.show()

        XCTAssertEqual(presentation.state, .shown)
        XCTAssertFalse(target.window.isHidden)
        XCTAssertTrue(target.window.rootViewController === sharedTestWebViewController)
        XCTAssertEqual(target.window.windowLevel, UIWindow.Level.normal + 1)
        XCTAssertFalse(target.window.isKeyWindow)
        XCTAssertTrue(target.appWindow.accessibilityElementsHidden, "앱 창을 VoiceOver 에서 숨긴다")
        XCTAssertEqual(finishes.count, 0)
    }

    func testFinishWithOtherClaimDoesNothing() {
        let presentation = make(claim: 1)
        presentation.show()

        XCTAssertFalse(presentation.finish(claim: 2))

        XCTAssertEqual(presentation.state, .shown)
        XCTAssertFalse(target.window.isHidden)
        XCTAssertEqual(finishes.count, 0)
    }

    func testFinishTwiceIsHandledOnce() {
        let presentation = make()
        presentation.show()

        XCTAssertTrue(presentation.finish(claim: 1))
        XCTAssertFalse(presentation.finish(claim: 1))

        XCTAssertEqual(finishes.map(\.claim), [1])
    }

    func testFinishBeforeShowDoesNothing() {
        let presentation = make()

        XCTAssertFalse(presentation.finish(claim: 1))
        XCTAssertEqual(finishes.count, 0)
    }

    func testRightIsReleasedAfterWindowIsTornDown() {
        target.appWindow.accessibilityElementsHidden = false
        let presentation = make()
        presentation.show()

        presentation.finish(claim: 1)

        let snapshot = finishes.first
        XCTAssertEqual(snapshot?.windowHidden, true, "반납 전에 창을 숨긴다")
        XCTAssertEqual(snapshot?.hasRoot, false, "반납 전에 화면을 뗀다")
        XCTAssertEqual(snapshot?.appWindowAccessibilityHidden, false, "반납 전에 접근성을 되돌린다")
        XCTAssertEqual(snapshot?.state, .finishing)
    }

    func testAccessibilityValueIsRestored() {
        target.appWindow.accessibilityElementsHidden = false
        let first = make(claim: 1)
        first.show()
        first.finish(claim: 1)
        XCTAssertFalse(target.appWindow.accessibilityElementsHidden)

        target.appWindow.accessibilityElementsHidden = true
        let second = make(claim: 2)
        second.show()
        second.finish(claim: 2)
        XCTAssertTrue(target.appWindow.accessibilityElementsHidden, "앱이 걸어 둔 값은 그대로 둔다")
    }

    func testUnrelatedSceneDisconnectIsIgnored() {
        let presentation = make()
        presentation.show()

        center.post(name: UIScene.didDisconnectNotification, object: NSObject())
        center.post(name: UIScene.didDisconnectNotification, object: nil)

        XCTAssertEqual(presentation.state, .shown)
        XCTAssertEqual(finishes.count, 0)
    }

    func testDeinitWhileShownRestoresAccessibilityAndWindow() {
        target.appWindow.accessibilityElementsHidden = false
        weak var released: InAppPopupPresentation?
        autoreleasepool {
            let presentation = InAppPopupPresentation(
                claim: 1, campaignId: "c", target: target,
                content: sharedTestWebViewController, notificationCenter: center
            ) { _ in }
            presentation.show()
            XCTAssertTrue(target.appWindow.accessibilityElementsHidden)
            released = presentation
        }

        XCTAssertNil(released)
        XCTAssertFalse(target.appWindow.accessibilityElementsHidden)
        XCTAssertTrue(target.window.isHidden)
        XCTAssertNil(target.window.rootViewController)
        center.post(name: UIScene.didDisconnectNotification, object: nil)
    }

    func testPinnedSceneDisconnectFinishes() {
        let scene = NSObject()
        let presentation = make(scene: scene)
        presentation.show()

        center.post(name: UIScene.didDisconnectNotification, object: NSObject())
        XCTAssertEqual(finishes.count, 0, "다른 scene 의 종료에는 반응하지 않는다")

        center.post(name: UIScene.didDisconnectNotification, object: scene)

        XCTAssertEqual(finishes.map(\.claim), [1])
        center.post(name: UIScene.didDisconnectNotification, object: scene)
        XCTAssertEqual(finishes.count, 1, "구독은 finish 에서 풀린다")
    }
}

final class InAppDocumentGateTests: XCTestCase {
    func testCampaignDocumentAcceptsMessagesOnlyAfterItsCommit() {
        var gate = InAppDocumentGate()
        XCTAssertNil(gate.committedClaim)

        let first = NSObject()
        gate.didStartLoading(claim: 1, navigation: first)
        XCTAssertEqual(gate.loadedClaim, 1)
        XCTAssertNil(gate.committedClaim)

        gate.didCommit(navigation: NSObject())
        XCTAssertNil(gate.committedClaim, "다른 내비게이션의 커밋은 무시한다")

        gate.didCommit(navigation: first)
        XCTAssertEqual(gate.committedClaim, 1)
    }

    func testNextDocumentClosesGateUntilItsOwnCommit() {
        var gate = InAppDocumentGate()
        let first = NSObject()
        let second = NSObject()
        gate.didStartLoading(claim: 1, navigation: first)
        gate.didCommit(navigation: first)

        gate.didStartLoading(claim: 2, navigation: second)
        XCTAssertNil(gate.committedClaim)
        gate.didCommit(navigation: first)
        XCTAssertNil(gate.committedClaim, "이전 문서의 늦은 커밋으로 열리지 않는다")

        gate.didCommit(navigation: second)
        XCTAssertEqual(gate.committedClaim, 2)
    }

    func testBlankAndShellNeverCountAsCampaignDocument() {
        var gate = InAppDocumentGate()
        let first = NSObject()
        gate.didStartLoading(claim: 1, navigation: first)
        gate.didCommit(navigation: first)

        gate.didStartLoadingNonCampaign()
        XCTAssertNil(gate.loadedClaim)
        XCTAssertNil(gate.committedClaim)

        let pending = NSObject()
        gate.didStartLoading(claim: 2, navigation: pending)
        gate.didStartLoadingNonCampaign()
        gate.didCommit(navigation: pending)
        XCTAssertNil(gate.committedClaim, "빈 페이지를 올린 뒤에는 이전 팝업 문서가 커밋돼도 열리지 않는다")
    }

    func testMissingNavigationCountsAsCommitted() {
        var gate = InAppDocumentGate()
        gate.didStartLoading(claim: 3, navigation: nil)
        XCTAssertEqual(gate.committedClaim, 3)
    }
}

private final class PopupTestAPI: MarketapAPIProtocol {
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

private final class PopupTestClicks: MarketapCustomHandlerStoreProtocol {
    private(set) var clicked: [String?] = []
    func handleClick(_ event: MarketapClickEvent) { clicked.append(event.url) }
    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void) {}
}

private final class PopupTestEvents: InAppMessageServiceDelegate {
    private let lock = NSLock()
    private var names: [String] = []
    var eventNames: [String] { lock.lock(); defer { lock.unlock() }; return names }
    func trackEvent(eventName: String, eventProperties: [String: Any]?) {
        lock.lock(); names.append(eventName); lock.unlock()
    }
    func setUserProperties(userProperties: [String: Any]) {}
}

private final class PopupTestOrigin: InAppWebOrigin {
    var visible = true
    var onOpen: (() -> Void)?
    private(set) var opened: [String] = []

    var isWebViewVisible: Bool { visible }
    func openInWebView(url: String) {
        onOpen?()
        opened.append(url)
    }
    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool { true }
    func endWatchingWindow(owner: AnyObject) {}
}

final class InAppPopupServiceTests: XCTestCase {
    private var service: InAppMessageService!
    private var defaults: UserDefaults!
    private var clicks: PopupTestClicks!
    private var events: PopupTestEvents!
    private var origin: PopupTestOrigin!
    private var targets: [InAppPopupPresentation.Target] = []

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults(self)
        clicks = PopupTestClicks()
        events = PopupTestEvents()
        origin = PopupTestOrigin()
        targets = []
        service = InAppMessageService(customHandlerStore: clicks, api: PopupTestAPI(), cache: MockMarketapCache(), defaults: defaults)
        service.campaignViewController = sharedTestWebViewController
        service.pendingClaimTimeoutSeconds = 600
        service.didFinishLoad = true
        service.delegate = events
        service.clickRoutingSettings = { (false, true) }
        service.floatingPresenter = FloatingPresenter(makeWindow: { container in
            FloatingWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844), container: container)
        })
        service.makePopupTarget = { [unowned self] in
            let target = makeTestPopupTarget()
            self.targets.append(target)
            return target
        }
    }

    override func tearDown() {
        if let popup = service.popupPresentation {
            service.finishPopup(claim: popup.claim)
        }
        service.floatingPresenter.dismiss()
        service = nil
        defaults = nil
        clicks = nil
        events = nil
        origin = nil
        targets = []
        super.tearDown()
    }

    private func campaign(_ id: String, slot: InAppDisplaySlot = .popup) -> InAppCampaign {
        InAppCampaign(
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
    }

    private func run(_ candidates: [InAppCampaign], origin: InAppWebOrigin? = nil) {
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

    private func showPopup(_ id: String = "p", origin: InAppWebOrigin? = nil) {
        run([campaign(id)], origin: origin)
        drainMain()
    }

    private func impressionCount(_ id: String) -> Int {
        (defaults.object(forKey: "impression_\(id)") as? [TimeInterval])?.count ?? 0
    }

    private var popupWindow: InAppPopupWindow? { targets.last?.window }

    private func assertClosed(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(service.popupPresentation, file: file, line: line)
        XCTAssertFalse(service.isModalShown, file: file, line: line)
        XCTAssertEqual(popupWindow?.isHidden, true, file: file, line: line)
    }

    func testShowPinsAppWindowAndRecordsImpressionOnce() {
        showPopup()

        let popup = service.popupPresentation
        XCTAssertEqual(popup?.campaignId, "p")
        XCTAssertEqual(popup?.claim, service.displayClaim)
        XCTAssertTrue(popup?.appWindow === targets.first?.appWindow)
        XCTAssertEqual(popupWindow?.isHidden, false)
        XCTAssertEqual(sharedTestWebViewController.claim, service.displayClaim)
        XCTAssertNotNil(service.popupShownAt)
        XCTAssertEqual(impressionCount("p"), 1)
        XCTAssertEqual(events.eventNames.filter { $0 == "mkt_delivery_message" }.count, 1)
        XCTAssertEqual(targets.count, 1, "앱 창은 띄울 때 한 번만 고른다")
    }

    func testNoSceneReleasesClaimWithoutImpression() {
        service.makePopupTarget = { nil }

        showPopup()

        XCTAssertFalse(service.isModalShown)
        XCTAssertNil(service.popupPresentation)
        XCTAssertEqual(impressionCount("p"), 0)
        XCTAssertEqual(events.eventNames, [])
    }

    func testSecondPopupIsSkippedWhileOneIsShown() {
        showPopup("first")
        showPopup("second")

        XCTAssertEqual(service.popupPresentation?.campaignId, "first")
        XCTAssertEqual(impressionCount("second"), 0)
    }

    func testREG_ScreenChangedClosesShownPopup() {
        showPopup()
        service.monotonicNow = { ProcessInfo.processInfo.systemUptime + 1 }

        service.screenChanged()
        drainMain()

        assertClosed()
    }

    func testREG_WebPageMoveClosesShownPopup() {
        showPopup(origin: origin)

        service.originDidLeavePage(ObjectIdentifier(origin))
        drainMain()

        assertClosed()
    }

    func testREG_OriginDisappearingClosesShownPopup() {
        showPopup(origin: origin)

        service.originDidDisappear(ObjectIdentifier(origin))
        drainMain()

        assertClosed()
    }

    func testREG_HideForTodayRecordsHideAndCloses() {
        showPopup()

        service.hideCampaign(campaignId: "p", until: 86400, claim: service.displayClaim)

        assertClosed()
        XCTAssertTrue(service.isCampaignHiden(campaign: campaign("p")))
        showPopup()
        XCTAssertNil(service.popupPresentation, "숨긴 캠페인은 다시 뜨지 않는다")
    }

    func testREG_WebViewClickClosesPopupBeforeOpeningInOrigin() {
        showPopup(origin: origin)
        var closedBeforeOpen: Bool?
        origin.onOpen = { [unowned self] in closedBeforeOpen = self.service.popupPresentation == nil }

        service.onClick(
            campaign: campaign("p"), locationId: "loc", messageId: "m",
            url: "https://shop.example.com/a", claim: service.displayClaim
        )

        XCTAssertEqual(origin.opened, ["https://shop.example.com/a"])
        XCTAssertEqual(closedBeforeOpen, true)
        assertClosed()
    }

    func testREG_AppClickKeepsPopup() {
        showPopup()

        service.onClick(
            campaign: campaign("p"), locationId: "loc", messageId: "m",
            url: "https://shop.example.com/a", claim: service.displayClaim
        )

        XCTAssertEqual(clicks.clicked, ["https://shop.example.com/a"])
        XCTAssertNotNil(service.popupPresentation)
        XCTAssertEqual(popupWindow?.isHidden, false)
    }

    func testREG_PopupAndFloatingShowTogether() {
        run([campaign("p"), campaign("f", slot: .floating)])
        let service = self.service!
        waitUntil(self, "플로팅이 붙는다") { service.floatingPresenter.isShowing }
        drainMain()

        XCTAssertEqual(service.popupPresentation?.campaignId, "p")
        XCTAssertEqual(popupWindow?.isHidden, false)
        XCTAssertTrue(service.floatingPresenter.isWindowVisible, "팝업이 떠도 플로팅을 숨기지 않는다")
    }

    private func commitCurrentDocument() {
        let controller = sharedTestWebViewController
        service.webView(controller.webView, didCommit: controller.documentGate.pendingNavigation as? WKNavigation)
    }

    func testLateMessagesFromPreviousDocumentDoNotReachNextPopup() {
        let controller = sharedTestWebViewController
        controller.delegate = service
        showPopup("a")
        commitCurrentDocument()
        controller.handleScriptMessage(name: "hide", body: ["CLOSE"])
        XCTAssertNil(service.popupPresentation, "커밋된 문서의 hide 는 그 팝업을 닫는다")

        showPopup("b")
        let claimB = service.displayClaim
        controller.handleScriptMessage(name: "click", body: ["loc", "https://shop.example.com/late"])
        controller.handleScriptMessage(name: "hide", body: ["HIDE_FOR_ONE_DAY"])

        XCTAssertEqual(service.popupPresentation?.claim, claimB)
        XCTAssertTrue(service.isModalShown, "B 의 표시 권리를 지킨다")
        XCTAssertEqual(popupWindow?.isHidden, false)
        XCTAssertFalse(service.isCampaignHiden(campaign: campaign("b")))
        XCTAssertEqual(clicks.clicked, [])

        commitCurrentDocument()
        controller.handleScriptMessage(name: "click", body: ["loc", "https://shop.example.com/b"])
        XCTAssertEqual(clicks.clicked, ["https://shop.example.com/b"])
        controller.handleScriptMessage(name: "hide", body: ["CLOSE"])
        assertClosed()
    }

    func testMessagesAfterNativeCloseAreDropped() {
        let controller = sharedTestWebViewController
        controller.delegate = service
        showPopup("a")
        commitCurrentDocument()
        service.hideCampaign(campaignId: "a", until: 0, claim: service.displayClaim)

        controller.handleScriptMessage(name: "hide", body: ["HIDE_FOREVER"])

        XCTAssertFalse(service.isCampaignHiden(campaign: campaign("a")), "빈 페이지로 바뀐 뒤의 메시지는 버린다")
    }

    func testTerminationWithoutLoadedDocumentKeepsQueuedPopup() {
        showPopup("a")
        service.hideCampaign(campaignId: "a", until: 0, claim: service.displayClaim)

        run([campaign("b")])
        service.webViewWebContentProcessDidTerminate(sharedTestWebViewController.webView)
        drainMain()

        XCTAssertEqual(service.popupPresentation?.campaignId, "b", "이미 닫힌 문서의 프로세스 종료가 다음 팝업을 닫지 않는다")
        XCTAssertTrue(service.isModalShown)
    }

    func testShutdownWhileShownRestoresAccessibilityAndReleasesWindow() {
        showPopup()
        let appWindow = targets.last?.appWindow
        XCTAssertEqual(appWindow?.accessibilityElementsHidden, true)

        service.shutdown()

        XCTAssertEqual(appWindow?.accessibilityElementsHidden, false)
        XCTAssertNil(popupWindow?.rootViewController)
        assertClosed()
    }

    func testShutdownBeforeQueuedPresentationRunsDropsIt() {
        run([campaign("a")])
        service.shutdown()
        drainMain()

        XCTAssertNil(service.popupPresentation, "shutdown 전에 예약된 표시는 실행되지 않는다")
        XCTAssertFalse(service.isModalShown)
        XCTAssertEqual(impressionCount("a"), 0)
    }

    func testShutdownDropsPendingCampaignAndRefusesNewClaims() {
        service.didFinishLoad = false
        run([campaign("a")])
        XCTAssertNotNil(service.pendingCampaign)

        service.shutdown()
        XCTAssertNil(service.pendingCampaign)
        XCTAssertFalse(service.isModalShown)

        service.didFinishLoad = true
        showPopup("b")
        XCTAssertNil(service.popupPresentation, "shutdown 뒤에는 새 팝업을 띄우지 않는다")
        XCTAssertFalse(service.isModalShown)
    }

    func testShutdownFromBackgroundThreadFinishesOnMain() {
        showPopup()
        let service = self.service!
        let called = expectation(description: "shutdown called")
        DispatchQueue.global().async {
            service.shutdown()
            called.fulfill()
        }
        wait(for: [called], timeout: 5)
        drainMain()

        XCTAssertEqual(targets.last?.appWindow.accessibilityElementsHidden, false)
        assertClosed()
    }

    func testREG_ContentProcessTerminationClosesPopupAndNextPopupShows() {
        showPopup("first")

        service.webViewWebContentProcessDidTerminate(sharedTestWebViewController.webView)
        drainMain()
        assertClosed()

        showPopup("second")
        XCTAssertEqual(service.popupPresentation?.campaignId, "second")
        XCTAssertEqual(impressionCount("second"), 1)
    }
}
