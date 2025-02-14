//
//  InAppMessageService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

class InAppMessageService {
    static let cacheExpiration = Double(60 * 5)
    static let campaignCacheKey = "InAppMessageService_campaigns"
    static let lastFetchKey = "InAppMessageService_lastFetch"

    private let api: MarketapAPI
    private let cache: MarketapCache

    private var projectId: String {
        cache.config.projectId
    }

    private var campaigns: [InAppCampaign]?
    private var lastFetch: Date?

    init(api: MarketapAPI, cache: MarketapCache) {
        self.cache = cache
        self.api = api
    }

    func fetchCampaigns(force: Bool) {
        if let lastFetch, !force, Date().timeIntervalSince(lastFetch) < Self.cacheExpiration { return }

        let userId = cache.loadUserId()
        let device = cache.loadDevice()

        api.request(
            path: "/api/v1/campaigns",
            body: FetchCampaignRequest(projectId: projectId, userId: userId, device: device.makeRequest()),
            responseType: [InAppCampaign].self
        ) { [weak self] result in
            switch result {
            case .success(let campaigns):
                self?.campaigns = campaigns
                self?.cache.saveCodableObject(campaigns, key: Self.campaignCacheKey)
                self?.cache.saveCodableObject(Date(), key: Self.lastFetchKey)
            case .failure(_):
                // TODO: retry
                return
            }
        }
    }
}
