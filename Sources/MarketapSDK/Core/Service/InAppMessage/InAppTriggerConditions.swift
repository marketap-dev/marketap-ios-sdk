import Foundation

struct InAppWindowChecker {
    private static let weekdays = ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]

    var calendar: Calendar = .autoupdatingCurrent

    func check(_ window: SendableTimeWindow?, now: Date) -> Bool {
        guard let window = window else { return true }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = components.weekday,
              let rule = window.weeklyTimeRules.first(where: { $0.dayOfWeek == Self.weekdays[weekday - 1] }) else {
            return false
        }
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return rule.timeRanges.contains { $0.startMinuteOfDay <= minuteOfDay && minuteOfDay <= $0.endMinuteOfDay }
    }
}

final class OccurrenceConditionEvaluator {
    static let nonWindowedKeyPrefix = "inapp_trigger_occurrence_non_windowed:"
    static let windowedKeyPrefix = "inapp_trigger_occurrence_windowed:"

    private struct NonWindowedState: Codable {
        let validityKey: String
        var lastSessionId: String?
        var sessionCount: Int
        var totalCount: Int
    }

    private struct Occurrence: Codable {
        let timestamp: TimeInterval
        let sessionId: String?
    }

    private struct WindowedState: Codable {
        let validityKey: String
        var occurrences: [Occurrence]
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let lock = NSLock()

    init(defaults: UserDefaults, now: @escaping () -> Date) {
        self.defaults = defaults
        self.now = now
    }

    func recordAndEvaluate(campaign: InAppCampaign, sessionId: String?) -> Bool {
        guard let condition = campaign.triggerEventCondition.occurrenceCondition else { return true }
        let validityKey = campaign.triggerConditionVersion ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let durationMinutes = condition.durationMinutes {
            return recordWindowed(campaign.id, condition, durationMinutes, validityKey, sessionId)
        }
        return recordNonWindowed(campaign.id, condition, validityKey, sessionId)
    }

    /// 횟수 조건이 있고, 이번 이벤트를 세기 전에 이미 센 횟수가 1회 이상이면 true 다. 기록하지 않는다.
    func hasCounted(campaign: InAppCampaign, sessionId: String?) -> Bool {
        guard let condition = campaign.triggerEventCondition.occurrenceCondition else { return false }
        let validityKey = campaign.triggerConditionVersion ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let durationMinutes = condition.durationMinutes {
            guard let state: WindowedState = load(Self.windowedKeyPrefix + campaign.id),
                  state.validityKey == validityKey else { return false }
            let cutoff = now().timeIntervalSince1970 - TimeInterval(durationMinutes * 60)
            return state.occurrences.contains {
                $0.timestamp >= cutoff && (condition.sessionScoped != true || $0.sessionId == sessionId)
            }
        }
        guard let state: NonWindowedState = load(Self.nonWindowedKeyPrefix + campaign.id),
              state.validityKey == validityKey else { return false }
        return condition.sessionScoped == true
            ? state.lastSessionId == sessionId && state.sessionCount > 0
            : state.totalCount > 0
    }

    func reset(campaignId: String) {
        lock.lock()
        defaults.removeObject(forKey: Self.nonWindowedKeyPrefix + campaignId)
        defaults.removeObject(forKey: Self.windowedKeyPrefix + campaignId)
        lock.unlock()
    }

