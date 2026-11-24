import XCTest
@testable import MarketapSDK

final class TestClock {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = date
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock()
    }
}

func triggerCampaign(
    _ id: String,
    eventName: String = "mkt_home_view",
    html: String? = "<div></div>",
    delaySeconds: Int? = nil,
    occurrence: OccurrenceCondition? = nil,
    abort: [String]? = nil,
    window: SendableTimeWindow? = nil,
    version: String? = "v1",
    tagIds: [String]? = nil,
    disableGlobalCap: Bool? = nil,
    slot: InAppDisplaySlot? = nil,
    orEventNames: [String]? = nil,
    frequencyCap: FrequencyCap? = nil
) -> InAppCampaign {
    var trigger = EventTriggerCondition(
        condition: Condition(eventFilter: EventFilter(eventName: eventName), propertyConditions: nil),
        conditions: orEventNames?.map { Condition(eventFilter: EventFilter(eventName: $0), propertyConditions: nil) },
        frequencyCap: frequencyCap,
        delayMinutes: nil
    )
    trigger.delaySeconds = delaySeconds
    trigger.occurrenceCondition = occurrence
    trigger.abortConditions = abort?.map { Condition(eventFilter: EventFilter(eventName: $0), propertyConditions: nil) }
    trigger.sendableTimeWindow = window
    var campaign = InAppCampaign(
        id: id,
        layout: Layout(layoutType: "MODAL", layoutSubType: "CENTER", orientations: ["portrait"]),
        triggerEventCondition: trigger,
        html: html,
        updatedAt: "2026-11-09T00:00:00Z",
        displaySlot: slot
    )
    campaign.triggerConditionVersion = version
    campaign.tagIds = tagIds
    campaign.disableGlobalFrequencyCap = disableGlobalCap
    return campaign
}

final class OccurrenceConditionEvaluatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock: TestClock!
    private var evaluator: OccurrenceConditionEvaluator!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults(self)
        clock = TestClock()
        let clock = self.clock!
        evaluator = OccurrenceConditionEvaluator(defaults: defaults, now: { clock.now })
    }

    func testNoConditionAlwaysSatisfied() {
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: triggerCampaign("a"), sessionId: "s1"))
    }

    func testTotalCountAcrossSessions() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 3))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1"))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s2"))
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s3"))
    }

    func testSessionScopedCountRestartsInNewSession() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2, sessionScoped: true))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1"))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s2"))
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s2"))
    }

    func testWindowDropsOldOccurrences() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2, durationMinutes: 10))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1"))
        clock.advance(11 * 60)
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1"))
        clock.advance(5 * 60)
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1"))
    }

    func testWindowedSessionScoped() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2, durationMinutes: 60, sessionScoped: true))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1"))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s2"))
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1"))
    }

    func testVersionChangeResetsCount() {
        let v1 = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2), version: "v1")
        let v2 = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2), version: "v2")
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: v1, sessionId: "s1"))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: v2, sessionId: "s1"))
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: v2, sessionId: "s1"))
    }

    func testResetAndResetAll() {
        let a = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2))
        let b = triggerCampaign("b", occurrence: OccurrenceCondition(count: 2, durationMinutes: 10))
        _ = evaluator.recordAndEvaluate(campaign: a, sessionId: "s1")
        _ = evaluator.recordAndEvaluate(campaign: b, sessionId: "s1")
        evaluator.reset(campaignId: "a")
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: a, sessionId: "s1"))
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: b, sessionId: "s1"))

        evaluator.resetAll()
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: a, sessionId: "s1"))
        XCTAssertFalse(evaluator.recordAndEvaluate(campaign: b, sessionId: "s1"))
    }

    func testHasCountedIsFalseWithoutCondition() {
        let campaign = triggerCampaign("a")
        _ = evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1")
        XCTAssertFalse(evaluator.hasCounted(campaign: campaign, sessionId: "s1"))
    }

    func testHasCountedTotalDoesNotRecord() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2))
        XCTAssertFalse(evaluator.hasCounted(campaign: campaign, sessionId: "s1"))
        _ = evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1")
        XCTAssertTrue(evaluator.hasCounted(campaign: campaign, sessionId: "s2"))
        XCTAssertTrue(evaluator.hasCounted(campaign: campaign, sessionId: "s2"))
        XCTAssertTrue(evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s2"))
    }

    func testHasCountedSessionScopedLooksAtSameSession() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2, sessionScoped: true))
        _ = evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1")
        XCTAssertTrue(evaluator.hasCounted(campaign: campaign, sessionId: "s1"))
        XCTAssertFalse(evaluator.hasCounted(campaign: campaign, sessionId: "s2"))
    }

    func testHasCountedWindowLooksAtRecordsInWindow() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2, durationMinutes: 10))
        _ = evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1")
        clock.advance(10 * 60)
        XCTAssertTrue(evaluator.hasCounted(campaign: campaign, sessionId: "s1"))
        clock.advance(1)
        XCTAssertFalse(evaluator.hasCounted(campaign: campaign, sessionId: "s1"))
    }

    func testHasCountedWindowedSessionScoped() {
        let campaign = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2, durationMinutes: 10, sessionScoped: true))
        _ = evaluator.recordAndEvaluate(campaign: campaign, sessionId: "s1")
        XCTAssertTrue(evaluator.hasCounted(campaign: campaign, sessionId: "s1"))
        XCTAssertFalse(evaluator.hasCounted(campaign: campaign, sessionId: "s2"))
    }

    func testHasCountedIgnoresOtherVersionAndReset() {
        let v1 = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2), version: "v1")
        let v2 = triggerCampaign("a", occurrence: OccurrenceCondition(count: 2), version: "v2")
        _ = evaluator.recordAndEvaluate(campaign: v1, sessionId: "s1")
        XCTAssertFalse(evaluator.hasCounted(campaign: v2, sessionId: "s1"))
        XCTAssertTrue(evaluator.hasCounted(campaign: v1, sessionId: "s1"))
        evaluator.reset(campaignId: "a")
        XCTAssertFalse(evaluator.hasCounted(campaign: v1, sessionId: "s1"))
    }
}

