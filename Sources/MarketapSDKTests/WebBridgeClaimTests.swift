//
//  WebBridgeClaimTests.swift
//  MarketapSDK
//
//  웹브릿지 전달 권리가 원자적으로 선점되는지.
//  예전 구조는 hasActiveWebBridge() 로 확인한 뒤 따로 전달을 불렀는데, 전달이 브릿지를
//  소비하므로 두 체인이 동시에 확인을 통과하면 뒤쪽은 impression 만 남기고 전달은 아무
//  일도 안 일어났다. 모달 폴백도 없어 캠페인은 어디에도 안 뜨는데 빈도수만 소진됐다.
//

import XCTest
@testable import MarketapSDK

/// 단건 fetch 를 타지 않는 정적 캠페인만 쓰므로 응답은 필요 없다.
private class NoopAPIForWebBridge: MarketapAPIProtocol {
    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL, path: String, queryItems: [URLQueryItem]?,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {}

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        responseType: T.Type, completion: ((Result<T, MarketapError>) -> Void)?
    ) {}

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL, path: String, body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    ) {
        completion?(.success(()))
    }
}

/// 외부 브릿지로 전달된 캠페인을 기록한다. 여러 스레드에서 들어올 수 있어 락을 쓴다.
private final class DeliveryRecorder {
    private let lock = NSLock()
    private var ids: [String] = []

    func record(_ id: String) {
        lock.lock(); ids.append(id); lock.unlock()
    }

    var delivered: [String] {
        lock.lock(); defer { lock.unlock() }
        return ids
    }
}

/// 지정한 키에 대한 **첫 쓰기**에서 멈춰 서는 UserDefaults.
///
/// 검사-후-사용 구조의 창(브릿지 확인 → impression 기록 → 브릿지 소비)을 결정적으로 벌려서,
/// 두 체인이 같은 브릿지를 보고 통과하는 상황을 재현한다. 진짜 스레드 경합에 기대면
/// 산발적으로만 재현돼 회귀를 못 잡는다.
private final class GatedDefaults: UserDefaults {
    /// 이 키에 처음 쓸 때 멈춘다. nil 이면 그냥 통과.
    var gatedKey: String?
    /// 게이트에 도착했음을 알린다.
    let entered = DispatchSemaphore(value: 0)
    /// 신호를 주면 다시 진행한다.
    let proceed = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var didGate = false

    override func set(_ value: Any?, forKey defaultName: String) {
        var shouldWait = false
        lock.lock()
        if !didGate, let gatedKey = gatedKey, defaultName == gatedKey {
            didGate = true
            shouldWait = true
        }
        lock.unlock()

        if shouldWait {
            entered.signal()
            // 타임아웃을 둔다. 게이트가 영영 안 풀리면 테스트가 매달리는 대신 실패해야 한다.
            _ = proceed.wait(timeout: .now() + 10)
        }
        super.set(value, forKey: defaultName)
    }

    /// 테스트가 끝나도 게이트에 갇힌 스레드가 남지 않게 한다.
    func openGate() {
        proceed.signal()
    }
}

class WebBridgeClaimTests: XCTestCase {
    private var service: InAppMessageService!
    private var defaults: GatedDefaults!
    private var recorder: DeliveryRecorder!

    override func setUp() {
        super.setUp()
        recorder = DeliveryRecorder()
        defaults = makeGatedDefaults()
        service = InAppMessageService(
            customHandlerStore: CustomHandlerStor(), api: NoopAPIForWebBridge(),
            cache: MockMarketapCache(), defaults: defaults
        )
        // 브릿지 상태는 static 이라 테스트 사이에 샌다. 매번 깨끗한 상태에서 시작한다.
        resetWebBridgeState()
    }

    override func tearDown() {
        resetWebBridgeState()
        defaults?.openGate()
        service = nil
        defaults = nil
        recorder = nil
        super.tearDown()
    }

