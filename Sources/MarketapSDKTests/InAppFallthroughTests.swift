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
    /// 응답을 영영 주지 않는 캠페인(느린 서버·행 흉내). fetchCampaign 의 1초 타임아웃이 이긴다.
    var hangingIds: Set<String> = []
    /// 요청이 들어올 때마다 불린다(비동기 테스트에서 진행을 관찰하는 용도).
    var onRequest: ((String) -> Void)?

    /// 타임아웃은 백그라운드 큐에서 체인을 이어가므로 기록이 여러 스레드에서 들어온다.
    private let lock = NSLock()
    private var requestedPaths: [String] = []

    /// "/api/v2/campaigns/{id}" 경로에서 실제로 단건 fetch 를 탄 campaignId 만 추린다.
    var fetchedCampaignIds: [String] {
        lock.lock(); defer { lock.unlock() }
        return requestedPaths.compactMap { path in
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
        lock.lock(); requestedPaths.append(path); lock.unlock()
        onRequest?(path)
        if T.self == InAppCampaignSingleFetchResponse.self {
            let id = path.components(separatedBy: "/").last ?? ""
            // 응답을 주지 않는다 → fetchCampaign 의 타임아웃이 이기는 경로를 탄다.
            if hangingIds.contains(id) { return }
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
            // 프로덕션이 단조시계로 비교하므로 여기도 같은 시계를 써야 한다.
            // 벽시계 epoch(~1.7e9)를 넣으면 예산이 사실상 무한이 되어 검사가 헛돈다.
            deadline: ProcessInfo.processInfo.systemUptime + 2,
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

    func testHiddenCandidateIsSkippedWithoutFetch() {
        // 오늘 하루 안 보기 등으로 숨겨진 후보는 요청 없이 건너뛰고 다음 후보를 시도한다.
        UserDefaults.standard.set(Date().timeIntervalSince1970 + 3600, forKey: "hide_campaign_hidden")
        defer { UserDefaults.standard.removeObject(forKey: "hide_campaign_hidden") }

        api.singleResponses = ["b": campaign("b", html: "<div>b</div>")]
        runFallthrough([campaign("hidden"), campaign("b")])

        // hidden 은 fetch 조차 하지 않고, b 만 요청한다.
        XCTAssertEqual(api.fetchedCampaignIds, ["b"])
    }

    func testExpiredDeadlineStopsBeforeFetching() {
        // 시간 예산이 이미 지났으면 요청을 시작조차 하지 않는다.
        api.singleResponses = ["a": campaign("a", html: "<div>a</div>")]
        service.tryShowCampaigns(
            candidates: [campaign("a")],
            index: 0,
            fetches: 0,
            deadline: ProcessInfo.processInfo.systemUptime - 1,
            eventName: "mkt_home_view",
            eventProperties: nil,
            fromWebBridge: false
        )

        XCTAssertEqual(api.fetchedCampaignIds, [])
    }

    func testTimedOutFetchAdvancesToNextCandidate() {
        // 가장 흔한 실패는 "빈 응답"이 아니라 "느린 응답"이다. 1초 타임아웃이 이겼을 때
        // 호출자 콜백이 안 불리면 폴스루가 통째로 멈춘다(이 기능의 존재 이유가 무력화).
        api.hangingIds = ["slow"]
        api.singleResponses = ["b": campaign("b", html: "<div>b</div>")]

        let advanced = expectation(description: "느린 후보를 넘어 다음 후보를 시도한다")
        api.onRequest = { path in
            if path.hasSuffix("/b") { advanced.fulfill() }
        }

        runFallthrough([campaign("slow"), campaign("b")])

        wait(for: [advanced], timeout: 3)
        XCTAssertEqual(api.fetchedCampaignIds, ["slow", "b"])
    }

    func testFetchBudgetCapsAtFive() {
        // 7개 후보가 전부 빈 응답 → 요청 증폭을 막는 상한(5)에서 멈춘다.
        let candidates = (1...7).map { campaign("c\($0)") }
        runFallthrough(candidates)

        XCTAssertEqual(api.fetchedCampaignIds.count, 5)
        XCTAssertEqual(api.fetchedCampaignIds, ["c1", "c2", "c3", "c4", "c5"])
    }
}
