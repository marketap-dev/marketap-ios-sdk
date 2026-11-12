import XCTest
@testable import MarketapSDK
@testable import MarketapSDKNotificationServiceExtension

private final class PolicyBundle: Bundle {
    override func object(forInfoDictionaryKey key: String) -> Any? {
        key == "MarketapAppGroupIdentifier" ? "group.policy.tests" : nil
    }
}

private final class PolicyAPI: MarketapAPIProtocol {
    private let lock = NSLock()
    private var _paths: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return _paths }
    var policy: AnyCodable?
    var fails = false
    var holdEvents = false
    var heldEvent: ((Result<Void, MarketapError>) -> Void)?
    var campaignsResponse: ((String?) -> InAppCampaignFetchResponse)?
    var campaignChecksums: [String?] = []

    func get<T: Decodable>(baseURL: MarketapAPI.BaseURL, path: String, queryItems: [URLQueryItem]?, responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?) {
        lock.lock(); _paths.append(path); lock.unlock()
        if fails {
            completion?(.failure(.serverError(statusCode: 500)))
        } else if let response = SyncDateResponse(serverTimeOffset: 0, useWebClickRouting: true, sdkPolicy: policy) as? T {
            completion?(.success(response))
        }
    }

    func request<T: Decodable, U: Encodable>(baseURL: MarketapAPI.BaseURL, path: String, body: U, responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?) {
        lock.lock(); _paths.append(path); lock.unlock()
        if let body = body as? FetchCampaignsRequest, let response = campaignsResponse?(body.checksum) as? T {
            campaignChecksums.append(body.checksum)
            completion?(.success(response))
            return
        }
        completion?(.failure(.serverError(statusCode: 500)))
    }

    func requestWithoutResponse<U: Encodable>(baseURL: MarketapAPI.BaseURL, path: String, body: U, completion: ((Result<Void, MarketapError>) -> Void)?) {
        lock.lock(); _paths.append(path); lock.unlock()
        if holdEvents && path.contains("/events") {
            heldEvent = completion
        } else {
            completion?(fails ? .failure(.serverError(statusCode: 500)) : .success(()))
        }
    }
}

private final class PolicyTime: ServerTimeManagerProtocol {
    var refresh: (() -> Void)?
    var calls = 0
    func withServerTime(completion: @escaping (Date?) -> Void) {
        calls += 1
        refresh?()
        completion(Date())
    }
}

private final class HeldTime: ServerTimeManagerProtocol {
    var holds = false
    var held: [(Date?) -> Void] = []
    func withServerTime(completion: @escaping (Date?) -> Void) {
        if holds { held.append(completion) } else { completion(Date()) }
    }
}

private final class PolicyRequestLog {
    private let lock = NSLock()
    private var _urls: [String] = []
    var urls: [String] { lock.lock(); defer { lock.unlock() }; return _urls }
    func record(_ url: String) { lock.lock(); _urls.append(url); lock.unlock() }
}

final class RemotePolicyTests: XCTestCase {
    private func payload(_ json: String) -> AnyCodable {
        try! JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
    }

    private func stopped(_ revision: Int, refresh: Int = 300) -> AnyCodable {
        payload("{\"version\":1,\"revision\":\(revision),\"refreshAfterSec\":\(refresh),\"collection\":{\"mode\":\"stop\"},\"inApp\":{\"mode\":\"stop\"},\"pushTracking\":{\"mode\":\"stop\"}}")
    }

    func test_미지원_버전과_16KB_초과는_정책을_유지한다() {
        let store = RemotePolicyStore(projectId: UUID().uuidString, defaults: makeIsolatedDefaults(self))
        store.received(stopped(10))
        for _ in 0..<2 { store.received(payload("{\"version\":2,\"revision\":11}")) }
        XCTAssertFalse(store.isAllowed(.collection))
        XCTAssertEqual(store.revision, 10)
        store.received(payload("{\"version\":1,\"revision\":12,\"unknown\":\"\(String(repeating: "x", count: 16384))\"}"))
        XCTAssertEqual(store.revision, 10)
        XCTAssertFalse(store.isAllowed(.pushTracking))
    }

