//
//  IngestEventRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct IngestEventRequest: Encodable {
    let id: String?
    let name: String
    let userId: String?
    let device: UpdateDeviceRequest
    let properties: [String: AnyCodable]?
    var timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case userId = "user_id"
        case device
        case properties
        case timestamp
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encode(device, forKey: .device)
        try container.encodeIfPresent(properties, forKey: .properties)
        
        if let timestamp = timestamp {
            let dateFormatter = ISO8601DateFormatter()
            let timestampString = dateFormatter.string(from: timestamp)
            try container.encode(timestampString, forKey: .timestamp)
        }
    }
}
