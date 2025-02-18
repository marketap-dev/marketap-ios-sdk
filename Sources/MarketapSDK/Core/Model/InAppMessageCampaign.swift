//
//  InAppMessageCampaign.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

enum TaxonomyOperator: String, Codable {
    case equal = "EQUAL"
    case notEqual = "NOT_EQUAL"
    case greaterThan = "GREATER_THAN"
    case greaterThanOrEqual = "GREATER_THAN_OR_EQUAL"
    case lessThan = "LESS_THAN"
    case lessThanOrEqual = "LESS_THAN_OR_EQUAL"
    case `in` = "IN"
    case notIn = "NOT_IN"
    case between = "BETWEEN"
    case notBetween = "NOT_BETWEEN"
    case like = "LIKE"
    case notLike = "NOT_LIKE"
    case isNull = "IS_NULL"
    case isNotNull = "IS_NOT_NULL"
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
    let html: String
}
