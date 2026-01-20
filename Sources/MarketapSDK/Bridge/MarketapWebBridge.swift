//
//  MarketapWebBridge.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/25/25.
//

import WebKit
import UIKit

/// 웹브릿지를 통해 인앱 메시지를 웹으로 전달하기 위한 프로토콜
protocol WebBridgeInAppMessageDelegate: AnyObject {
    func sendCampaignToWeb(campaign: InAppCampaign, messageId: String)
}

/// 외부에서 인앱 메시지를 받기 위한 콜백 타입 (Flutter, React Native 등)
public typealias ExternalInAppMessageCallback = (_ campaign: [String: Any], _ messageId: String, _ hasCustomClickHandler: Bool) -> Void

@objc public class MarketapWebBridge: NSObject, WKScriptMessageHandler {
    public static let name = "marketap"
    private weak var webView: WKWebView?

    /// 현재 활성화된 웹브릿지 인스턴스 (웹뷰가 살아있는 동안)
    private static weak var activeInstance: MarketapWebBridge?

    /// 외부 인앱 메시지 콜백 (Flutter, React Native 등에서 등록)
    private static var externalInAppMessageCallback: ExternalInAppMessageCallback?
    /// 외부 웹브릿지가 활성화되었는지 여부
    private static var isExternalWebBridgeActive: Bool = false

    /// 인앱 메시지를 웹뷰에서 처리할지 여부 (false면 네이티브에서 처리)
    private let handleInAppInWebView: Bool

    /// 현재 진행 중인 웹 인앱 메시지의 캠페인 정보
    private var currentCampaign: InAppCampaign?
    private var currentMessageId: String?

    /// MarketapWebBridge 초기화
    /// - Parameter handleInAppInWebView: 인앱 메시지를 웹뷰에서 처리할지 여부 (기본값: true)
    @objc public init(handleInAppInWebView: Bool = true) {
        self.handleInAppInWebView = handleInAppInWebView
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        self.webView = message.webView

        guard message.name == Self.name,
              let body = message.body as? [String: Any],
              let typeString = body["type"] as? String,
              let eventType = MarketapBridgeEventType(rawValue: typeString) else {
            if message.name == Self.name {
                MarketapLogger.error("invalid body: \(message.body)")
            }
            return
        }

        let event = MarketapBridgeEvent(type: eventType, params: body["params"] as? [String: Any])
        handleEvent(event)
    }

    private func handleEvent(_ event: MarketapBridgeEvent) {
        switch event.type {
        case .track:
            handleTrackEvent(params: event.params)
        case .identify:
            handleIdentifyEvent(params: event.params)
        case .resetIdentity:
            Marketap.resetIdentity()
        case .marketapBridgeCheck:
            handleBridgeCheck()
        // 웹에서 인앱 메시지 이벤트 처리
        case .inAppMessageImpression:
            handleInAppImpression(params: event.params)
        case .inAppMessageClick:
            handleInAppClick(params: event.params)
        case .inAppMessageHide:
            handleInAppHide(params: event.params)
        case .inAppMessageTrack:
            handleInAppTrack(params: event.params)
        case .inAppMessageSetUserProperties:
            handleInAppSetUserProperties(params: event.params)
        }
    }

    private func handleTrackEvent(params: [String: Any]?) {
        guard let eventName = params?["eventName"] as? String else {
            return
        }
        // 웹뷰에서 인앱 메시지를 처리하는 경우에만 활성 인스턴스로 등록
        if handleInAppInWebView {
            Self.activeInstance = self
        }
        let eventProperties = params?["eventProperties"] as? [String: Any]
        // 웹브릿지 컨텍스트 표시하여 track 호출
        Marketap.trackFromWebBridge(eventName: eventName, eventProperties: eventProperties)
    }

    private func handleIdentifyEvent(params: [String: Any]?) {
        guard let userId = params?["userId"] as? String else {
            return
        }
        let userProperties = params?["userProperties"] as? [String: Any]
        Marketap.identify(userId: userId, userProperties: userProperties)
    }

