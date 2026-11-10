import XCTest
import UserNotifications
@testable import MarketapSDK
@testable import MarketapSDKNotificationServiceExtension

final class SDKHeaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseBody = Data("{\"code\":200000,\"message\":\"ok\",\"data\":\"ok\"}".utf8)
        StubURLProtocol.lastRequest = nil
    }

    override func tearDown() {
        StubURLProtocol.onRequest = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    func test_앱의_세_송신경로는_키_없이도_네이티브_버전과_래퍼를_보낸다() {
        for type in ["ios", "flutter", "react_native", "other"] {
            let config = MarketapConfig(projectId: "p", sdkType: type, sdkVersion: "3.2.1-beta+1", clientKey: nil)
            let api = MarketapAPI(config: config)
            for path in 0..<3 {
                let done = expectation(description: "headers")
                if path == 0 {
                    api.get(baseURL: .crm, path: "/test", responseType: String.self) { _ in done.fulfill() }
                } else if path == 1 {
                    api.request(baseURL: .crm, path: "/test", body: "body", responseType: String.self) { _ in done.fulfill() }
                } else {
                    api.requestWithoutResponse(path: "/test", body: "body") { _ in done.fulfill() }
                }
                wait(for: [done], timeout: 5)
                let request = StubURLProtocol.lastRequest!
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Platform"), "ios")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Version"), MarketapConfig.nativeSdkVersion)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Source"), "app")
                let wrapper = ["flutter": "flutter", "react_native": "react-native"][type]
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Wrapper"), wrapper)
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Wrapper-Version"), wrapper == nil ? nil : config.sdkVersion)
                XCTAssertNil(request.value(forHTTPHeaderField: MarketapAPI.clientKeyHeader))
            }
        }
    }

    func test_버전만_불량이면_래퍼_종류는_유지하고_중복없이_set한다() {
        for version in ["", "unknown", "1.0\r\nBad: value", "1/2", String(repeating: "1", count: 65)] {
            let api = MarketapAPI(config: MarketapConfig(projectId: "p", sdkType: "flutter", sdkVersion: version, clientKey: nil))
            var request = URLRequest(url: URL(string: "https://event.marketap.io")!)
            for _ in 0..<2 { api.applySDKHeaders(to: &request) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Wrapper"), "flutter")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Marketap-SDK-Wrapper-Version"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Platform"), "ios")
        }
    }



    func test_NSE_이미지_다운로드에는_키와_SDK_헤더가_없다() {
        let intercepted = expectation(description: "image download")
        StubURLProtocol.onRequest = { request in
            XCTAssertEqual(request.url?.host, "images.test")
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Marketap-Client-Key"))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Marketap-SDK-Platform"))
            intercepted.fulfill()
        }
        let content = UNMutableNotificationContent()
        content.userInfo = ["marketap": ["imageUrl": "https://images.test/image.png"]]
        let client = MarketapNotificationServiceClient()
        XCTAssertTrue(client.didReceive(UNNotificationRequest(identifier: "image", content: content, trigger: nil), withContentHandler: { _ in }))
        wait(for: [intercepted], timeout: 5)
    }

    func test_NSE_실제_요청은_nse이고_버전은_앱과_같으며_래퍼는_없다() {
        XCTAssertEqual(MarketapNotificationServiceClient.nativeSdkVersion, MarketapConfig.nativeSdkVersion)
        MarketapNotificationServiceClient().handleImpression(.init(userId: "u", deviceId: "d", projectId: "p", campaignId: "c", messageId: "m", serverProperties: nil, imageUrl: nil))
        waitUntil(self, "NSE impression") { StubURLProtocol.lastRequest != nil }
        let request = StubURLProtocol.lastRequest!
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Platform"), "ios")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Version"), MarketapConfig.nativeSdkVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Marketap-SDK-Source"), "nse")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Marketap-SDK-Wrapper"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Marketap-SDK-Wrapper-Version"))
    }
}
