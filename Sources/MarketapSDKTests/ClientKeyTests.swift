import XCTest
@testable import MarketapSDK

final class StubURLProtocol: URLProtocol {
    static var statusCode = 200
    static var responseBody = Data()
    static var lastRequest: URLRequest?
    static var onRequest: ((URLRequest) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool {
        ["event.marketap.io", "crm.marketap.io", "images.test"].contains(request.url?.host ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.onRequest?(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ClientKeyTests: XCTestCase {
    private struct Body: Encodable {}

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseBody = Data()
        StubURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    private func send(api: MarketapAPI, statusCode: Int) -> Result<Void, MarketapError> {
        StubURLProtocol.statusCode = statusCode
        let done = expectation(description: "response")
        var result: Result<Void, MarketapError>?
        api.requestWithoutResponse(baseURL: .event, path: "/v1/client/events", body: Body()) {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result!
    }

    func test_헤더는_키가_있을_때만_붙는다() {
        var withKey = URLRequest(url: URL(string: "https://event.marketap.io")!)
        MarketapAPI(clientKey: "key-1").applySDKHeaders(to: &withKey)
        XCTAssertEqual(withKey.value(forHTTPHeaderField: "X-Marketap-Client-Key"), "key-1")

        var withoutKey = URLRequest(url: URL(string: "https://event.marketap.io")!)
        MarketapAPI().applySDKHeaders(to: &withoutKey)
        XCTAssertNil(withoutKey.value(forHTTPHeaderField: "X-Marketap-Client-Key"))
    }

    func test_실제_요청에_헤더가_실린다() {
        _ = send(api: MarketapAPI(clientKey: "key-1"), statusCode: 200)
        XCTAssertEqual(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Marketap-Client-Key"), "key-1")

        _ = send(api: MarketapAPI(), statusCode: 200)
        XCTAssertNil(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Marketap-Client-Key"))
    }

    func test_응답없는_요청의_모든_HTTP_실패는_serverError이다() {
        for code in [400, 401, 403, 404, 408, 429, 500, 503] {
            guard case .failure(.serverError(let status)) = send(api: MarketapAPI(), statusCode: code) else {
                return XCTFail("\(code)는 serverError여야 한다")
            }
            XCTAssertEqual(status, code)
        }
    }

    func test_설정에_키를_담고_공백키는_nil이다() {
        XCTAssertEqual(SdkMetadataProvider.createNativeConfig(projectId: "p", clientKey: "k").clientKey, "k")
        XCTAssertNil(SdkMetadataProvider.createNativeConfig(projectId: "p", clientKey: "  ").clientKey)
        XCTAssertNil(SdkMetadataProvider.createNativeConfig(projectId: "p").clientKey)
    }

    func test_헤더로_쓸_수_없는_문자가_섞인_키는_키_없이_보낸다() {
        XCTAssertEqual(SdkMetadataProvider.normalizeClientKey("  ck_aB-9 \n"), "ck_aB-9")
        XCTAssertNotNil(SdkMetadataProvider.normalizeClientKey(String(repeating: "a", count: 128)))
        for key in ["ck\u{200B}bad", "ck_bad키", "ck\nbad", "ck bad", String(repeating: "a", count: 129)] {
            XCTAssertNil(SdkMetadataProvider.normalizeClientKey(key), key)
        }

        let config = SdkMetadataProvider.createNativeConfig(projectId: "p1", clientKey: "ck\u{200B}bad")
        XCTAssertNil(config.clientKey)
        var request = URLRequest(url: URL(string: "https://event.marketap.io")!)
        MarketapAPI(clientKey: config.clientKey, config: config).applySDKHeaders(to: &request)
        XCTAssertNil(request.value(forHTTPHeaderField: MarketapAPI.clientKeyHeader))
        let defaults = makeIsolatedDefaults(self)
        let bundle = FakeBundle(infoPlist: [ClientKeyStore.appGroupInfoPlistKey: "group.test"])
        ClientKeyStore.save("ck_old", projectId: "p1", bundle: bundle, defaultsProvider: { _ in defaults })
        ClientKeyStore.save(config.clientKey, projectId: "p1", bundle: bundle, defaultsProvider: { _ in defaults })
        XCTAssertNil(defaults.string(forKey: ClientKeyStore.defaultsKeyPrefix + "p1"))
    }

    func test_ClientKeyStore는_projectId별로_쓰고_nil이면_해당_항목만_지운다() {
        let defaults = makeIsolatedDefaults(self)
        let bundle = FakeBundle(infoPlist: [ClientKeyStore.appGroupInfoPlistKey: "group.test"])

        ClientKeyStore.save("k1", projectId: "p1", bundle: bundle, defaultsProvider: { _ in defaults })
        ClientKeyStore.save("k2", projectId: "p2", bundle: bundle, defaultsProvider: { _ in defaults })
        XCTAssertEqual(defaults.string(forKey: ClientKeyStore.defaultsKeyPrefix + "p1"), "k1")
        XCTAssertEqual(defaults.string(forKey: ClientKeyStore.defaultsKeyPrefix + "p2"), "k2")

        ClientKeyStore.save(nil, projectId: "p1", bundle: bundle, defaultsProvider: { _ in defaults })
        XCTAssertNil(defaults.string(forKey: ClientKeyStore.defaultsKeyPrefix + "p1"))
        XCTAssertEqual(defaults.string(forKey: ClientKeyStore.defaultsKeyPrefix + "p2"), "k2")
    }

    func test_ClientKeyStore는_App_Group_ID가_없으면_아무것도_안_한다() {
        let defaults = makeIsolatedDefaults(self)
        var opened = false
        ClientKeyStore.save("k1", projectId: "p1", bundle: FakeBundle(infoPlist: [:]), defaultsProvider: { _ in
            opened = true
            return defaults
        })
        XCTAssertFalse(opened)
        XCTAssertNil(defaults.string(forKey: ClientKeyStore.defaultsKeyPrefix + "p1"))
    }

}

private final class FakeBundle: Bundle {
    private let infoPlist: [String: Any]

    init(infoPlist: [String: Any]) {
        self.infoPlist = infoPlist
        super.init()
    }

    override func object(forInfoDictionaryKey key: String) -> Any? { infoPlist[key] }
}
