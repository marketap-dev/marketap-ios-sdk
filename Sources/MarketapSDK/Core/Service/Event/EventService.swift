//
//  EventService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

final class EventService: EventServiceProtocol {
    static let deviceRequestKey = "EventService_deviceRequest"
    static let failedEventsKey = "EventService_failedEvents"
    static let failedUsersKey = "EventService_failedUsers"

    static let failedDataSize = 100

    private let api: MarketapAPIProtocol
    private let cache: MarketapCacheProtocol
    weak var delegate: EventServiceDelegate?

    private var projectId: String {
        cache.projectId
    }

    let eventQueue = DispatchQueue(label: "com.marketap.events", attributes: .concurrent)
    let userQueue = DispatchQueue(label: "com.marketap.user", attributes: .concurrent)

    let failedEventsStorage: DataStorageManager<BulkEvent>
    let failedUsersStorage: DataStorageManager<BulkProfile>

    init(api: MarketapAPIProtocol, cache: MarketapCacheProtocol) {
        self.api = api
        self.cache = cache

        self.failedEventsStorage = DataStorageManager<BulkEvent>(
            cache: cache,
            storageKey: Self.failedEventsKey,
            queueLabel: "com.marketap.events",
            maxStorageSize: Self.failedDataSize
        )
        self.failedUsersStorage = DataStorageManager<BulkProfile>(
            cache: cache,
            storageKey: Self.failedUsersKey,
            queueLabel: "com.marketap.users",
            maxStorageSize: Self.failedDataSize
        )

        sendFailedEventsIfNeeded()
        sendFailedUsersIfNeeded()
    }

    func setPushToken(token: String) {
        updateDevice(pushToken: token)
    }

    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?) {
        identify(userId: userId, userProperties: userProperties)
        trackEvent(eventName: MarketapEvent.login.rawValue, eventProperties: eventProperties)
    }

    func logout(eventProperties: [String: Any]?) {
        trackEvent(eventName: MarketapEvent.logout.rawValue, eventProperties: eventProperties)
        flushUser()
    }

    func identify(userId: String, userProperties: [String: Any]?) {
        let userIdChanged = cache.userId != userId
        cache.saveUserId(userId)

        let request = UpdateProfileRequest(
            userId: userId,
            properties: userProperties?.toAnyCodable(),
            device: cache.device.makeRequest(),
            timestamp: Date()
        )
        updateProfile(request: request)

        if userIdChanged {
            delegate?.handleUserIdChanged()
        }
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
        id: String? = nil,
        timestamp: Date? = nil
    ) {
        let device = cache.device
        var properties = eventProperties ?? [:]

        let currentTime = Date()
        let lastEventTimestamp = UserDefaults.standard.double(forKey: "last_event_time")
        let timeInterval = currentTime.timeIntervalSince1970 - lastEventTimestamp

        if timeInterval > 1800 || lastEventTimestamp == 0 {
            let newSessionId = UUID().uuidString
            cache.sessionId = newSessionId
            Logger.debug("session start: \(newSessionId)")

            let event = IngestEventRequest(
                id: nil,
                name: "mkt_session_start",
                userId: cache.userId,
                device: device.makeRequest(),
                properties: ["mkt_session_id": AnyCodable(newSessionId)],
                timestamp: Date()
            )
            track(request: event)
        }

        properties["mkt_session_id"] = cache.sessionId
        let eventTimestamp = timestamp ?? Date()

        let event = IngestEventRequest(
            id: id,
            name: eventName,
            userId: cache.userId,
            device: device.makeRequest(),
            properties: properties.toAnyCodable(),
            timestamp: eventTimestamp
        )

        UserDefaults.standard.set(eventTimestamp.timeIntervalSince1970, forKey: "last_event_time")

        track(request: event)
        delegate?.onEvent(eventRequest: event, device: device)
    }


    func updateDevice(pushToken: String? = nil, removeUserId: Bool = false) {
        cache.updateDevice(pushToken: pushToken)
        let updatedDevice = cache.device.makeRequest()
        let cachedRequest: UpdateDeviceRequest? = cache.loadCodableObject(forKey: Self.deviceRequestKey)

        guard updatedDevice != cachedRequest else { return }
        cache.saveCodableObject(updatedDevice, key: Self.deviceRequestKey)

        api.requestWithoutResponse(
            baseURL: .event,
            path: "/v1/client/profile/device?project_id=\(projectId)",
            body: updatedDevice
        )  { [weak self] result in
            switch result {
            case .success:
                self?.requestDidSuccess()
            case .failure:
                break
            }
        }
    }

    private func updateProfile(request: UpdateProfileRequest) {
        self.api.requestWithoutResponse(
            baseURL: .event,
            path: "/v1/client/profile/user?project_id=\(self.projectId)",
            body: request
        ) { [weak self] result in
            switch result {
            case .success:
                self?.requestDidSuccess()
            case .failure(let error):
                if case MarketapError.serverError = error {
                    self?.saveFailedUser(request)
                }
            }
        }
    }


    private func track(request: IngestEventRequest) {
        api.requestWithoutResponse(
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

    private func requestDidSuccess() {
        sendFailedEventsIfNeeded()
        sendFailedUsersIfNeeded()
    }
}

extension EventService {
    private func saveFailedEvent(_ event: IngestEventRequest) {
        let failedEvent = BulkEvent(
            id: event.id,
            userId: self.cache.userId,
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

    private func saveFailedUser(_ user: UpdateProfileRequest) {
        let failedUser = BulkProfile(
            userId: user.userId,
            properties: user.properties,
            device: user.device,
            timestamp: user.timestamp
        )
        failedUsersStorage.saveData(failedUser)
    }


    func sendFailedUsersIfNeeded() {
        let failedUsersSnapshot = failedUsersStorage.getAndClearData()
        guard !failedUsersSnapshot.isEmpty else { return }

        let bulkRequest = BulkProfileRequest(
            device: self.cache.device.makeRequest(),
            profiles: failedUsersSnapshot
        )

        api.requestWithoutResponse(
            baseURL: .event,
            path: "/v1/client/profile/user/bulk?project_id=\(projectId)",
            body: bulkRequest
        ) { [weak self] result in
            if case .failure(let error) = result, case MarketapError.serverError = error {
                self?.failedUsersStorage.restoreFailedData(failedUsersSnapshot)
            }
        }
    }
}
