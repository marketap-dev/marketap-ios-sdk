//
//  InAppFallthroughTests.swift
//  MarketapSDK
//
//  한 이벤트에 후보 캠페인이 여러 개일 때, 1순위가 못 뜨면 다음 후보로 넘어가는지.
//  실제 사례(web SDK): 1순위 [쿠폰지급] 캠페인이 쿠폰 발급 실패로 상세 fetch 에서 빈 응답을
//  받았는데, SDK 가 후보 하나만 시도해서 화면에 아무것도 안 떴다. iOS 도 같은 구조였다.
//

import XCTest
import WebKit
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
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        api = RecordingAPIForFallthrough()
        defaults = makeIsolatedDefaults(self)
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: api,
            cache: MockMarketapCache(), defaults: defaults
        )
        // 이 스위트는 적재 시한을 시험하지 않는다. 시한을 기본값으로 두면 느린 머신에서
        // 폴링이 밀렸을 때 적재가 만료돼 사라지고, 폴스루가 아니라 시한을 시험하게 된다.
        // 시한 자체는 testStalePendingClaimIsReleased 가 직접 짧게 잡아 따로 본다.
        service.pendingClaimTimeoutSeconds = 600
    }

    override func tearDown() {
        service = nil
        api = nil
        defaults = nil
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

    private func runFallthrough(
        _ candidates: [InAppCampaign],
        budgetSeconds: TimeInterval = 2
    ) {
        service.tryShowCampaigns(
            candidates: candidates,
            index: 0,
            fetches: 0,
            // 프로덕션이 단조시계로 비교하므로 여기도 같은 시계를 써야 한다.
            // 벽시계 epoch(~1.7e9)를 넣으면 예산이 사실상 무한이 되어 검사가 헛돈다.
            deadline: ProcessInfo.processInfo.systemUptime + budgetSeconds,
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
        // 요청이 나갔다는 것만으로는 부족하다. 이 버그의 증상은 "화면에 아무것도 안 뜸"이므로
        // 실제로 노출까지 갔는지 본다. didFinishLoad=false 라 pendingCampaign 에 적재된다.
        XCTAssertEqual(service.pendingCampaign?.id, "b")
    }

    func testStopWhenFirstShows() {
        api.singleResponses = ["a": campaign("a", html: "<div>a</div>")]
        runFallthrough([campaign("a"), campaign("b")])

        // a 가 떴으면 b 는 시도하지 않는다.
        XCTAssertEqual(api.fetchedCampaignIds, ["a"])
        XCTAssertEqual(service.pendingCampaign?.id, "a")
    }

    func testStaticCampaignDoesNotFetch() {
        // html 이 이미 있는 정적 렌더 캠페인은 상세 fetch 를 타지 않고 바로 노출된다.
        runFallthrough([campaign("static", html: "<div>static</div>"), campaign("b")])

        XCTAssertEqual(api.fetchedCampaignIds, [])
        XCTAssertEqual(service.pendingCampaign?.id, "static")
    }

    func testHiddenCandidateIsSkippedWithoutFetch() {
        // 오늘 하루 안 보기 등으로 숨겨진 후보는 요청 없이 건너뛰고 다음 후보를 시도한다.
        defaults.set(Date().timeIntervalSince1970 + 3600, forKey: "hide_campaign_hidden")

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

        // 요청이 나간 시점에 fulfill 하면 체인이 아직 진행 중인데 wait 가 풀려서, 남은 작업이
        // tearDown 이나 다음 테스트로 새어 나간다. 최종 상태(노출)를 기다린다.
        // 예산을 넉넉히 준다. 이 테스트가 보는 건 "타임아웃이 나면 다음 후보로 가는가"이지
        // 예산이 아니다. 기본 2초는 1초짜리 fetch 타임아웃이 절반을 먹어서 여유가 1초뿐인데,
        // CI 처럼 타이머가 조금만 밀리면 예산이 먼저 끊어 폴스루가 아니라 예산을 시험하게 된다.
        // (예산 자체는 testExpiredDeadline / testFetchBudgetCapsAtFive 가 따로 본다)
        runFallthrough([campaign("slow"), campaign("b")], budgetSeconds: 30)

        // ivar 를 백그라운드에서 건드리지 않는다. tearDown 이 nil 로 만든 뒤 폴링이 한 번 더
        // 돌면 암묵적 언랩이 터진다. 인스턴스를 먼저 붙잡아 둔다.
        let service = self.service!
        waitUntil(self, "느린 후보를 넘어 다음 후보가 노출된다") {
            service.pendingCampaign?.id == "b"
        }
        XCTAssertEqual(api.fetchedCampaignIds, ["slow", "b"])
        XCTAssertEqual(service.pendingCampaign?.id, "b")
    }

    func testCampaignListTimeoutStillStartsFallthrough() {
        // 단건 fetch 뿐 아니라 목록(/api/v2/campaigns) 요청이 느릴 때도 체인이 시작돼야 한다.
        // 예전엔 목록 타임아웃이면 inTimeout 이 영영 안 불려 이벤트가 통째로 버려졌다.
        let cached = campaign("cached", html: "<div>cached</div>")
        service.campaigns = [cached]      // 캐시는 있지만 lastFetch 는 nil → 네트워크 경로를 탄다
        service.lastFetch = nil

        service.onEvent(
            eventRequest: IngestEventRequest(
                id: "e1", name: "mkt_home_view", userId: "u",
                device: MockMarketapCache().device.makeRequest(), properties: nil, timestamp: Date()
            ),
            fromWebBridge: false
        )

        let service = self.service!
        waitUntil(self, "목록 타임아웃 후에도 캐시로 노출까지 간다") {
            service.pendingCampaign?.id == "cached"
        }
        // 실패했을 때 "타임아웃이 아예 안 떴는지" vs "떴는데 체인이 안 갔는지" 를 구분한다.
        XCTAssertEqual(
            service.pendingCampaign?.id, "cached",
            "요청 경로=\(api.fetchedCampaignIds), 캠페인 캐시=\(service.campaigns?.map(\.id) ?? [])"
        )
    }

    func testAlreadyShownStopsFallthrough() {
        // 이미 떠 있으면 후보를 하나도 건드리지 않는다(요청도, 노출도 없음).
        service.isModalShown = true
        api.singleResponses = ["a": campaign("a", html: "<div>a</div>")]

        runFallthrough([campaign("a"), campaign("b")])

        XCTAssertEqual(api.fetchedCampaignIds, [])
        XCTAssertNil(service.pendingCampaign)
    }

    func testDisplayIsClaimedOnlyOnce() {
        // 표시 권리는 원자적으로 선점된다. 두 체인이 동시에 통과해 둘 다 띄우면 안 된다.
        // (웹뷰 로딩이 끝난 상태 = pendingCampaign 적재가 아니라 실제 선점 경로)
        service.didFinishLoad = true

        runFallthrough([campaign("first", html: "<div>1</div>")])
        XCTAssertTrue(service.isModalShown, "첫 후보가 표시 권리를 가져가야 한다")

        // 두 번째 체인은 선점에 실패해야 하고, impression 도 남기면 안 된다.
        let before = defaults.object(forKey: "impression_second") as? [TimeInterval] ?? []
        runFallthrough([campaign("second", html: "<div>2</div>")])
        let after = defaults.object(forKey: "impression_second") as? [TimeInterval] ?? []

        XCTAssertEqual(before.count, after.count, "못 띄웠으면 빈도수를 소진하면 안 된다")
    }

    func testRecordedHideIsHonoredByTheSameService() {
        // 웹브릿지/플러그인이 남긴 숨김 기록을, 숨김 여부를 읽는 쪽이 실제로 본다.
        // (쓰는 저장소와 읽는 저장소가 갈리면 숨김이 조용히 무시된다 — 플러그인이 예전에
        //  UserDefaults.standard 를 직접 찌르던 게 정확히 그 구조였다)
        service.recordHidden(campaignId: "muted", until: 3600)

        api.singleResponses = ["b": campaign("b", html: "<div>b</div>")]
        runFallthrough([campaign("muted"), campaign("b")])

        XCTAssertEqual(api.fetchedCampaignIds, ["b"], "숨긴 후보는 요청조차 하면 안 된다")
        XCTAssertEqual(service.pendingCampaign?.id, "b")
    }

    func testRecordHiddenIgnoresNonPositiveDuration() {
        // CLOSE(=0) 는 "이번만 닫기"라 영구 기록을 남기면 안 된다.
        service.recordHidden(campaignId: "closed", until: 0)

        // 동작만 보면 가드를 빼도 통과한다(now+0 은 곧바로 과거라 어차피 안 숨겨짐).
        // 가드 자체를 검증하려면 키가 안 써졌는지를 봐야 한다.
        XCTAssertNil(defaults.object(forKey: "hide_campaign_closed"), "CLOSE 는 기록을 남기지 않는다")

        api.singleResponses = ["closed": campaign("closed", html: "<div>c</div>")]
        runFallthrough([campaign("closed")])

        XCTAssertEqual(service.pendingCampaign?.id, "closed", "닫기만 한 캠페인은 다시 뜰 수 있어야 한다")
    }

    func testDismissalReleasesTheDisplayClaim() {
        // 표시 권리 해제가 JS 의 hide 메시지에만 묶여 있으면, 그 경로를 안 타고 닫히는 순간
        // (호스트 앱이 상위 VC 를 dismiss, UIKit 이 present 를 거절 등) 권리가 영구히 남아
        // 이후 인앱이 하나도 안 뜬다. 화면에서 내려갔다는 신호로도 풀려야 한다.
        service.didFinishLoad = true
        runFallthrough([campaign("first", html: "<div>1</div>")])
        XCTAssertTrue(service.isModalShown, "첫 캠페인이 표시 권리를 가져가야 한다")

        service.onDismissed()
        XCTAssertFalse(service.isModalShown, "내려갔으면 권리를 반납해야 한다")

        // 반납됐으니 다음 캠페인이 다시 뜰 수 있어야 한다.
        runFallthrough([campaign("second", html: "<div>2</div>")])
        XCTAssertTrue(service.isModalShown)
    }

    // MARK: - 웹뷰 로딩 중 적재(pending) 경로

    func testPendingClaimIsNotOverwrittenByLaterEvent() {
        // didFinishLoad == false (웹뷰가 아직 안 떴다). 예전에는 적재 경로가 표시 권리를
        // 안 잡아서, 뒤이어 오는 이벤트마다 같은 분기를 타며 pendingCampaign 을 덮어썼다.
        // 앱 시작 직후처럼 웹뷰 초기화가 느릴 때 먼저 도착한 후보가 조용히 사라졌다.
        XCTAssertFalse(service.didFinishLoad, "전제: 웹뷰가 아직 준비되지 않았다")

        runFallthrough([campaign("first", html: "<div>1</div>")])
        XCTAssertEqual(service.pendingCampaign?.id, "first")

        runFallthrough([campaign("second", html: "<div>2</div>")])
        XCTAssertEqual(
            service.pendingCampaign?.id, "first",
            "먼저 적재된 후보를 뒤 이벤트가 덮어쓰면 안 된다"
        )
    }

    func testPendingClaimBlocksLaterCandidatesFromFetching() {
        // 적재도 선점이므로, 뒤 이벤트는 상세 fetch 조차 시작하면 안 된다.
        api.singleResponses = ["late": campaign("late", html: "<div>late</div>")]

        runFallthrough([campaign("first", html: "<div>1</div>")])
        XCTAssertTrue(service.isModalShown, "적재도 표시 권리를 잡아야 한다")

        runFallthrough([campaign("late")])
        XCTAssertEqual(api.fetchedCampaignIds, [], "권리가 잡혀 있으면 요청도 나가면 안 된다")
    }

    func testPendingClaimIsPromotedWhenWebViewBecomesReady() {
        runFallthrough([campaign("first", html: "<div>1</div>")])
        XCTAssertEqual(service.pendingCampaign?.id, "first")

        service.webView(WKWebView(), didFinish: nil)

        XCTAssertTrue(service.didFinishLoad)
        XCTAssertNil(service.pendingCampaign, "준비되면 적재는 비워져야 한다")
        // 적재 선점을 그대로 이어받아야 한다. 승격 경로가 claimDisplay 를 다시 타면
        // 자기가 잡아둔 권리에 막혀 영영 못 뜬다.
        XCTAssertTrue(service.isModalShown, "적재 선점이 표시 선점으로 이어져야 한다")
    }

    func testStalePendingClaimIsReleased() {
        // 웹뷰가 영영 준비되지 않으면 적재 선점이 남아 인앱이 하나도 안 뜬다. 시한을 둔다.
        service.pendingClaimTimeoutSeconds = 0.2

        runFallthrough([campaign("first", html: "<div>1</div>")])
        XCTAssertTrue(service.isModalShown)
        XCTAssertEqual(service.pendingCampaign?.id, "first")

        let service = self.service!
        waitUntil(self, "시한이 지나면 적재 선점이 풀린다") {
            service.pendingCampaign == nil
        }
        XCTAssertFalse(service.isModalShown, "적재를 버렸으면 표시 권리도 반납해야 한다")

        // 권리가 풀렸으니 다음 이벤트가 다시 시도할 수 있어야 한다.
        runFallthrough([campaign("second", html: "<div>2</div>")])
        XCTAssertEqual(service.pendingCampaign?.id, "second")
    }

    // MARK: - 초기 로드 실패 복구

    func testProvisionalNavigationFailureUnblocksDisplay() {
        // 초기 blank 로드가 실패하면 예전엔 didFinishLoad 가 영영 false 라
        // 그 뒤로 **어떤 인앱도 뜨지 못했다**.
        service.webView(
            WKWebView(),
            didFailProvisionalNavigation: nil,
            withError: URLError(.networkConnectionLost)
        )

        XCTAssertTrue(service.didFinishLoad, "로드 실패도 웹뷰 준비 완료로 처리해야 한다")

        runFallthrough([campaign("a", html: "<div>a</div>")])
        XCTAssertNil(service.pendingCampaign, "준비됐으면 적재가 아니라 바로 표시로 가야 한다")
        XCTAssertTrue(service.isModalShown)
    }

    func testNavigationFailureDrainsPendingCampaign() {
        // 실패 전에 적재된 후보가 있으면 그대로 노출로 승격돼야 한다(이벤트 유실 방지).
        runFallthrough([campaign("pending", html: "<div>p</div>")])
        XCTAssertEqual(service.pendingCampaign?.id, "pending")

        service.webView(WKWebView(), didFail: nil, withError: URLError(.timedOut))

        XCTAssertTrue(service.didFinishLoad)
        XCTAssertNil(service.pendingCampaign, "적재된 후보가 승격돼 비워져야 한다")
        XCTAssertTrue(service.isModalShown)
    }

    func testContentProcessTerminationUnblocksDisplay() {
        // 콘텐츠 프로세스가 죽어도 다음 노출은 가능해야 한다.
        service.webViewWebContentProcessDidTerminate(WKWebView())

        XCTAssertTrue(service.didFinishLoad)

        runFallthrough([campaign("a", html: "<div>a</div>")])
        XCTAssertNil(service.pendingCampaign)
        XCTAssertTrue(service.isModalShown)
    }

    func testFetchBudgetCapsAtFive() {
        // 7개 후보가 전부 빈 응답 → 요청 증폭을 막는 상한(5)에서 멈춘다.
        let candidates = (1...7).map { campaign("c\($0)") }
        runFallthrough(candidates)

        XCTAssertEqual(api.fetchedCampaignIds.count, 5)
        XCTAssertEqual(api.fetchedCampaignIds, ["c1", "c2", "c3", "c4", "c5"])
        XCTAssertNil(service.pendingCampaign, "아무것도 못 띄웠어야 한다")
    }
}
