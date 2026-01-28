//
//  InAppMessageService+Operator.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

extension InAppMessageService {
    func isEventTriggered(condition: EventTriggerCondition, event: IngestEventRequest) -> Bool {
        guard condition.condition.eventFilter.eventName == event.name else {
            return false
        }

        guard let propertyConditions = condition.condition.propertyConditions, !propertyConditions.isEmpty else {
            return true
        }

        return propertyConditions.contains { propertySet in
            propertySet.allSatisfy { isPropertyConditionMatched($0, event: event) }
        }
    }

    func isPropertyConditionMatched(_ propertyCondition: EventPropertyCondition, event: IngestEventRequest) -> Bool {
        let operatorType = propertyCondition.operatorType

        if propertyCondition.extractionStrategy.propertySchema.path == .item {
            guard let items = event.properties?["mkt_items"]?.value as? [[String: Any]] else {
                return false
            }

            let results = items.map { item -> Bool in
                guard let property = item[propertyCondition.extractionStrategy.propertySchema.name] else {
                    return operatorType == .isNull
                }
                return compare(
                    dataType: propertyCondition.extractionStrategy.propertySchema.dataType,
                    operator: operatorType,
                    source: property,
                    targets: propertyCondition.targetValues.map(\.value)
                )
            }

            return aggregate(results: results, operator: operatorType)
        } else {
            let property = event.properties?[propertyCondition.extractionStrategy.propertySchema.name]?.value

            if property == nil {
                return operatorType == .isNull
            }

            return compare(
                dataType: propertyCondition.extractionStrategy.propertySchema.dataType,
                operator: operatorType,
                source: property!,
                targets: propertyCondition.targetValues.map(\.value)
            )
        }
    }

    private func aggregate(results: [Bool], operator: TaxonomyOperator) -> Bool {
        if results.isEmpty {
            return false
        }

        if `operator`.isNegativeOperator {
            return results.allSatisfy { $0 }
        } else {
            return results.contains { $0 }
        }
    }

    func compare(dataType: DataType, operator: TaxonomyOperator, source: Any, targets: [Any]) -> Bool {
        switch `operator` {
        case .isNull:
            return source is NSNull
        case .isNotNull:
            return !(source is NSNull)
        default:
            break
        }

        switch dataType {
        case .string:
            guard let sourceString = source as? String else { return false }
            return compareString(operator: `operator`, source: sourceString, targets: targets)
        case .int, .bigint, .double:
            let sourceValue: Double? = {
                if let intValue = source as? Int {
                    return Double(intValue)
                } else if let doubleValue = source as? Double {
                    return doubleValue
                } else {
                    return nil
                }
            }()

            guard let sourceValue = sourceValue else { return false }
            return compareNumber(operator: `operator`, source: sourceValue, targets: targets)
        case .boolean:
            guard let sourceBool = source as? Bool else { return false }
            return compareBoolean(operator: `operator`, source: sourceBool, targets: targets)
        case .datetime:
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let parsedSource: Date? = {
                if let date = source as? Date {
                    return date
                } else if let dateString = source as? String, let date = isoFormatter.date(from: dateString) {
                    return date
                }
                return nil
            }()

            guard let parsedSource = parsedSource else { return false }
            return compareDateTime(operator: `operator`, source: parsedSource, targets: targets)

        case .date:
            return compareDate(operator: `operator`, source: source, targets: targets)
        case .object:
            return false
        case .arrayString:
            guard let sourceArray = source as? [String] else { return false }
            return compareStringArray(operator: `operator`, source: sourceArray, targets: targets)
        }
    }

    func compareString(operator: TaxonomyOperator, source: String, targets: [Any]) -> Bool {
        switch `operator` {
        case .equal:
            guard let target = targets.first as? String else { return false }
            return source == target
        case .notEqual:
            guard let target = targets.first as? String else { return false }
            return source != target
        case .like:
            guard let target = targets.first as? String else { return false }
            return source.lowercased().contains(target.lowercased())
        case .notLike:
            guard let target = targets.first as? String else { return false }
            return !source.lowercased().contains(target.lowercased())
        case .in:
            let targetStrings = targets.compactMap { $0 as? String }
            return targetStrings.contains(source)
        case .notIn:
            let targetStrings = targets.compactMap { $0 as? String }
            return !targetStrings.contains(source)
        default:
            return false
        }
    }

