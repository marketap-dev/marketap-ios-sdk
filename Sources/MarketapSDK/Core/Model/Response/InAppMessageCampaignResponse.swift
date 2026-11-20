//
//  InAppMessageCampaignResponse.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/16/25.
//

import Foundation

/// 해석할 수 없는 캠페인(이 버전이 모르는 조건 값 등)은 그 캠페인만 제외한다.
/// 전체 빈도 규칙은 하나라도 해석할 수 없으면 nil 로 읽어 저장된 규칙을 유지한다.
struct InAppCampaignFetchResponse: Decodable, Equatable {
    let checksum: String
    let campaigns: [InAppCampaign]?
    var globalFrequencyCaps: [GlobalFrequencyCapRule]? = nil

    private enum CodingKeys: String, CodingKey {
        case checksum
        case campaigns
        case globalFrequencyCaps
    }

    init(checksum: String, campaigns: [InAppCampaign]?, globalFrequencyCaps: [GlobalFrequencyCapRule]? = nil) {
        self.checksum = checksum
        self.campaigns = campaigns
        self.globalFrequencyCaps = globalFrequencyCaps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checksum = try container.decode(String.self, forKey: .checksum)
        campaigns = try container
            .decodeIfPresent([DecodableOrSkipped<InAppCampaign>].self, forKey: .campaigns)?
            .compactMap { $0.value }
        do {
            globalFrequencyCaps = try container
                .decodeIfPresent([GlobalFrequencyCapRule].self, forKey: .globalFrequencyCaps)
        } catch {
            MarketapLogger.warn("ignored global frequency caps that cannot be decoded: \(error)")
            globalFrequencyCaps = nil
        }
    }
}

struct InAppCampaignSingleFetchResponse: Decodable, Equatable {
    let campaign: InAppCampaign?

    private enum CodingKeys: String, CodingKey {
        case campaign
    }

    init(campaign: InAppCampaign?) {
        self.campaign = campaign
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        campaign = try container
            .decodeIfPresent(DecodableOrSkipped<InAppCampaign>.self, forKey: .campaign)?
            .value
    }
}

private struct DecodableOrSkipped<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
        } catch {
            MarketapLogger.warn("skipped an in-app \(T.self) that cannot be decoded: \(error)")
            value = nil
        }
    }
}
