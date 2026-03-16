//
//  EventService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

final class EventService: EventServiceProtocol {
    static let failedEventsKey = "EventService_failedEvents"
    static let lastSentDeviceRequestKey = "EventService_lastSentDeviceRequest"
    static let lastSentDeviceRequestAtKey = "EventService_lastSentDeviceRequestAt"
    static let deviceRequestTTL: TimeInterval = 24 * 60 * 60
    static let pendingUserProfileKey = "EventService_pendingUserProfile"
    static let pendingDeviceProfileKey = "EventService_pendingDeviceProfile"

    static let failedDataSize = 100

    let api: MarketapAPIProtocol
    private let cache: MarketapCacheProtocol
    weak var delegate: EventServiceDelegate?
    private var lastSentDeviceRequest: UpdateDeviceRequest?

    private var projectId: String {
        cache.projectId
    }

    let eventQueue = DispatchQueue(label: "com.marketap.events", attributes: .concurrent)
    // serial queue: user profile과 device profile 직렬 처리 (최신 상태만 유효)
    let userQueue = DispatchQueue(label: "com.marketap.user")

    let failedEventsStorage: DataStorageManager<BulkEvent>
    let serverTimeManager: ServerTimeManagerProtocol

    init(api: MarketapAPIProtocol, cache: MarketapCacheProtocol, serverTimeManager: ServerTimeManagerProtocol? = nil) {
        self.api = api
        self.cache = cache
        self.serverTimeManager = serverTimeManager ?? ServerTimeManager(api: api, projectId: cache.projectId)

        self.failedEventsStorage = DataStorageManager<BulkEvent>(
            cache: cache,
            storageKey: Self.failedEventsKey,
            queueLabel: "com.marketap.events",
            maxStorageSize: Self.failedDataSize
        )

        sendFailedEventsIfNeeded()
        userQueue.async { [weak self] in
            self?.checkUserQueue()
            self?.checkDeviceQueue()
        }
        self.serverTimeManager.withServerTime { _ in }
    }

    func setPushToken(token: String) {
        updateDevice(pushToken: token)
    }

    func setDeviceOptIn(optIn: Bool?) {
        if let optIn = optIn {
            updateDevice(optIn: optIn)
        } else {
            updateDevice(clearOptIn: true)
        }
    }

    func identify(userId: String, userProperties: [String: Any]?) {
        let userIdChanged = cache.userId != userId
        cache.saveUserId(userId)

        let request = UpdateProfileRequest(
            userId: userId,
            properties: userProperties?.toAnyCodable(),
            device: cache.device.makeRequest()
        )
        updateProfile(request: request)

        if userIdChanged {
            delegate?.handleUserIdChanged()
        }
    }

    func setUserProperties(
        userProperties: [String : Any],
        userId: String? = nil,
    ) {
        guard let currentUserId = userId ?? cache.userId else { return }
        let request = UpdateProfileRequest(
            userId: currentUserId,
            properties: userProperties.toAnyCodable(),
            device: cache.device.makeRequest()
        )
        updateProfile(request: request)
    }

    func flushUser() {
        let userIdChanged = cache.userId != nil

        cache.saveUserId(nil)
        updateDevice(removeUserId: true)

        if userIdChanged {
            delegate?.handleUserIdChanged()
        }
    }

    func trackEvent(
        eventName: String,
        eventProperties: [String: Any]?,
        userId: String? = nil,
        id: String? = nil,
        timestamp: Date? = nil,
        fromWebBridge: Bool = false
    ) {
        let device = cache.device
        var properties = eventProperties ?? [:]
        let sdkIntegrationState = SdkIntegrationState.toJsonString()

        let currentTime = Date()
        let lastEventTimestamp = UserDefaults.standard.double(forKey: "marketap_last_event_time")
        let timeInterval = currentTime.timeIntervalSince1970 - lastEventTimestamp

        if timeInterval > 1800 || lastEventTimestamp == 0 {
            let newSessionId = UUID().uuidString
            cache.sessionId = newSessionId
            MarketapLogger.debug("session start: \(newSessionId)")

            let event = IngestEventRequest(
                id: UUID().uuidString,
                name: "mkt_session_start",
                userId: userId ?? cache.userId,
                device: device.makeRequest(),
                properties: [
                    "mkt_session_id": AnyCodable(newSessionId),
                    "sdk_integration_state": AnyCodable(sdkIntegrationState)
                ]
            )
            track(request: event)
        }

        properties["mkt_session_id"] = cache.sessionId
        properties["sdk_integration_state"] = sdkIntegrationState
        let eventTimestamp = timestamp ?? Date()

        let event = IngestEventRequest(
            id: id ?? UUID().uuidString,
            name: eventName,
            userId: cache.userId,
            device: device.makeRequest(),
            properties: properties.toAnyCodable(),
            timestamp: eventTimestamp
        )

        UserDefaults.standard.set(eventTimestamp.timeIntervalSince1970, forKey: "marketap_last_event_time")

        track(request: event)
        delegate?.onEvent(eventRequest: event, device: device, fromWebBridge: fromWebBridge)
    }


