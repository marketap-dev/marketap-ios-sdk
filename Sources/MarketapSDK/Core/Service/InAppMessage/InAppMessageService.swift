//
//  InAppMessageService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import WebKit

protocol InAppMessageServiceDelegate: AnyObject {
    func trackEvent(eventName: String, eventProperties: [String: Any]?)
    func setUserProperties(userProperties: [String: Any])
}

private final class InAppMessageTimeoutController {
    private let timeoutSeconds: TimeInterval
    private let stateQueue: DispatchQueue
    private let logMessage: String
    private var didComplete = false
    private let startTime = Date()
    private lazy var workItem: DispatchWorkItem = {
        DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            var shouldLog = false
            self.stateQueue.sync {
                if self.didComplete { return }
                self.didComplete = true
                shouldLog = true
            }
            guard shouldLog else { return }
            MarketapLogger.warn(self.logMessage)
        }
    }()

    init(timeoutSeconds: TimeInterval, queueLabel: String, logMessage: String) {
        self.timeoutSeconds = timeoutSeconds
        self.stateQueue = DispatchQueue(label: queueLabel)
        self.logMessage = logMessage
    }

    func start() {
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeoutSeconds,
            execute: workItem
        )
    }

    func markCompleted() -> Bool {
        var isFirst = false
        stateQueue.sync {
            if didComplete { return }
            didComplete = true
            isFirst = true
        }
        workItem.cancel()
        return isFirst
    }

    func isWithinTimeout() -> Bool {
        return Date().timeIntervalSince(startTime) <= timeoutSeconds
    }
}

final class InAppMessageService: NSObject, InAppMessageServiceProtocol {
    static let cacheExpiration = Double(30)
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

    func fetchCampaigns(
        force: Bool = false,
        inTimeout: (([InAppCampaign]) -> Void)? = nil,
        completion: (([InAppCampaign]) -> Void)? = nil,
    ) {
        let timeoutSeconds: TimeInterval = 1
        let timeoutController = inTimeout.map {
            _ in InAppMessageTimeoutController(
                timeoutSeconds: timeoutSeconds,
                queueLabel: "com.marketap.fetchCampaigns.timeout",
                logMessage: "fetchCampaigns timeout"
            )
        }
        timeoutController?.start()

        func handleInTimeout(_ campaigns: [InAppCampaign]) {
            guard let inTimeout = inTimeout else { return }
            let shouldHandle = timeoutController?.isWithinTimeout() ?? false
            guard shouldHandle else { return }
            inTimeout(campaigns)
        }

        if let lastFetch = lastFetch, !force, Date().timeIntervalSince(lastFetch) < Self.cacheExpiration {
            if self.campaigns == nil {
                self.campaigns = cache.loadCodableObject(forKey: Self.campaignCacheKey)
            }
            let cachedCampaigns = campaigns ?? []
            timeoutController?.markCompleted()
            handleInTimeout(cachedCampaigns)
            completion?(cachedCampaigns)
            return
        }

        let userId = cache.userId
        let device = cache.device

        api.request(
            baseURL: .crm,
            path: "/api/v2/campaigns",
            body: FetchCampaignsRequest(projectId: projectId, userId: userId, device: device.makeRequest()),
            responseType: InAppCampaignFetchResponse.self
        ) { [weak self] result in
            guard let self = self else { return }

            timeoutController?.markCompleted()

            switch result {
            case .success(let response):
                let campaigns = response.campaigns
                self.campaigns = campaigns
                self.cache.saveCodableObject(campaigns, key: Self.campaignCacheKey)
                self.cache.saveCodableObject(Date(), key: Self.lastFetchKey)
                self.lastFetch = Date()
                handleInTimeout(campaigns)
                completion?(campaigns)
            case .failure(_):
                let cachedCampaigns = self.campaigns ?? []
                handleInTimeout(cachedCampaigns)
                completion?(cachedCampaigns)
            }
        }
    }

    func fetchCampaign(
        campaignId: String,
        eventName: String? = nil,
        eventProperties: [String: Any]? = nil,
        completion: ((InAppCampaign?) -> Void)? = nil
    ) {
        let timeoutSeconds: TimeInterval = 1
        let timeoutController = InAppMessageTimeoutController(
            timeoutSeconds: timeoutSeconds,
            queueLabel: "com.marketap.fetchCampaign.timeout",
            logMessage: "fetchCampaign timeout: \(campaignId)"
        )
        timeoutController.start()

        let userId = cache.userId
        let device = cache.device
        let request = FetchCampaignRequest(
            projectId: projectId,
            userId: userId,
            device: device.makeRequest(),
            eventName: eventName,
            eventProperties: eventProperties?.toAnyCodable()
        )

        api.request(
            baseURL: .crm,
            path: "/api/v2/campaigns/\(campaignId)",
            body: request,
            responseType: InAppCampaignSingleFetchResponse.self
        ) { [weak self] result in
            guard self != nil else { return }

            guard timeoutController.markCompleted() else { return }

            switch result {
            case .success(let response):
                completion?(response.campaign)
            case .failure(_):
                MarketapLogger.warn("fetchCampaign failed: \(campaignId)")
                completion?(nil)
            }
        }
    }

    
}
