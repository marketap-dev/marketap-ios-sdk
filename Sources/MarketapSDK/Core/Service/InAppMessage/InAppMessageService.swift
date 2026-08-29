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
            var shouldFire = false
            self.stateQueue.sync {
                if self.didComplete { return }
                self.didComplete = true
                // 수명 해제도 didComplete 와 같은 전이 안에서 한다. 밖에서 하면 진 쪽과
                // 이긴 쪽이 같은 strong 프로퍼티를 동시에 써서 이중 해제가 난다.
                // self 는 이 클로저의 강한 지역변수라 여기서 해제해도 안전하다.
                self.selfRetain = nil
                shouldFire = true
            }
            guard shouldFire else { return }
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
        // .utility 가 아니라 .userInitiated 다. 이 타이머는 사용자에게 보일 팝업을 가로막는
        // 관문이라(타임아웃이 떠야 다음 후보로 넘어간다) 백그라운드 우선순위로 두면 안 된다.
        // 실측: 갓 부팅한 시뮬레이터에서 .utility 는 1초짜리 타이머가 16초 넘게 밀렸고,
        // 그 사이 시간 예산(2초)이 끝나 폴스루가 통째로 무산됐다. .userInitiated 로는 1.03초.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + timeoutSeconds,
            execute: workItem
        )
    }

    func markCompleted() -> Bool {
        var isFirst = false
        stateQueue.sync {
            if didComplete { return }
            didComplete = true
            selfRetain = nil
            isFirst = true
        }
        // 진 쪽(이미 타임아웃이 끝낸 경우)은 이긴 쪽의 수명을 건드리지 않는다.
        workItem.cancel()
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
    /// 숨김·노출 기록을 담는 저장소. 기본은 표준 저장소이고, 테스트만 격리된 suite 를 넣는다.
    /// (예전엔 UserDefaults.standard 를 직접 써서 테스트가 시뮬레이터 상태를 영구 오염시켰다)
    let defaults: UserDefaults
    weak var delegate: InAppMessageServiceDelegate?

    /// 적재·표시 선점 상태 일체를 지키는 락(아래 네 필드 전부).
    /// 파일 전역이 아니라 인스턴스 소유다 — 지키는 상태가 인스턴스별이라, 전역으로 두면
    /// 인스턴스가 둘일 때 서로 배제해주지도 못하면서 경합만 늘린다.
    let displayLock = NSLock()

    /// 표시 권리를 누가 잡고 있는지. 이름은 "모달이 떠 있다"지만 실제 의미는 **표시 권리를
    /// 선점했다**이다. 웹뷰 로딩을 기다리며 pendingCampaign 에 적재한 상태도 여기 포함된다
    /// (적재를 선점으로 안 치면 뒤 이벤트가 앞 후보를 조용히 덮어썼다).
    ///
    /// 불변식: `pendingCampaign != nil` 이면 반드시 `isModalShown == true`.
    var isModalShown: Bool = false

    /// 웹뷰가 노출에 쓸 수 있는 상태인가. 초기 blank 로드가 **끝났든 실패했든** true 가 된다.
    /// 실패도 종료로 치는 이유: 캠페인 노출은 어차피 새 loadHTMLString 을 걸기 때문에 초기
    /// 로드 결과와 무관하다. 예전엔 didFinish 에서만 true 가 돼서, 초기 로드가 실패하면
    /// 그 뒤로 어떤 인앱도 뜨지 못했다.
    var didFinishLoad = false

    /// 웹뷰가 준비되기 전에 도착해 적재된 후보. 준비되는 즉시 노출로 승격된다.
    var pendingCampaign: InAppCampaign?

    /// 적재 선점의 세대. 시한 타이머가 자기가 걸었던 적재만 취소하도록 구분한다.
    /// (권리가 이미 다른 경로로 반납·승격됐는데 늦게 뜬 타이머가 남의 선점을 푸는 걸 막는다)
    var pendingGeneration: Int = 0

    /// 적재 선점의 시한(초). 웹뷰가 이 안에 준비되지 않으면 적재를 버리고 표시 권리를 반납한다.
    /// 시한이 없으면 초기 로드가 영영 안 끝날 때 선점이 영구히 남아 인앱이 하나도 못 뜬다.
    ///
    /// 튜닝된 값이 아니라 보수적인 상한이다. 웹뷰가 준비되기까지 실제로 얼마나 걸리는지는
    /// 재지 않았다. 근거는 비용의 비대칭이다: 짧으면 앱 시작이 느릴 때 적재된 후보를 버려
    /// 이 수정이 없애려던 증상(먼저 도착한 후보가 조용히 사라짐)을 되살리는 반면, 길어서
    /// 손해 보는 구간은 "웹뷰가 고장 나 어차피 아무것도 못 뜨는" 동안뿐이다.
    /// (테스트에서만 값을 바꾼다)
    var pendingClaimTimeoutSeconds: TimeInterval = 10

    private var projectId: String {
        cache.projectId
    }

    /// campaigns / lastFetch 는 세 스레드에서 만진다: 코어 시리얼큐(onEvent), URLSession
    /// 델리게이트 스레드(응답), 그리고 타임아웃 글로벌큐(캐시 강등). Swift 배열은 한쪽이 쓰는
    /// 동안 다른 쪽이 읽으면 CoW 버퍼가 찢어져 크래시가 난다. 락으로 감싼다.
    ///
    /// 타이머 QoS 를 .userInitiated 로 올리면서 타임아웃이 제때(1초) 뜨게 됐는데, 하필 그게
    /// 1초 안팎에 오는 응답과 정면으로 겹친다. 예전엔 타임아웃이 늘 늦어서 안 부딪혔을 뿐이다.
    private let stateLock = NSLock()
    private var _campaigns: [InAppCampaign]?
    private var _lastFetch: Date?

    var campaigns: [InAppCampaign]? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _campaigns }
        set { stateLock.lock(); _campaigns = newValue; stateLock.unlock() }
    }
    var lastFetch: Date? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _lastFetch }
        set { stateLock.lock(); _lastFetch = newValue; stateLock.unlock() }
    }
    lazy var campaignViewController = InAppMessageWebViewController()

    init(
        customHandlerStore: MarketapCustomHandlerStoreProtocol,
        api: MarketapAPIProtocol,
        cache: MarketapCacheProtocol,
        defaults: UserDefaults = .standard
    ) {
        self.customHandlerStore = customHandlerStore
        self.cache = cache
        self.api = api
        self.defaults = defaults

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
        let timeoutController = inTimeout.map { handler in
            InAppMessageTimeoutController(
                timeoutSeconds: timeoutSeconds,
                queueLabel: "com.marketap.fetchCampaigns.timeout",
                logMessage: "fetchCampaigns timeout",
                // 목록 요청이 1초를 넘기면 응답이 와도 markCompleted()==false 라 inTimeout 이
                // 안 불린다. 그러면 후보 폴스루가 시작조차 못 하고 이벤트가 통째로 버려진다.
                // (단건 fetch 에서 고친 것과 같은 구멍이 한 층 위에 그대로 있었다.)
                // 캐시로 강등해서라도 체인을 깨운다.
                onTimeout: { [weak self] in
                    guard let self = self else { return }
                    let cached = self.campaigns
                        ?? self.cache.loadCodableObject(forKey: Self.campaignCacheKey)
                        ?? []
                    handler(cached)
                }
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
