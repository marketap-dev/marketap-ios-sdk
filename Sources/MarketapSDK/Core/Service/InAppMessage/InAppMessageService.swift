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
    /// 타임아웃이 이겼을 때 한 번만 불린다. 응답이 늦게 와도 markCompleted() 가 false 라
    /// 호출자 콜백이 영영 안 불리므로, 대기 중인 쪽에 "끝났다"를 알려줄 통로가 필요하다.
    private let onTimeout: (() -> Void)?
    private var didComplete = false
    /// 타임아웃이 뜰 때까지 자기 자신을 붙잡는다.
    ///
    /// 이게 없으면 컨트롤러의 수명이 "응답 클로저를 누가 붙잡고 있느냐"에 달린다. 요청이
    /// 클로저를 놓아버리면(동기 실패 등) 컨트롤러가 해제되고 workItem 의 weak self 가 nil 이
    /// 되어 **타임아웃이 아예 안 뜬다** — 대기 중인 호출자는 영영 콜백을 못 받는다.
    private var selfRetain: InAppMessageTimeoutController?
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
            defer { self.selfRetain = nil }
            guard shouldLog else { return }
            MarketapLogger.warn(self.logMessage)
            self.onTimeout?()
        }
    }()

    init(
        timeoutSeconds: TimeInterval,
        queueLabel: String,
        logMessage: String,
        onTimeout: (() -> Void)? = nil
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.stateQueue = DispatchQueue(label: queueLabel)
        self.logMessage = logMessage
        self.onTimeout = onTimeout
    }

    func start() {
        selfRetain = self
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
        selfRetain = nil
        return isFirst
    }
}

final class InAppMessageService: NSObject, InAppMessageServiceProtocol {
    static let cacheExpiration = Double(60 * 5)
    static let campaignCacheKey = "InAppMessageService_campaigns"
    static let lastFetchKey = "InAppMessageService_lastFetch"
    static let checksumKey = "InAppMessageService_checksum"

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
    lazy var campaignViewController = InAppMessageWebViewController()

    init(
        customHandlerStore: MarketapCustomHandlerStoreProtocol,
        api: MarketapAPIProtocol,
        cache: MarketapCacheProtocol
    ) {
        self.customHandlerStore = customHandlerStore
        self.cache = cache
        self.api = api

        super.init()

        self.lastFetch = cache.loadCodableObject(forKey: Self.lastFetchKey)
        fetchCampaigns()

        DispatchQueue.main.async {
            self.campaignViewController.delegate = self
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

        if let lastFetch = lastFetch, !force, Date().timeIntervalSince(lastFetch) < Self.cacheExpiration {
            if self.campaigns == nil {
                self.campaigns = cache.loadCodableObject(forKey: Self.campaignCacheKey)
            }
            let cachedCampaigns = campaigns ?? []
            let didCompleteWithinTimeout = timeoutController?.markCompleted() ?? false
            if didCompleteWithinTimeout {
                inTimeout?(cachedCampaigns)
            }
            completion?(cachedCampaigns)
            return
        }

        let userId = cache.userId
        let device = cache.device
        let cachedChecksum: String? = cache.loadCodableObject(forKey: Self.checksumKey)

        api.request(
            baseURL: .crm,
            path: "/api/v2/campaigns",
            body: FetchCampaignsRequest(projectId: projectId, userId: userId, device: device.makeRequest(), checksum: cachedChecksum),
            responseType: InAppCampaignFetchResponse.self
        ) { [weak self] result in
            guard let self = self else { return }

            let didCompleteWithinTimeout = timeoutController?.markCompleted() ?? false

            switch result {
            case .success(let response):
                let campaigns: [InAppCampaign]
                if let newCampaigns = response.campaigns {
                    campaigns = newCampaigns
                    self.campaigns = campaigns
                    self.cache.saveCodableObject(campaigns, key: Self.campaignCacheKey)
                } else {
                    campaigns = self.campaigns ?? self.cache.loadCodableObject(forKey: Self.campaignCacheKey) ?? []
                }
                self.cache.saveCodableObject(response.checksum, key: Self.checksumKey)
                self.cache.saveCodableObject(Date(), key: Self.lastFetchKey)
                self.lastFetch = Date()
                if didCompleteWithinTimeout {
                    inTimeout?(campaigns)
                }
                completion?(campaigns)
            case .failure(_):
                let cachedCampaigns = self.campaigns ?? []
                if didCompleteWithinTimeout {
                    inTimeout?(cachedCampaigns)
                }
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
            logMessage: "fetchCampaign timeout: \(campaignId)",
            // 타임아웃이 이기면 뒤늦게 온 응답은 버려지고 콜백이 영영 안 불린다.
            // 그러면 후보 폴스루가 여기서 조용히 멈춰 아무 캠페인도 안 뜬다. nil 로 깨워
            // 다음 후보로 넘어가게 한다. (Android 는 withTimeoutOrNull 로 이미 같은 동작)
            onTimeout: { completion?(nil) }
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
