//
//  AnyCodable.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct AnyCodable: Codable, Equatable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        guard let value = value else {
            try container.encodeNil()
            return
        }

        switch value {
        case let v as String:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as Bool:
            try container.encode(v)
        case let v as [Any]:
            let encodedArray = v.map { AnyCodable($0) }
            try container.encode(encodedArray)
        case let v as [String: Any]:
            let encodedDict = v.mapValues { AnyCodable($0) }
            try container.encode(encodedDict)
        default:
            throw MarketapError.encodingError(
                EncodingError.invalidValue(
                    value,
                    EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type")
                )
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(Bool.self) {
            self.value = value
        } else if let value = try? container.decode([AnyCodable].self) {
            self.value = value.map { $0.value }
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self.value = value.mapValues { $0.value }
        } else if container.decodeNil() {
            self.value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        let lhsValue = lhs.value as? NSNull == nil ? lhs.value : nil
        let rhsValue = rhs.value as? NSNull == nil ? rhs.value : nil

        switch (lhsValue, rhsValue) {
        case (nil, nil):
            return true
        case let (lhs as String, rhs as String):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as [Any], rhs as [Any]):
            return NSArray(array: lhs).isEqual(to: rhs)
        case let (lhs as [String: Any], rhs as [String: Any]):
            return NSDictionary(dictionary: lhs).isEqual(to: rhs)
        default:
            return false
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func toAnyCodable() -> [String: AnyCodable] {
        return self.mapValues { AnyCodable($0) }
    }
}

