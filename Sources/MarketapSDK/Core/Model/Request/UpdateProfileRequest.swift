//
//  UpdateProfileRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct UpdateProfileRequest: Codable {
    let userId: String
    var properties: [String: AnyCodable]?
    let device: UpdateDeviceRequest?
    var timestamp: Date?

    init(userId: String, properties: [String: AnyCodable]?, device: UpdateDeviceRequest?) {
        self.userId = userId
        self.properties = properties
        self.device = device
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
        try container.encodeIfPresent(device, forKey: .device)

        if let timestamp = timestamp {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestampString = dateFormatter.string(from: timestamp)
            try container.encode(timestampString, forKey: .timestamp)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        userId = try container.decode(String.self, forKey: .userId)
        properties = try container.decodeIfPresent([String: AnyCodable].self, forKey: .properties)
        device = try container.decodeIfPresent(UpdateDeviceRequest.self, forKey: .device)

        if let timestampString = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = dateFormatter.date(from: timestampString) {
                timestamp = date
            } else {
                dateFormatter.formatOptions = [.withInternetDateTime]
                timestamp = dateFormatter.date(from: timestampString)
            }
        } else {
            timestamp = nil
        }
    }
}
