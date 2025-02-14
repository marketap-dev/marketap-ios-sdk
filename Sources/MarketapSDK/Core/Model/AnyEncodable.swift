//
//  AnyEncodable.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct AnyEncodable: Encodable {
    private let value: Any?

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
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}


extension Dictionary where Key == String, Value == Any {
    /// ✅ `[String: Any]`을 `[String: AnyEncodable]`로 변환하는 확장 메서드
    func toAnyEncodable() -> [String: AnyEncodable] {
        return self.mapValues { AnyEncodable($0) }
    }
}