    private func handleBridgeCheck() {
        webView?.evaluateJavaScript("""
            window.postMessage({
                type: 'marketapBridgeAck',
                metadata: {
                    sdk_type: 'ios',
                    sdk_version: '\(MarketapConfig.sdkVersion)',
                    platform: 'ios'
                }
            }, '*');
        """)
    }

    // MARK: - 인앱 메시지 이벤트 핸들러

    private func handleInAppImpression(params: [String: Any]?) {
        guard let campaignId = params?["campaignId"] as? String,
              let messageId = params?["messageId"] as? String else {
            MarketapLogger.warn("inAppMessageImpression: missing required params")
            return
        }

        MarketapLogger.debug("Web InApp Impression: campaignId=\(campaignId), messageId=\(messageId)")

        // 캠페인 정보가 있으면 impression 이벤트 전송
        if let campaign = currentCampaign, campaign.id == campaignId {
            Marketap.client?.track(
                eventName: "mkt_delivery_message",
                eventProperties: [
                    "mkt_campaign_id": campaign.id,
                    "mkt_campaign_category": "ON_SITE",
                    "mkt_channel_type": "IN_APP_MESSAGE",
                    "mkt_sub_channel_type": campaign.layout.layoutSubType,
                    "mkt_result_status": 200000,
                    "mkt_result_message": "SUCCESS",
                    "mkt_is_success": true,
                    "mkt_message_id": messageId
                ],
                id: nil,
                timestamp: nil
            )
        }
    }

    private func handleInAppClick(params: [String: Any]?) {
        guard let campaignId = params?["campaignId"] as? String,
              let messageId = params?["messageId"] as? String,
              let locationId = params?["locationId"] as? String else {
            MarketapLogger.warn("inAppMessageClick: missing required params")
            return
        }

        let url = params?["url"] as? String
        MarketapLogger.debug("Web InApp Click: campaignId=\(campaignId), locationId=\(locationId), url=\(url ?? "nil")")

        // 클릭 핸들러 호출
        if let campaign = currentCampaign, campaign.id == campaignId {
            if Marketap.customHandlerStore.customized {
                Marketap.customHandlerStore.handleClick(
                    MarketapClickEvent(campaignType: .inAppMessage, campaignId: campaign.id, url: url)
                )
            }

            Marketap.client?.track(
                eventName: "mkt_click_message",
                eventProperties: [
                    "mkt_campaign_id": campaign.id,
                    "mkt_campaign_category": "ON_SITE",
                    "mkt_channel_type": "IN_APP_MESSAGE",
                    "mkt_sub_channel_type": campaign.layout.layoutSubType,
                    "mkt_result_status": 200000,
                    "mkt_result_message": "SUCCESS",
                    "mkt_location_id": locationId,
                    "mkt_is_success": true,
                    "mkt_message_id": messageId
                ],
                id: nil,
                timestamp: nil
            )
        }
    }

    private func handleInAppHide(params: [String: Any]?) {
        guard let campaignId = params?["campaignId"] as? String else {
            MarketapLogger.warn("inAppMessageHide: missing campaignId")
            return
        }

        let hideTypeString = params?["hideType"] as? String
        MarketapLogger.debug("Web InApp Hide: campaignId=\(campaignId), hideType=\(hideTypeString ?? "nil")")

        // 캠페인 숨김 처리
        if let hideTypeString = hideTypeString,
           let hideType = CampaignHideType(rawValue: hideTypeString) {
            let hideDuration = hideType.hideDuration
            if hideDuration > 0 {
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970 + hideDuration,
                    forKey: "hide_campaign_\(campaignId)"
                )
            }
        }