final class InAppWindowCheckerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    /// 2026-11-09 은 월요일.
    private func date(hour: Int, minute: Int, day: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private let window = SendableTimeWindow(weeklyTimeRules: [
        WeeklyTimeRule(dayOfWeek: "MONDAY", timeRanges: [SendableTimeRange(startMinuteOfDay: 540, endMinuteOfDay: 1080)])
    ])

    func testNoWindowAllows() {
        XCTAssertTrue(InAppWindowChecker(calendar: calendar).check(nil, now: date(hour: 3, minute: 0)))
    }

    func testInsideRangeIncludingBoundaries() {
        let checker = InAppWindowChecker(calendar: calendar)
        XCTAssertTrue(checker.check(window, now: date(hour: 9, minute: 0)))
        XCTAssertTrue(checker.check(window, now: date(hour: 18, minute: 0)))
        XCTAssertTrue(checker.check(window, now: date(hour: 12, minute: 30)))
    }

    func testOutsideRange() {
        let checker = InAppWindowChecker(calendar: calendar)
        XCTAssertFalse(checker.check(window, now: date(hour: 8, minute: 59)))
        XCTAssertFalse(checker.check(window, now: date(hour: 18, minute: 1)))
    }

    func testDayWithoutRuleIsBlocked() {
        XCTAssertFalse(InAppWindowChecker(calendar: calendar).check(window, now: date(hour: 12, minute: 0, day: 10)))
    }
}

final class GlobalImpressionLogTests: XCTestCase {
    private var log: GlobalImpressionLog!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        log = GlobalImpressionLog(defaults: makeIsolatedDefaults(self))
    }

    func testRuleWithoutTagsCountsEveryImpression() {
        let rule = GlobalFrequencyCapRule(limit: 2, durationMinutes: 60, tagIds: [])
        log.record(tagIds: ["x"], at: now)
        XCTAssertFalse(log.isCapped(campaign: triggerCampaign("a"), rules: [rule], now: now))
        log.record(tagIds: [], at: now)
        XCTAssertTrue(log.isCapped(campaign: triggerCampaign("a"), rules: [rule], now: now))
    }

    func testTaggedRuleAppliesOnlyToMatchingCampaignsAndImpressions() {
        let rule = GlobalFrequencyCapRule(limit: 1, durationMinutes: 60, tagIds: ["sale"])
        log.record(tagIds: ["other"], at: now)
        XCTAssertFalse(log.isCapped(campaign: triggerCampaign("a", tagIds: ["sale"]), rules: [rule], now: now))
        log.record(tagIds: ["sale"], at: now)
        XCTAssertTrue(log.isCapped(campaign: triggerCampaign("a", tagIds: ["sale"]), rules: [rule], now: now))
        XCTAssertFalse(log.isCapped(campaign: triggerCampaign("b", tagIds: ["other"]), rules: [rule], now: now))
    }

    func testNoCountTruncationAndTimeBasedPruning() {
        for _ in 0..<1_200 {
            log.record(tagIds: ["other"], at: now)
        }
        log.record(tagIds: ["sale"], at: now)
        let saleRule = GlobalFrequencyCapRule(limit: 1, durationMinutes: 60, tagIds: ["sale"])
        XCTAssertTrue(log.isCapped(campaign: triggerCampaign("a", tagIds: ["sale"]), rules: [saleRule], now: now))
        let bigRule = GlobalFrequencyCapRule(limit: 1_201, durationMinutes: 60, tagIds: [])
        XCTAssertTrue(log.isCapped(campaign: triggerCampaign("a"), rules: [bigRule], now: now))

        let later = now.addingTimeInterval(GlobalImpressionLog.minimumRetention + 60)
        log.record(tagIds: ["sale"], at: later)
        let yearRule = GlobalFrequencyCapRule(limit: 2, durationMinutes: 400 * 24 * 60, tagIds: ["sale"])
        XCTAssertFalse(log.isCapped(campaign: triggerCampaign("a", tagIds: ["sale"]), rules: [yearRule], now: later))
    }

    func testDurationAndOptOut() {
        let rule = GlobalFrequencyCapRule(limit: 1, durationMinutes: 10, tagIds: [])
        log.record(tagIds: [], at: now.addingTimeInterval(-11 * 60))
        XCTAssertFalse(log.isCapped(campaign: triggerCampaign("a"), rules: [rule], now: now))
        log.record(tagIds: [], at: now)
        XCTAssertTrue(log.isCapped(campaign: triggerCampaign("a"), rules: [rule], now: now))
        XCTAssertFalse(log.isCapped(campaign: triggerCampaign("a", disableGlobalCap: true), rules: [rule], now: now))
    }
}

