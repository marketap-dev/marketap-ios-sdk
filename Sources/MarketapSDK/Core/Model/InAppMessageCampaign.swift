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
    let frequencyCap: FrequencyCap?
    let delayMinutes: Int?
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

struct InAppCampaign: Codable, Equatable {
    let id: String
    let layout: Layout
    let triggerEventCondition: EventTriggerCondition
    let html: String?
    let updatedAt: String

    func toDictionary() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
