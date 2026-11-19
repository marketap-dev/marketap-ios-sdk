import Foundation

protocol InAppDelayTimer {
    func cancel()
}

extension DispatchWorkItem: InAppDelayTimer {}

protocol InAppDelayScheduler {
    func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> InAppDelayTimer
}

struct DispatchInAppDelayScheduler: InAppDelayScheduler {
    let queue: DispatchQueue

    func schedule(after seconds: TimeInterval, _ block: @escaping () -> Void) -> InAppDelayTimer {
        let item = DispatchWorkItem(block: block)
        queue.asyncAfter(deadline: .now() + max(seconds, 0), execute: item)
        return item
    }
}

/// 지연 노출 예약. 캠페인 본문은 저장하지 않고 실행할 때 최신 목록에서 다시 찾는다.
/// `abortConditions`는 재실행 직후 목록을 받기 전에도 취소를 판정하려고 함께 저장한다.
struct DelayedInAppReservation: Codable, Equatable {
    let reservationId: String
    let campaignId: String
    let triggerEventName: String
    let triggerEventProperties: [String: AnyCodable]?
    let abortConditions: [Condition]?
    let slot: InAppDisplaySlot
    let dueAt: TimeInterval
    let expireAt: TimeInterval
}

private final class WeakInAppWebOrigin {
    weak var value: InAppWebOrigin?

    init(_ value: InAppWebOrigin) {
        self.value = value
    }
}

enum DelayedInAppOutcome {
    case finished
    /// 지금은 띄울 수 없었다(목록 확인 불가·백그라운드·present 실패). 예약을 남겨 두고 만료 전까지 다시 본다.
    case retryLater
}

/// 실행 중인 예약 하나를 가리킨다. 취소·사용자 변경·백그라운드 전환이 일어나면 무효가 된다.
struct DelayedInAppTicket {
    let reservation: DelayedInAppReservation
    fileprivate let token: Int
}

enum DelayedInAppTicketState {
    case valid
    case background
    case invalidated
}

/// 지연 노출 예약을 단말에 저장하고 예약 시각에 실행한다.
/// 포그라운드일 때만 실행하고, 예약 시각 + `reservationTTL`이 지나면 버린다. 캠페인당 1건.
/// 예약을 만든 이벤트의 출처 웹뷰는 메모리에만 약하게 들고, 앱을 다시 시작해 복원한 예약에는 출처가 없다.
final class DelayedInAppCoordinator {
    static let storageKey = "delayed_in_app_reservations"
    static let reservationTTL: TimeInterval = 10 * 60
    static let retryInterval: TimeInterval = 30

    typealias Executor = (DelayedInAppTicket, @escaping (DelayedInAppOutcome) -> Void) -> Void

    var executor: Executor?
    var isSlotOccupied: (InAppDisplaySlot) -> Bool = { _ in false }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let scheduler: InAppDelayScheduler
    private let lock = NSLock()
    private var timers: [String: InAppDelayTimer] = [:]
    private var origins: [String: WeakInAppWebOrigin] = [:]
    private var executing: [String: Int] = [:]
    private var nextToken = 0
    private var isForeground: Bool
    private var isStopped = false

    init(defaults: UserDefaults, now: @escaping () -> Date, scheduler: InAppDelayScheduler, isForeground: Bool = false) {
        self.defaults = defaults
        self.now = now
        self.scheduler = scheduler
        self.isForeground = isForeground
    }

    var reservations: [DelayedInAppReservation] {
        lock.lock()
        defer { lock.unlock() }
        return readActive()
    }

    func isScheduled(campaignId: String) -> Bool {
        reservations.contains { $0.campaignId == campaignId }
    }

    func schedule(
        campaign: InAppCampaign,
        eventName: String,
        eventProperties: [String: AnyCodable]?,
        origin: InAppWebOrigin? = nil
    ) -> Bool {
        guard let delay = campaign.triggerEventCondition.delayInterval else { return false }
        lock.lock()
        if isStopped {
            lock.unlock()
            return false
        }
        var list = readActive()
        if list.contains(where: { $0.campaignId == campaign.id }) {
            lock.unlock()
            return false
        }
        let dueAt = now().timeIntervalSince1970 + delay
        let reservation = DelayedInAppReservation(
            reservationId: UUID().uuidString,
            campaignId: campaign.id,
            triggerEventName: eventName,
            triggerEventProperties: eventProperties,
            abortConditions: campaign.triggerEventCondition.abortConditions,
            slot: campaign.slot,
            dueAt: dueAt,
            expireAt: dueAt + Self.reservationTTL
        )
        list.append(reservation)
        if let origin = origin {
            origins[reservation.reservationId] = WeakInAppWebOrigin(origin)
        }
        write(list)
        arm(reservation, after: delay)
        lock.unlock()
        return true
    }

    /// 취소 조건에 맞는 예약을 지운다.
    func cancelMatching(_ matches: ([Condition]) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        let list = readActive()
        let kept = list.filter { reservation in
            guard let conditions = reservation.abortConditions, !conditions.isEmpty, matches(conditions) else {
                return true
            }
            disarm(reservation.reservationId)
            executing.removeValue(forKey: reservation.reservationId)
            return false
        }
        if kept.count != list.count {
            write(kept)
        }
    }

