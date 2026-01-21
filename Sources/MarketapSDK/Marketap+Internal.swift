//
//  Marketap+Internal.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/11/25.
//

import Foundation

// MARK: - 인앱 이벤트 속성 빌더

enum InAppEventBuilder {

    /// 인앱 메시지 노출 이벤트 속성 생성
    static func impressionEventProperties(
        campaignId: String,
        messageId: String,
        layoutSubType: String?
    ) -> [String: Any] {
        return [
            "mkt_campaign_id": campaignId,
            "mkt_campaign_category": "ON_SITE",
            "mkt_channel_type": "IN_APP_MESSAGE",
            "mkt_sub_channel_type": layoutSubType ?? "MODAL",
            "mkt_result_status": 200000,
            "mkt_result_message": "SUCCESS",
            "mkt_is_success": true,
            "mkt_message_id": messageId
        ]
    }

    /// 인앱 메시지 클릭 이벤트 속성 생성
    static func clickEventProperties(
        campaignId: String,
        messageId: String,
        locationId: String,
        url: String?,
        layoutSubType: String?
    ) -> [String: Any] {
        var props: [String: Any] = [
            "mkt_campaign_id": campaignId,
            "mkt_campaign_category": "ON_SITE",
            "mkt_channel_type": "IN_APP_MESSAGE",
            "mkt_sub_channel_type": layoutSubType ?? "MODAL",
            "mkt_result_status": 200000,
            "mkt_result_message": "SUCCESS",
            "mkt_is_success": true,
            "mkt_message_id": messageId,
            "mkt_location_id": locationId
        ]
        if let url = url {
            props["mkt_url"] = url
        }
        return props
    }
}

// MARK: - Internal Methods (Flutter/React Native)

extension Marketap {

    // MARK: - 인앱 이벤트 처리 (공통 로직)

    /// 인앱 메시지 노출 이벤트 처리
    static func handleInAppImpression(
        campaignId: String,
        messageId: String,
        layoutSubType: String?
    ) {
        MarketapLogger.debug("handleInAppImpression: campaignId=\(campaignId), messageId=\(messageId)")
        let props = InAppEventBuilder.impressionEventProperties(
            campaignId: campaignId,
            messageId: messageId,
            layoutSubType: layoutSubType
        )
        client?.track(eventName: "mkt_delivery_message", eventProperties: props, id: nil, timestamp: nil)
    }

    /// 인앱 메시지 클릭 이벤트 처리
    /// 클릭 핸들러 호출 + 이벤트 트래킹
    static func handleInAppClick(
        campaignId: String,
        messageId: String,
        locationId: String,
        url: String?,
        layoutSubType: String?
    ) {
        MarketapLogger.debug("handleInAppClick: campaignId=\(campaignId), locationId=\(locationId), url=\(url ?? "nil")")

        // 클릭 핸들러 호출
        if let url = url, customHandlerStore.customized {
            customHandlerStore.handleClick(
                MarketapClickEvent(campaignType: .inAppMessage, campaignId: campaignId, url: url)
            )
        }

        // 클릭 이벤트 트래킹
        let props = InAppEventBuilder.clickEventProperties(
            campaignId: campaignId,
            messageId: messageId,
            locationId: locationId,
            url: url,
            layoutSubType: layoutSubType
        )
        client?.track(eventName: "mkt_click_message", eventProperties: props, id: nil, timestamp: nil)
    }

    /// 인앱 메시지 숨김 처리
    static func handleInAppHide(campaignId: String, hideType: String?) {
        MarketapLogger.debug("handleInAppHide: campaignId=\(campaignId), hideType=\(hideType ?? "nil")")
        if let hideTypeString = hideType,
           let hideType = CampaignHideType(rawValue: hideTypeString) {
            let hideDuration = hideType.hideDuration
            if hideDuration > 0 {
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970 + hideDuration,
                    forKey: "hide_campaign_\(campaignId)"
                )
            }
        }
    }

    // MARK: - 웹브릿지 이벤트 처리

    /// 유저 속성을 업데이트합니다.
    /// - Parameter userProperties: 유저 속성
    static func setUserProperties(userProperties: [String: Any]) {
        client?.setUserProperties(userProperties: userProperties)
    }

    /// 웹브릿지에서 호출된 이벤트를 추적합니다.
    /// 인앱 캠페인이 웹으로 위임되어 처리됩니다.
    /// - Parameters:
    ///   - eventName: 추적할 이벤트 이름
    ///   - eventProperties: 이벤트 속성 (선택)
    static func trackFromWebBridge(eventName: String, eventProperties: [String: Any]? = nil) {
        client?.trackFromWebBridge(eventName: eventName, eventProperties: eventProperties)
    }
}

/// MarketapInternal - Flutter/React Native 플러그인에서 사용하는 내부 API
@objcMembers
public class MarketapInternal: NSObject {

    private override init() {}

    // MARK: - 외부 웹브릿지 인앱 이벤트 처리 (Flutter/React Native)

    /// 외부 웹브릿지에서 인앱 메시지 노출 이벤트 처리
    public static func handleExternalInAppImpression(
        campaignId: String,
        messageId: String,
        layoutSubType: String?
    ) {
        Marketap.handleInAppImpression(
            campaignId: campaignId,
            messageId: messageId,
            layoutSubType: layoutSubType
        )
    }

    /// 외부 웹브릿지에서 인앱 메시지 클릭 이벤트 처리
    /// 클릭 핸들러 호출 + 이벤트 트래킹
    public static func handleExternalInAppClick(
        campaignId: String,
        messageId: String,
        locationId: String,
        url: String?,
        layoutSubType: String?
    ) {
        Marketap.handleInAppClick(
            campaignId: campaignId,
            messageId: messageId,
            locationId: locationId,
            url: url,
            layoutSubType: layoutSubType
        )
    }

    /// 외부 웹브릿지에서 인앱 메시지 숨김 처리
    public static func handleExternalInAppHide(campaignId: String, hideType: String?) {
        Marketap.handleInAppHide(campaignId: campaignId, hideType: hideType)
    }

    // MARK: - 웹브릿지 이벤트 처리

    /// 웹브릿지에서 호출된 이벤트를 추적합니다.
    /// 인앱 캠페인이 웹으로 위임되어 처리됩니다.
    public static func trackFromWebBridge(eventName: String, eventProperties: [String: Any]? = nil) {
        Marketap.trackFromWebBridge(eventName: eventName, eventProperties: eventProperties)
    }

    /// 유저 속성을 업데이트합니다.
    public static func setUserProperties(userProperties: [String: Any]) {
        Marketap.setUserProperties(userProperties: userProperties)
    }
}