        // 현재 캠페인 정보 클리어
        if currentCampaign?.id == campaignId {
            currentCampaign = nil
            currentMessageId = nil
        }
    }

    private func handleInAppTrack(params: [String: Any]?) {
        guard let eventName = params?["eventName"] as? String else {
            MarketapLogger.warn("inAppMessageTrack: missing eventName")
            return
        }

        let eventProperties = params?["eventProperties"] as? [String: Any]
        MarketapLogger.debug("Web InApp Track: eventName=\(eventName)")

        Marketap.client?.track(eventName: eventName, eventProperties: eventProperties, id: nil, timestamp: nil)
    }

    private func handleInAppSetUserProperties(params: [String: Any]?) {
        guard let userProperties = params?["userProperties"] as? [String: Any] else {
            MarketapLogger.warn("inAppMessageSetUserProperties: missing userProperties")
            return
        }

        MarketapLogger.debug("Web InApp SetUserProperties")
        Marketap.setUserProperties(userProperties: userProperties)
    }
}

// MARK: - WebBridgeInAppMessageDelegate

extension MarketapWebBridge: WebBridgeInAppMessageDelegate {
    /// 캠페인을 웹으로 전달
    func sendCampaignToWeb(campaign: InAppCampaign, messageId: String) {
        guard let webView = webView else {
            MarketapLogger.warn("sendCampaignToWeb: webView is nil")
            return
        }

        self.currentCampaign = campaign
        self.currentMessageId = messageId

        // 캠페인 정보를 JSON으로 직렬화
        guard let campaignData = try? JSONEncoder().encode(campaign),
              let campaignJson = String(data: campaignData, encoding: .utf8) else {
            MarketapLogger.error("sendCampaignToWeb: failed to encode campaign")
            return
        }

        // 커스텀 클릭 핸들러 등록 여부
        let hasCustomClickHandler = Marketap.customHandlerStore.customized

        MarketapLogger.debug("Sending campaign to web: \(campaign.id), hasCustomClickHandler: \(hasCustomClickHandler)")

        DispatchQueue.main.async {
            webView.evaluateJavaScript("""
                window.postMessage({
                    type: 'marketapShowInAppMessage',
                    campaign: \(campaignJson),
                    messageId: '\(messageId)',
                    hasCustomClickHandler: \(hasCustomClickHandler)
                }, '*');
            """) { _, error in
                if let error = error {
                    MarketapLogger.error("sendCampaignToWeb failed: \(error)")
                }
            }
        }
    }

    /// 현재 활성화된 웹브릿지가 있는지 확인
    static func hasActiveWebBridge() -> Bool {
        // 네이티브 웹브릿지 또는 외부 웹브릿지가 활성화되어 있는지 확인
        return activeInstance?.webView != nil || isExternalWebBridgeActive
    }

    /// 현재 활성화된 웹브릿지로 캠페인 전달
    /// 전달 후 activeInstance를 클리어하여 다음 이벤트에서 올바른 웹브릿지를 사용하도록 함
    static func sendCampaignToActiveWeb(campaign: InAppCampaign, messageId: String) {
        // 외부 웹브릿지가 활성화된 경우 외부로 전달
        if isExternalWebBridgeActive {
            isExternalWebBridgeActive = false  // 전달 후 클리어
            if let callback = externalInAppMessageCallback {
                // InAppCampaign을 Dictionary로 변환
                let campaignDict = campaign.toDictionary()
                let hasCustomClickHandler = Marketap.customHandlerStore.customized
                callback(campaignDict, messageId, hasCustomClickHandler)
            }
            return
        }

        // 네이티브 웹브릿지로 전달
        let bridge = activeInstance
        activeInstance = nil  // 전달 전에 클리어 (sendCampaignToWeb이 실패해도 클리어)
        bridge?.sendCampaignToWeb(campaign: campaign, messageId: messageId)
    }

    // MARK: - External Bridge Support

    /// 외부 인앱 메시지 콜백 등록 (Flutter, React Native 등에서 사용)
    /// - Parameter callback: 인앱 메시지를 받을 콜백 함수
    @objc public static func setExternalInAppMessageCallback(_ callback: ExternalInAppMessageCallback?) {
        externalInAppMessageCallback = callback
    }

    /// 외부 웹브릿지 활성화 상태 설정
    /// 외부에서 trackFromWebBridge 호출 시 true로 설정
    @objc public static func setExternalWebBridgeActive(_ active: Bool) {
        isExternalWebBridgeActive = active
    }
}
