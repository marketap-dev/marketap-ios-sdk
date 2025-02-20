//
//  BulkProfileRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/20/25.
//

import Foundation

struct BulkProfile: Codable {
    let userId: String
    var properties: [String: AnyCodable]?
    let timestamp: Date?

    init(userId: String, properties: [String: AnyCodable]?, device: UpdateDeviceRequest?, timestamp: Date?) {
        self.userId = userId
        self.properties = properties
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case properties
        case device
        case timestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(properties, forKey: .properties)

        if let timestamp = timestamp {
            let dateFormatter = ISO8601DateFormatter()
            let timestampString = dateFormatter.string(from: timestamp)
            try container.encode(timestampString, forKey: .timestamp)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        userId = try container.decode(String.self, forKey: .userId)
        properties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties)

        if let timestampString = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            let dateFormatter = ISO8601DateFormatter()
            timestamp = dateFormatter.date(from: timestampString)
        } else {
            timestamp = nil
        }
    }
}

struct BulkProfileRequest: Codable {
    let device: UpdateDeviceRequest
    let profiles: [BulkProfile]

    enum CodingKeys: String, CodingKey {
        case device
        case profiles
    }
}