    func compareNumber(operator: TaxonomyOperator, source: Double, targets: [Any]) -> Bool {
        let targetValues = targets.compactMap { target -> Double? in
            if let intValue = target as? Int {
                return Double(intValue)
            } else if let doubleValue = target as? Double {
                return doubleValue
            }
            return nil
        }

        switch `operator` {
        case .equal:
            guard let target = targetValues.first else { return false }
            return source == target
        case .notEqual:
            guard let target = targetValues.first else { return false }
            return source != target
        case .greaterThan:
            guard let target = targetValues.first else { return false }
            return source > target
        case .greaterThanOrEqual:
            guard let target = targetValues.first else { return false }
            return source >= target
        case .lessThan:
            guard let target = targetValues.first else { return false }
            return source < target
        case .lessThanOrEqual:
            guard let target = targetValues.first else { return false }
            return source <= target
        case .between:
            guard targetValues.count == 2 else { return false }
            return source > targetValues[0] && source < targetValues[1]
        case .notBetween:
            guard targetValues.count == 2 else { return false }
            return source <= targetValues[0] || source >= targetValues[1]
        case .in:
            return targetValues.contains(source)
        case .notIn:
            return !targetValues.contains(source)
        default:
            return false
        }
    }

    func compareBoolean(operator: TaxonomyOperator, source: Bool, targets: [Any]) -> Bool {
        let targetBools = targets.compactMap { $0 as? Bool }

        switch `operator` {
        case .equal:
            guard let target = targetBools.first else { return false }
            return source == target
        case .notEqual:
            guard let target = targetBools.first else { return false }
            return source != target
        case .in:
            return targetBools.contains(source)
        case .notIn:
            return !targetBools.contains(source)
        default:
            return false
        }
    }

