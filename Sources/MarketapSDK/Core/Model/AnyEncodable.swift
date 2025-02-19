//
//  AnyEncodable.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct AnyEncodable: Encodable, Equatable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        guard let value else {
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
            let encodedArray = v.map { AnyEncodable($0) }
            try container.encode(encodedArray)
        case let v as [String: Any]:
            let encodedDict = v.mapValues { AnyEncodable($0) }
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

    static func == (lhs: AnyEncodable, rhs: AnyEncodable) -> Bool {
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
    func toAnyEncodable() -> [String: AnyEncodable] {
        return self.mapValues { AnyEncodable($0) }
    }
}