    func updateDevice(pushToken: String? = nil, optIn: Bool? = nil, removeUserId: Bool = false, clearOptIn: Bool = false) {
        cache.updateDevice(pushToken: pushToken, optIn: optIn, clearOptIn: clearOptIn)
        let updatedDevice = cache.device.makeRequest(removeUserId: removeUserId)

        if updatedDevice == lastSentDeviceRequest {
            return
        }

        let storedRequest: UpdateDeviceRequest? = cache.loadCodableObject(forKey: Self.lastSentDeviceRequestKey)
        let storedAt = UserDefaults.standard.double(forKey: Self.lastSentDeviceRequestAtKey)
        let isExpired = Date().timeIntervalSince1970 - storedAt > Self.deviceRequestTTL

        if !isExpired && updatedDevice == storedRequest {
            MarketapLogger.debug("Device info unchanged and within TTL, skipping update")
            lastSentDeviceRequest = updatedDevice
            return
        }

        cache.saveCodableObject(updatedDevice, key: Self.pendingDeviceProfileKey)
        userQueue.async { [weak self] in
            self?.checkDeviceQueue()
        }
    }

    private func updateProfile(request: UpdateProfileRequest) {
        cache.saveCodableObject(request, key: Self.pendingUserProfileKey)
        userQueue.async { [weak self] in
            self?.checkUserQueue()
        }
    }

    // userQueue에서 실행 (serial). 대기 중인 user profile 요청을 순차적으로 전송
    private func checkUserQueue() {
        while true {
            guard let item: UpdateProfileRequest = cache.loadCodableObject(forKey: Self.pendingUserProfileKey) else { break }
            cache.clearObject(forKey: Self.pendingUserProfileKey)

            let semaphore = DispatchSemaphore(value: 0)
            var sent = false

            serverTimeManager.withServerTime { [weak self] serverTime in
                guard let self = self else {
                    semaphore.signal()
                    return
                }
                var request = item
                request.timestamp = serverTime

                self.api.requestWithoutResponse(
                    baseURL: .event,
                    path: "/v1/client/profile/user?project_id=\(self.projectId)",
                    body: request
                ) { result in
                    if case .success = result {
                        sent = true
                    }
                    semaphore.signal()
                }
            }

            semaphore.wait()

            if !sent {
                // 더 새로운 요청이 없을 때만 복구 (있으면 새 요청이 최신 상태)
                if (cache.loadCodableObject(forKey: Self.pendingUserProfileKey) as UpdateProfileRequest?) == nil {
                    cache.saveCodableObject(item, key: Self.pendingUserProfileKey)
                }
                break
            }
        }
    }

    // userQueue에서 실행 (serial). 대기 중인 device profile 요청을 순차적으로 전송
    private func checkDeviceQueue() {
        while true {
            guard let item: UpdateDeviceRequest = cache.loadCodableObject(forKey: Self.pendingDeviceProfileKey) else { break }
            cache.clearObject(forKey: Self.pendingDeviceProfileKey)

            let semaphore = DispatchSemaphore(value: 0)
            var sent = false

            api.requestWithoutResponse(
                baseURL: .event,
                path: "/v1/client/profile/device?project_id=\(projectId)",
                body: item
            ) { [weak self] result in
                if case .success = result {
                    sent = true
                    self?.lastSentDeviceRequest = item
                    self?.cache.saveCodableObject(item, key: Self.lastSentDeviceRequestKey)
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSentDeviceRequestAtKey)
                }
                semaphore.signal()
            }

            semaphore.wait()

            if !sent {
                if (cache.loadCodableObject(forKey: Self.pendingDeviceProfileKey) as UpdateDeviceRequest?) == nil {
                    cache.saveCodableObject(item, key: Self.pendingDeviceProfileKey)
                }
                break
            }
        }
    }

    private func track(request: IngestEventRequest) {
        serverTimeManager.withServerTime { [weak self] serverTime in
            guard let self = self else { return }
            var request = request
            request.timestamp = serverTime
            self.api.requestWithoutResponse(
                baseURL: .event,
                path: "/v1/client/events?project_id=\(self.projectId)",
                body: request
            ) { [weak self] result in
                switch result {
                case .success:
                    self?.requestDidSuccess()
                case .failure(let error):
                    if case MarketapError.serverError = error {
                        self?.saveFailedEvent(request)
                    }
                }
            }
        }
    }

    private func requestDidSuccess() {
        sendFailedEventsIfNeeded()
        userQueue.async { [weak self] in
            self?.checkUserQueue()
            self?.checkDeviceQueue()
        }
    }
}

extension EventService {
    private func saveFailedEvent(_ event: IngestEventRequest) {
        let failedEvent = BulkEvent(
            id: event.id,
            userId: event.userId,
            name: event.name,
            timestamp: event.timestamp,
            properties: event.properties
        )
        failedEventsStorage.saveData(failedEvent)
    }

    func sendFailedEventsIfNeeded() {
        let failedEventsSnapshot = failedEventsStorage.getAndClearData()
        guard !failedEventsSnapshot.isEmpty else { return }

        let bulkRequest = CreateBulkClientEventRequest(
            device: cache.device.makeRequest(),
            events: failedEventsSnapshot
        )

        api.requestWithoutResponse(
            baseURL: .event,
            path: "/v1/client/events/bulk?project_id=\(projectId)",
            body: bulkRequest
        ) { [weak self] result in
            if case .failure(let error) = result, case MarketapError.serverError = error {
                self?.failedEventsStorage.restoreFailedData(failedEventsSnapshot)
            }
        }
    }
}