    func test_revision_역전과_동일값을_무시하고_새_정책으로_전체_교체한다() {
        let store = RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self))
        store.received(stopped(10))
        for revision in [9, 10] {
            store.received(payload("{\"version\":1,\"revision\":\(revision)}"))
            XCTAssertFalse(store.isAllowed(.collection))
        }
        store.received(payload("{\"version\":1,\"revision\":11,\"unknownBlock\":{\"mode\":\"stop\"},\"inApp\":{\"mode\":\"allow\",\"unknown\":1}}"))
        for block in RemotePolicyStore.Block.allCases { XCTAssertTrue(store.isAllowed(block)) }
        XCTAssertEqual(store.revision, 11)
    }

    func test_아는_블록의_잘못된_mode만_이전_상태를_유지한다() {
        let store = RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self))
        store.received(stopped(1))
        store.received(payload("{\"version\":1,\"revision\":2,\"collection\":{\"mode\":\"new-mode\"},\"inApp\":{\"mode\":\"allow\"}}"))
        XCTAssertFalse(store.isAllowed(.collection))
        XCTAssertTrue(store.isAllowed(.inApp))
        XCTAssertTrue(store.isAllowed(.pushTracking))
    }

    func test_만료는_조회실패_상황에서도_allow로_전환된다() {
        var now = ISO8601DateFormatter().date(from: "2026-11-11T08:59:59Z")!
        let store = RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self), now: { now })
        store.received(payload("{\"version\":1,\"revision\":1,\"collection\":{\"mode\":\"stop\",\"expiresAt\":\"2026-11-11T09:00:00Z\"},\"pushTracking\":{\"mode\":\"stop\",\"expiresAt\":\"2026-11-11T09:00:00.000Z\"}}"))
        XCTAssertFalse(store.isAllowed(.collection))
        XCTAssertFalse(store.isAllowed(.pushTracking))
        now.addTimeInterval(1)
        XCTAssertTrue(store.isAllowed(.collection))
        XCTAssertTrue(store.isAllowed(.pushTracking))
        XCTAssertTrue(store.isAllowed(.collection))
    }

    func test_정책_없는_응답은_저장된_정책을_그대로_유지한다() throws {
        let defaults = makeIsolatedDefaults(self)
        let store = RemotePolicyStore(projectId: "p", defaults: defaults)
        store.received(stopped(1))
        let persisted = defaults.data(forKey: RemotePolicyStore.keyPrefix + "p")
        let response = try JSONDecoder().decode(SyncDateResponse.self, from: Data("{\"serverTimeOffset\":123,\"useWebClickRouting\":false}".utf8))
        store.received(response.sdkPolicy)
        XCTAssertEqual(response.serverTimeOffset, 123)
        XCTAssertFalse(response.useWebClickRouting)
        XCTAssertFalse(store.isAllowed(.collection))
        XCTAssertEqual(store.revision, 1)
        XCTAssertEqual(defaults.data(forKey: RemotePolicyStore.keyPrefix + "p"), persisted)
        let fresh = RemotePolicyStore(projectId: "q", defaults: makeIsolatedDefaults(self))
        fresh.received(response.sdkPolicy)
        for block in RemotePolicyStore.Block.allCases { XCTAssertTrue(fresh.isAllowed(block)) }
        XCTAssertNil(fresh.revision)
    }

    func test_정책_갱신주기는_기본값과_clamp를_적용한다() {
        for (input, expected) in [(nil, 300), (0, 60), (90, 90), (4000, 3600)] as [(Int?, Int)] {
            var now = Date()
            let store = RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self), now: { now })
            XCTAssertTrue(store.needsRefresh)
            let field = input.map { ",\"refreshAfterSec\":\($0)" } ?? ""
            store.received(payload("{\"version\":1,\"revision\":1\(field)}"))
            now.addTimeInterval(Double(expected - 1))
            XCTAssertFalse(store.needsRefresh)
            now.addTimeInterval(1)
            XCTAssertTrue(store.needsRefresh)
        }
    }

    func test_프로젝트별_영속저장은_AppGroup이_있으면_공유저장소를_쓴다() {
        let fallback = makeIsolatedDefaults(self)
        let group = makeIsolatedDefaults(self)
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(5))
        let store = RemotePolicyStore(projectId: "a", defaults: fallback, bundle: PolicyBundle(), defaultsProvider: { _ in group })
        store.received(payload("{\"version\":1,\"revision\":20,\"pushTracking\":{\"mode\":\"stop\",\"expiresAt\":\"\(expiry)\"}}"))
        XCTAssertNil(fallback.data(forKey: RemotePolicyStore.keyPrefix + "a"))
        XCTAssertEqual(RemotePolicyStore(projectId: "a", defaults: group).revision, 20)
        XCTAssertTrue(RemotePolicyStore(projectId: "b", defaults: group).isAllowed(.pushTracking))
    }

    func test_SDK_버전이나_래퍼가_바뀌면_저장된_정책을_버리고_저장소에서도_지운다() {
        let defaults = makeIsolatedDefaults(self)
        let key = RemotePolicyStore.keyPrefix + "p"
        for (version, type) in [("1.6.0", "flutter"), ("1.5.0", "ios")] {
            RemotePolicyStore(projectId: "p", sdkVersion: "1.5.0", sdkType: "flutter", defaults: defaults).received(stopped(10))
            XCTAssertFalse(RemotePolicyStore(projectId: "p", sdkVersion: "1.5.0", sdkType: "flutter", defaults: defaults).isAllowed(.collection))
            XCTAssertNotNil(defaults.data(forKey: key))
            let updated = RemotePolicyStore(projectId: "p", sdkVersion: version, sdkType: type, defaults: defaults)
            for block in RemotePolicyStore.Block.allCases { XCTAssertTrue(updated.isAllowed(block)) }
            XCTAssertNil(updated.revision)
            XCTAssertNil(defaults.data(forKey: key))
            updated.received(payload("{\"version\":1,\"revision\":10}"))
            XCTAssertEqual(updated.revision, 10)
            XCTAssertTrue(updated.isAllowed(.collection))
            XCTAssertEqual(RemotePolicyStore(projectId: "p", sdkVersion: version, sdkType: type, defaults: defaults).revision, 10)
            defaults.removeObject(forKey: key)
        }
    }

    func test_시간캐시가_유효해도_정책갱신은_serverInfo를_재사용하고_실패시_유지한다() {
        var now = Date()
        let store = RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self), now: { now })
        let api = PolicyAPI()
        api.policy = stopped(1, refresh: 60)
        let manager = ServerTimeManager(api: api, projectId: "p", policyStore: store, now: { now })
        func fetch() {
            let done = expectation(description: "server-info")
            manager.withServerTime { _ in done.fulfill() }
            wait(for: [done], timeout: 30)
        }
        fetch()
        XCTAssertFalse(store.isAllowed(.collection))
        fetch()
        XCTAssertEqual(api.paths.count, 1)
        now.addTimeInterval(60)
        api.fails = true
        fetch()
        XCTAssertEqual(api.paths.count, 2)
        XCTAssertFalse(store.isAllowed(.collection))
        api.fails = false
        api.policy = payload("{\"version\":1,\"revision\":2}")
        now.addTimeInterval(59)
        fetch()
        XCTAssertEqual(api.paths.count, 2)
        XCTAssertFalse(store.isAllowed(.collection))
        now.addTimeInterval(1)
        fetch()
        XCTAssertEqual(api.paths.count, 3)
        XCTAssertTrue(store.isAllowed(.collection))
        XCTAssertTrue(api.paths.allSatisfy { $0 == "/api/v2/meta/server-info" })
    }

    func test_serverInfo_조회에_실패하면_60초_동안_다시_조회하지_않는다() {
        var now = Date()
        let api = PolicyAPI()
        api.fails = true
        let manager = ServerTimeManager(api: api, projectId: "p", policyStore: RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self)), now: { now })
        func fetch() {
            let done = expectation(description: "server-info")
            manager.withServerTime { time in
                XCTAssertNotNil(time)
                done.fulfill()
            }
            wait(for: [done], timeout: 30)
        }
        fetch()
        fetch()
        now.addTimeInterval(59)
        fetch()
        XCTAssertEqual(api.paths.count, 1)
        now.addTimeInterval(1)
        api.fails = false
        fetch()
        fetch()
        XCTAssertEqual(api.paths.count, 2)
    }

    func test_다른_프로젝트의_serverInfo_진행중_요청을_공유하지_않는다() {
        let apiA = PolicyAPI()
        apiA.policy = stopped(1)
        let apiB = PolicyAPI()
        let a = RemotePolicyStore(projectId: "a", defaults: makeIsolatedDefaults(self))
        let b = RemotePolicyStore(projectId: "b", defaults: makeIsolatedDefaults(self))
        let managerA = ServerTimeManager(api: apiA, projectId: "a", policyStore: a)
        let managerB = ServerTimeManager(api: apiB, projectId: "b", policyStore: b)
        let doneA = expectation(description: "a")
        let doneB = expectation(description: "b")
        managerA.withServerTime { _ in doneA.fulfill() }
        managerB.withServerTime { _ in doneB.fulfill() }
        wait(for: [doneA, doneB], timeout: 30)
        XCTAssertFalse(a.isAllowed(.collection))
        XCTAssertTrue(b.isAllowed(.collection))
        XCTAssertEqual(apiA.paths.count, 1)
        XCTAssertEqual(apiB.paths.count, 1)
    }

    func test_서버_응답_예시를_그대로_해석하고_이미_지난_expiresAt은_allow로_받는다() throws {
        let json = "{\"serverTimeOffset\":0,\"useWebClickRouting\":false,\"sdkPolicy\":{\"version\":1,\"revision\":1794280000000,\"refreshAfterSec\":300,\"collection\":{\"mode\":\"stop\",\"expiresAt\":\"2026-11-11T09:00:00Z\"},\"inApp\":{\"mode\":\"allow\"},\"pushTracking\":{\"mode\":\"allow\"},\"future\":{\"mode\":\"stop\"}}}"
        let response = try JSONDecoder().decode(SyncDateResponse.self, from: Data(json.utf8))
        let before = ISO8601DateFormatter().date(from: "2026-11-11T08:00:00Z")!
        let after = ISO8601DateFormatter().date(from: "2026-11-11T09:00:01Z")!
        let early = RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self), now: { before })
        early.received(response.sdkPolicy)
        XCTAssertEqual(early.revision, 1794280000000)
        XCTAssertFalse(early.isAllowed(.collection))
        XCTAssertTrue(early.isAllowed(.inApp))
        XCTAssertTrue(early.isAllowed(.pushTracking))
        let late = RemotePolicyStore(projectId: "p", defaults: makeIsolatedDefaults(self), now: { after })
        late.received(response.sdkPolicy)
        XCTAssertEqual(late.revision, 1794280000000)
        XCTAssertTrue(late.isAllowed(.collection))
    }

    func test_stop_전환은_이벤트큐와_대기프로필을_지우고_토큰등록은_계속한다() {
        let defaults = makeIsolatedDefaults(self)
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        let cache = MockMarketapCache()
        let api = PolicyAPI()
        let time = PolicyTime()
        let events = EventService(api: api, cache: cache, serverTimeManager: time, defaults: defaults, policyStore: store)
        events.userQueue.sync {}
        let event = BulkEvent(id: "queued", userId: nil, name: "old", timestamp: nil, properties: nil)
        events.failedEventsStorage.saveData(event)
        cache.saveCodableObject("pending-profile", key: EventService.pendingUserProfileKey)
        XCTAssertEqual(events.failedEventsStorage.getStoredData().count, 1)
        store.received(stopped(1))
        XCTAssertTrue(events.failedEventsStorage.getStoredData().isEmpty)
        XCTAssertNil(cache.loadCodableObject(forKey: EventService.pendingUserProfileKey) as String?)
        let count = api.paths.count
        events.trackEvent(eventName: "blocked", eventProperties: nil)
        events.identify(userId: "blocked-user", userProperties: ["x": 1])
        events.setUserProperties(userProperties: ["x": 2], userId: "blocked-user")
        events.sendFailedEventsIfNeeded()
        events.userQueue.sync {}
        XCTAssertEqual(api.paths.count, count)
        XCTAssertNil(cache.loadCodableObject(forKey: EventService.pendingUserProfileKey) as UpdateProfileRequest?)
        events.setPushToken(token: "new-token")
        events.userQueue.sync {}
        XCTAssertEqual(api.paths.last, "/v1/client/profile/device?project_id=mock_project")
        XCTAssertTrue(events.failedEventsStorage.getStoredData().isEmpty)
    }

    func test_중지중_갱신으로_allow를_받으면_새_데이터부터_보낸다() {
        let defaults = makeIsolatedDefaults(self)
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        store.received(stopped(1))
        let api = PolicyAPI()
        let time = PolicyTime()
        let events = EventService(api: api, cache: MockMarketapCache(), serverTimeManager: time, defaults: defaults, policyStore: store)
        events.trackEvent(eventName: "discarded", eventProperties: nil)
        XCTAssertFalse(api.paths.contains { $0.contains("/events") })
        let calls = time.calls
        time.refresh = { store.received(self.payload("{\"version\":1,\"revision\":2}")) }
        events.trackEvent(eventName: "new", eventProperties: nil)
        XCTAssertGreaterThan(time.calls, calls)
        XCTAssertTrue(api.paths.contains { $0.contains("/events") })
        XCTAssertTrue(events.failedEventsStorage.getStoredData().isEmpty)
    }

    func test_실제_중지중_이벤트가_정책을_먼저_갱신하고_해제_신호를_받는다() {
        var now = Date()
        let defaults = makeIsolatedDefaults(self)
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults, now: { now })
        let api = PolicyAPI()
        api.policy = stopped(1, refresh: 60)
        let manager = ServerTimeManager(api: api, projectId: "mock_project", policyStore: store)
        let events = EventService(api: api, cache: MockMarketapCache(), serverTimeManager: manager, defaults: defaults, policyStore: store)
        let ready = expectation(description: "initial policy")
        manager.withServerTime { _ in ready.fulfill() }
        wait(for: [ready], timeout: 30)
        XCTAssertFalse(store.isAllowed(.collection))
        events.trackEvent(eventName: "discarded", eventProperties: nil)
        let discarded = expectation(description: "discard finished")
        manager.withServerTime { _ in discarded.fulfill() }
        wait(for: [discarded], timeout: 30)
        XCTAssertFalse(api.paths.contains { $0.contains("/events") })
        let previous = api.paths.count
        now.addTimeInterval(60)
        api.policy = payload("{\"version\":1,\"revision\":2}")
        events.trackEvent(eventName: "resumed", eventProperties: nil)
        waitUntil(self, "resumed event") { api.paths.contains { $0.contains("/events") } }
        XCTAssertEqual(api.paths[previous], "/api/v2/meta/server-info")
        XCTAssertTrue(store.isAllowed(.collection))
    }

    func test_중지_전_송신한_이벤트는_늦게_실패해도_큐에_복구하지_않는다() {
        let defaults = makeIsolatedDefaults(self)
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        let api = PolicyAPI()
        api.holdEvents = true
        defaults.set(Date().timeIntervalSince1970, forKey: "marketap_last_event_time")
        let events = EventService(api: api, cache: MockMarketapCache(), serverTimeManager: PolicyTime(), defaults: defaults, policyStore: store)
        events.trackEvent(eventName: "inflight", eventProperties: nil)
        XCTAssertNotNil(api.heldEvent)
        store.received(stopped(1))
        store.received(payload("{\"version\":1,\"revision\":2}"))
        api.heldEvent?(.failure(.serverError(statusCode: 503)))
        XCTAssertTrue(events.failedEventsStorage.getStoredData().isEmpty)
    }

    func test_pushTracking_stop은_앱의_푸시_추적만_막는다() {
        let defaults = makeIsolatedDefaults(self)
        defaults.set(Date().timeIntervalSince1970, forKey: "marketap_last_event_time")
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        store.received(payload("{\"version\":1,\"revision\":1,\"pushTracking\":{\"mode\":\"stop\"}}"))
        let api = PolicyAPI()
        let events = EventService(api: api, cache: MockMarketapCache(), serverTimeManager: PolicyTime(), defaults: defaults, policyStore: store)
        events.trackEvent(eventName: "mkt_click_message", eventProperties: ["mkt_channel_type": "PUSH"])
        XCTAssertFalse(api.paths.contains { $0.contains("/events") })
        events.trackEvent(eventName: "ordinary", eventProperties: nil)
        XCTAssertTrue(api.paths.contains { $0.contains("/events") })
    }

    func test_푸시_이벤트는_collection_stop이어도_pushTracking이_허용이면_보낸다() {
        let defaults = makeIsolatedDefaults(self)
        defaults.set(Date().timeIntervalSince1970, forKey: "marketap_last_event_time")
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        store.received(payload("{\"version\":1,\"revision\":1,\"collection\":{\"mode\":\"stop\"}}"))
        let api = PolicyAPI()
        let events = EventService(api: api, cache: MockMarketapCache(), serverTimeManager: PolicyTime(), defaults: defaults, policyStore: store)
        events.trackEvent(eventName: "ordinary", eventProperties: nil)
        XCTAssertFalse(api.paths.contains { $0.contains("/events") })
        events.trackEvent(eventName: "mkt_push_impression", eventProperties: nil)
        XCTAssertEqual(api.paths.filter { $0.contains("/events") }.count, 1)
        events.trackEvent(eventName: "mkt_click_message", eventProperties: ["mkt_channel_type": "PUSH"])
        XCTAssertEqual(api.paths.filter { $0.contains("/events") }.count, 2)
    }

    func test_저장된_stop은_재시작해도_유지되고_시작하면서_대기_데이터를_지운다() {
        let defaults = makeIsolatedDefaults(self)
        RemotePolicyStore(projectId: "mock_project", defaults: defaults).received(stopped(1))
        let restarted = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        XCTAssertFalse(restarted.isAllowed(.collection))
        let cache = MockMarketapCache()
        cache.saveCodableObject("pending-profile", key: EventService.pendingUserProfileKey)
        let events = EventService(api: PolicyAPI(), cache: cache, serverTimeManager: PolicyTime(), defaults: defaults, policyStore: restarted)
        events.userQueue.sync {}
        XCTAssertNil(cache.loadCodableObject(forKey: EventService.pendingUserProfileKey) as String?)
        XCTAssertTrue(events.failedEventsStorage.getStoredData().isEmpty)
    }

    func test_inApp_stop이_풀리면_이전_checksum없이_캠페인을_다시_받는다() {
        let defaults = makeIsolatedDefaults(self)
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        let cache = MockMarketapCache()
        let campaign = InAppCampaign(
            id: "c",
            layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
            triggerEventCondition: EventTriggerCondition(condition: Condition(eventFilter: EventFilter(eventName: "e"), propertyConditions: nil), frequencyCap: nil, delayMinutes: nil),
            html: nil,
            updatedAt: ""
        )
        let api = PolicyAPI()
        api.campaignsResponse = { InAppCampaignFetchResponse(checksum: "c1", campaigns: $0 == "c1" ? nil : [campaign]) }
        let service = InAppMessageService(customHandlerStore: MarketapCustomHandlerStore(), api: api, cache: cache, defaults: defaults, policyStore: store)
        service.campaignViewController = sharedTestWebViewController
        XCTAssertEqual(service.campaigns, [campaign])
        store.received(payload("{\"version\":1,\"revision\":1,\"inApp\":{\"mode\":\"stop\"}}"))
        service.fetchCampaigns()
        XCTAssertEqual(service.campaigns, [])
        XCTAssertNil(cache.loadCodableObject(forKey: InAppMessageService.checksumKey) as String?)
        XCTAssertNil(cache.loadCodableObject(forKey: InAppMessageService.lastFetchKey) as Date?)
        store.received(payload("{\"version\":1,\"revision\":2}"))
        var list: [InAppCampaign]?
        service.fetchCampaigns(completion: { list = $0 })
        XCTAssertEqual(api.campaignChecksums, [nil, nil])
        XCTAssertEqual(list, [campaign])
        XCTAssertEqual(service.campaigns, [campaign])
    }

    func test_inApp_stop은_목록과_단건_조회없이_캠페인_없음으로_처리한다() {
        let defaults = makeIsolatedDefaults(self)
        let store = RemotePolicyStore(projectId: "mock_project", defaults: defaults)
        store.received(stopped(1))
        let api = PolicyAPI()
        let service = InAppMessageService(customHandlerStore: MarketapCustomHandlerStore(), api: api, cache: MockMarketapCache(), defaults: defaults, policyStore: store)
        service.campaignViewController = sharedTestWebViewController
        var list: [InAppCampaign]?
        service.fetchCampaigns(force: true, completion: { list = $0 })
        XCTAssertEqual(list?.count, 0)
        var singleCalled = false
        service.fetchCampaign(campaignId: "c") { campaign in
            XCTAssertNil(campaign)
            singleCalled = true
        }
        XCTAssertTrue(singleCalled)
        XCTAssertTrue(api.paths.isEmpty)
        store.received(payload("{\"version\":1,\"revision\":2}"))
        service.fetchCampaigns(force: true)
        XCTAssertEqual(api.paths, ["/api/v2/campaigns"])
    }

    func test_NSE는_저장된_정책만_읽고_만료되면_추적을_허용한다() {
        let fallback = makeIsolatedDefaults(self)
        let group = makeIsolatedDefaults(self)
        let now = Date()
        let expiry = ISO8601DateFormatter().string(from: now.addingTimeInterval(5))
        RemotePolicyStore(projectId: "a", defaults: fallback, bundle: PolicyBundle(), defaultsProvider: { _ in group })
            .received(payload("{\"version\":1,\"revision\":20,\"pushTracking\":{\"mode\":\"stop\",\"expiresAt\":\"\(expiry)\"}}"))
        XCTAssertFalse(MarketapNotificationServiceClient.isPushTrackingAllowed(projectId: "a", bundle: PolicyBundle(), defaults: fallback, defaultsProvider: { _ in group }, now: now))
        XCTAssertTrue(MarketapNotificationServiceClient.isPushTrackingAllowed(projectId: "b", bundle: PolicyBundle(), defaults: fallback, defaultsProvider: { _ in group }, now: now))
        XCTAssertTrue(MarketapNotificationServiceClient.isPushTrackingAllowed(projectId: "a", bundle: PolicyBundle(), defaults: fallback, defaultsProvider: { _ in group }, now: now.addingTimeInterval(6)))
        _ = RemotePolicyStore(projectId: "a", sdkVersion: "0.0.0-updated", defaults: fallback, bundle: PolicyBundle(), defaultsProvider: { _ in group })
        XCTAssertTrue(MarketapNotificationServiceClient.isPushTrackingAllowed(projectId: "a", bundle: PolicyBundle(), defaults: fallback, defaultsProvider: { _ in group }, now: now))
    }

    func test_NSE는_pushTracking_stop이면_노출_추적을_보내지_않는다() {
        let defaults = makeIsolatedDefaults(self)
        RemotePolicyStore(projectId: "mock_project", defaults: defaults)
            .received(payload("{\"version\":1,\"revision\":1,\"pushTracking\":{\"mode\":\"stop\"}}"))
        let stoppedProject = UUID().uuidString
        let allowedProject = UUID().uuidString
        let standardKey = RemotePolicyStore.keyPrefix + stoppedProject
        UserDefaults.standard.set(defaults.data(forKey: RemotePolicyStore.keyPrefix + "mock_project"), forKey: standardKey)
        defer { UserDefaults.standard.removeObject(forKey: standardKey) }
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
        let log = PolicyRequestLog()
        StubURLProtocol.onRequest = { log.record($0.url?.absoluteString ?? "") }
        defer { StubURLProtocol.onRequest = nil }
        let client = MarketapNotificationServiceClient()
        client.handleImpression(.init(userId: "u", deviceId: "d", projectId: stoppedProject, campaignId: "c", messageId: "m", serverProperties: nil, imageUrl: nil))
        client.handleImpression(.init(userId: "u", deviceId: "d", projectId: allowedProject, campaignId: "c", messageId: "m", serverProperties: nil, imageUrl: nil))
        waitUntil(self, "allowed project impression") { log.urls.contains { $0.contains(allowedProject) } }
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(log.urls.contains { $0.contains(stoppedProject) })
    }
}