final class InAppTriggerModelDecodingTests: XCTestCase {
    func testREG6_OldResponseWithoutNewFieldsDecodes() throws {
        let json = """
        {"checksum":"c","campaigns":[{"id":"a","layout":{"layoutType":"MODAL","layoutSubType":"CENTER","orientations":[]},
        "triggerEventCondition":{"condition":{"eventFilter":{"eventName":"mkt_home_view"}}},"html":null,"updatedAt":"x"}]}
        """
        let response = try JSONDecoder().decode(InAppCampaignFetchResponse.self, from: Data(json.utf8))
        let campaign = try XCTUnwrap(response.campaigns?.first)
        XCTAssertNil(campaign.triggerEventCondition.delayInterval)
        XCTAssertNil(campaign.triggerEventCondition.occurrenceCondition)
        XCTAssertNil(campaign.triggerConditionVersion)
        XCTAssertNil(response.globalFrequencyCaps)
    }

    func testDecodesTriggerConditionFields() throws {
        let json = """
        {"checksum":"c","globalFrequencyCaps":[{"channelType":"IN_APP_MESSAGE","limit":3,"durationMinutes":60,"tagIds":["t"]}],
        "campaigns":[{"id":"a","layout":{"layoutType":"MODAL","layoutSubType":"CENTER","orientations":[]},
        "triggerEventCondition":{"condition":{"eventFilter":{"eventName":"mkt_home_view"}},"delaySeconds":30,
        "occurrenceCondition":{"count":2,"durationMinutes":10,"sessionScoped":true},
        "abortConditions":[{"eventFilter":{"eventName":"mkt_purchase"}}],
        "sendableTimeWindow":{"weeklyTimeRules":[{"dayOfWeek":"MONDAY","timeRanges":[{"startMinuteOfDay":0,"endMinuteOfDay":1439}]}],
        "sendableTimePolicy":"DROP_IF_OUTSIDE_WINDOW","timezone":"Asia/Seoul"}},
        "triggerConditionVersion":"hash","priority":"HIGH","html":null,"updatedAt":"x","tagIds":["t"],"disableGlobalFrequencyCap":true}]}
        """
        let response = try JSONDecoder().decode(InAppCampaignFetchResponse.self, from: Data(json.utf8))
        let campaign = try XCTUnwrap(response.campaigns?.first)
        let trigger = campaign.triggerEventCondition
        XCTAssertEqual(trigger.delayInterval, 30)
        XCTAssertEqual(trigger.occurrenceCondition, OccurrenceCondition(count: 2, durationMinutes: 10, sessionScoped: true))
        XCTAssertEqual(trigger.abortConditions?.first?.eventFilter.eventName, "mkt_purchase")
        XCTAssertEqual(trigger.sendableTimeWindow?.weeklyTimeRules.first?.timeRanges.first?.endMinuteOfDay, 1439)
        XCTAssertEqual(campaign.triggerConditionVersion, "hash")
        XCTAssertEqual(campaign.tagIds, ["t"])
        XCTAssertEqual(campaign.disableGlobalFrequencyCap, true)
        XCTAssertEqual(response.globalFrequencyCaps?.first?.limit, 3)
    }

    func testZeroDelayIsImmediate() {
        XCTAssertNil(triggerCampaign("a", delaySeconds: 0).triggerEventCondition.delayInterval)
    }
}