    /// makeIsolatedDefaults 와 같은 격리 정책을 쓰되, 게이트를 걸 수 있는 하위 클래스로 만든다.
    private func makeGatedDefaults() -> GatedDefaults {
        let suiteName = "marketap.tests.WebBridgeClaimTests.\(UUID().uuidString)"
        guard let defaults = GatedDefaults(suiteName: suiteName) else {
            fatalError("격리된 UserDefaults suite 를 만들지 못했다: \(suiteName)")
        }
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    private func resetWebBridgeState() {
        MarketapWebBridge.setExternalWebBridgeActive(false)
        MarketapWebBridge.setExternalInAppMessageCallback(nil)
    }

    /// 외부 래퍼(Flutter/RN)가 붙어 있는 상태를 만든다.
    private func activateExternalBridge() {
        let recorder = self.recorder!
        MarketapWebBridge.setExternalInAppMessageCallback { campaign, _, _ in
            recorder.record(campaign["id"] as? String ?? "?")
        }
        MarketapWebBridge.setExternalWebBridgeActive(true)
    }

    private func campaign(_ id: String) -> InAppCampaign {
        // 전부 정적 렌더(html 있음) 캠페인이다. 이 테스트가 보는 건 상세 fetch 가 아니라
        // 확정된 캠페인을 어디로 보내는지(웹브릿지 vs 모달)다.
        InAppCampaign(
            id: id,
            layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
            triggerEventCondition: EventTriggerCondition(
                condition: Condition(eventFilter: EventFilter(eventName: "mkt_home_view"), propertyConditions: nil),
                frequencyCap: nil,
                delayMinutes: nil
            ),
            html: "<div>\(id)</div>",
            updatedAt: "\(Date())"
        )
    }

    /// 웹브릿지에서 온 이벤트로 후보 하나를 표시 경로에 태운다.
    private func runFromWebBridge(_ candidate: InAppCampaign) {
        service.tryShowCampaigns(
            candidates: [candidate],
            index: 0,
            fetches: 0,
            deadline: ProcessInfo.processInfo.systemUptime + 2,
            eventName: "mkt_home_view",
            eventProperties: nil,
            fromWebBridge: true
        )
    }

    private func impressionCount(_ campaignId: String) -> Int {
        (defaults.object(forKey: "impression_\(campaignId)") as? [TimeInterval] ?? []).count
    }

    func testBridgeIsClaimedOnlyOnce() {
        // 같은 브릿지를 두 번 선점할 수 없다. 두 체인이 동시에 통과하던 자리다.
        activateExternalBridge()

        XCTAssertNotNil(MarketapWebBridge.claimActiveWebBridge(), "첫 선점은 성공해야 한다")
        XCTAssertNil(MarketapWebBridge.claimActiveWebBridge(), "이미 소비된 브릿지를 또 선점하면 안 된다")
    }

    func testConcurrentClaimsYieldExactlyOneWinner() {
        // 검사-후-사용이던 시절의 실제 조건: 여러 큐에서 동시에 들어온다.
        // 락 없이 확인만 하면 여러 체인이 전부 "브릿지 있음"을 보고 통과했다.
        activateExternalBridge()

        let winners = DeliveryRecorder()
        let group = DispatchGroup()
        for i in 0..<32 {
            DispatchQueue.global().async(group: group) {
                if MarketapWebBridge.claimActiveWebBridge() != nil {
                    winners.record("\(i)")
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        XCTAssertEqual(winners.delivered.count, 1, "동시에 들어와도 선점은 정확히 하나여야 한다")
    }

    func testChainThatLosesTheRaceFallsBackToModal() {
        // 이 이슈의 핵심. 두 체인이 같은 브릿지를 보고 통과하면, 뒤쪽은 impression 만 남기고
        // 전달은 아무 데도 안 되며 모달 폴백도 없었다 — 캠페인은 안 뜨는데 빈도수만 소진.
        //
        // 검사-후-사용 구조에서 창이 벌어지는 지점이 "확인 → impression 기록 → 소비" 사이라,
        // impression 기록에서 A 를 붙잡아 둔 채 B 를 들여보낸다.
        activateExternalBridge()
        defaults.gatedKey = "impression_first"

        // A: 웹으로 갈 체인. impression 기록에서 멈춘다.
        DispatchQueue.global().async { [service] in
            service?.tryShowCampaigns(
                candidates: [self.campaign("first")], index: 0, fetches: 0,
                deadline: ProcessInfo.processInfo.systemUptime + 2,
                eventName: "mkt_home_view", eventProperties: nil, fromWebBridge: true
            )
        }
        XCTAssertEqual(
            defaults.entered.wait(timeout: .now() + 10), .success,
            "A 체인이 impression 기록 지점까지 와야 한다"
        )

        // B: A 가 아직 진행 중인(= 예전 구조라면 브릿지가 아직 안 비워진) 상태에서 들어온다.
        runFromWebBridge(campaign("second"))

        // 여기서 A 는 이미 선점·전달을 끝내고 기록 직전에 멈춰 있다. 웹으로 간 건 A 뿐이어야 한다.
        XCTAssertEqual(recorder.delivered, ["first"], "선점한 체인만 웹으로 전달한다")

        // B 는 브릿지를 못 잡았으니 모달로 폴백해야 한다. 그냥 사라지면 안 된다.
        XCTAssertEqual(
            service.pendingCampaign?.id, "second",
            "선점에 실패한 캠페인은 네이티브 모달로 폴백해야 한다"
        )
        XCTAssertEqual(
            impressionCount("second"), 0,
            "어디에도 안 뜬 캠페인이 빈도수를 소진하면 안 된다"
        )

        // A 를 풀어 기록까지 끝낸다. (실제로 전달된 캠페인은 빈도수를 소진한다)
        defaults.openGate()
        waitUntil(self, "A 의 impression 기록이 끝난다") { self.impressionCount("first") == 1 }
    }

    func testActiveFlagWithoutCallbackFallsBackToModal() {
        // 플래그만 켜져 있고 받을 콜백이 없으면 전달해도 아무 데도 안 간다.
        // 예전엔 그래도 플래그를 소비하고 조용히 끝냈다. 모달로 폴백해야 한다.
        MarketapWebBridge.setExternalWebBridgeActive(true)

        runFromWebBridge(campaign("orphan"))

        XCTAssertEqual(service.pendingCampaign?.id, "orphan", "받을 곳이 없으면 모달로 폴백한다")
        XCTAssertEqual(impressionCount("orphan"), 0, "안 떴으면 빈도수를 소진하면 안 된다")
    }

    func testNoBridgeGoesStraightToModal() {
        // 브릿지가 아예 없으면(웹뷰가 이미 내려감 등) 기존대로 네이티브 모달이다.
        runFromWebBridge(campaign("nobridge"))

        XCTAssertEqual(service.pendingCampaign?.id, "nobridge")
        XCTAssertEqual(recorder.delivered, [])
    }

    func testDeliveredCampaignDoesNotAlsoOpenModal() {
        // 웹으로 갔으면 네이티브 모달까지 같이 뜨면 안 된다(중복 노출).
        activateExternalBridge()

        runFromWebBridge(campaign("web"))

        XCTAssertEqual(recorder.delivered, ["web"])
        XCTAssertNil(service.pendingCampaign, "웹으로 전달됐으면 모달 경로를 타면 안 된다")
        XCTAssertFalse(service.isModalShown)
    }
}
