//
//  InAppMessageCampaign.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

/// 조건 비교 연산자
enum TaxonomyOperator: String, Codable {
    /// 이다
    case equal = "EQUAL"
    /// (이)가 아니다
    case notEqual = "NOT_EQUAL"
    /// 보다 크다
    case greaterThan = "GREATER_THAN"
    /// 보다 크거나 같다
    case greaterThanOrEqual = "GREATER_THAN_OR_EQUAL"
    /// 보다 작다
    case lessThan = "LESS_THAN"
    /// 보다 작거나 같다
    case lessThanOrEqual = "LESS_THAN_OR_EQUAL"
    /// 중 하나다
    case `in` = "IN"
    /// (이)가 아니다 (복수)
    case notIn = "NOT_IN"
    /// 의 사이값이다 (exclusive)
    case between = "BETWEEN"
    /// 의 사이값이 아니다
    case notBetween = "NOT_BETWEEN"
    /// 을(를) 포함한다 (case insensitive)
    case like = "LIKE"
    /// 을(를) 포함하지 않는다 (case insensitive)
    case notLike = "NOT_LIKE"
    /// 을(를) 포함하는 항목이 있다 (배열용, case insensitive)
    case arrayLike = "ARRAY_LIKE"
    /// 을(를) 포함하는 항목이 없다 (배열용, case insensitive)
    case arrayNotLike = "ARRAY_NOT_LIKE"
    /// 값이 없다
    case isNull = "IS_NULL"
    /// 값이 있다
    case isNotNull = "IS_NOT_NULL"
    /// 년이다
    case yearEqual = "YEAR_EQUAL"
    /// 월이다
    case monthEqual = "MONTH_EQUAL"
    /// 년월이다
    case yearMonthEqual = "YEAR_MONTH_EQUAL"
    /// 을(를) 포함한다 (배열에 값 포함 여부)
    case contains = "CONTAINS"
    /// 을(를) 포함하지 않는다 (배열에 값 미포함 여부)
    case notContains = "NOT_CONTAINS"
    /// 중 하나 이상 포함한다 (배열용)
    case any = "ANY"
    /// 을(를) 모두 포함하지 않는다 (배열용)
    case none = "NONE"
    /// N일 전이다 (정확히 N일 전)
    case before = "BEFORE"
    /// N일 이상 지났다
    case past = "PAST"
    /// N일 이내로 지났다 (최근 N일 이내)
    case withinPast = "WITHIN_PAST"
    /// N일 후이다 (정확히 N일 후)
    case after = "AFTER"
    /// N일 이상 남았다
    case remaining = "REMAINING"
    /// N일 이내로 남았다
    case withinRemaining = "WITHIN_REMAINING"

    var isNegativeOperator: Bool {
        switch self {
        case .notEqual, .notIn, .notBetween, .notLike, .arrayNotLike,
             .isNotNull, .notContains, .none:
            return true
        default:
            return false
        }
    }
}

enum DataType: String, Codable {
    case string = "STRING"
    case int = "INT"
    case bigint = "BIGINT"
    case double = "DOUBLE"
    case boolean = "BOOLEAN"
    case datetime = "DATETIME"
    case object = "OBJECT"
    case arrayString = "ARRAY_STRING"
    case date = "DATE"
}

enum Path: String, Codable {
    case event = "EVENT"
    case device = "DEVICE"
    case item = "ITEM"
}

struct EventPropertyCondition: Codable, Equatable {
    let extractionStrategy: ExtractionStrategy
    let operatorType: TaxonomyOperator
    let targetValues: [AnyCodable]

    enum CodingKeys: String, CodingKey {
        case extractionStrategy
        case operatorType = "operator"
        case targetValues
    }
}

struct ExtractionStrategy: Codable, Equatable {
    let propertySchema: PropertySchema
}

struct PropertySchema: Codable, Equatable {
    let id: String
    let name: String
    let dataType: DataType
    let path: Path?
}

struct EventFilter: Codable, Equatable {
    let eventName: String
}

struct EventTriggerCondition: Codable, Equatable {
    let condition: Condition
    /// 하나라도 이벤트에 맞으면 트리거된다. 없으면 `condition` 하나로 판정한다.
    let conditions: [Condition]?
    let frequencyCap: FrequencyCap?
    let delayMinutes: Int?
    var sendableTimeWindow: SendableTimeWindow? = nil
    var delaySeconds: Int? = nil
    var occurrenceCondition: OccurrenceCondition? = nil
    var abortConditions: [Condition]? = nil
    /// 도달(트리거 조건) 전에 차례로 일어나야 하는 이벤트 단계. 없으면 트리거 조건만으로 판정한다.
    var flow: EventFlow? = nil

    init(condition: Condition, conditions: [Condition]? = nil, frequencyCap: FrequencyCap?, delayMinutes: Int?) {
        self.condition = condition
        self.conditions = conditions
        self.frequencyCap = frequencyCap
        self.delayMinutes = delayMinutes
    }

