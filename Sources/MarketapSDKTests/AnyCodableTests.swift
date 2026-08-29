//
//  AnyCodableTests.swift
//  MarketapSDK
//
//  AnyCodable 은 캐시(UserDefaults)에 저장했다가 다시 꺼내 재전송하는 경로를 타므로
//  encode/decode 가 대칭이어야 한다. 비대칭이면 "저장은 됐는데 다시 인코딩할 때 실패"가
//  되어 재전송 대기 중이던 데이터가 조용히 사라진다.
//

import XCTest
@testable import MarketapSDK

class AnyCodableTests: XCTestCase {

    /// JSON null 라운드트립. decode 가 null 을 NSNull 로 되살리는데 encode 에 NSNull
    /// 케이스가 없어서, 캐시에서 꺼낸 값을 다시 저장할 때 통째로 실패했다.
    func testNullRoundTrips() throws {
        let original: [String: AnyCodable] = ["screen": AnyCodable(nil)]

        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "{\"screen\":null}")

        // 한 번 왕복하면 값이 NSNull 이 된다.
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: encoded)
        XCTAssertTrue(decoded["screen"]?.value is NSNull)

        // 그 상태로 다시 인코딩해도 실패하지 않아야 한다(예전엔 여기서 throw).
        let reEncoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(String(data: reEncoded, encoding: .utf8), "{\"screen\":null}")
    }

    /// null 이 섞인 device 속성을 가진 프로필 요청이 캐시 왕복 후에도 다시 저장되는지.
    /// (identify 실패 → 재전송 대기 저장 경로에서 실제로 깨졌던 조합)
    func testProfileRequestSurvivesCacheRoundTrip() throws {
        let cache = MockMarketapCache()
        let request = UpdateProfileRequest(
            userId: "u",
            properties: ["age": 30].toAnyCodable(),
            device: cache.device.makeRequest()   // screen 이 nil 인 mock device
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateProfileRequest.self, from: encoded)

        XCTAssertNoThrow(try JSONEncoder().encode(decoded))
    }
}
