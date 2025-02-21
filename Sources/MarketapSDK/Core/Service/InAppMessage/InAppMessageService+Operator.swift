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
        if propertyCondition.extractionStrategy.propertySchema.path == .item {
            guard let items = event.properties?["mkt_items"]?.value as? [[String: Any]] else {
                return false
            }
            return items.allSatisfy { item in
                guard let property = item[propertyCondition.extractionStrategy.propertySchema.name] else {
                    return false
                }
                return compare(
                    dataType: propertyCondition.extractionStrategy.propertySchema.dataType,
                    operator: propertyCondition.operatorType,
                    source: property,
                    targets: propertyCondition.targetValues.map(\.value)
                )
            }
        } else {
            guard let property = event.properties?[propertyCondition.extractionStrategy.propertySchema.name]?.value else {
                return false
            }

            return compare(
                dataType: propertyCondition.extractionStrategy.propertySchema.dataType,
                operator: propertyCondition.operatorType,
                source: property,
                targets: propertyCondition.targetValues.map(\.value)
            )
        }
    }

    func compare(dataType: DataType, operator: TaxonomyOperator, source: Any, targets: [Any]) -> Bool {
        switch `operator` {
        case .isNull:
            return source is NSNull
        case .isNotNull:
            return !(source is NSNull)
        default:
            guard !targets.isEmpty else { return false }
        }

        switch dataType {
        case .string:
            return compareString(operator: `operator`, source: source as? String ?? "", targets: targets as? [String] ?? [])
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

            let targetValues = targets.compactMap { target in
                if let intValue = target as? Int {
                    return Double(intValue)
                } else if let doubleValue = target as? Double {
                    return doubleValue
                } else {
                    return nil
                }
            }

            guard let sourceValue = sourceValue else { return false }

            return compareNumber(operator: `operator`, source: sourceValue, targets: targetValues)
        case .boolean:
            return compareBoolean(operator: `operator`, source: source as? Bool ?? false, targets: targets as? [Bool] ?? [])
        case .datetime:
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let parsedSource: Date = {
                if let date = source as? Date {
                    return date
                } else if let dateString = source as? String, let date = isoFormatter.date(from: dateString) {
                    return date
                }
                return Date()
            }()

            let parsedTargets: [Date] = targets.compactMap {
                if let date = $0 as? Date {
                    return date
                } else if let dateString = $0 as? String {
                    return isoFormatter.date(from: dateString)
                }
                return nil
            }

            return compareDateTime(operator: `operator`, source: parsedSource, targets: parsedTargets)

        case .date:
            return compareDate(operator: `operator`, source: source, targets: targets)
        case .object:
            return false
        case .arrayString:
            if let sourceArray = source as? [String], let targetArrays = targets as? [[String]] {
                return compareArray(operator: `operator`, source: sourceArray, targets: targetArrays)
            }
            return false
        }
    }

    func compareString(operator: TaxonomyOperator, source: String, targets: [String]) -> Bool {
        switch `operator` {
        case .equal:
            return targets.contains(source)
        case .notEqual:
            return !targets.contains(source)
        case .like:
            return targets.contains { source.contains($0) }
        case .notLike:
            return !targets.contains { source.contains($0) }
        default:
            return false
        }
    }

    func compareNumber(operator: TaxonomyOperator, source: Double, targets: [Double]) -> Bool {
        switch `operator` {
        case .equal:
            return targets.contains(source)
        case .notEqual:
            return !targets.contains(source)
        case .greaterThan:
            return targets.contains { source > $0 }
        case .greaterThanOrEqual:
            return targets.contains { source >= $0 }
        case .lessThan:
            return targets.contains { source < $0 }
        case .lessThanOrEqual:
            return targets.contains { source <= $0 }
        case .between:
            return targets.count == 2 && source >= targets[0] && source <= targets[1]
        case .notBetween:
            return targets.count == 2 && (source < targets[0] || source > targets[1])
        default:
            return false
        }
    }

    func compareBoolean(operator: TaxonomyOperator, source: Bool, targets: [Bool]) -> Bool {
        switch `operator` {
        case .equal:
            return targets.contains(source)
        case .notEqual:
            return !targets.contains(source)
        default:
            return false
        }
    }

    func compareDateTime(operator: TaxonomyOperator, source: Date, targets: [Date]) -> Bool {
        switch `operator` {
        case .equal:
            return targets.contains { source == $0 }
        case .notEqual:
            return targets.allSatisfy { source != $0 }
        case .greaterThan:
            return targets.contains { source > $0 }
        case .greaterThanOrEqual:
            return targets.contains { source >= $0 }
        case .lessThan:
            return targets.contains { source < $0 }
        case .lessThanOrEqual:
            return targets.contains { source <= $0 }
        case .between:
            return targets.count == 2 && source >= targets[0] && source <= targets[1]
        case .notBetween:
            return targets.count == 2 && (source < targets[0] || source > targets[1])
        default:
            return false
        }
    }

    func compareDate(operator: TaxonomyOperator, source: Any, targets: [Any]) -> Bool {
        func toDateString(_ value: Any) -> String? {
            if let date = value as? Date {
                return ISO8601DateFormatter().string(from: date).prefix(10).description
            }
            if let str = value as? String, str.count == 10 || str.count == 8 {
                return str.replacingOccurrences(of: ".", with: "-")
                          .replacingOccurrences(of: "/", with: "-")
            }
            return nil
        }

        guard let sourceDate = toDateString(source) else { return false }
        let targetDates = targets.compactMap(toDateString)

        switch `operator` {
        case .equal:
            return targetDates.contains(sourceDate)
        case .notEqual:
            return !targetDates.contains(sourceDate)
        case .greaterThan:
            return targetDates.contains { sourceDate > $0 }
        case .greaterThanOrEqual:
            return targetDates.contains { sourceDate >= $0 }
        case .lessThan:
            return targetDates.contains { sourceDate < $0 }
        case .lessThanOrEqual:
            return targetDates.contains { sourceDate <= $0 }
        case .between:
            return targetDates.count == 2 && sourceDate >= targetDates[0] && sourceDate <= targetDates[1]
        case .notBetween:
            return targetDates.count == 2 && (sourceDate < targetDates[0] || sourceDate > targetDates[1])
        default:
            return false
        }
    }

    func compareArray<T: Equatable>(operator: TaxonomyOperator, source: [T], targets: [[T]]) -> Bool {
        switch `operator` {
        case .in:
            return targets.contains { target in target.allSatisfy { source.contains($0) } }
        case .notIn:
            return targets.allSatisfy { target in target.allSatisfy { !source.contains($0) } }
        default:
            return false
        }
    }

}
