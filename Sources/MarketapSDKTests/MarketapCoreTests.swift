//
//  MarketapCoreTests.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

import XCTest
@testable import MarketapSDK

/// MarketapCore 는 내부 큐에서 서비스를 부르고, 테스트는 다른 스레드에서 결과를 확인한다.
/// 락 없이 배열을 쓰고 읽으면 실제로 크래시가 난다(CI 처럼 바쁜 환경에서 특히).
class MockEventService: EventServiceProtocol {
    weak var delegate: EventServiceDelegate?

    private let lock = NSLock()
    private func sync<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private var _pushToken: String?
    private var _optIn: Bool?
    private var _trackedEvents: [String] = []
    private var _identifiedUserId: String?
    private var _userFlushed = false

    var pushToken: String? { sync { _pushToken } }
    var optIn: Bool? { sync { _optIn } }
    var trackedEvents: [String] { sync { _trackedEvents } }
    var identifiedUserId: String? { sync { _identifiedUserId } }
    var userFlushed: Bool { sync { _userFlushed } }

    func setPushToken(token: String) {
        sync { _pushToken = token }
    }

    func setDeviceOptIn(optIn: Bool?) {
        sync { _optIn = optIn }
    }

    func trackEvent(eventName: String, eventProperties: [String : Any]?, userId: String?, id: String?, timestamp: Date?, fromWebBridge: Bool) {
        sync { _trackedEvents.append(eventName) }
    }

    func identify(userId: String, userProperties: [String : Any]?) {
        sync { _identifiedUserId = userId }
        delegate?.handleUserIdChanged()
    }

    func setUserProperties(userProperties: [String: Any], userId: String?) { }

    func flushUser() {
        sync { _userFlushed = true }
    }

    func updateDevice(pushToken: String? = nil, optIn: Bool? = nil, removeUserId: Bool = false, clearOptIn: Bool = false) { }
}

class MockInAppMessageService: InAppMessageServiceProtocol {
    private let lock = NSLock()
    private func sync<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private var _fetchCampaignsCalled = false
    private var _receivedEvent: IngestEventRequest?

    var fetchCampaignsCalled: Bool { sync { _fetchCampaignsCalled } }
    var receivedEvent: IngestEventRequest? { sync { _receivedEvent } }

    func fetchCampaigns(force: Bool, inTimeout: (([InAppCampaign]) -> Void)?, completion: (([InAppCampaign]) -> Void)?) {
        sync { _fetchCampaignsCalled = true }
    }

    func onEvent(eventRequest: IngestEventRequest, fromWebBridge: Bool) {
        sync { _receivedEvent = eventRequest }
    }

    var hiddenCampaigns: [(id: String, until: TimeInterval)] = []
    func recordHidden(campaignId: String, until: TimeInterval) {
        hiddenCampaigns.append((campaignId, until))
    }
}

// 예전엔 "0.5초 자고 한 번 단언" + wait(timeout: 1.0) 이었다. 여유가 0.5초뿐이라
// CI 러너처럼 느린 환경에서 11개가 한꺼번에 타임아웃으로 죽었다. 조건이 충족될 때까지
// 폴링한다 — 성공 경로에선 오히려 더 빨리 끝난다(0.5초를 무조건 기다리지 않는다).
class MarketapCoreTests: XCTestCase {
    var core: MarketapCore!
    var mockEventService: MockEventService!
    var mockInAppService: MockInAppMessageService!

    override func setUp() {
        super.setUp()
        mockEventService = MockEventService()
        mockInAppService = MockInAppMessageService()
        // 격리 suite 라 매 실행이 "첫 방문"으로 동일하게 시작한다(예전엔 최초 1회만
        // mkt_first_visit 이 발생해 실행 이력에 따라 결과가 달라졌다).
        core = MarketapCore(
            customHandlerStore: CustomHandlerStor(), eventService: mockEventService,
            inAppMessageService: mockInAppService, defaults: makeIsolatedDefaults(self)
        )
        mockEventService.delegate = core
    }

