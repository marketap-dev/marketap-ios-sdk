import Foundation

/// 한 캠페인의 플로우 진행 위치.
/// - nextStep: 기다리는 단계 번호(1부터). `precedingSteps.count` 와 같으면 도달을 기다린다. 재진입 제한 중이면 0.
/// - lastStepAt: 직전 단계를 일으킨 이벤트의 발생 시각(epoch ms). 재진입 제한 중이면 취소 이벤트의 발생 시각.
/// - blockedUntil: 이 시각(epoch ms) 전까지 진입하지 않는다.
struct EventFlowState: Equatable {
    var nextStep: Int
    var lastStepAt: Int64
    var blockedUntil: Int64? = nil
}

/// - fired: 도달했다. 이후 처리는 일반 트리거와 같다.
/// - restarted: 진입 또는 취소로 진행이 새로 시작되거나 버려졌다. 트리거 횟수 조건은 이때 초기화한다.
struct EventFlowTransition: Equatable {
    let state: EventFlowState?
    let fired: Bool
    let restarted: Bool
}

/// 이벤트 플로우 판정 규칙. web SDK `eventFlowRule.ts`, backend `EventFlowRule.kt` 와 같은 규칙이며
/// 같은 사례 파일(`event-flow-cases.json`)로 검증한다.
///
/// `arrivalMatched` 는 이 이벤트가 캠페인의 트리거 조건(도달)에 맞는지다. `cancelConditions` 는 트리거의 취소 이벤트다.
/// 인앱이 실제로 노출되면 호출하는 쪽이 상태를 지운다. 도달했지만 노출되지 않았으면 상태를 유지한다.
enum EventFlowRule {
    static func next(
        state: EventFlowState?,
        flow: EventFlow,
        arrivalMatched: Bool,
        cancelConditions: [Condition],
        eventAt: Int64,
        matches: (Condition) -> Bool
    ) -> EventFlowTransition {
        let steps = flow.precedingSteps
        guard !steps.isEmpty else {
            return EventFlowTransition(state: nil, fired: false, restarted: false)
        }

        if cancelConditions.contains(where: matches) {
            if let blockedUntil = state?.blockedUntil, eventAt < blockedUntil {
                return EventFlowTransition(state: state, fired: false, restarted: false)
            }
            let hasProgress = state.map { $0.blockedUntil == nil && $0.nextStep >= 1 } ?? false
            if let block = flow.reentryBlockSeconds, hasProgress {
                let blocked = EventFlowState(nextStep: 0, lastStepAt: eventAt, blockedUntil: eventAt + Int64(block) * 1000)
                return EventFlowTransition(state: blocked, fired: false, restarted: true)
            }
            let reentered = steps[0].conditions.contains(where: matches)
                ? EventFlowState(nextStep: 1, lastStepAt: eventAt)
                : nil
            return EventFlowTransition(state: reentered, fired: false, restarted: true)
        }

        if let blockedUntil = state?.blockedUntil, eventAt < blockedUntil {
            return EventFlowTransition(state: state, fired: false, restarted: false)
        }

        let alive = state.flatMap { isAlive($0, steps: steps, at: eventAt) ? $0 : nil }
        if let alive = alive {
            let reachesArrival = alive.nextStep == steps.count
            let waitingMatched = reachesArrival
                ? arrivalMatched
                : steps[alive.nextStep].conditions.contains(where: matches)
            if waitingMatched {
                return reachesArrival
                    ? EventFlowTransition(state: alive, fired: true, restarted: false)
                    : EventFlowTransition(
                        state: EventFlowState(nextStep: alive.nextStep + 1, lastStepAt: eventAt),
                        fired: false,
                        restarted: false
                    )
            }
        }

        let progressedBeyondEntry = (alive?.nextStep ?? 0) > 1
        if !progressedBeyondEntry && steps[0].conditions.contains(where: matches) {
            return EventFlowTransition(state: EventFlowState(nextStep: 1, lastStepAt: eventAt), fired: false, restarted: true)
        }

        return EventFlowTransition(state: alive, fired: false, restarted: false)
    }

    private static func isAlive(_ state: EventFlowState, steps: [EventFlowStep], at eventAt: Int64) -> Bool {
        let index = state.nextStep - 1
        guard steps.indices.contains(index) else { return false }
        return eventAt <= state.lastStepAt + Int64(steps[index].withinSeconds) * 1000
    }
}