    func removeAll() {
        lock.lock()
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        executing.removeAll()
        origins.removeAll()
        defaults.removeObject(forKey: Self.storageKey)
        lock.unlock()
    }

    /// 백그라운드에서는 타이머를 모두 거둔다. 정지 중에는 타이머 시계가 멈추므로 복귀 때 새로 건다.
    func setForeground(_ foreground: Bool) {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isForeground = foreground
        if !foreground {
            timers.values.forEach { $0.cancel() }
            timers.removeAll()
            executing.removeAll()
        }
        lock.unlock()
        if foreground {
            rearm()
        }
    }

    /// 이 인스턴스의 실행을 멈춘다. 저장된 예약은 남겨 다음 인스턴스가 이어받는다.
    func stop() {
        lock.lock()
        isStopped = true
        isForeground = false
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        executing.removeAll()
        lock.unlock()
    }

    /// 저장된 예약마다 타이머를 건다(이미 걸린 것은 그대로 둔다).
    func rearm() {
        lock.lock()
        defer { lock.unlock() }
        guard !isStopped else { return }
        let current = now().timeIntervalSince1970
        for reservation in readActive() where timers[reservation.reservationId] == nil
            && executing[reservation.reservationId] == nil {
            arm(reservation, after: reservation.dueAt - current)
        }
    }

    private func arm(_ reservation: DelayedInAppReservation, after seconds: TimeInterval) {
        let id = reservation.reservationId
        timers[id] = scheduler.schedule(after: seconds) { [weak self] in
            self?.fire(reservationId: id)
        }
    }

    private func disarm(_ reservationId: String) {
        timers.removeValue(forKey: reservationId)?.cancel()
    }

    private func fire(reservationId: String) {
        lock.lock()
        timers.removeValue(forKey: reservationId)
        guard isForeground,
              executing[reservationId] == nil,
              let reservation = readActive().first(where: { $0.reservationId == reservationId }) else {
            lock.unlock()
            return
        }
        lock.unlock()

        if isSlotOccupied(reservation.slot) {
            MarketapLogger.verbose("delayed campaign dropped, slot is occupied: \(reservation.campaignId)")
            remove(reservationId)
            return
        }
        guard let executor = executor else { return }

        lock.lock()
        guard executing[reservationId] == nil else {
            lock.unlock()
            return
        }
        nextToken &+= 1
        let ticket = DelayedInAppTicket(reservation: reservation, token: nextToken)
        executing[reservationId] = ticket.token
        lock.unlock()

        executor(ticket) { [weak self] outcome in
            self?.finish(ticket, outcome: outcome)
        }
    }

    /// 예약을 만든 이벤트의 출처 웹뷰. 이미 해제됐거나 복원한 예약이면 nil.
    func origin(of ticket: DelayedInAppTicket) -> InAppWebOrigin? {
        lock.lock()
        defer { lock.unlock() }
        return origins[ticket.reservation.reservationId]?.value
    }

    /// 실행 중인 예약이 아직 유효한지. 비동기 경계를 넘을 때마다, 화면에 띄우기 직전에 확인한다.
    func state(of ticket: DelayedInAppTicket) -> DelayedInAppTicketState {
        lock.lock()
        defer { lock.unlock() }
        let id = ticket.reservation.reservationId
        guard executing[id] == ticket.token else {
            return isForeground ? .invalidated : .background
        }
        guard readActive().contains(where: { $0.reservationId == id }) else { return .invalidated }
        return isForeground ? .valid : .background
    }

    private func finish(_ ticket: DelayedInAppTicket, outcome: DelayedInAppOutcome) {
        let reservation = ticket.reservation
        lock.lock()
        guard executing[reservation.reservationId] == ticket.token else {
            lock.unlock()
            return
        }
        executing.removeValue(forKey: reservation.reservationId)
        lock.unlock()

        switch outcome {
        case .finished:
            remove(reservation.reservationId)
        case .retryLater:
            lock.lock()
            if isForeground, readActive().contains(where: { $0.reservationId == reservation.reservationId }) {
                let remaining = reservation.expireAt - now().timeIntervalSince1970
                arm(reservation, after: min(Self.retryInterval, max(remaining, 0)))
            }
            lock.unlock()
        }
    }

    private func remove(_ reservationId: String) {
        lock.lock()
        disarm(reservationId)
        write(readActive().filter { $0.reservationId != reservationId })
        lock.unlock()
    }

    private func readActive() -> [DelayedInAppReservation] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([DelayedInAppReservation].self, from: data) else {
            return []
        }
        let current = now().timeIntervalSince1970
        let active = stored.filter { $0.expireAt > current }
        if active.count != stored.count {
            stored.filter { $0.expireAt <= current }.forEach { disarm($0.reservationId) }
            write(active)
        }
        return active
    }

    private func write(_ reservations: [DelayedInAppReservation]) {
        let ids = Set(reservations.map(\.reservationId))
        origins = origins.filter { ids.contains($0.key) && $0.value.value != nil }
        guard !reservations.isEmpty, let data = try? JSONEncoder().encode(reservations) else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }
}