    override func tearDown() {
        core = nil
        mockEventService = nil
        mockInAppService = nil
        super.tearDown()
    }

    func testSetPushToken() {
        core.setPushToken(token: "test_push_token")

        let events = mockEventService!
        waitUntil(self, "푸시 토큰이 서비스까지 전달된다") { events.pushToken == "test_push_token" }
    }

    func testLogin() {
        core.login(userId: "user_123", userProperties: nil, eventProperties: nil)

        let events = mockEventService!
        waitUntil(self, "로그인이 identify 로 이어진다") { events.identifiedUserId == "user_123" }
    }

    func testLogout() {
        core.logout(eventProperties: nil)

        let events = mockEventService!
        waitUntil(self, "로그아웃이 유저를 비운다") { events.userFlushed }
    }

    func testTrackEvent() {
        core.track(eventName: "test_event", eventProperties: nil, id: nil, timestamp: nil)

        let events = mockEventService!
        waitUntil(self, "이벤트가 서비스까지 전달된다") { events.trackedEvents.contains("test_event") }
    }

    func testTrackPurchase() {
        core.trackPurchase(revenue: 9.99, eventProperties: nil)

        let events = mockEventService!
        waitUntil(self, "구매 이벤트가 전달된다") { events.trackedEvents.contains(MarketapEvent.purchase.rawValue) }
    }

    func testTrackRevenue() {
        core.trackRevenue(eventName: "purchase_event", revenue: 20.0, eventProperties: nil)

        let events = mockEventService!
        waitUntil(self, "매출 이벤트가 전달된다") { events.trackedEvents.contains("purchase_event") }
    }

    func testTrackPageView() {
        core.trackPageView(eventProperties: nil)

        let events = mockEventService!
        waitUntil(self, "페이지뷰 이벤트가 전달된다") { events.trackedEvents.contains(MarketapEvent.view.rawValue) }
    }

    func testIdentify() {
        core.identify(userId: "user_456", userProperties: nil)

        let events = mockEventService!
        let inApp = mockInAppService!
        waitUntil(self, "identify 가 유저 설정과 캠페인 재조회를 모두 부른다") {
            events.identifiedUserId == "user_456" && inApp.fetchCampaignsCalled
        }
    }

    func testResetIdentity() {
        core.resetIdentity()

        let events = mockEventService!
        waitUntil(self, "아이덴티티 초기화가 유저를 비운다") { events.userFlushed }
    }

    func testHandleUserIdChanged() {
        core.handleUserIdChanged()

        let inApp = mockInAppService!
        waitUntil(self, "유저 변경이 캠페인 재조회를 부른다") { inApp.fetchCampaignsCalled }
    }

    func testHideInAppMessageReachesTheService() {
        // 숨김 기록은 반드시 서비스(=숨김 키를 읽는 쪽)로 흘러야 한다. 예전엔 플러그인이
        // UserDefaults.standard 를 직접 찔러서, 서비스가 다른 저장소를 보면 숨김이 무시됐다.
        core.hideInAppMessage(campaignId: "c1", until: 3600)

        XCTAssertEqual(mockInAppService.hiddenCampaigns.count, 1)
        XCTAssertEqual(mockInAppService.hiddenCampaigns.first?.id, "c1")
        XCTAssertEqual(mockInAppService.hiddenCampaigns.first?.until, 3600)
    }

    func testOnEvent() {
        let eventRequest = IngestEventRequest(id: "1", name: "custom_event", userId: "user_789", device: MockDevice().toDevice().makeRequest(), properties: nil, timestamp: Date())
        let mockDevice = MockDevice().toDevice()

        core.onEvent(eventRequest: eventRequest, device: mockDevice, fromWebBridge: false)

        let inApp = mockInAppService!
        waitUntil(self, "이벤트가 인앱 서비스까지 전달된다") {
            inApp.receivedEvent?.name == "custom_event"
        }
    }
}
