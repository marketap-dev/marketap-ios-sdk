//
//  InAppMessageServiceOperatorTests.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

import XCTest
@testable import MarketapSDK

class InAppMessageServiceOperatorTests: XCTestCase {
    var inAppMessageService: InAppMessageService!

    override func setUp() {
        super.setUp()
        let api = MockMarketapAPIForIAM()
        let cache = MockMarketapCache()
        inAppMessageService = InAppMessageService(
            customHandlerStore: CustomHandlerStor(),
            api: api,
            cache: cache
        )
    }

    override func tearDown() {
        inAppMessageService = nil
        super.tearDown()
    }

    func testIsEventTriggered() {
        let eventFilter = EventFilter(eventName: "test_event")
        let condition = Condition(eventFilter: eventFilter, propertyConditions: nil)
        let triggerCondition = EventTriggerCondition(condition: condition, frequencyCap: nil, delayMinutes: nil)

        let eventRequest = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: nil,
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isEventTriggered(condition: triggerCondition, event: eventRequest))
    }

    func testIsEventTriggeredWithIncorrectName() {
        let eventFilter = EventFilter(eventName: "expected_event")
        let condition = Condition(eventFilter: eventFilter, propertyConditions: nil)
        let triggerCondition = EventTriggerCondition(condition: condition, frequencyCap: nil, delayMinutes: nil)

        let eventRequest = IngestEventRequest(
            id: "1",
            name: "wrong_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: nil,
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isEventTriggered(condition: triggerCondition, event: eventRequest))
    }

    func testCompareString() {
        XCTAssertTrue(inAppMessageService.compareString(operator: .equal, source: "hello", targets: ["hello"]))
        XCTAssertFalse(inAppMessageService.compareString(operator: .notEqual, source: "hello", targets: ["hello"]))
        XCTAssertTrue(inAppMessageService.compareString(operator: .like, source: "hello world", targets: ["hello"]))
        XCTAssertFalse(inAppMessageService.compareString(operator: .notLike, source: "hello world", targets: ["hello"]))
    }

    func testCompareNumber() {
        XCTAssertTrue(inAppMessageService.compareNumber(operator: .equal, source: 10, targets: [10]))
        XCTAssertFalse(inAppMessageService.compareNumber(operator: .notEqual, source: 10, targets: [10]))
        XCTAssertTrue(inAppMessageService.compareNumber(operator: .greaterThan, source: 10, targets: [5]))
        XCTAssertFalse(inAppMessageService.compareNumber(operator: .lessThan, source: 10, targets: [5]))
        XCTAssertTrue(inAppMessageService.compareNumber(operator: .between, source: 7, targets: [5, 10]))
        XCTAssertFalse(inAppMessageService.compareNumber(operator: .notBetween, source: 7, targets: [5, 10]))
    }

    func testCompareBoolean() {
        XCTAssertTrue(inAppMessageService.compareBoolean(operator: .equal, source: true, targets: [true]))
        XCTAssertFalse(inAppMessageService.compareBoolean(operator: .notEqual, source: true, targets: [true]))
    }

    func testCompareDate() {
        let date1 = "2025-02-15"
        let date2 = "2025-02-14"

        XCTAssertTrue(inAppMessageService.compareDate(operator: .equal, source: date1, targets: [date1]))
        XCTAssertFalse(inAppMessageService.compareDate(operator: .notEqual, source: date1, targets: [date1]))
        XCTAssertTrue(inAppMessageService.compareDate(operator: .greaterThan, source: date1, targets: [date2]))
        XCTAssertFalse(inAppMessageService.compareDate(operator: .lessThan, source: date1, targets: [date2]))
    }

    func testCompareStringArray() {
        // CONTAINS: source 배열에 target이 포함되어 있는지
        XCTAssertTrue(inAppMessageService.compareStringArray(operator: .contains, source: ["apple", "banana"], targets: ["apple"]))
        XCTAssertFalse(inAppMessageService.compareStringArray(operator: .contains, source: ["apple", "banana"], targets: ["grape"]))

        // NOT_CONTAINS: source 배열에 target이 포함되어 있지 않은지
        XCTAssertTrue(inAppMessageService.compareStringArray(operator: .notContains, source: ["apple", "banana"], targets: ["grape"]))
        XCTAssertFalse(inAppMessageService.compareStringArray(operator: .notContains, source: ["apple", "banana"], targets: ["apple"]))
    }

    func testIsPropertyConditionMatchedForInt() {
        let schema = PropertySchema(id: "1", name: "price", dataType: .int, path: .event)
        let testValue = 50

        let operators: [TaxonomyOperator] = [.equal, .notEqual, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .between, .notBetween]

        for op in operators {
            let condition = EventPropertyCondition(
                extractionStrategy: ExtractionStrategy(propertySchema: schema),
                operatorType: op,
                targetValues: [AnyCodable(30), AnyCodable(60)]
            )

            let event = IngestEventRequest(
                id: "1",
                name: "test_event",
                userId: "user_123",
                device: MockDevice().toDevice().makeRequest(),
                properties: ["price": AnyCodable(testValue)],
                timestamp: Date()
            )

            let expectedResult: Bool
            switch op {
            case .equal: expectedResult = testValue == 30
            case .notEqual: expectedResult = testValue != 30
            case .greaterThan: expectedResult = testValue > 30
            case .greaterThanOrEqual: expectedResult = testValue >= 30
            case .lessThan: expectedResult = testValue < 30  // uses first target
            case .lessThanOrEqual: expectedResult = testValue <= 30  // uses first target
            case .between: expectedResult = (testValue > 30 && testValue < 60)  // exclusive
            case .notBetween: expectedResult = (testValue <= 30 || testValue >= 60)  // inclusive on boundaries
            default: expectedResult = false
            }

            XCTAssertEqual(
                inAppMessageService.isPropertyConditionMatched(condition, event: event),
                expectedResult,
                "Operator \(op.rawValue) failed for INT"
            )
        }
    }

    func testIsPropertyConditionMatchedForDouble() {
        let schema = PropertySchema(id: "2", name: "rating", dataType: .double, path: .event)
        let testValue = 4.5

        let operators: [TaxonomyOperator] = [.equal, .notEqual, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .between, .notBetween]

        for op in operators {
            let condition = EventPropertyCondition(
                extractionStrategy: ExtractionStrategy(propertySchema: schema),
                operatorType: op,
                targetValues: [AnyCodable(4.0), AnyCodable(5.0)]
            )

            let event = IngestEventRequest(
                id: "2",
                name: "test_event",
                userId: "user_123",
                device: MockDevice().toDevice().makeRequest(),
                properties: ["rating": AnyCodable(testValue)],
                timestamp: Date()
            )

            let expectedResult: Bool
            switch op {
            case .equal: expectedResult = testValue == 4.0
            case .notEqual: expectedResult = testValue != 4.0
            case .greaterThan: expectedResult = testValue > 4.0
            case .greaterThanOrEqual: expectedResult = testValue >= 4.0
            case .lessThan: expectedResult = testValue < 4.0  // uses first target
            case .lessThanOrEqual: expectedResult = testValue <= 4.0  // uses first target
            case .between: expectedResult = (testValue > 4.0 && testValue < 5.0)  // exclusive
            case .notBetween: expectedResult = (testValue <= 4.0 || testValue >= 5.0)  // inclusive on boundaries
            default: expectedResult = false
            }

            XCTAssertEqual(
                inAppMessageService.isPropertyConditionMatched(condition, event: event),
                expectedResult,
                "Operator \(op.rawValue) failed for DOUBLE"
            )
        }
    }

    func testIsPropertyConditionMatchedForString() {
        let schema = PropertySchema(id: "3", name: "status", dataType: .string, path: .event)
        let testValue = "ACTIVE"

        let operators: [TaxonomyOperator] = [.equal, .notEqual, .like, .notLike]

        for op in operators {
            let condition = EventPropertyCondition(
                extractionStrategy: ExtractionStrategy(propertySchema: schema),
                operatorType: op,
                targetValues: [AnyCodable("ACTIVE"), AnyCodable("ACT")]
            )

            let event = IngestEventRequest(
                id: "3",
                name: "test_event",
                userId: "user_123",
                device: MockDevice().toDevice().makeRequest(),
                properties: ["status": AnyCodable(testValue)],
                timestamp: Date()
            )

            let expectedResult: Bool
            switch op {
            case .equal: expectedResult = testValue == "ACTIVE"
            case .notEqual: expectedResult = testValue != "ACTIVE"
            case .like: expectedResult = testValue.contains("ACT")
            case .notLike: expectedResult = !testValue.contains("ACT")
            default: expectedResult = false
            }

            XCTAssertEqual(
                inAppMessageService.isPropertyConditionMatched(condition, event: event),
                expectedResult,
                "Operator \(op.rawValue) failed for STRING"
            )
        }
    }

    func testIsPropertyConditionMatchedForBoolean() {
        let schema = PropertySchema(id: "4", name: "is_member", dataType: .boolean, path: .event)
        let testValue = true

        let operators: [TaxonomyOperator] = [.equal, .notEqual]

        for op in operators {
            let condition = EventPropertyCondition(
                extractionStrategy: ExtractionStrategy(propertySchema: schema),
                operatorType: op,
                targetValues: [AnyCodable(true)]
            )

            let event = IngestEventRequest(
                id: "4",
                name: "test_event",
                userId: "user_123",
                device: MockDevice().toDevice().makeRequest(),
                properties: ["is_member": AnyCodable(testValue)],
                timestamp: Date()
            )

            let expectedResult: Bool
            switch op {
            case .equal: expectedResult = testValue == true
            case .notEqual: expectedResult = testValue != true
            default: expectedResult = false
            }

            XCTAssertEqual(
                inAppMessageService.isPropertyConditionMatched(condition, event: event),
                expectedResult,
                "Operator \(op.rawValue) failed for BOOLEAN"
            )
        }
    }

    func testIsPropertyConditionMatchedForDateTime() {
        let schema = PropertySchema(id: "5", name: "last_login", dataType: .datetime, path: .event)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let testDate = Date()
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        let futureDate = Calendar.current.date(byAdding: .day, value: 1, to: testDate)!

        let testDateString = isoFormatter.string(from: testDate)
        let pastDateString = isoFormatter.string(from: pastDate)
        let futureDateString = isoFormatter.string(from: futureDate)

        let operators: [TaxonomyOperator] = [.equal, .notEqual, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .between, .notBetween]

        for op in operators {
            let condition = EventPropertyCondition(
                extractionStrategy: ExtractionStrategy(propertySchema: schema),
                operatorType: op,
                targetValues: [AnyCodable(pastDateString), AnyCodable(futureDateString)]
            )

            let event = IngestEventRequest(
                id: "5",
                name: "test_event",
                userId: "user_123",
                device: MockDevice().toDevice().makeRequest(),
                properties: ["last_login": AnyCodable(testDateString)],
                timestamp: Date()
            )

            let expectedResult: Bool
            switch op {
            case .equal: expectedResult = testDate == pastDate
            case .notEqual: expectedResult = testDate != pastDate
            case .greaterThan: expectedResult = testDate > pastDate
            case .greaterThanOrEqual: expectedResult = testDate >= pastDate
            case .lessThan: expectedResult = testDate < pastDate  // uses first target
            case .lessThanOrEqual: expectedResult = testDate <= pastDate  // uses first target
            case .between: expectedResult = (testDate > pastDate && testDate < futureDate)  // exclusive
            case .notBetween: expectedResult = (testDate <= pastDate || testDate >= futureDate)  // inclusive on boundaries
            default: expectedResult = false
            }

            XCTAssertEqual(
                inAppMessageService.isPropertyConditionMatched(condition, event: event),
                expectedResult,
                "Operator \(op.rawValue) failed for DATETIME"
            )
        }
    }

    func testIsPropertyConditionMatchedForDate() {
        let schema = PropertySchema(id: "6", name: "birth_date", dataType: .date, path: .event)
        let testValue = "2024-02-20"

        let operators: [TaxonomyOperator] = [.equal, .notEqual, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .between, .notBetween]

        for op in operators {
            let condition = EventPropertyCondition(
                extractionStrategy: ExtractionStrategy(propertySchema: schema),
                operatorType: op,
                targetValues: [AnyCodable("2024-02-10"), AnyCodable("2024-02-25")]
            )

            let event = IngestEventRequest(
                id: "6",
                name: "test_event",
                userId: "user_123",
                device: MockDevice().toDevice().makeRequest(),
                properties: ["birth_date": AnyCodable(testValue)],
                timestamp: Date()
            )

            let expectedResult: Bool
            switch op {
            case .equal: expectedResult = testValue == "2024-02-10"
            case .notEqual: expectedResult = testValue != "2024-02-10"
            case .greaterThan: expectedResult = testValue > "2024-02-10"
            case .greaterThanOrEqual: expectedResult = testValue >= "2024-02-10"
            case .lessThan: expectedResult = testValue < "2024-02-10"  // uses first target
            case .lessThanOrEqual: expectedResult = testValue <= "2024-02-10"  // uses first target
            case .between: expectedResult = (testValue > "2024-02-10" && testValue < "2024-02-25")  // exclusive
            case .notBetween: expectedResult = (testValue <= "2024-02-10" || testValue >= "2024-02-25")  // inclusive on boundaries
            default: expectedResult = false
            }

            XCTAssertEqual(
                inAppMessageService.isPropertyConditionMatched(condition, event: event),
                expectedResult,
                "Operator \(op.rawValue) failed for DATE"
            )
        }
    }

    func testIsPropertyConditionMatchedForArrayString() {
        let schema = PropertySchema(id: "7", name: "tags", dataType: .arrayString, path: .event)

        let eventTags = ["sports", "news", "tech"]

        // CONTAINS: source 배열에 target이 포함되어 있는지
        let conditionContains = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .contains,
            targetValues: [AnyCodable("sports")]
        )

        // NOT_CONTAINS: source 배열에 target이 포함되어 있지 않은지
        let conditionNotContains = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .notContains,
            targetValues: [AnyCodable("finance")]
        )

        // ANY: targets 중 하나라도 source에 있는지
        let conditionAny = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .any,
            targetValues: [AnyCodable("sports"), AnyCodable("finance")]
        )

        // NONE: targets 중 어떤 것도 source에 없는지
        let conditionNone = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .none,
            targetValues: [AnyCodable("finance"), AnyCodable("health")]
        )

        let event = IngestEventRequest(
            id: "7",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["tags": AnyCodable(eventTags)],
            timestamp: Date()
        )

        // CONTAINS: "sports"가 eventTags에 있으므로 true
        XCTAssertTrue(
            inAppMessageService.isPropertyConditionMatched(conditionContains, event: event),
            "Operator CONTAINS failed for ARRAY_STRING"
        )

        // NOT_CONTAINS: "finance"가 eventTags에 없으므로 true
        XCTAssertTrue(
            inAppMessageService.isPropertyConditionMatched(conditionNotContains, event: event),
            "Operator NOT_CONTAINS failed for ARRAY_STRING"
        )

        // ANY: "sports"가 eventTags에 있으므로 true
        XCTAssertTrue(
            inAppMessageService.isPropertyConditionMatched(conditionAny, event: event),
            "Operator ANY failed for ARRAY_STRING"
        )

        // NONE: "finance", "health" 둘 다 eventTags에 없으므로 true
        XCTAssertTrue(
            inAppMessageService.isPropertyConditionMatched(conditionNone, event: event),
            "Operator NONE failed for ARRAY_STRING"
        )
    }


    func testCompareNullValues() {
        XCTAssertTrue(inAppMessageService.compare(dataType: .string, operator: .isNull, source: NSNull(), targets: []))
        XCTAssertFalse(inAppMessageService.compare(dataType: .string, operator: .isNotNull, source: NSNull(), targets: []))
    }

    // MARK: - Aggregate 로직 테스트 (Item Path)

    /// NOT_LIKE with Item Path - 모든 아이템이 조건을 만족해야 true
    func testItemPathNotLikeAllItemsMustMatch() {
        let schema = PropertySchema(id: "1", name: "mkt_product_name", dataType: .string, path: .item)

        // 조건: mkt_product_name NOT_LIKE "콜라"
        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .notLike,
            targetValues: [AnyCodable("콜라")]
        )

        // Case 1: 모든 아이템이 "콜라"를 포함하지 않음 → true
        let event1 = IngestEventRequest(
            id: "1",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "사이다"],
                    ["mkt_product_name": "환타"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertTrue(
            inAppMessageService.isPropertyConditionMatched(condition, event: event1),
            "All items without '콜라' should return true"
        )

        // Case 2: 하나의 아이템이 "콜라"를 포함 → false
        let event2 = IngestEventRequest(
            id: "2",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "콜라"],
                    ["mkt_product_name": "사이다"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertFalse(
            inAppMessageService.isPropertyConditionMatched(condition, event: event2),
            "One item with '콜라' should return false"
        )

        // Case 3: 모든 아이템이 "콜라"를 포함 → false
        let event3 = IngestEventRequest(
            id: "3",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "코카콜라"],
                    ["mkt_product_name": "펩시콜라"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertFalse(
            inAppMessageService.isPropertyConditionMatched(condition, event: event3),
            "All items with '콜라' should return false"
        )
    }

    /// LIKE with Item Path - 하나라도 조건을 만족하면 true
    func testItemPathLikeAnyItemMatches() {
        let schema = PropertySchema(id: "1", name: "mkt_product_name", dataType: .string, path: .item)

        // 조건: mkt_product_name LIKE "콜라"
        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .like,
            targetValues: [AnyCodable("콜라")]
        )

        // Case 1: 하나의 아이템이 "콜라"를 포함 → true
        let event1 = IngestEventRequest(
            id: "1",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "콜라"],
                    ["mkt_product_name": "사이다"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertTrue(
            inAppMessageService.isPropertyConditionMatched(condition, event: event1),
            "One item with '콜라' should return true"
        )

        // Case 2: 모든 아이템이 "콜라"를 포함하지 않음 → false
        let event2 = IngestEventRequest(
            id: "2",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "사이다"],
                    ["mkt_product_name": "환타"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertFalse(
            inAppMessageService.isPropertyConditionMatched(condition, event: event2),
            "No items with '콜라' should return false"
        )
    }

    /// 복합 조건 테스트 - 사용자 시나리오
    func testComplexItemCondition() {
        let schema = PropertySchema(id: "1", name: "mkt_product_name", dataType: .string, path: .item)

        // 조건: IS_NOT_NULL AND NOT_LIKE "콜라" AND NOT_LIKE "스프라이트"
        let condition1 = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .isNotNull,
            targetValues: [AnyCodable("콜라")]
        )
        let condition2 = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .notLike,
            targetValues: [AnyCodable("콜라")]
        )
        let condition3 = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .notLike,
            targetValues: [AnyCodable("스프라이트")]
        )

        let eventFilter = EventFilter(eventName: "mkt_begin_checkout")
        let condition = Condition(eventFilter: eventFilter, propertyConditions: [[condition1, condition2, condition3]])
        let triggerCondition = EventTriggerCondition(condition: condition, frequencyCap: nil, delayMinutes: nil)

        // Case 1: 콜라도 스프라이트도 없는 아이템들 → true
        let event1 = IngestEventRequest(
            id: "1",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "사이다"],
                    ["mkt_product_name": "환타"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertTrue(
            inAppMessageService.isEventTriggered(condition: triggerCondition, event: event1),
            "Items without '콜라' and '스프라이트' should return true"
        )

        // Case 2: 콜라가 포함된 아이템 → false
        let event2 = IngestEventRequest(
            id: "2",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "코카콜라"],
                    ["mkt_product_name": "환타"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertFalse(
            inAppMessageService.isEventTriggered(condition: triggerCondition, event: event2),
            "Items with '콜라' should return false"
        )

        // Case 3: 스프라이트가 포함된 아이템 → false
        let event3 = IngestEventRequest(
            id: "3",
            name: "mkt_begin_checkout",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: [
                "mkt_items": AnyCodable([
                    ["mkt_product_name": "사이다"],
                    ["mkt_product_name": "스프라이트"]
                ])
            ],
            timestamp: Date()
        )
        XCTAssertFalse(
            inAppMessageService.isEventTriggered(condition: triggerCondition, event: event3),
            "Items with '스프라이트' should return false"
        )
    }

    /// BETWEEN exclusive 테스트
    func testBetweenExclusive() {
        // Number
        XCTAssertFalse(inAppMessageService.compareNumber(operator: .between, source: 10, targets: [10, 20]),
                       "BETWEEN should be exclusive - boundary value 10 should return false")
        XCTAssertFalse(inAppMessageService.compareNumber(operator: .between, source: 20, targets: [10, 20]),
                       "BETWEEN should be exclusive - boundary value 20 should return false")
        XCTAssertTrue(inAppMessageService.compareNumber(operator: .between, source: 15, targets: [10, 20]),
                      "BETWEEN should return true for value in range")

        // NOT_BETWEEN inclusive
        XCTAssertTrue(inAppMessageService.compareNumber(operator: .notBetween, source: 10, targets: [10, 20]),
                      "NOT_BETWEEN should be inclusive - boundary value 10 should return true")
        XCTAssertTrue(inAppMessageService.compareNumber(operator: .notBetween, source: 20, targets: [10, 20]),
                      "NOT_BETWEEN should be inclusive - boundary value 20 should return true")
    }

    /// LIKE case insensitive 테스트
    func testLikeCaseInsensitive() {
        XCTAssertTrue(inAppMessageService.compareString(operator: .like, source: "Hello World", targets: ["hello"]),
                      "LIKE should be case insensitive")
        XCTAssertTrue(inAppMessageService.compareString(operator: .like, source: "hello world", targets: ["HELLO"]),
                      "LIKE should be case insensitive")
        XCTAssertFalse(inAppMessageService.compareString(operator: .notLike, source: "Hello World", targets: ["hello"]),
                       "NOT_LIKE should be case insensitive")
    }

    /// IN/NOT_IN 테스트
    func testInNotInOperators() {
        // String
        XCTAssertTrue(inAppMessageService.compareString(operator: .in, source: "apple", targets: ["apple", "banana", "cherry"]),
                      "IN should return true when source is in targets")
        XCTAssertFalse(inAppMessageService.compareString(operator: .in, source: "grape", targets: ["apple", "banana", "cherry"]),
                       "IN should return false when source is not in targets")
        XCTAssertTrue(inAppMessageService.compareString(operator: .notIn, source: "grape", targets: ["apple", "banana", "cherry"]),
                      "NOT_IN should return true when source is not in targets")

        // Number
        XCTAssertTrue(inAppMessageService.compareNumber(operator: .in, source: 10, targets: [10, 20, 30]),
                      "IN should work for numbers")
        XCTAssertFalse(inAppMessageService.compareNumber(operator: .in, source: 15, targets: [10, 20, 30]),
                       "IN should return false when number not in list")
    }

    /// ANY/NONE 테스트 (StringArray)
    func testAnyNoneOperators() {
        let source = ["apple", "banana", "cherry"]

        XCTAssertTrue(inAppMessageService.compareStringArray(operator: .any, source: source, targets: ["banana", "grape"]),
                      "ANY should return true when at least one target is in source")
        XCTAssertFalse(inAppMessageService.compareStringArray(operator: .any, source: source, targets: ["grape", "melon"]),
                       "ANY should return false when no targets are in source")
        XCTAssertTrue(inAppMessageService.compareStringArray(operator: .none, source: source, targets: ["grape", "melon"]),
                      "NONE should return true when no targets are in source")
        XCTAssertFalse(inAppMessageService.compareStringArray(operator: .none, source: source, targets: ["banana", "grape"]),
                       "NONE should return false when at least one target is in source")
    }

    /// ARRAY_LIKE/ARRAY_NOT_LIKE 테스트
    func testArrayLikeOperators() {
        let source = ["apple pie", "banana bread", "cherry cake"]

        XCTAssertTrue(inAppMessageService.compareStringArray(operator: .arrayLike, source: source, targets: ["pie"]),
                      "ARRAY_LIKE should return true when any element contains target")
        XCTAssertTrue(inAppMessageService.compareStringArray(operator: .arrayLike, source: source, targets: ["PIE"]),
                      "ARRAY_LIKE should be case insensitive")
        XCTAssertFalse(inAppMessageService.compareStringArray(operator: .arrayLike, source: source, targets: ["pizza"]),
                       "ARRAY_LIKE should return false when no element contains target")

        XCTAssertTrue(inAppMessageService.compareStringArray(operator: .arrayNotLike, source: source, targets: ["pizza"]),
                      "ARRAY_NOT_LIKE should return true when no element contains target")
        XCTAssertFalse(inAppMessageService.compareStringArray(operator: .arrayNotLike, source: source, targets: ["pie"]),
                       "ARRAY_NOT_LIKE should return false when any element contains target")
    }

    // MARK: - 날짜 추출 연산자 테스트

    /// YEAR_EQUAL 테스트
    func testYearEqualOperator() {
        // DateTime
        let datetimeSchema = PropertySchema(id: "1", name: "created_at", dataType: .datetime, path: .event)
        let testDate = Date() // 현재 날짜
        let currentYear = Calendar.current.component(.year, from: testDate)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let testDateString = isoFormatter.string(from: testDate)

        let conditionMatch = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: datetimeSchema),
            operatorType: .yearEqual,
            targetValues: [AnyCodable(currentYear)]
        )

        let conditionNoMatch = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: datetimeSchema),
            operatorType: .yearEqual,
            targetValues: [AnyCodable(currentYear - 1)]
        )

        let event = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["created_at": AnyCodable(testDateString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(conditionMatch, event: event),
                      "YEAR_EQUAL should match current year")
        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(conditionNoMatch, event: event),
                       "YEAR_EQUAL should not match different year")

        // Date
        let dateSchema = PropertySchema(id: "2", name: "birth_date", dataType: .date, path: .event)
        let dateConditionMatch = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: dateSchema),
            operatorType: .yearEqual,
            targetValues: [AnyCodable(2024)]
        )

        let dateEvent = IngestEventRequest(
            id: "2",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["birth_date": AnyCodable("2024-06-15")],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(dateConditionMatch, event: dateEvent),
                      "YEAR_EQUAL should work for DATE type")
    }

    /// MONTH_EQUAL 테스트
    func testMonthEqualOperator() {
        let datetimeSchema = PropertySchema(id: "1", name: "created_at", dataType: .datetime, path: .event)
        let testDate = Date()
        let currentMonth = Calendar.current.component(.month, from: testDate)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let testDateString = isoFormatter.string(from: testDate)

        let conditionMatch = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: datetimeSchema),
            operatorType: .monthEqual,
            targetValues: [AnyCodable(currentMonth)]
        )

        let conditionNoMatch = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: datetimeSchema),
            operatorType: .monthEqual,
            targetValues: [AnyCodable((currentMonth % 12) + 1)] // 다른 월
        )

        let event = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["created_at": AnyCodable(testDateString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(conditionMatch, event: event),
                      "MONTH_EQUAL should match current month")
        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(conditionNoMatch, event: event),
                       "MONTH_EQUAL should not match different month")
    }

    /// YEAR_MONTH_EQUAL 테스트
    func testYearMonthEqualOperator() {
        let datetimeSchema = PropertySchema(id: "1", name: "created_at", dataType: .datetime, path: .event)
        let testDate = Date()
        let currentYear = Calendar.current.component(.year, from: testDate)
        let currentMonth = Calendar.current.component(.month, from: testDate)
        let yearMonthString = String(format: "%d-%02d", currentYear, currentMonth)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let testDateString = isoFormatter.string(from: testDate)

        let conditionMatch = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: datetimeSchema),
            operatorType: .yearMonthEqual,
            targetValues: [AnyCodable(yearMonthString)]
        )

        let conditionNoMatch = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: datetimeSchema),
            operatorType: .yearMonthEqual,
            targetValues: [AnyCodable("\(currentYear - 1)-\(String(format: "%02d", currentMonth))")]
        )

        let event = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["created_at": AnyCodable(testDateString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(conditionMatch, event: event),
                      "YEAR_MONTH_EQUAL should match current year-month")
        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(conditionNoMatch, event: event),
                       "YEAR_MONTH_EQUAL should not match different year-month")
    }

    // MARK: - 상대 날짜 연산자 테스트

    /// BEFORE 테스트 (N일 전인 날짜)
    func testBeforeOperator() {
        let dateSchema = PropertySchema(id: "1", name: "event_date", dataType: .date, path: .event)

        // 3일 전 날짜 생성
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let threeDaysAgoString = formatter.string(from: threeDaysAgo)

        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: dateSchema),
            operatorType: .before,
            targetValues: [AnyCodable(3)] // 3일 전
        )

        let eventMatch = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(threeDaysAgoString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(condition, event: eventMatch),
                      "BEFORE should match date that is exactly N days ago")

        // 2일 전 (매칭 안됨)
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let twoDaysAgoString = formatter.string(from: twoDaysAgo)

        let eventNoMatch = IngestEventRequest(
            id: "2",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(twoDaysAgoString)],
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(condition, event: eventNoMatch),
                       "BEFORE should not match date that is not exactly N days ago")
    }

    /// PAST 테스트 (N일 이상 지난 날짜)
    func testPastOperator() {
        let dateSchema = PropertySchema(id: "1", name: "event_date", dataType: .date, path: .event)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // 5일 전 날짜 (3일 이상 지남 → true)
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let fiveDaysAgoString = formatter.string(from: fiveDaysAgo)

        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: dateSchema),
            operatorType: .past,
            targetValues: [AnyCodable(3)] // 3일 이상 지남
        )

        let eventMatch = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(fiveDaysAgoString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(condition, event: eventMatch),
                      "PAST should match date that is more than N days ago")

        // 1일 전 (3일 이상 안 지남 → false)
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oneDayAgoString = formatter.string(from: oneDayAgo)

        let eventNoMatch = IngestEventRequest(
            id: "2",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(oneDayAgoString)],
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(condition, event: eventNoMatch),
                       "PAST should not match date within N days")
    }

    /// WITHIN_PAST 테스트 (최근 N일 이내)
    func testWithinPastOperator() {
        let dateSchema = PropertySchema(id: "1", name: "event_date", dataType: .date, path: .event)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // 2일 전 (최근 5일 이내 → true)
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let twoDaysAgoString = formatter.string(from: twoDaysAgo)

        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: dateSchema),
            operatorType: .withinPast,
            targetValues: [AnyCodable(5)] // 최근 5일 이내
        )

        let eventMatch = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(twoDaysAgoString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(condition, event: eventMatch),
                      "WITHIN_PAST should match date within N days")

        // 10일 전 (최근 5일 이내 아님 → false)
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let tenDaysAgoString = formatter.string(from: tenDaysAgo)

        let eventNoMatch = IngestEventRequest(
            id: "2",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(tenDaysAgoString)],
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(condition, event: eventNoMatch),
                       "WITHIN_PAST should not match date older than N days")
    }

    /// AFTER 테스트 (N일 후인 날짜)
    func testAfterOperator() {
        let dateSchema = PropertySchema(id: "1", name: "event_date", dataType: .date, path: .event)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // 3일 후 날짜
        let threeDaysLater = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let threeDaysLaterString = formatter.string(from: threeDaysLater)

        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: dateSchema),
            operatorType: .after,
            targetValues: [AnyCodable(3)] // 3일 후
        )

        let eventMatch = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(threeDaysLaterString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(condition, event: eventMatch),
                      "AFTER should match date that is exactly N days later")

        // 5일 후 (정확히 3일 후 아님 → false)
        let fiveDaysLater = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let fiveDaysLaterString = formatter.string(from: fiveDaysLater)

        let eventNoMatch = IngestEventRequest(
            id: "2",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["event_date": AnyCodable(fiveDaysLaterString)],
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(condition, event: eventNoMatch),
                       "AFTER should not match date that is not exactly N days later")
    }

    /// REMAINING 테스트 (N일 이상 남은 날짜)
    func testRemainingOperator() {
        let dateSchema = PropertySchema(id: "1", name: "expiry_date", dataType: .date, path: .event)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // 10일 후 (5일 이상 남음 → true)
        let tenDaysLater = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let tenDaysLaterString = formatter.string(from: tenDaysLater)

        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: dateSchema),
            operatorType: .remaining,
            targetValues: [AnyCodable(5)] // 5일 이상 남음
        )

        let eventMatch = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["expiry_date": AnyCodable(tenDaysLaterString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(condition, event: eventMatch),
                      "REMAINING should match date more than N days in future")

        // 2일 후 (5일 이상 안 남음 → false)
        let twoDaysLater = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let twoDaysLaterString = formatter.string(from: twoDaysLater)

        let eventNoMatch = IngestEventRequest(
            id: "2",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["expiry_date": AnyCodable(twoDaysLaterString)],
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(condition, event: eventNoMatch),
                       "REMAINING should not match date less than N days in future")
    }

    /// WITHIN_REMAINING 테스트 (N일 이내 남은 날짜)
    func testWithinRemainingOperator() {
        let dateSchema = PropertySchema(id: "1", name: "expiry_date", dataType: .date, path: .event)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // 3일 후 (5일 이내 남음 → true)
        let threeDaysLater = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let threeDaysLaterString = formatter.string(from: threeDaysLater)

        let condition = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: dateSchema),
            operatorType: .withinRemaining,
            targetValues: [AnyCodable(5)] // 5일 이내 남음
        )

        let eventMatch = IngestEventRequest(
            id: "1",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["expiry_date": AnyCodable(threeDaysLaterString)],
            timestamp: Date()
        )

        XCTAssertTrue(inAppMessageService.isPropertyConditionMatched(condition, event: eventMatch),
                      "WITHIN_REMAINING should match date within N days in future")

        // 10일 후 (5일 이내 아님 → false)
        let tenDaysLater = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let tenDaysLaterString = formatter.string(from: tenDaysLater)

        let eventNoMatch = IngestEventRequest(
            id: "2",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["expiry_date": AnyCodable(tenDaysLaterString)],
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(condition, event: eventNoMatch),
                       "WITHIN_REMAINING should not match date more than N days in future")

        // 과거 날짜 (미래 아님 → false)
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let oneDayAgoString = formatter.string(from: oneDayAgo)

        let eventPast = IngestEventRequest(
            id: "3",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["expiry_date": AnyCodable(oneDayAgoString)],
            timestamp: Date()
        )

        XCTAssertFalse(inAppMessageService.isPropertyConditionMatched(condition, event: eventPast),
                       "WITHIN_REMAINING should not match past date")
    }

}
