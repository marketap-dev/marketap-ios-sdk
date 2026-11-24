import Foundation

/// - fired: 이 이벤트로 트리거된다. 플로우가 없는 캠페인은 트리거 조건 일치 여부 그대로다.
/// - restarted: 플로우가 진입·취소로 새로 시작되거나 버려졌다.
struct EventFlowEvaluation: Equatable {
    let fired: Bool
    let restarted: Bool
}

/// 캠페인별 이벤트 플로우 진행을 단말에 저장하고 판정한다.
final class EventFlowStore {
    static let storageKey = "inapp_event_flow_states"
    /// 진행 상태를 이보다 오래 두지 않는다. 플로우 단계 제한 시간 상한(31일)보다 길게 잡는다.
    static let maxStateAgeMillis: Int64 = 32 * 24 * 60 * 60 * 1000

    private struct Stored: Codable {
        var nextStep: Int
        var lastStepAt: Int64
        var blockedUntil: Int64?
        var version: String

        var state: EventFlowState {
            EventFlowState(nextStep: nextStep, lastStepAt: lastStepAt, blockedUntil: blockedUntil)
        }
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let lock = NSLock()

    init(defaults: UserDefaults, now: @escaping () -> Date) {
        self.defaults = defaults
        self.now = now
    }

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// - Parameter occurredAt: 이벤트가 일어난 시각. 목록 응답을 기다린 뒤 판정해도 이 시각으로 잰다.
    func evaluate(
        campaign: InAppCampaign,
        arrivalMatched: Bool,
        arrivalCounted: Bool,
        occurredAt: Date,
        matches: (Condition) -> Bool
    ) -> EventFlowEvaluation {
        guard let flow = campaign.triggerEventCondition.flow, !flow.precedingSteps.isEmpty else {
            return EventFlowEvaluation(fired: arrivalMatched, restarted: false)
        }
        let version = campaign.triggerConditionVersion ?? ""

        lock.lock()
        defer { lock.unlock() }
        var states = load()
        let current = states[campaign.id].flatMap { $0.version == version ? $0.state : nil }

        let transition = EventFlowRule.next(
            state: current,
            flow: flow,
            arrivalMatched: arrivalMatched,
            arrivalCounted: arrivalCounted,
            cancelConditions: campaign.triggerEventCondition.abortConditions ?? [],
            eventAt: Self.millis(occurredAt),
            matches: matches
        )

        if let state = transition.state {
            states[campaign.id] = Stored(
                nextStep: state.nextStep, lastStepAt: state.lastStepAt, blockedUntil: state.blockedUntil, version: version
            )
            save(states)
        } else if current != nil {
            // 설정 버전이 다른 진행은 지우지 않는다. 옛 설정 목록으로 먼저 판정할 때 새 설정의 진행을 날리지 않게 한다.
            states.removeValue(forKey: campaign.id)
            save(states)
        }

        return EventFlowEvaluation(fired: transition.fired, restarted: transition.restarted)
    }

    /// 노출 직전에 부른다. 도달 뒤 상세 조회·딜레이를 기다리는 사이 취소 이벤트로 진행이 버려졌거나
    /// 재진입이 막혔으면 false 다. 플로우가 없는 캠페인은 항상 true 다.
    func canShow(campaign: InAppCampaign) -> Bool {
        guard campaign.triggerEventCondition.hasEventFlow else { return true }
        lock.lock()
        defer { lock.unlock() }
        guard let stored = load()[campaign.id] else { return false }
        return stored.version == (campaign.triggerConditionVersion ?? "")
            && stored.nextStep >= 1
            && stored.blockedUntil == nil
    }

    /// 인앱이 실제로 노출됐을 때 부른다. 다시 뜨려면 진입부터 다시 해야 한다.
    func clear(campaignId: String) {
        lock.lock()
        defer { lock.unlock() }
        var states = load()
        guard states.removeValue(forKey: campaignId) != nil else { return }
        save(states)
    }

    /// 로그아웃하거나 다른 회원으로 바뀌었을 때 부른다.
    func clearAll() {
        lock.lock()
        defaults.removeObject(forKey: Self.storageKey)
        lock.unlock()
    }

    private func load() -> [String: Stored] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let states = try? JSONDecoder().decode([String: Stored].self, from: data) else { return [:] }
        return states
    }

    private func save(_ states: [String: Stored]) {
        let cutoff = Self.millis(now()) - Self.maxStateAgeMillis
        let kept = states.filter { $0.value.lastStepAt >= cutoff }
        guard !kept.isEmpty, let data = try? JSONEncoder().encode(kept) else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