    func resetAll() {
        lock.lock()
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.nonWindowedKeyPrefix) || $0.hasPrefix(Self.windowedKeyPrefix) }
            .forEach { defaults.removeObject(forKey: $0) }
        lock.unlock()
    }

    private func recordNonWindowed(
        _ campaignId: String,
        _ condition: OccurrenceCondition,
        _ validityKey: String,
        _ sessionId: String?
    ) -> Bool {
        let key = Self.nonWindowedKeyPrefix + campaignId
        let current: NonWindowedState? = load(key)
        let base: NonWindowedState
        if let current = current, current.validityKey == validityKey {
            base = current
        } else {
            defaults.removeObject(forKey: Self.windowedKeyPrefix + campaignId)
            base = NonWindowedState(validityKey: validityKey, lastSessionId: nil, sessionCount: 0, totalCount: 0)
        }
        let next = NonWindowedState(
            validityKey: validityKey,
            lastSessionId: sessionId,
            sessionCount: base.lastSessionId == sessionId ? base.sessionCount + 1 : 1,
            totalCount: base.totalCount + 1
        )
        save(next, key)
        let count = condition.sessionScoped == true ? next.sessionCount : next.totalCount
        return count >= condition.count
    }

    private func recordWindowed(
        _ campaignId: String,
        _ condition: OccurrenceCondition,
        _ durationMinutes: Int,
        _ validityKey: String,
        _ sessionId: String?
    ) -> Bool {
        let key = Self.windowedKeyPrefix + campaignId
        let current: WindowedState? = load(key)
        let base: WindowedState
        if let current = current, current.validityKey == validityKey {
            base = current
        } else {
            defaults.removeObject(forKey: Self.nonWindowedKeyPrefix + campaignId)
            base = WindowedState(validityKey: validityKey, occurrences: [])
        }
        let timestamp = now().timeIntervalSince1970
        let cutoff = timestamp - TimeInterval(durationMinutes * 60)
        let occurrences = base.occurrences.filter { $0.timestamp >= cutoff }
            + [Occurrence(timestamp: timestamp, sessionId: sessionId)]
        save(WindowedState(validityKey: validityKey, occurrences: occurrences), key)
        let count = condition.sessionScoped == true
            ? occurrences.filter { $0.sessionId == sessionId }.count
            : occurrences.count
        return count >= condition.count
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

/// 전체 빈도 제한용 노출 기록. `disableGlobalFrequencyCap` 캠페인의 노출도 기록한다.
final class GlobalImpressionLog {
    static let storageKey = "global_impressions"
    /// 서버에 전체 빈도 기간 상한이 없어, 적어도 이 기간의 기록은 남긴다.
    static let minimumRetention: TimeInterval = 365 * 24 * 60 * 60

    private struct Entry: Codable {
        let ts: TimeInterval
        let tagIds: [String]
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// - Parameter retention: 이보다 오래된 기록은 지운다. 가장 긴 규칙 기간 이상이어야 한다.
    func record(tagIds: [String], at date: Date, retention: TimeInterval = minimumRetention) {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = date.timeIntervalSince1970 - retention
        let entries = load().filter { $0.ts >= cutoff } + [Entry(ts: date.timeIntervalSince1970, tagIds: tagIds)]
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func isCapped(campaign: InAppCampaign, rules: [GlobalFrequencyCapRule], now: Date) -> Bool {
        guard campaign.disableGlobalFrequencyCap != true, !rules.isEmpty else { return false }
        let campaignTags = campaign.tagIds ?? []
        lock.lock()
        let entries = load()
        lock.unlock()
        return rules.contains { rule in
            guard Self.tagsIntersect(rule.tagIds, campaignTags) else { return false }
            let cutoff = now.timeIntervalSince1970 - TimeInterval(rule.durationMinutes * 60)
            let count = entries.filter { $0.ts >= cutoff && Self.tagsIntersect(rule.tagIds, $0.tagIds) }.count
            return count >= rule.limit
        }
    }

    private static func tagsIntersect(_ ruleTagIds: [String], _ tagIds: [String]) -> Bool {
        ruleTagIds.isEmpty || ruleTagIds.contains(where: tagIds.contains)
    }

    private func load() -> [Entry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}

/// 첫 노출 후 N분 타이머의 시작 시각(epoch 밀리초)을 캠페인·`revision` 별로 저장한다.
final class InAppTimerStore {
    static let keyPrefix = "timer_"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func startMillis(campaignId: String, revision: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.object(forKey: key(campaignId, revision)) as? Double
    }

    /// 시작 시각이 없을 때만 기록하고, 최종 시작 시각을 돌려준다.
    @discardableResult
    func recordStartIfAbsent(campaignId: String, revision: String, nowMillis: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        let key = key(campaignId, revision)
        if let existing = defaults.object(forKey: key) as? Double { return existing }
        defaults.set(nowMillis, forKey: key)
        return nowMillis
    }

    func isExpired(campaign: InAppCampaign, now: Date) -> Bool {
        guard let timer = campaign.timer, campaign.isTest != true,
              let start = startMillis(campaignId: campaign.id, revision: timer.revision) else { return false }
        return now.timeIntervalSince1970 * 1000 >= start + Double(timer.minutes) * 60_000
    }

    private func key(_ campaignId: String, _ revision: String) -> String {
        "\(Self.keyPrefix)\(campaignId)_\(revision)"
    }
}