    func compareDateTime(operator: TaxonomyOperator, source: Date, targets: [Any]) -> Bool {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let parsedTargets: [Date] = targets.compactMap {
            if let date = $0 as? Date {
                return date
            } else if let dateString = $0 as? String {
                return isoFormatter.date(from: dateString)
            }
            return nil
        }

        switch `operator` {
        case .equal:
            guard let target = parsedTargets.first else { return false }
            return source == target
        case .notEqual:
            guard let target = parsedTargets.first else { return false }
            return source != target
        case .greaterThan:
            guard let target = parsedTargets.first else { return false }
            return source > target
        case .greaterThanOrEqual:
            guard let target = parsedTargets.first else { return false }
            return source >= target
        case .lessThan:
            guard let target = parsedTargets.first else { return false }
            return source < target
        case .lessThanOrEqual:
            guard let target = parsedTargets.first else { return false }
            return source <= target
        case .between:
            guard parsedTargets.count == 2 else { return false }
            return source > parsedTargets[0] && source < parsedTargets[1]
        case .notBetween:
            guard parsedTargets.count == 2 else { return false }
            return source <= parsedTargets[0] || source >= parsedTargets[1]
        case .in:
            return parsedTargets.contains(source)
        case .notIn:
            return !parsedTargets.contains(source)
        case .yearEqual:
            guard let targetYear = targets.first as? Int else { return false }
            return Calendar.current.component(.year, from: source) == targetYear
        case .monthEqual:
            guard let targetMonth = targets.first as? Int else { return false }
            return Calendar.current.component(.month, from: source) == targetMonth
        case .yearMonthEqual:
            guard let targetString = targets.first as? String else { return false }
            let components = targetString.split(separator: "-").compactMap { Int($0) }
            guard components.count == 2 else { return false }
            let year = Calendar.current.component(.year, from: source)
            let month = Calendar.current.component(.month, from: source)
            return year == components[0] && month == components[1]
        case .before:
            guard let days = targets.first as? Int else { return false }
            let targetDate = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -days, to: Date())!)
            let sourceDay = Calendar.current.startOfDay(for: source)
            return sourceDay == targetDate
        case .past:
            guard let days = targets.first as? Int else { return false }
            let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            return source < targetDate
        case .withinPast:
            guard let days = targets.first as? Int else { return false }
            let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            return source > targetDate && source < Date()
        case .after:
            guard let days = targets.first as? Int else { return false }
            let targetDate = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: days, to: Date())!)
            let sourceDay = Calendar.current.startOfDay(for: source)
            return sourceDay == targetDate
        case .remaining:
            guard let days = targets.first as? Int else { return false }
            let targetDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
            return source > targetDate
        case .withinRemaining:
            guard let days = targets.first as? Int else { return false }
            let targetDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
            return source > Date() && source < targetDate
        default:
            return false
        }
    }

    func compareDate(operator: TaxonomyOperator, source: Any, targets: [Any]) -> Bool {
        func toDateString(_ value: Any) -> String? {
            if let date = value as? Date {
                return ISO8601DateFormatter().string(from: date).prefix(10).description
            }
            if let str = value as? String {
                let normalized = str.replacingOccurrences(of: ".", with: "-")
                                    .replacingOccurrences(of: "/", with: "-")
                if normalized.count == 10 {
                    return normalized
                } else if normalized.count == 8 {
                    return "\(normalized.prefix(4))-\(normalized.dropFirst(4).prefix(2))-\(normalized.suffix(2))"
                }
            }
            return nil
        }

        func toDate(_ dateString: String) -> Date? {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.date(from: dateString)
        }

        guard let sourceDate = toDateString(source) else { return false }
        let targetDates = targets.compactMap(toDateString)

        switch `operator` {
        case .equal:
            guard let target = targetDates.first else { return false }
            return sourceDate == target
        case .notEqual:
            guard let target = targetDates.first else { return false }
            return sourceDate != target
        case .greaterThan:
            guard let target = targetDates.first else { return false }
            return sourceDate > target
        case .greaterThanOrEqual:
            guard let target = targetDates.first else { return false }
            return sourceDate >= target
        case .lessThan:
            guard let target = targetDates.first else { return false }
            return sourceDate < target
        case .lessThanOrEqual:
            guard let target = targetDates.first else { return false }
            return sourceDate <= target
        case .between:
            guard targetDates.count == 2 else { return false }
            return sourceDate > targetDates[0] && sourceDate < targetDates[1]
        case .notBetween:
            guard targetDates.count == 2 else { return false }
            return sourceDate <= targetDates[0] || sourceDate >= targetDates[1]
        case .in:
            return targetDates.contains(sourceDate)
        case .notIn:
            return !targetDates.contains(sourceDate)
        case .yearEqual:
            guard let targetYear = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            return Calendar.current.component(.year, from: date) == targetYear
        case .monthEqual:
            guard let targetMonth = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            return Calendar.current.component(.month, from: date) == targetMonth
        case .yearMonthEqual:
            guard let targetString = targets.first as? String else { return false }
            let components = targetString.split(separator: "-").compactMap { Int($0) }
            guard components.count == 2,
                  let date = toDate(sourceDate) else { return false }
            let year = Calendar.current.component(.year, from: date)
            let month = Calendar.current.component(.month, from: date)
            return year == components[0] && month == components[1]
        case .before:
            guard let days = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            let today = Calendar.current.startOfDay(for: Date())
            let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: today)!
            return Calendar.current.startOfDay(for: date) == targetDate
        case .past:
            guard let days = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            let today = Calendar.current.startOfDay(for: Date())
            let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: today)!
            return date < targetDate
        case .withinPast:
            guard let days = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            let today = Calendar.current.startOfDay(for: Date())
            let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: today)!
            return date > targetDate && date < today
        case .after:
            guard let days = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            let today = Calendar.current.startOfDay(for: Date())
            let targetDate = Calendar.current.date(byAdding: .day, value: days, to: today)!
            return Calendar.current.startOfDay(for: date) == targetDate
        case .remaining:
            guard let days = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            let today = Calendar.current.startOfDay(for: Date())
            let targetDate = Calendar.current.date(byAdding: .day, value: days, to: today)!
            return date > targetDate
        case .withinRemaining:
            guard let days = targets.first as? Int,
                  let date = toDate(sourceDate) else { return false }
            let today = Calendar.current.startOfDay(for: Date())
            let targetDate = Calendar.current.date(byAdding: .day, value: days, to: today)!
            return date > today && date < targetDate
        default:
            return false
        }
    }

    func compareStringArray(operator: TaxonomyOperator, source: [String], targets: [Any]) -> Bool {
        let targetStrings = targets.compactMap { $0 as? String }

        switch `operator` {
        case .contains:
            guard let target = targetStrings.first else { return false }
            return source.contains(target)
        case .notContains:
            guard let target = targetStrings.first else { return false }
            return !source.contains(target)
        case .any:
            return targetStrings.contains { source.contains($0) }
        case .none:
            return targetStrings.allSatisfy { !source.contains($0) }
        case .arrayLike:
            return targetStrings.contains { target in
                source.contains { $0.lowercased().contains(target.lowercased()) }
            }
        case .arrayNotLike:
            return targetStrings.allSatisfy { target in
                source.allSatisfy { !$0.lowercased().contains(target.lowercased()) }
            }
        default:
            return false
        }
    }
}