    var effectiveConditions: [Condition] {
        if let conditions = conditions, !conditions.isEmpty { return conditions }
        return [condition]
    }

    var hasEventFlow: Bool {
        flow?.precedingSteps.isEmpty == false
    }

    var delayInterval: TimeInterval? {
        guard let delaySeconds = delaySeconds, delaySeconds > 0 else { return nil }
        return TimeInterval(delaySeconds)
    }
}

/// 이벤트 플로우. `precedingSteps` 를 차례로 거친 뒤 트리거 조건(도달)에 맞는 이벤트가 오면 트리거된다.
/// `reentryBlockSeconds` 가 있으면 진행 중 취소 이벤트가 일어난 뒤 그 시간 동안 다시 진입하지 않는다.
struct EventFlow: Codable, Equatable {
    let precedingSteps: [EventFlowStep]
    var reentryBlockSeconds: Int? = nil
}

/// 플로우 단계. `conditions` 중 하나에 맞는 이벤트가 직전 단계 뒤 `withinSeconds` 초 안에 일어나야 한다.
struct EventFlowStep: Codable, Equatable {
    let conditions: [Condition]
    let withinSeconds: Int
}

/// 트리거 이벤트가 `count`번 쌓여야 노출한다. `durationMinutes`가 있으면 그 기간 안의 횟수만 센다.
struct OccurrenceCondition: Codable, Equatable {
    let count: Int
    var durationMinutes: Int? = nil
    var sessionScoped: Bool? = nil
}

/// 노출 가능 시간대. 단말의 현지 시각으로 판정한다(`timezone`은 쓰지 않는다).
struct SendableTimeWindow: Codable, Equatable {
    let weeklyTimeRules: [WeeklyTimeRule]
    var sendableTimePolicy: String? = nil
    var timezone: String? = nil
}

struct WeeklyTimeRule: Codable, Equatable {
    /// `MONDAY` ~ `SUNDAY`
    let dayOfWeek: String
    let timeRanges: [SendableTimeRange]
}

/// 하루 중 분(0~1439), 양 끝 포함.
struct SendableTimeRange: Codable, Equatable {
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
}

/// 첫 노출 후 `minutes` 분 동안만 보이는 타이머. `revision` 이 바뀌면 시작 시각을 새로 잡는다.
struct InAppCampaignTimer: Codable, Equatable {
    let minutes: Int
    let revision: String
}

/// 채널 단위 전체 빈도 제한. `tagIds`가 비어 있으면 모든 캠페인에 적용한다.
struct GlobalFrequencyCapRule: Codable, Equatable {
    var channelType: String? = nil
    let limit: Int
    let durationMinutes: Int
    let tagIds: [String]
}

struct Condition: Codable, Equatable {
    let eventFilter: EventFilter
    let propertyConditions: [[EventPropertyCondition]]?
}

struct FrequencyCap: Codable, Equatable {
    let limit: Int
    let durationMinutes: Int
}

struct Layout: Codable, Equatable {
    let layoutType: String
    let layoutSubType: String
    let orientations: [String]
}

/// 인앱이 차지하는 자리. 자리마다 하나씩 뜨고 서로 막지 않는다. 값이 없거나 모르는 값이면 `popup`.
enum InAppDisplaySlot: String, Codable, Equatable {
    case popup = "POPUP"
    case floating = "FLOATING"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InAppDisplaySlot(rawValue: raw) ?? .popup
    }
}

struct InAppCampaign: Codable, Equatable {
    let id: String
    let layout: Layout
    let triggerEventCondition: EventTriggerCondition
    let html: String?
    let updatedAt: String
    /// 서버는 플로팅일 때만 싣는다.
    var displaySlot: InAppDisplaySlot? = nil
    /// 플로팅의 화면 이동 값. `PAGE` 면 "이 페이지에서만", 그 밖의 값과 값 없음은 "닫을 때까지 유지".
    var floatingScope: String? = nil
    /// 트리거·횟수 조건이 바뀌면 달라진다. 누적 횟수의 유효성 키.
    var triggerConditionVersion: String? = nil
    var tagIds: [String]? = nil
    var disableGlobalFrequencyCap: Bool? = nil
    var timer: InAppCampaignTimer? = nil
    /// 테스트 발송 캠페인. 타이머 시작 시각을 기록하지 않고 만료도 판정하지 않는다.
    var isTest: Bool? = nil

    var slot: InAppDisplaySlot { displaySlot ?? .popup }

    /// 상세 응답에 자리·타이머·테스트 정보가 없으면 목록 응답의 값을 쓴다.
    func inheritingSlot(from listed: InAppCampaign) -> InAppCampaign {
        var resolved = self
        if displaySlot == nil {
            resolved.displaySlot = listed.displaySlot
            resolved.floatingScope = floatingScope ?? listed.floatingScope
        }
        resolved.timer = timer ?? listed.timer
        resolved.isTest = isTest ?? listed.isTest
        return resolved
    }

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
