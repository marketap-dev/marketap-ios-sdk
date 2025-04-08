//
//  ImpressionRequest.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/19/25.
//

import Foundation

struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }

    var intValue: Int? { return nil }
    init?(intValue: Int) { return nil }
}

struct Device: Encodable {
    let deviceId: String
    let platform: String = "ios"

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case platform
    }

    init(deviceId: String) {
        self.deviceId = deviceId
    }
}

struct ImpressionRequestProperties: Encodable {
    let campaignId: String
    let messageId: String
    let campaignCategory: String = "ON_SITE"
    let channelType: String = "PUSH"
    let subChannelType: String = "IOS"
    let resultStatus: Int = 200
    let resultMessage: String = "SUCCESS"
    let isSuccess: Bool = true
    let serverProperties: [String: String]?

    enum CodingKeys: String, CodingKey {
        case campaignId = "mkt_campaign_id"
        case campaignCategory = "mkt_campaign_category"
        case channelType = "mkt_channel_type"
        case subChannelType = "mkt_sub_channel_type"
        case resultStatus = "mkt_result_status"
        case resultMessage = "mkt_result_message"
        case isSuccess = "mkt_is_success"
        case messageId = "mkt_message_id"
    }

    init(campaignId: String, messageId: String, serverProperties: [String: String]?) {
        self.campaignId = campaignId
        self.messageId = messageId
        self.serverProperties = serverProperties
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(campaignId, forKey: .campaignId)
        try container.encode(messageId, forKey: .messageId)
        try container.encode(campaignCategory, forKey: .campaignCategory)
        try container.encode(channelType, forKey: .channelType)
        try container.encode(subChannelType, forKey: .subChannelType)
        try container.encode(resultStatus, forKey: .resultStatus)
        try container.encode(resultMessage, forKey: .resultMessage)
        try container.encode(isSuccess, forKey: .isSuccess)

        if let serverProperties = serverProperties {
            var dynamicContainer = encoder.container(keyedBy: DynamicCodingKeys.self)
            for (key, value) in serverProperties {
                let dynamicKey = DynamicCodingKeys(stringValue: key)
                try dynamicContainer.encode(value, forKey: dynamicKey)
            }
        }
    }
}


struct ImpressionRequest: Encodable {
    let name: String
    let userId: String
    let device: Device
    let properties: ImpressionRequestProperties
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case name
        case userId = "user_id"
        case device
        case properties
        case timestamp
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(userId, forKey: .userId)
        try container.encode(device, forKey: .device)
        try container.encode(properties, forKey: .properties)

        let dateFormatter = ISO8601DateFormatter()
        let timestampString = dateFormatter.string(from: timestamp)
        try container.encode(timestampString, forKey: .timestamp)
    }
}
