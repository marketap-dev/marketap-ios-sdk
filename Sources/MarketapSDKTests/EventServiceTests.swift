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
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockAPI = MockMarketapAPI()
        mockCache = MockMarketapCache()
        mockServerTimeManager = MockServerTimeManager()
        mockDelegate = MockEventServiceDelegate()
        defaults = makeIsolatedDefaults(self)
        // 세션이 이미 진행 중인 상태에서 시작한다. 이걸 안 정해두면 빈 저장소에서
        // lastEventTimestamp == 0 이라 매 테스트가 mkt_session_start 를 한 번 더 발생시켜,
        // 이벤트 개수를 세는 테스트가 조용히 어긋난다(예전엔 이전 실행이 남긴 값 덕에
        // 우연히 맞았다). 세션 자체를 검증하는 테스트는 각자 이 값을 덮어쓴다.
        defaults.set(Date().timeIntervalSince1970, forKey: "marketap_last_event_time")
        eventService = EventService(
            api: mockAPI, cache: mockCache,
            serverTimeManager: mockServerTimeManager, defaults: defaults
        )
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
        defaults.set(thirtyOneMinutesAgo, forKey: "marketap_last_event_time")
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
        defaults.set(fiveMinutesAgo, forKey: "marketap_last_event_time")

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

        let lastEventTimestamp = defaults.double(forKey: "marketap_last_event_time")
        let currentTime = Date().timeIntervalSince1970

        XCTAssertTrue(currentTime - lastEventTimestamp < 1, "Last event timestamp should be updated to the current time.")
    }

    /// 디바이스 전송 dedupe 는 스냅샷과 그 타임스탬프 두 값을 같이 보는데, 이 둘이 서로 다른
    /// 저장소에 있으면(스냅샷은 cache, 타임스탬프는 defaults) 한쪽만 비어 있을 때 TTL 판단이
    /// 깨진다. 두 저장소를 일부러 갈라놓고 그래도 판단이 유지되는지 본다.
    func testDeviceDedupeStateSurvivesSeparateDefaultsStore() {
        eventService.updateDevice(pushToken: "token-1")
        eventService.userQueue.sync {}
        XCTAssertEqual(
            mockAPI.lastRequestPath, "/v1/client/profile/device?project_id=mock_project",
            "첫 전송은 실제로 나가야 한다"
        )

        // cache 는 그대로 유지한 채 세션 타이밍 저장소만 다른 suite 로 바꿔 다시 시작한다.
        // 타임스탬프가 cache 가 아니라 defaults 에 있으면 여기서 TTL 을 통째로 잃는다.
        let otherDefaults = makeIsolatedDefaults(self)
        otherDefaults.set(Date().timeIntervalSince1970, forKey: "marketap_last_event_time")
        let restarted = EventService(
            api: mockAPI, cache: mockCache,
            serverTimeManager: mockServerTimeManager, defaults: otherDefaults
        )
        restarted.userQueue.sync {}
        mockAPI.lastRequestPath = nil

        restarted.updateDevice(pushToken: "token-1")
        restarted.userQueue.sync {}

        XCTAssertNil(
            mockAPI.lastRequestPath,
            "디바이스 정보가 같고 TTL 안이면 저장소 구성과 무관하게 재전송하지 않아야 한다"
        )
    }

    /// 반대 방향: cache 에 있는 타임스탬프가 TTL 을 넘겼으면 다시 보내야 한다.
    /// 타임스탬프가 defaults 에 있으면 이 조작이 무시돼 잘못 건너뛴다.
    func testDeviceIsResentWhenStoredTimestampIsExpired() {
        eventService.updateDevice(pushToken: "token-1")
        eventService.userQueue.sync {}

        let expiredAt = Date().timeIntervalSince1970 - EventService.deviceRequestTTL - 60
        mockCache.saveCodableObject(expiredAt, key: EventService.lastSentDeviceRequestAtKey)

        let restarted = EventService(
            api: mockAPI, cache: mockCache,
            serverTimeManager: mockServerTimeManager, defaults: defaults
        )
        restarted.userQueue.sync {}
        mockAPI.lastRequestPath = nil

        restarted.updateDevice(pushToken: "token-1")
        restarted.userQueue.sync {}

        XCTAssertEqual(
            mockAPI.lastRequestPath, "/v1/client/profile/device?project_id=mock_project",
            "TTL 이 지난 스냅샷은 다시 전송해야 한다"
        )
    }
}
