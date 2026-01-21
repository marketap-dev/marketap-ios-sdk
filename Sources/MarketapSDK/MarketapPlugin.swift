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

/// MarketapPlugin - 플러그인(Flutter/React Native) 및 웹브릿지에서 사용하는 API
@objcMembers
public class MarketapPlugin: NSObject {

    private override init() {}

    // MARK: - 인앱 이벤트 처리 (플러그인용)

    /// 인앱 메시지 노출 이벤트 처리
    public static func trackInAppImpression(
        campaignId: String,
        messageId: String,
        layoutSubType: String?
    ) {
        MarketapLogger.debug("trackInAppImpression: campaignId=\(campaignId), messageId=\(messageId)")
        let props = InAppEventBuilder.impressionEventProperties(
            campaignId: campaignId,
            messageId: messageId,
            layoutSubType: layoutSubType
        )
        Marketap.client?.track(eventName: "mkt_delivery_message", eventProperties: props, id: nil, timestamp: nil)
    }

    /// 인앱 메시지 클릭 이벤트 처리
    public static func trackInAppClick(
        campaignId: String,
        messageId: String,
        locationId: String,
        url: String?,
        layoutSubType: String?
    ) {
        MarketapLogger.debug("trackInAppClick: campaignId=\(campaignId), locationId=\(locationId), url=\(url ?? "nil")")

        // 클릭 핸들러 호출 (커스텀 핸들러가 등록된 경우에만)
        if let url = url, Marketap.customHandlerStore.customized {
            Marketap.customHandlerStore.handleClick(
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
        Marketap.client?.track(eventName: "mkt_click_message", eventProperties: props, id: nil, timestamp: nil)
    }

    /// 인앱 메시지 숨김 처리
    public static func hideInAppMessage(campaignId: String, hideType: String?) {
        MarketapLogger.debug("hideInAppMessage: campaignId=\(campaignId), hideType=\(hideType ?? "nil")")
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

    // MARK: - 이벤트 처리 (플러그인용)

    /// 이벤트를 추적합니다. 인앱 캠페인이 플러그인으로 전달됩니다.
    public static func trackEvent(eventName: String, eventProperties: [String: Any]? = nil) {
        Marketap.client?.trackFromWebBridge(eventName: eventName, eventProperties: eventProperties)
    }

    /// 유저 속성을 업데이트합니다.
    public static func setUserProperties(userProperties: [String: Any]) {
        Marketap.client?.setUserProperties(userProperties: userProperties)
    }
}
