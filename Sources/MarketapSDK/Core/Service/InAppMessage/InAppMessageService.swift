//
//  InAppMessageService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import WebKit

protocol InAppMessageServiceDelegate: AnyObject {
    func trackEvent(eventName: String, eventProperties: [String: Any]?)
}

final class InAppMessageService: NSObject, InAppMessageServiceProtocol {
    static let cacheExpiration = Double(60 * 5)
    static let campaignCacheKey = "InAppMessageService_campaigns"
    static let lastFetchKey = "InAppMessageService_lastFetch"

    let customHandlerStore: MarketapCustomHandlerStoreProtocol
    private let api: MarketapAPIProtocol
    private let cache: MarketapCacheProtocol
    weak var delegate: InAppMessageServiceDelegate?

    var isModalShown: Bool = false
    var didFinishLoad = false
    var pendingCampaign: InAppCampaign?

    private var projectId: String {
        cache.projectId
    }

    var campaigns: [InAppCampaign]?
    var lastFetch: Date?
    let campaignViewController = InAppMessageWebViewController()

    init(
        customHandlerStore: MarketapCustomHandlerStoreProtocol,
        api: MarketapAPIProtocol,
        cache: MarketapCacheProtocol
    ) {
        self.customHandlerStore = customHandlerStore
        self.cache = cache
        self.api = api

        super.init()

        campaignViewController.delegate = self
        self.lastFetch = cache.loadCodableObject(forKey: Self.lastFetchKey)
        fetchCampaigns()

        DispatchQueue.main.async {
            self.campaignViewController.loadViewIfNeeded()
        }
    }

    func fetchCampaigns(force: Bool = false, completion: (([InAppCampaign]) -> Void)? = nil) {
        if let lastFetch = lastFetch, !force, Date().timeIntervalSince(lastFetch) < Self.cacheExpiration {
            if self.campaigns == nil {
                self.campaigns = cache.loadCodableObject(forKey: Self.campaignCacheKey)
            }
            completion?(campaigns ?? [])
            return
        }

        let userId = cache.userId
        let device = cache.device

        api.request(
            baseURL: .crm,
            path: "/api/v1/campaigns",
            body: FetchCampaignRequest(projectId: projectId, userId: userId, device: device.makeRequest()),
            responseType: InAppCampaignFetchResponse.self
        ) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                let campaigns = response.campaigns
                self.campaigns = campaigns
                self.cache.saveCodableObject(campaigns, key: Self.campaignCacheKey)
                self.cache.saveCodableObject(Date(), key: Self.lastFetchKey)
                self.lastFetch = Date()
                completion?(campaigns)
            case .failure(_):
                completion?(self.campaigns ?? [])
            }
        }
    }

}
