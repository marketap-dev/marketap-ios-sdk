//
//  CreateBulkClientEventRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

struct BulkEvent: Codable, Equatable {
    let id: String?
    let userId: String?
    let name: String
    let timestamp: Date?
    let properties: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case timestamp
        case properties
    }

    init(id: String? = nil, userId: String? = nil, name: String, timestamp: Date? = nil, properties: [String: AnyCodable]? = nil) {
        self.id = id
        self.userId = userId
        self.name = name
        self.timestamp = timestamp ?? Date()
        self.properties = properties
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
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

        id = try container.decodeIfPresent(String.self, forKey: .id)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        properties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties)

        if let timestampString = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            let dateFormatter = ISO8601DateFormatter()
            timestamp = dateFormatter.date(from: timestampString)
        } else {
            timestamp = nil
        }
    }
}


struct CreateBulkClientEventRequest: Codable {
    let device: UpdateDeviceRequest
    let events: [BulkEvent]

    enum CodingKeys: String, CodingKey {
        case device
        case events
    }
}
