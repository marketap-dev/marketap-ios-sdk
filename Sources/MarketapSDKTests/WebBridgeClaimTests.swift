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
/// 체인 하나를 impression 기록 지점에 붙잡아 둬서 두 체인이 겹치는 구간을 결정적으로 만든다.
/// 예전 순서(브릿지 확인 → impression 기록 → 브릿지 소비)에서는 이 지점이 확인과 소비 사이라,
/// 붙잡힌 동안 들어온 두 번째 체인이 같은 브릿지를 보고 통과했다. 진짜 스레드 경합에 기대면
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

/// 선점은 되지만 전달은 늘 실패하는 가짜 브릿지.
/// show() 의 "선점은 했는데 전달 실패" 폴백 배선을 실제로 태우기 위한 것.
private final class AlwaysFailingBridge: WebBridgeInAppMessageDelegate {
    var canDeliver: Bool { true }
    func sendCampaignToWeb(campaign: InAppCampaign, messageId: String) -> Bool { false }
}

/// 이미 죽은(웹뷰가 사라진) 브릿지.
private final class DeadBridge: WebBridgeInAppMessageDelegate {
    var canDeliver: Bool { false }
    func sendCampaignToWeb(campaign: InAppCampaign, messageId: String) -> Bool { false }
}

/// 전달에 성공하고 무엇이 갔는지 기록하는 가짜 브릿지.
private final class RecordingBridge: WebBridgeInAppMessageDelegate {
    private let recorder: DeliveryRecorder
    var canDeliver: Bool { true }

    init(recorder: DeliveryRecorder) { self.recorder = recorder }

    func sendCampaignToWeb(campaign: InAppCampaign, messageId: String) -> Bool {
        recorder.record(campaign.id)
        return true
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
        // activeInstance 는 선점이 곧 소비라서, 한 번 선점해 버리면 비워진다.
        // (전용 reset 훅을 프로덕션에 두지 않기 위해 기존 API 로 치운다)
        _ = MarketapWebBridge.claimActiveWebBridge()
    }

    /// 외부 래퍼(Flutter/RN)가 붙어 있는 상태를 만든다.
    private func activateExternalBridge() {
        let recorder = self.recorder!
        MarketapWebBridge.setExternalInAppMessageCallback { campaign, _, _ in
            recorder.record(campaign["id"] as? String ?? "?")
        }
        MarketapWebBridge.setExternalWebBridgeActive(true)
    }

