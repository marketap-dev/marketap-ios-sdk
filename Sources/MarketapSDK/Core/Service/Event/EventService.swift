//
//  EventService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

class EventService: EventServiceProtocol {
    static let deviceRequestKey = "EventService_deviceRequest"
    static let failedEventsKey = "EventService_failedEvents"
    static let failedUserKey = "EventService_failedUser"

    static let failedEventsSize = 100

    private let api: MarketapAPIProtocol
    private let cache: MarketapCacheProtocol
    weak var delegate: EventServiceDelegate?

    private var projectId: String {
        cache.projectId
    }

    let eventQueue = DispatchQueue(label: "com.marketap.events", attributes: .concurrent)
    let userQueue = DispatchQueue(label: "com.marketap.user", attributes: .concurrent)

    var _failedEvents: [BulkEvent] {
        didSet {
            cache.saveCodableObject(_failedEvents, key: Self.failedEventsKey)
        }
    }
    var failedEvents: [BulkEvent] {
        get {
            eventQueue.sync { _failedEvents }
        }
    }

    var _failedUser: UpdateProfileRequest?
    var failedUser: UpdateProfileRequest? {
        get {
            userQueue.sync { _failedUser }
        }
        set {
            userQueue.async(flags: .barrier) {
                self._failedUser = newValue
                self.cache.saveCodableObject(newValue, key: Self.failedUserKey)
            }
        }
    }

    init(api: MarketapAPIProtocol, cache: MarketapCacheProtocol) {
        self.api = api
        self.cache = cache
        self._failedEvents = cache.loadCodableObject(forKey: Self.failedEventsKey) ?? []
        self._failedUser = cache.loadCodableObject(forKey: Self.failedUserKey)

        sendFailedEventsIfNeeded()
        sendFailedUserIfNeeded()
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

    func trackEvent(eventName: String, eventProperties: [String: Any]?, id: String? = nil, timestamp: Date? = nil) {
        let event = IngestEventRequest(
            id: id,
            name: eventName,
            userId: cache.userId,
            device: cache.device.makeRequest(),
            properties: eventProperties?.toAnyCodable(),
            timestamp: timestamp ?? Date()
        )

        track(request: event)
        delegate?.onEvent(eventRequest: event, device: cache.device)
    }

    func updateDevice(pushToken: String? = nil, removeUserId: Bool = false) {
        let updatedDevice = cache.updateDevice(pushToken: pushToken).makeRequest(removeUserId: removeUserId)
        let cachedRequest: UpdateDeviceRequest? = cache.loadCodableObject(forKey: Self.deviceRequestKey)

        guard updatedDevice != cachedRequest else { return }
        cache.saveCodableObject(updatedDevice, key: Self.deviceRequestKey)

        api.requestWithoutResponse(
            baseURL: .event,
            path: "/v1/client/profile/device?project_id=\(projectId)",
            body: updatedDevice
        )
    }

    private func updateProfile(request: UpdateProfileRequest) {
        api.requestWithoutResponse(
            baseURL: .event,
            path: "/v1/client/profile/user?project_id=\(projectId)",
            body: request
        ) { [weak self] result in
            switch result {
            case .success:
                self?.failedUser = nil
            case .failure(let error):
                if case MarketapError.serverError = error {
                    self?.failedUser = request
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
                self?.sendFailedEventsIfNeeded()
                // 유저도 함께 재시도함
                self?.sendFailedUserIfNeeded()
            case .failure(let error):
                if case MarketapError.serverError = error {
                    self?.saveFailedEvent(request)
                }
            }
        }
    }
}

extension EventService {
    private func saveFailedEvent(_ event: IngestEventRequest) {
        eventQueue.async(flags: .barrier) {
            var newFailedEvents = self._failedEvents
            newFailedEvents.append(
                BulkEvent(
                    id: event.id,
                    name: event.name,
                    timestamp: event.timestamp,
                    properties: event.properties
                )
            )

            if newFailedEvents.count > Self.failedEventsSize {
                newFailedEvents.removeFirst(newFailedEvents.count - Self.failedEventsSize)
            }

            self._failedEvents = newFailedEvents
        }
    }

    func sendFailedEventsIfNeeded() {
        let failedEventsSnapshot = self.failedEvents

        guard !failedEventsSnapshot.isEmpty else { return }

        let bulkRequest = CreateBulkClientEventRequest(
            device: self.cache.device.makeRequest(),
            events: failedEventsSnapshot
        )

        self.api.requestWithoutResponse(
            baseURL: .event,
            path: "/v1/client/events/bulk?project_id=\(self.projectId)",
            body: bulkRequest
        ) { [weak self] result in
            if case .success = result {
                self?.eventQueue.async(flags: .barrier) {
                    self?._failedEvents = []
                }
            }
        }
    }

    func sendFailedUserIfNeeded() {
        if let user = failedUser {
            updateProfile(request: user)
        }
    }
}
