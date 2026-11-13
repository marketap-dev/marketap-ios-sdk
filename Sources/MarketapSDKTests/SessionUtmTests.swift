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

    override func setUp() {
        super.setUp()
        cache = MockMarketapCache()
    }

    func testEventWithUtmIsKeptAndLaterEventsGetIt() {
        let store = SessionUtmStore(cache: cache)
        let first = store.apply(["mkt_utm_source": "naver", "mkt_utm_medium": "cpc", "a": 1], sessionId: "s1")
        XCTAssertEqual(first["mkt_utm_source"] as? String, "naver")

        let next = store.apply(["b": 2], sessionId: "s1")
        XCTAssertEqual(next["mkt_utm_source"] as? String, "naver")
        XCTAssertEqual(next["mkt_utm_medium"] as? String, "cpc")
        XCTAssertEqual(next["b"] as? Int, 2)
    }

    func testNewUtmReplacesWholeSet() {
        let store = SessionUtmStore(cache: cache)
        _ = store.apply(["mkt_utm_source": "naver", "mkt_utm_medium": "cpc", "mkt_utm_campaign": "fall"], sessionId: "s1")
        _ = store.apply(["mkt_utm_source": "kakao", "mkt_utm_medium": "message"], sessionId: "s1")

        let next = store.apply([:], sessionId: "s1")
        XCTAssertEqual(next["mkt_utm_source"] as? String, "kakao")
        XCTAssertEqual(next["mkt_utm_medium"] as? String, "message")
        XCTAssertNil(next["mkt_utm_campaign"])
    }

    func testNewSessionDoesNotGetPreviousUtm() {
        let store = SessionUtmStore(cache: cache)
        _ = store.apply(["mkt_utm_source": "naver"], sessionId: "s1")

        XCTAssertNil(store.apply(["a": 1], sessionId: "s2")["mkt_utm_source"])
    }

    func testEmptyUtmIsTreatedAsMissing() {
        let store = SessionUtmStore(cache: cache)
        _ = store.apply(["mkt_utm_source": "naver"], sessionId: "s1")

        XCTAssertEqual(store.apply(["mkt_utm_source": ""], sessionId: "s1")["mkt_utm_source"] as? String, "naver")
    }

    private func makeService(defaults: UserDefaults) -> (EventService, CapturingAPI) {
        let api = CapturingAPI()
        let service = EventService(api: api, cache: cache, serverTimeManager: ImmediateServerTime(), defaults: defaults)
        service.userQueue.sync {}
        return (service, api)
    }

    func testSessionOpeningUtmIsOnSessionStartAndLaterEvents() {
        let defaults = makeIsolatedDefaults(self)
        let (service, api) = makeService(defaults: defaults)

        service.trackEvent(eventName: "mkt_page_view", eventProperties: ["mkt_utm_source": "naver"])
        service.trackEvent(eventName: "mkt_add_to_cart", eventProperties: ["product": "p"])

        XCTAssertEqual(api.sentEvents.map { $0.name }, ["mkt_session_start", "mkt_page_view", "mkt_add_to_cart"])
        for event in api.sentEvents {
            XCTAssertEqual(event.properties["mkt_utm_source"] as? String, "naver", event.name)
        }
    }

    func testInAppEventsGetSessionUtm() {
        let defaults = makeIsolatedDefaults(self)
        let (service, api) = makeService(defaults: defaults)

        service.trackEvent(eventName: "mkt_page_view", eventProperties: ["mkt_utm_source": "naver"])
        service.trackEvent(eventName: "mkt_delivery_message", eventProperties: ["mkt_campaign_id": "c1"])

        XCTAssertEqual(api.sentEvents.last?.name, "mkt_delivery_message")
        XCTAssertEqual(api.sentEvents.last?.properties["mkt_utm_source"] as? String, "naver")
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
            XCTAssertNil(event.properties["mkt_utm_source"], event.name)
        }
    }
}
