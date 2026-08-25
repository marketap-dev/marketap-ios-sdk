//
//  MarketapCore.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

final class MarketapCore: MarketapClientProtocol, MarketapNotificationHandlerProtocol {
    let customHandlerStore: MarketapCustomHandlerStoreProtocol
    /// 최초 방문 플래그 저장소. 기본은 표준 저장소, 테스트만 격리 suite 를 넣어
    /// 매 실행이 동일한 초기 상태에서 시작하게 한다.
    private let defaults: UserDefaults
    let eventService: EventServiceProtocol
    let inAppMessageService: InAppMessageServiceProtocol
    let queue = DispatchQueue(label: "com.marketap.core")

    init(
        customHandlerStore: MarketapCustomHandlerStoreProtocol,
        eventService: EventServiceProtocol,
        inAppMessageService: InAppMessageServiceProtocol,
        defaults: UserDefaults = .standard
    ) {
        self.customHandlerStore = customHandlerStore
        self.inAppMessageService = inAppMessageService
        self.eventService = eventService
        self.defaults = defaults

        queue.async {
            self.eventService.updateDevice(pushToken: nil, optIn: nil, removeUserId: false, clearOptIn: false)

            // 기존 키 마이그레이션
            if defaults.bool(forKey: "first_visit") {
                defaults.set(true, forKey: "marketap_first_visit")
            }

            if !defaults.bool(forKey: "marketap_first_visit") {
                defaults.set(true, forKey: "marketap_first_visit")
                self.eventService.trackEvent(eventName: "mkt_first_visit", eventProperties: nil)
            }
        }
    }

    deinit {
        MarketapLogger.verbose("client has been deallocated: \(ObjectIdentifier(self).hashValue)")
    }
}


extension MarketapCore: EventServiceDelegate {
    func handleUserIdChanged() {
        queue.async {
            self.inAppMessageService.fetchCampaigns(force: true)
        }
    }

    /// 인앱 캠페인 숨김 기록. 웹브릿지/플러그인 경로에서 들어온다.
    ///
    /// 숨김 키는 InAppMessageService 가 자기 저장소에서 읽으므로, 기록도 반드시 같은 곳에
    /// 남겨야 한다. 예전엔 플러그인이 UserDefaults.standard 를 직접 찔러서 저장소가 갈렸다.
    public func hideInAppMessage(campaignId: String, until: TimeInterval) {
        inAppMessageService.recordHidden(campaignId: campaignId, until: until)
    }

    func onEvent(eventRequest: IngestEventRequest, device: Device, fromWebBridge: Bool) {
        queue.async {
            if !["mkt_delivery_message", "mkt_click_message"].contains(eventRequest.name) {
                self.inAppMessageService.onEvent(eventRequest: eventRequest, fromWebBridge: fromWebBridge)
            }
        }
    }
}

extension MarketapCore: InAppMessageServiceDelegate {
    func trackEvent(eventName: String, eventProperties: [String : Any]?) {
        track(eventName: eventName, eventProperties: eventProperties, id: nil, timestamp: nil)
    }
    
    func setUserProperties(userProperties: [String : Any]) {
        queue.async {
            MarketapLogger.debug("setUserProperties:\n\(userProperties.prettyPrintedJSONString)")
            self.eventService.setUserProperties(userProperties: userProperties, userId: nil)
        }
    }
}
