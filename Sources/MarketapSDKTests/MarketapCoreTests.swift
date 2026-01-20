//
//  MarketapCoreTests.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

import XCTest
@testable import MarketapSDK

class MockEventService: EventServiceProtocol {
    weak var delegate: EventServiceDelegate?

    var pushToken: String?
    var trackedEvents: [String] = []
    var identifiedUserId: String?
    var userFlushed = false

    func setPushToken(token: String) {
        pushToken = token
    }

    func trackEvent(eventName: String, eventProperties: [String : Any]?, userId: String?, id: String?, timestamp: Date?, fromWebBridge: Bool) {
        trackedEvents.append(eventName)
    }

    func identify(userId: String, userProperties: [String : Any]?) {
        identifiedUserId = userId
        delegate?.handleUserIdChanged()
    }
    
    func setUserProperties(userProperties: [String: Any], userId: String?) { }

    func flushUser() {
        userFlushed = true
    }

    func updateDevice(pushToken: String? = nil, removeUserId: Bool = false) { }
}

class MockInAppMessageService: InAppMessageServiceProtocol {
    var fetchCampaignsCalled = false
    var receivedEvent: IngestEventRequest?

    func fetchCampaigns(force: Bool, inTimeout: (([InAppCampaign]) -> Void)?, completion: (([InAppCampaign]) -> Void)?) {
        fetchCampaignsCalled = true
    }

    func onEvent(eventRequest: IngestEventRequest, fromWebBridge: Bool) {
        receivedEvent = eventRequest
    }
}

class MarketapCoreTests: XCTestCase {
    var core: MarketapCore!
    var mockEventService: MockEventService!
    var mockInAppService: MockInAppMessageService!

    override func setUp() {
        super.setUp()
        mockEventService = MockEventService()
        mockInAppService = MockInAppMessageService()
        core = MarketapCore(customHandlerStore: CustomHandlerStor(), eventService: mockEventService, inAppMessageService: mockInAppService)
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

        let expectation = expectation(description: "Push token set")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(self.mockEventService.pushToken, "test_push_token")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testLogin() {
        core.login(userId: "user_123", userProperties: nil, eventProperties: nil)

        let expectation = expectation(description: "Login complete")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(self.mockEventService.identifiedUserId, "user_123")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testLogout() {
        core.logout(eventProperties: nil)

        let expectation = expectation(description: "Logout complete")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.mockEventService.userFlushed)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testTrackEvent() {
        core.track(eventName: "test_event", eventProperties: nil, id: nil, timestamp: nil)

        let expectation = expectation(description: "Track event complete")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.mockEventService.trackedEvents.contains("test_event"))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testTrackPurchase() {
        core.trackPurchase(revenue: 9.99, eventProperties: nil)

        let expectation = expectation(description: "Track purchase event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.mockEventService.trackedEvents.contains(MarketapEvent.purchase.rawValue))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testTrackRevenue() {
        core.trackRevenue(eventName: "purchase_event", revenue: 20.0, eventProperties: nil)

        let expectation = expectation(description: "Track revenue event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.mockEventService.trackedEvents.contains("purchase_event"))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testTrackPageView() {
        core.trackPageView(eventProperties: nil)

        let expectation = expectation(description: "Track page view event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.mockEventService.trackedEvents.contains(MarketapEvent.view.rawValue))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testIdentify() {
        core.identify(userId: "user_456", userProperties: nil)

        let expectation = expectation(description: "Identify event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(self.mockEventService.identifiedUserId, "user_456")
            XCTAssertTrue(self.mockInAppService.fetchCampaignsCalled)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testResetIdentity() {
        core.resetIdentity()

        let expectation = expectation(description: "Reset identity")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.mockEventService.userFlushed)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testHandleUserIdChanged() {
        core.handleUserIdChanged()

        let expectation = expectation(description: "Handle user ID change")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(self.mockInAppService.fetchCampaignsCalled)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testOnEvent() {
        let eventRequest = IngestEventRequest(id: "1", name: "custom_event", userId: "user_789", device: MockDevice().toDevice().makeRequest(), properties: nil, timestamp: Date())
        let mockDevice = MockDevice().toDevice()

        core.onEvent(eventRequest: eventRequest, device: mockDevice, fromWebBridge: false)

        let expectation = expectation(description: "OnEvent processed")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(self.mockInAppService.receivedEvent?.name, "custom_event")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
