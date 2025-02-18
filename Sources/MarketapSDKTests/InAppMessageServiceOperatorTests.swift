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
            api: api,
            cache: cache,
            eventService: EventService(api: api, cache: cache)
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

    func testCompareArray() {
        XCTAssertTrue(inAppMessageService.compareArray(operator: .in, source: ["apple", "banana"], targets: [["apple"]]))
        XCTAssertFalse(inAppMessageService.compareArray(operator: .notIn, source: ["apple", "banana"], targets: [["apple"]]))
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
            case .lessThan: expectedResult = testValue < 60
            case .lessThanOrEqual: expectedResult = testValue <= 60
            case .between: expectedResult = (testValue >= 30 && testValue <= 60)
            case .notBetween: expectedResult = !(testValue >= 30 && testValue <= 60)
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
            case .lessThan: expectedResult = testValue < 5.0
            case .lessThanOrEqual: expectedResult = testValue <= 5.0
            case .between: expectedResult = (testValue >= 4.0 && testValue <= 5.0)
            case .notBetween: expectedResult = !(testValue >= 4.0 && testValue <= 5.0)
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
            case .lessThan: expectedResult = testDate < futureDate
            case .lessThanOrEqual: expectedResult = testDate <= futureDate
            case .between: expectedResult = (testDate >= pastDate && testDate <= futureDate)
            case .notBetween: expectedResult = !(testDate >= pastDate && testDate <= futureDate)
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
            case .lessThan: expectedResult = testValue < "2024-02-25"
            case .lessThanOrEqual: expectedResult = testValue <= "2024-02-25"
            case .between: expectedResult = (testValue >= "2024-02-10" && testValue <= "2024-02-25")
            case .notBetween: expectedResult = !(testValue >= "2024-02-10" && testValue <= "2024-02-25")
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

        let conditionIn = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .in,
            targetValues: [AnyCodable(["sports", "tech"])]
        )

        let conditionNotIn = EventPropertyCondition(
            extractionStrategy: ExtractionStrategy(propertySchema: schema),
            operatorType: .notIn,
            targetValues: [AnyCodable(["finance", "health"])]
        )

        let event = IngestEventRequest(
            id: "7",
            name: "test_event",
            userId: "user_123",
            device: MockDevice().toDevice().makeRequest(),
            properties: ["tags": AnyCodable(eventTags)],
            timestamp: Date()
        )

        let inExpected = ["sports", "tech"].allSatisfy { eventTags.contains($0) }
        XCTAssertEqual(
            inAppMessageService.isPropertyConditionMatched(conditionIn, event: event),
            inExpected,
            "Operator IN failed for ARRAY_STRING"
        )

        let notInExpected = ["finance", "health"].allSatisfy { !eventTags.contains($0) }
        XCTAssertEqual(
            inAppMessageService.isPropertyConditionMatched(conditionNotIn, event: event),
            notInExpected,
            "Operator NOT_IN failed for ARRAY_STRING"
        )
    }


    func testCompareNullValues() {
        XCTAssertTrue(inAppMessageService.compare(dataType: .string, operator: .isNull, source: NSNull(), targets: []))
        XCTAssertFalse(inAppMessageService.compare(dataType: .string, operator: .isNotNull, source: NSNull(), targets: []))
    }

}