    /// arm 없이 콜백만 등록한다.
    private func activateExternalBridgeCallbackOnly() {
        let recorder = self.recorder!
        MarketapWebBridge.setExternalInAppMessageCallback { campaign, _, _ in
            recorder.record(campaign["id"] as? String ?? "?")
        }
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
        // 예전 순서에서 창이 벌어지던 지점이 "확인 → impression 기록 → 소비" 사이였으므로,
        // impression 기록에서 A 를 붙잡아 둔 채 B 를 들여보낸다. (고친 뒤에는 A 가 이미
        // 선점·전달을 끝낸 상태로 붙잡히고, 그래서 B 가 브릿지를 못 잡는 것이 확인된다)
        activateExternalBridge()
        defaults.gatedKey = "impression_first"

        // A: 웹으로 갈 체인. impression 기록에서 멈춘다.
        // runFromWebBridge 헬퍼를 쓰지 않고 펼쳐 쓴다 — 헬퍼는 암묵적 언랩 ivar(service)를
        // 읽는데, 게이트가 안 풀린 채 테스트가 끝나면 tearDown 이 nil 로 만든 뒤 이 백그라운드
        // 블록이 그걸 건드려 프로세스가 죽는다. 인스턴스를 먼저 붙잡아 둔다.
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

    func testNativeDeliveryWithoutWebViewReportsFailure() {
        // 웹뷰가 안 붙은 네이티브 브릿지는 "전달 못 했다"고 보고해야 한다.
        // 예전엔 조용히 return 해서 호출자가 알 길이 없었고, 그래서 show() 가 폴백 대신
        // impression 만 남기고 끝났다. 이 계약이 폴백 전체를 떠받친다.
        let bridge = MarketapWebBridge(handleInAppInWebView: true)
        defer { SdkIntegrationState.handleInAppInWebView = nil }

        XCTAssertFalse(
            bridge.sendCampaignToWeb(campaign: campaign("native"), messageId: "m1"),
            "웹뷰가 없으면 전달을 시작하지 못했다고 보고해야 한다"
        )
        XCTAssertFalse(
            WebBridgeClaim.native(bridge).deliver(campaign: campaign("native"), messageId: "m1"),
            "claim 을 거쳐도 같은 실패가 그대로 올라와야 한다"
        )
    }

    func testNativeEventDoesNotConsumeTheWebBridge() {
        // 웹브릿지에서 온 이벤트가 아니면 브릿지를 건드리면 안 된다. 소비까지 해버리면
        // 정작 웹에서 온 다음 이벤트가 갈 곳을 잃는다(선점이 1회용이라 돌려받지 못한다).
        activateExternalBridge()

        service.tryShowCampaigns(
            candidates: [campaign("native")], index: 0, fetches: 0,
            deadline: ProcessInfo.processInfo.systemUptime + 2,
            eventName: "mkt_home_view", eventProperties: nil, fromWebBridge: false
        )

        XCTAssertEqual(recorder.delivered, [], "네이티브 이벤트는 웹으로 보내지 않는다")
        XCTAssertEqual(service.pendingCampaign?.id, "native", "모달 경로를 타야 한다")
        XCTAssertNotNil(
            MarketapWebBridge.claimActiveWebBridge(),
            "네이티브 이벤트가 웹브릿지 선점을 소비하면 안 된다"
        )
    }

    func testDeliveryFailureFallsBackToModalWithoutImpression() {
        // 선점은 됐는데 전달이 시작되지 않은 경우. 이 PR 이 존재하는 이유인 배선이다.
        // 여기서 폴백하지 않으면 캠페인은 어디에도 안 뜨는데 빈도수만 소진된다.
        let bridge = AlwaysFailingBridge()   // weak 로 잡히므로 테스트가 붙들고 있어야 한다
        MarketapWebBridge.registerActiveInstance(bridge)

        runFromWebBridge(campaign("dead"))

        XCTAssertEqual(service.pendingCampaign?.id, "dead", "전달 실패면 네이티브 모달로 폴백해야 한다")
        XCTAssertEqual(impressionCount("dead"), 0, "어디에도 안 뜬 캠페인이 빈도수를 소진하면 안 된다")
        XCTAssertEqual(recorder.delivered, [], "웹으로는 아무것도 가지 않았다")
    }

    func testFailedDeliveryReturnsTheClaim() {
        // 전달이 실패해도 브릿지 자체가 멀쩡하면(canDeliver) 선점을 돌려줘야 한다.
        // 안 돌려주면 살아있는 웹뷰가 등록 해제된 채 남아 다음 인앱까지 모달로 강등된다.
        let bridge = AlwaysFailingBridge()
        MarketapWebBridge.registerActiveInstance(bridge)

        runFromWebBridge(campaign("dead"))

        XCTAssertNotNil(
            MarketapWebBridge.claimActiveWebBridge(),
            "전달만 실패했을 뿐 살아있는 브릿지는 되돌려받아야 한다"
        )
    }

    func testNativeBridgeIsClaimedAndConsumed() {
        // 네이티브 브릿지 경로 전체: 등록 → 선점 → 전달 → 소비.
        let bridge = RecordingBridge(recorder: recorder)
        MarketapWebBridge.registerActiveInstance(bridge)

        runFromWebBridge(campaign("native"))

        XCTAssertEqual(recorder.delivered, ["native"], "네이티브 브릿지로 전달돼야 한다")
        XCTAssertEqual(impressionCount("native"), 1, "전달됐으면 빈도수를 소진한다")
        XCTAssertNil(service.pendingCampaign, "웹으로 갔으면 모달까지 뜨면 안 된다")
        XCTAssertNil(MarketapWebBridge.claimActiveWebBridge(), "전달했으면 선점은 소비된다")
    }

    func testDeadNativeBridgeIsNotClaimed() {
        // 웹뷰가 이미 사라진 브릿지는 선점 대상이 아니다 — 곧장 모달로.
        let bridge = DeadBridge()
        MarketapWebBridge.registerActiveInstance(bridge)

        XCTAssertNil(MarketapWebBridge.claimActiveWebBridge(), "죽은 브릿지를 선점하면 안 된다")

        MarketapWebBridge.registerActiveInstance(bridge)
        runFromWebBridge(campaign("dead"))
        XCTAssertEqual(service.pendingCampaign?.id, "dead")
        XCTAssertEqual(impressionCount("dead"), 0)
    }

    func testExternalArmIsConsumedEvenWithoutCallback() {
        // arm 은 1회용이다. 받을 콜백이 없어도 소비돼야, 웹에서 온 track 이 켠 arm 이
        // 한참 뒤 네이티브 이벤트를 가로채는 일이 없다.
        MarketapWebBridge.setExternalWebBridgeActive(true)

        XCTAssertNil(MarketapWebBridge.claimActiveWebBridge(), "받을 콜백이 없으면 선점하지 않는다")

        // 이제 콜백이 붙어도, 아까 그 arm 은 이미 소진돼 있어야 한다.
        activateExternalBridgeCallbackOnly()
        XCTAssertNil(MarketapWebBridge.claimActiveWebBridge(), "소비된 arm 이 나중에 되살아나면 안 된다")
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
