import XCTest
@testable import MarketapSDK

private class ImmediateServerTime: ServerTimeManagerProtocol {
    func withServerTime(completion: @escaping (Date?) -> Void) {
        completion(Date())
    }
}

private class CapturingAPI: MarketapAPIProtocol {
    var sentEvents: [(name: String, properties: [String: Any])] = []

    func get<T: Decodable>(baseURL: MarketapAPI.BaseURL, path: String, queryItems: [URLQueryItem]?, responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?) {
        completion?(.failure(.serverError(statusCode: 500)))
    }

    func request<T: Decodable, U: Encodable>(baseURL: MarketapAPI.BaseURL, path: String, body: U, responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?) {
        completion?(.failure(.serverError(statusCode: 500)))
    }

    func requestWithoutResponse<U: Encodable>(baseURL: MarketapAPI.BaseURL, path: String, body: U, completion: ((Result<Void, MarketapError>) -> Void)?) {
        if path.hasPrefix("/v1/client/events?"),
           let data = try? JSONEncoder().encode(body),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = json["name"] as? String {
            sentEvents.append((name, json["properties"] as? [String: Any] ?? [:]))
        }
        completion?(.success(()))
    }
}

final class SessionUtmTests: XCTestCase {
    private var cache: MockMarketapCache!
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        super.setUp()
        cache = MockMarketapCache()
    }

    private func makeStore(isEnabled: @escaping () -> Bool = { true }) -> SessionUtmStore {
        SessionUtmStore(cache: cache, now: { [unowned self] in self.clock }, isEnabled: isEnabled)
    }

    func testIncomingEventKeepsUtmAndGetsSessionUtm() {
        let result = makeStore().apply(["mkt_utm_source": "naver", "mkt_utm_medium": "cpc", "a": 1], sessionId: "s1")
        XCTAssertEqual(result["mkt_utm_source"] as? String, "naver")
        XCTAssertEqual(result["mkt_session_utm_source"] as? String, "naver")
        XCTAssertEqual(result["mkt_session_utm_medium"] as? String, "cpc")
    }

    func testLaterEventsGetOnlySessionUtm() {
        let store = makeStore()
        _ = store.apply(["mkt_utm_source": "naver"], sessionId: "s1")

        let next = store.apply(["b": 2], sessionId: "s1")
        XCTAssertEqual(next["mkt_session_utm_source"] as? String, "naver")
        XCTAssertNil(next["mkt_utm_source"])
        XCTAssertEqual(next["b"] as? Int, 2)
    }

    func testNewUtmReplacesWholeSetAndNewSessionGetsNothing() {
        let store = makeStore()
        _ = store.apply(["mkt_utm_source": "naver", "mkt_utm_campaign": "fall"], sessionId: "s1")
        _ = store.apply(["mkt_utm_source": "kakao"], sessionId: "s1")

        let next = store.apply([:], sessionId: "s1")
        XCTAssertEqual(next["mkt_session_utm_source"] as? String, "kakao")
        XCTAssertNil(next["mkt_session_utm_campaign"])
        XCTAssertNil(store.apply([:], sessionId: "s2")["mkt_session_utm_source"])
    }

    func testPendingUtmIsUsedFromNextEventWithoutMktUtm() {
        let store = makeStore()
        store.setPending(["mkt_utm_source": "meta", "mkt_utm_campaign": "winter"])

        for props in [store.apply(["a": 1], sessionId: "s1"), store.apply(["b": 2], sessionId: "s1")] {
            XCTAssertEqual(props["mkt_session_utm_source"] as? String, "meta")
            XCTAssertEqual(props["mkt_session_utm_campaign"] as? String, "winter")
            XCTAssertNil(props["mkt_utm_source"])
        }
    }

    func testPendingExpiresAndEventUtmWins() {
        let store = makeStore()
        store.setPending(["mkt_utm_source": "meta"])
        clock = clock.addingTimeInterval(SessionUtmStore.pendingTTL + 1)
        XCTAssertNil(store.apply(["a": 1], sessionId: "s1")["mkt_session_utm_source"])

        store.setPending(["mkt_utm_source": "meta"])
        XCTAssertEqual(store.apply(["mkt_utm_source": "naver"], sessionId: "s1")["mkt_session_utm_source"] as? String, "naver")
        XCTAssertEqual(store.apply([:], sessionId: "s1")["mkt_session_utm_source"] as? String, "naver")
    }

    func testDisabledStoreNeitherSavesNorAttachesNorKeepsPending() {
        var enabled = false
        let store = makeStore { enabled }

        let withUtm = store.apply(["mkt_utm_source": "naver", "a": 1], sessionId: "s1")
        XCTAssertEqual(withUtm["mkt_utm_source"] as? String, "naver")
        XCTAssertNil(withUtm["mkt_session_utm_source"])
        store.setPending(["mkt_utm_source": "meta"])

        enabled = true
        XCTAssertNil(store.apply(["b": 2], sessionId: "s1")["mkt_session_utm_source"])
    }

    func testUtmFromUrl() {
        let utm = SessionUtmStore.utm(fromUrl: "myapp://product/1?utm_source=naver&utm_medium=&utm_campaign=%EA%B0%80%EC%9D%84%20%EC%84%B8%EC%9D%BC&id=3")
        XCTAssertEqual(utm, ["mkt_utm_source": "naver", "mkt_utm_campaign": "가을 세일"])
        XCTAssertEqual(SessionUtmStore.utm(fromUrl: "https://a.com/b"), [:])
    }

    private func policyPayload(_ json: String) -> AnyCodable {
        try! JSONDecoder().decode(AnyCodable.self, from: Data(json.utf8))
    }

    private func makeService(defaults: UserDefaults, policyStore: RemotePolicyStore? = nil) -> (EventService, CapturingAPI) {
        let api = CapturingAPI()
        let service = EventService(api: api, cache: cache, serverTimeManager: ImmediateServerTime(), defaults: defaults, policyStore: policyStore)
        service.userQueue.sync {}
        return (service, api)
    }

    func testSessionOpeningUtmGoesToSessionStartAsSessionUtmOnly() {
        let (service, api) = makeService(defaults: makeIsolatedDefaults(self))

        service.trackEvent(eventName: "mkt_page_view", eventProperties: ["mkt_utm_source": "naver"])
        service.trackEvent(eventName: "mkt_add_to_cart", eventProperties: ["product": "p"])

        XCTAssertEqual(api.sentEvents.map { $0.name }, ["mkt_session_start", "mkt_page_view", "mkt_add_to_cart"])
        XCTAssertEqual(api.sentEvents.map { $0.properties["mkt_utm_source"] as? String }, [nil, "naver", nil])
        for event in api.sentEvents {
            XCTAssertEqual(event.properties["mkt_session_utm_source"] as? String, "naver", event.name)
        }
    }

    func testSetPendingBeforeSessionOpenGoesToSessionStart() {
        let (service, api) = makeService(defaults: makeIsolatedDefaults(self))

        service.setPendingUtm(["mkt_utm_source": "meta"])
        service.trackEvent(eventName: "mkt_first_visit", eventProperties: nil)
        service.trackEvent(eventName: "mkt_page_view", eventProperties: [:])

        XCTAssertEqual(api.sentEvents.map { $0.name }, ["mkt_session_start", "mkt_first_visit", "mkt_page_view"])
        for event in api.sentEvents {
            XCTAssertEqual(event.properties["mkt_session_utm_source"] as? String, "meta", event.name)
            XCTAssertNil(event.properties["mkt_utm_source"], event.name)
        }
    }

    func testInAppEventsGetSessionUtm() {
        let (service, api) = makeService(defaults: makeIsolatedDefaults(self))

        service.trackEvent(eventName: "mkt_page_view", eventProperties: ["mkt_utm_source": "naver"])
        service.trackEvent(eventName: "mkt_delivery_message", eventProperties: ["mkt_campaign_id": "c1"])

        XCTAssertEqual(api.sentEvents.last?.properties["mkt_session_utm_source"] as? String, "naver")
        XCTAssertNil(api.sentEvents.last?.properties["mkt_utm_source"])
    }

    func testNextSessionStartDoesNotGetPreviousUtm() {
        let defaults = makeIsolatedDefaults(self)
        let (service, api) = makeService(defaults: defaults)

        service.trackEvent(eventName: "mkt_page_view", eventProperties: ["mkt_utm_source": "naver"])
        defaults.set(Date().addingTimeInterval(-1860).timeIntervalSince1970, forKey: "marketap_last_event_time")
        service.trackEvent(eventName: "mkt_page_view", eventProperties: [:])

        let second = Array(api.sentEvents.dropFirst(2))
        XCTAssertEqual(second.map { $0.name }, ["mkt_session_start", "mkt_page_view"])
        for event in second {
            XCTAssertNil(event.properties["mkt_session_utm_source"], event.name)
        }
    }

    func testRemotePolicySessionUtmStopTurnsItOff() {
        let defaults = makeIsolatedDefaults(self)
        let policyStore = RemotePolicyStore(projectId: UUID().uuidString, defaults: defaults)
        policyStore.received(policyPayload("{\"version\":1,\"revision\":1,\"inApp\":{\"mode\":\"stop\"}}"))
        let (service, api) = makeService(defaults: defaults, policyStore: policyStore)

        service.trackEvent(eventName: "mkt_page_view", eventProperties: ["mkt_utm_source": "naver"])
        service.trackEvent(eventName: "mkt_add_to_cart", eventProperties: [:])
        XCTAssertEqual(api.sentEvents.map { $0.properties["mkt_session_utm_source"] as? String }, ["naver", "naver", "naver"])

        policyStore.received(policyPayload("{\"version\":1,\"revision\":2,\"sessionUtm\":{\"mode\":\"stop\"}}"))
        service.trackEvent(eventName: "mkt_add_to_cart", eventProperties: [:])
        XCTAssertNil(api.sentEvents.last?.properties["mkt_session_utm_source"])
    }
}
