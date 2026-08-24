//
//  InAppFallthroughTests.swift
//  MarketapSDK
//
//  한 이벤트에 후보 캠페인이 여러 개일 때, 1순위가 못 뜨면 다음 후보로 넘어가는지.
//  실제 사례(web SDK): 1순위 [쿠폰지급] 캠페인이 쿠폰 발급 실패로 상세 fetch 에서 빈 응답을
//  받았는데, SDK 가 후보 하나만 시도해서 화면에 아무것도 안 떴다. iOS 도 같은 구조였다.
//

import XCTest
@testable import MarketapSDK

/// 상세 fetch 요청 경로를 기록하고, 캠페인 id 별로 단건 응답을 돌려주는 mock.
private class RecordingAPIForFallthrough: MarketapAPIProtocol {
    /// campaignId → 단건 fetch 로 돌려줄 캠페인(html 포함) 또는 nil(빈 응답)
    var singleResponses: [String: InAppCampaign] = [:]
    /// request 로 들어온 경로(호출 순서 보존)
    var requestedPaths: [String] = []

    /// "/api/v2/campaigns/{id}" 경로에서 실제로 단건 fetch 를 탄 campaignId 만 추린다.
    var fetchedCampaignIds: [String] {
        requestedPaths.compactMap { path in
            guard path.hasPrefix("/api/v2/campaigns/") else { return nil }
            return path.components(separatedBy: "/").last
        }
    }

    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL, path: String, queryItems: [URLQueryItem]?,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {}

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {
        requestedPaths.append(path)
        if T.self == InAppCampaignSingleFetchResponse.self {
            let id = path.components(separatedBy: "/").last ?? ""
            let response = InAppCampaignSingleFetchResponse(campaign: singleResponses[id])
            if let typed = response as? T {
                completion?(.success(typed))
            }
        }
    }

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    ) {
        completion?(.success(()))
    }
}

class InAppFallthroughTests: XCTestCase {
    private var service: InAppMessageService!
    private var api: RecordingAPIForFallthrough!

    override func setUp() {
        super.setUp()
        api = RecordingAPIForFallthrough()
        service = InAppMessageService(customHandlerStore: CustomHandlerStor(), api: api, cache: MockMarketapCache())
    }

    override func tearDown() {
        service = nil
        api = nil
        super.tearDown()
    }

    private func campaign(_ id: String, html: String? = nil) -> InAppCampaign {
        InAppCampaign(
            id: id,
            layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
            triggerEventCondition: EventTriggerCondition(
                condition: Condition(eventFilter: EventFilter(eventName: "mkt_home_view"), propertyConditions: nil),
                frequencyCap: nil,
                delayMinutes: nil
            ),
            html: html,
            updatedAt: "\(Date())"
        )
    }

    private func runFallthrough(_ candidates: [InAppCampaign]) {
        service.tryShowCampaigns(
            candidates: candidates,
            index: 0,
            fetches: 0,
            deadline: Date().timeIntervalSince1970 + 2,
            eventName: "mkt_home_view",
            eventProperties: nil,
            fromWebBridge: false
        )
    }

    func testFirstEmptyThenNext() {
        // a 는 서버가 노출을 확정 못 해 빈 응답(campaign nil), b 는 html 을 받아 온다.
        api.singleResponses = ["b": campaign("b", html: "<div>b</div>")]
        runFallthrough([campaign("a"), campaign("b")])

        // a 를 시도하고 실패했으니 b 까지 fetch 해야 한다.
        XCTAssertEqual(api.fetchedCampaignIds, ["a", "b"])
    }

    func testStopWhenFirstShows() {
        api.singleResponses = ["a": campaign("a", html: "<div>a</div>")]
        runFallthrough([campaign("a"), campaign("b")])

        // a 가 떴으면 b 는 시도하지 않는다.
        XCTAssertEqual(api.fetchedCampaignIds, ["a"])
    }

    func testStaticCampaignDoesNotFetch() {
        // html 이 이미 있는 정적 렌더 캠페인은 상세 fetch 를 타지 않고 바로 노출된다.
        runFallthrough([campaign("static", html: "<div>static</div>"), campaign("b")])

        XCTAssertEqual(api.fetchedCampaignIds, [])
    }

    func testFetchBudgetCapsAtFive() {
        // 7개 후보가 전부 빈 응답 → 요청 증폭을 막는 상한(5)에서 멈춘다.
        let candidates = (1...7).map { campaign("c\($0)") }
        runFallthrough(candidates)

        XCTAssertEqual(api.fetchedCampaignIds.count, 5)
        XCTAssertEqual(api.fetchedCampaignIds, ["c1", "c2", "c3", "c4", "c5"])
    }
}
