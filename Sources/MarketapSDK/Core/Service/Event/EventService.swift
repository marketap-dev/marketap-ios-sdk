//
//  EventService.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

class EventService {
    private let api: MarketapAPI
    private let cache: MarketapCache
    private let inAppMessageService: InAppMessageService

    private var projectId: String {
        cache.config.projectId
    }

    init(api: MarketapAPI, cache: MarketapCache, inAppMessageService: InAppMessageService) {
        self.api = api
        self.cache = cache
        self.inAppMessageService = inAppMessageService
    }

    func login(userId: String, userProperties: [String : Any]?, eventProperties: [String : Any]?) {
        let device = cache.loadDevice().makeRequest()
        identify(userId: userId, userProperties: userProperties)
        trackEvent(eventName: MarketapEvent.login.rawValue, eventProperties: eventProperties)
    }

    func logout(eventProperties: [String : Any]?) {
        guard let userId = cache.loadUserId() else { return }
        flushUser()
        trackEvent(eventName: MarketapEvent.logout.rawValue, eventProperties: eventProperties)
    }


    func identify(userId: String, userProperties: [String: Any]?) {
        let userIdChanged = cache.loadUserId() != userId
        cache.saveUserId(userId)
        updateProfile(
            request: UpdateProfileRequest(
                userId: userId,
                properties: userProperties?.toAnyEncodable(),
                device: cache.loadDevice().makeRequest()
            )
        )
        if userIdChanged {
            inAppMessageService.fetchCampaigns(force: true)
        }
    }

    func flushUser() {
        let userId = cache.loadUserId()
        let userIdChanged = userId != nil

        cache.clearUserId()
        updateDevice(removeUserId: true)
        if userIdChanged {
            inAppMessageService.fetchCampaigns(force: true)
        }

    }

    func trackEvent(eventName: String, eventProperties: [String: Any]?, id: String? = nil, timestamp: Date? = nil) {
        let userId = cache.loadUserId()
        let device = cache.loadDevice()

        let event = IngestEventRequest(
            id: id,
            name: eventName,
            userId: userId,
            device: device.makeRequest(),
            properties: eventProperties?.toAnyEncodable(),
            timestamp: timestamp ?? Date()
        )
        track(request: event)
    }

    func updateDevice(removeUserId: Bool = false){
        let device = cache.loadDevice().makeRequest(removeUserId: removeUserId)
        api.requestWithoutResponse(path: "/v1/client/profile/device?project_id=\(projectId)", body: device)
    }

    private func track(request: IngestEventRequest){
        api.requestWithoutResponse(path: "/v1/client/events?project_id=\(projectId)", body: request)
    }

    private func updateProfile(request: UpdateProfileRequest){
        api.requestWithoutResponse(baseURL: .crm, path: "/v1/client/profile/user?project_id=\(projectId)", body: request)
    }
}
