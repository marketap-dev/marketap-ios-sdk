//
//  EventServiceTests.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import XCTest
@testable import MarketapSDK

private class MockServerTimeManager: ServerTimeManagerProtocol {
    func withServerTime(completion: @escaping (Date?) -> Void) {
        completion(Date())
    }
}

private class MockMarketapAPI: MarketapAPIProtocol {
    var shouldFail = false
    var lastRequestPath: String?
    var lastRequestBody: Data?
    var lastBulkEvents: [BulkEvent]?

    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        queryItems: [URLQueryItem]?,
        responseType: T.Type,
        completion: ((Result<T, MarketapError>) -> Void)?
    ) {
        lastRequestPath = path

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

    func onEvent(eventRequest: IngestEventRequest, device: Device, fromWebBridge: Bool) {
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
    fileprivate var mockServerTimeManager: MockServerTimeManager!

    override func setUp() {
        super.setUp()
        mockAPI = MockMarketapAPI()
        mockCache = MockMarketapCache()
        mockServerTimeManager = MockServerTimeManager()
        mockDelegate = MockEventServiceDelegate()
        eventService = EventService(api: mockAPI, cache: mockCache, serverTimeManager: mockServerTimeManager)
        eventService.delegate = mockDelegate
        // 초기화 시 dispatched된 checkUserQueue/checkDeviceQueue 완료 대기
        eventService.userQueue.sync {}
    }

    override func tearDown() {
        eventService = nil
        mockAPI = nil
        mockCache = nil
        mockDelegate = nil
        super.tearDown()
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
        // userQueue에서 checkDeviceQueue 완료 대기
        eventService.userQueue.sync {}

        XCTAssertEqual(mockCache.device.token, testToken, "Device의 푸시 토큰이 업데이트되지 않음")
        XCTAssertEqual(mockAPI.lastRequestPath, "/v1/client/profile/device?project_id=mock_project")
    }

    func testTrackEventFails() {
        let eventName = "test_event_fail"
        let testProperties: [String: Any] = ["key": "value"]

        mockAPI.shouldFail = true
        eventService.trackEvent(eventName: eventName, eventProperties: testProperties)
        XCTAssertEqual(self.eventService.failedEventsStorage.getStoredData().count, 1)

        mockAPI.shouldFail = false
        eventService.trackEvent(eventName: "test_event_success", eventProperties: nil)
        XCTAssertEqual(self.eventService.failedEventsStorage.getStoredData().count, 0)
    }

    func testFailedEventsAreSentInBulk() {
        let events = (1...5).map {
            BulkEvent(id: "\($0)", name: "failed_event_\($0)", timestamp: Date(), properties: nil)
        }

        events.forEach { eventService.failedEventsStorage.saveData($0) }
        eventService.sendFailedEventsIfNeeded()

        XCTAssertEqual(self.mockAPI.lastRequestPath, "/v1/client/events/bulk?project_id=mock_project")
        XCTAssertEqual(self.mockAPI.lastBulkEvents?.count, 5, "벌크 이벤트가 정상적으로 전송되지 않음")
    }

    func testIdentifyFails() {
        let userId = "testUser_fail"
        let userProperties: [String: Any] = ["age": 30, "gender": "male"]

        // 실패 시 pendingUserProfile이 cache에 복구되어야 함
        mockAPI.shouldFail = true
        eventService.identify(userId: userId, userProperties: userProperties)
        eventService.userQueue.sync {}

        let pending: UpdateProfileRequest? = mockCache.loadCodableObject(forKey: EventService.pendingUserProfileKey)
        XCTAssertNotNil(pending, "identify 실패 시 pendingUserProfile이 cache에 저장되어야 함")
        XCTAssertEqual(pending?.userId, userId)

        // 성공 시 pendingUserProfile이 제거되어야 함
        mockAPI.shouldFail = false
        eventService.identify(userId: "testUser_success", userProperties: nil)
        eventService.userQueue.sync {}

        let pendingAfterSuccess: UpdateProfileRequest? = mockCache.loadCodableObject(forKey: EventService.pendingUserProfileKey)
        XCTAssertNil(pendingAfterSuccess, "identify 성공 후 pendingUserProfile이 제거되어야 함")
    }

    func testPendingUserProfileIsSentOnNextRequest() {
        // pending으로 저장된 user profile이 다음 요청 시 전송되어야 함
        let pendingRequest = UpdateProfileRequest(
            userId: "pending_user",
            properties: ["key": "value"].toAnyCodable(),
            device: mockCache.device.makeRequest()
        )
        mockCache.saveCodableObject(pendingRequest, key: EventService.pendingUserProfileKey)

        // identify 호출 시 checkUserQueue가 트리거되어 pending도 처리됨
        eventService.identify(userId: "new_user", userProperties: nil)
        eventService.userQueue.sync {}

        // pending이 처리되어 cache에서 제거되어야 함
        let remaining: UpdateProfileRequest? = mockCache.loadCodableObject(forKey: EventService.pendingUserProfileKey)
        XCTAssertNil(remaining, "pending user profile이 전송 후 제거되어야 함")
    }

    func testTrackEventClearsFailedEventsStorage() {
        let event = BulkEvent(
            id: "event_1",
            userId: "testUser",
            name: "test_event",
            timestamp: Date(),
            properties: ["key": "value"].toAnyCodable()
        )
        eventService.failedEventsStorage.saveData(event)

        XCTAssertEqual(eventService.failedEventsStorage.getStoredData().count, 1, "trackEvent 전에 failedEventsStorage에 데이터가 있어야 함")

        mockAPI.shouldFail = false
        eventService.trackEvent(eventName: "foo", eventProperties: nil)
        XCTAssertEqual(eventService.failedEventsStorage.getStoredData().count, 0, "trackEvent 후 failedEventsStorage가 비워지지 않음")
    }

    func testNewSessionCreatedIfLastEventTimeIsMoreThan30Minutes() {
        let thirtyOneMinutesAgo = Date().addingTimeInterval(-1860).timeIntervalSince1970
        UserDefaults.standard.set(thirtyOneMinutesAgo, forKey: "last_event_time")
        let previousSessionId = "existing-session-id"
        mockCache.sessionId = previousSessionId

        eventService.trackEvent(
            eventName: "test_event",
            eventProperties: ["key": "value"]
        )

        XCTAssertNotEqual(mockCache.sessionId, previousSessionId)
    }

    func testExistingSessionMaintainedIfWithin30Minutes() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300).timeIntervalSince1970
        let previousSessionId = "existing-session-id"
        mockCache.sessionId = previousSessionId
        UserDefaults.standard.set(fiveMinutesAgo, forKey: "last_event_time")

        eventService.trackEvent(
            eventName: "test_event",
            eventProperties: ["key": "value"]
        )

        XCTAssertEqual(mockCache.sessionId, previousSessionId)
    }

    func testLastEventTimeIsUpdated() {
        eventService.trackEvent(
            eventName: "test_event",
            eventProperties: ["key": "value"]
        )

        let lastEventTimestamp = UserDefaults.standard.double(forKey: "last_event_time")
        let currentTime = Date().timeIntervalSince1970

        XCTAssertTrue(currentTime - lastEventTimestamp < 1, "Last event timestamp should be updated to the current time.")
    }
}
