//
//  EventServiceTests.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import XCTest
@testable import MarketapSDK

private class MockMarketapAPI: MarketapAPIProtocol {
    var shouldFail = false
    var lastRequestPath: String?
    var lastRequestBody: Data?
    var lastBulkEvents: [BulkEvent]?

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        body: U,
        responseType: T.Type,
        completion: ((Result<T, MarketapError>) -> Void)?
    ) {
        lastRequestPath = path
        lastRequestBody = try? JSONEncoder().encode(body)

        if shouldFail {
            completion?(.failure(.serverError(statusCode: 500)))
        } else {
            if let response = try? JSONDecoder().decode(responseType, from: Data()) {
                completion?(.success(response))
            } else {
                completion?(.failure(.decodingError(NSError(domain: "MockError", code: -1, userInfo: nil))))
            }
        }
    }

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    ) {
        lastRequestPath = path
        lastRequestBody = try? JSONEncoder().encode(body)

        if let bulkRequest = body as? CreateBulkClientEventRequest {
            lastBulkEvents = bulkRequest.events
        }

        if shouldFail {
            completion?(.failure(.serverError(statusCode: 500)))
        } else {
            completion?(.success(()))
        }
    }
}


class MockEventServiceDelegate: EventServiceDelegate {
    var handleUserIdChangedCalled = false
    var lastEventRequest: IngestEventRequest?
    var lastDevice: Device?
    private let queue = DispatchQueue(label: "com.marketap.core")

    func handleUserIdChanged() {
        handleUserIdChangedCalled = true
    }

    func onEvent(eventRequest: IngestEventRequest, device: Device) {
        queue.sync {
            self.lastEventRequest = eventRequest
            self.lastDevice = device
        }
    }
}

class EventServiceTests: XCTestCase {
    var eventService: EventService!
    fileprivate var mockAPI: MockMarketapAPI!
    var mockCache: MockMarketapCache!
    var mockDelegate: MockEventServiceDelegate!

    override func setUp() {
        super.setUp()
        mockAPI = MockMarketapAPI()
        mockCache = MockMarketapCache()
        mockDelegate = MockEventServiceDelegate()
        eventService = EventService(api: mockAPI, cache: mockCache)
        eventService.delegate = mockDelegate
    }

    override func tearDown() {
        eventService = nil
        mockAPI = nil
        mockCache = nil
        mockDelegate = nil
        super.tearDown()
        print("###tearDOwn")
    }

    func testLogin() {
        let testUserId = "user_123"
        eventService.login(userId: testUserId, userProperties: nil, eventProperties: nil)

        XCTAssertTrue(mockDelegate.handleUserIdChangedCalled, "Delegate의 handleUserIdChanged가 호출되지 않음")
        XCTAssertEqual(mockCache.userId, testUserId, "UserID가 정상적으로 저장되지 않음")
    }

    func testLogout() {
        mockCache.userId = "user_123"
        eventService.logout(eventProperties: nil)

        XCTAssertTrue(mockDelegate.handleUserIdChangedCalled, "Delegate의 handleUserIdChanged가 호출되지 않음")
        XCTAssertNil(mockCache.userId, "UserID가 정상적으로 삭제되지 않음")
    }

    func testTrackEvent() {
        let eventName = "test_event"
        let testProperties: [String: Any] = ["key": "value"]

        eventService.trackEvent(eventName: eventName, eventProperties: testProperties)

        XCTAssertEqual(mockAPI.lastRequestPath, "/v1/client/events?project_id=mock_project")
        XCTAssertEqual(mockDelegate.lastEventRequest?.name, eventName, "Delegate의 onEvent가 정상적으로 호출되지 않음")
        XCTAssertEqual(mockDelegate.lastDevice?.makeRequest(), mockCache.device.makeRequest(), "Device 정보가 올바르지 않음")
    }

    func testUpdateDevice() {
        let testToken = "test_push_token"
        eventService.updateDevice(pushToken: testToken)

        XCTAssertEqual(mockCache.device.token, testToken, "Device의 푸시 토큰이 업데이트되지 않음")
        XCTAssertEqual(mockAPI.lastRequestPath, "/v1/client/profile/device?project_id=mock_project")
    }


    func testTrackEventFails() {
        let eventName = "test_event_fail"
        let testProperties: [String: Any] = ["key": "value"]

        mockAPI.shouldFail = true
        eventService.trackEvent(eventName: eventName, eventProperties: testProperties)
        XCTAssertEqual(self.eventService.failedEvents.count, 1)

        mockAPI.shouldFail = false
        eventService.trackEvent(eventName: "test_event_success", eventProperties: nil)
        XCTAssertEqual(self.eventService.failedEvents.count, 0)
    }

    func testFailedEventsAreSentInBulk() {
        let events = (1...5).map {
            BulkEvent(id: "\($0)", name: "failed_event_\($0)", timestamp: Date(), properties: nil)
        }

        eventService._failedEvents = events
        eventService.sendFailedEventsIfNeeded()

        XCTAssertEqual(self.mockAPI.lastRequestPath, "/v1/client/events/bulk?project_id=mock_project")
        XCTAssertEqual(self.mockAPI.lastBulkEvents?.count, 5, "벌크 이벤트가 정상적으로 전송되지 않음")
    }


    func testFailedEventsThreadSafety() {
        let concurrentQueue = DispatchQueue(label: "com.marketap.concurrent", attributes: .concurrent)
        let expectation = self.expectation(description: "Concurrent Event Tracking")

        for i in 0..<200 {
            concurrentQueue.async {
                let eventName = "concurrent_event_\(i)"
                self.eventService.trackEvent(eventName: eventName, eventProperties: nil)
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        XCTAssertTrue(eventService.failedEvents.count <= 100, "이벤트 저장 개수 제한이 제대로 적용되지 않음")
    }

    func testUpdateProfileFailsAndStoresFailedUser() {
        mockAPI.shouldFail = true

        eventService.identify(userId: "testUser", userProperties: ["key": "value"])

        XCTAssertNotNil(eventService.failedUser, "updateProfile 실패 시 failedUser가 저장되지 않음")
        XCTAssertEqual(eventService.failedUser?.userId, "testUser", "저장된 failedUser의 userId가 다름")
    }

    func testSendFailedUserIfNeededRetriesUpdateProfile() {
        let failedRequest = UpdateProfileRequest(
            userId: "testUser",
            properties: ["key": "value"].toAnyCodable(),
            device: mockCache.device.makeRequest(),
            timestamp: Date()
        )
        eventService.failedUser = failedRequest

        eventService.sendFailedUserIfNeeded()

        XCTAssertEqual(mockAPI.lastRequestPath, "/v1/client/profile/user?project_id=mock_project")
    }

    func testUpdateProfileSuccessClearsFailedUser() {
        let failedRequest = UpdateProfileRequest(
            userId: "testUser",
            properties: ["key": "value"].toAnyCodable(),
            device: mockCache.device.makeRequest(),
            timestamp: Date()
        )
        eventService.failedUser = failedRequest

        mockAPI.shouldFail = false
        eventService.sendFailedUserIfNeeded()

        XCTAssertNil(eventService.failedUser, "updateProfile 성공 후 failedUser가 초기화되지 않음")
    }

}
