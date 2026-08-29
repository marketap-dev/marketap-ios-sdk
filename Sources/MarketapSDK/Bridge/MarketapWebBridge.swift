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
    /// 지금 이 브릿지로 전달을 시도할 수 있는지(웹뷰가 살아있는지).
    /// 선점 시점에 죽은 브릿지를 걸러내는 데 쓴다.
    var canDeliver: Bool { get }

    /// - Returns: 실제로 전달을 시작했는지. false 면 호출자가 다른 경로(네이티브 모달)로 폴백해야 한다.
    func sendCampaignToWeb(campaign: InAppCampaign, messageId: String) -> Bool
}

/// 웹브릿지 전달 권리를 한 번만 가져간 결과. `claimActiveWebBridge()` 로만 만들어진다.
///
/// 예전 API 는 확인(hasActiveWebBridge)과 소비(sendCampaignToActiveWeb)가 나뉘어 있어서,
/// 두 체인이 동시에 확인을 통과하면 뒤쪽은 impression 만 남기고 전달은 아무 데도 안 됐다.
/// 선점에 성공한 쪽만 이 값을 받는다.
enum WebBridgeClaim {
    /// 외부 래퍼(Flutter/RN) 콜백
    case external(ExternalInAppMessageCallback)
    /// 네이티브 웹뷰 브릿지
    case native(WebBridgeInAppMessageDelegate)

    /// - Returns: 실제로 전달을 시작했는지. false 면 호출자가 네이티브 모달로 폴백해야 한다.
    func deliver(campaign: InAppCampaign, messageId: String) -> Bool {
        switch self {
        case .external(let callback):
            callback(campaign.toDictionary(), messageId, MarketapWebBridge.shouldHandleUrlRouting)
            return true
        case .native(let bridge):
            return bridge.sendCampaignToWeb(campaign: campaign, messageId: messageId)
        }
    }

    /// 선점했는데 결국 전달하지 못했을 때 되돌린다. `releaseDisplay()` 와 같은 자리다.
    ///
    /// 되돌리기는 **아무도 그 사이에 새로 선점하지 않았을 때만** 한다. 안 그러면 방금 등록된
    /// 새 브릿지를 낡은 것으로 덮어쓴다. 죽은 브릿지(canDeliver == false)도 되돌리지 않는다 —
    /// 되살려봐야 다음 이벤트가 똑같이 실패한다.
    func release() {
        switch self {
        case .external:
            MarketapWebBridge.restoreExternalArm()
        case .native(let bridge):
            MarketapWebBridge.restoreActiveInstance(bridge)
        }
    }
}

/// 외부에서 인앱 메시지를 받기 위한 콜백 타입 (Flutter, React Native 등)
public typealias ExternalInAppMessageCallback = (_ campaign: [String: Any], _ messageId: String, _ hasCustomClickHandler: Bool) -> Void

@objc public class MarketapWebBridge: NSObject, WKScriptMessageHandler {
    public static let name = "marketap"

    /// static 브릿지 상태(activeInstance / externalInAppMessageCallback /
    /// isExternalWebBridgeActive)를 지키는 락.
    ///
    /// 이 상태는 세 군데 이상에서 만진다: WKWebView 메시지(메인 스레드), 래퍼 SDK 의
    /// setExternalWebBridgeActive(호출자 스레드), 그리고 인앱 표시 체인(코어 시리얼큐 ·
    /// URLSession 델리게이트 · 타임아웃 글로벌큐). 동기화 없이 두면 선점 자체가 성립하지 않는다.
    private static let stateLock = NSLock()

    /// 인스턴스 상태(webView / currentCampaign)를 지키는 락.
    /// webView 는 메인 스레드에서 쓰고 전달 체인(임의 큐)에서 읽는다.
    private let instanceLock = NSLock()

    private weak var _webView: WKWebView?
    private var webView: WKWebView? {
        get { instanceLock.lock(); defer { instanceLock.unlock() }; return _webView }
        set { instanceLock.lock(); _webView = newValue; instanceLock.unlock() }
    }

    /// 현재 활성화된 웹브릿지 (웹뷰가 살아있는 동안)
    private static weak var activeInstance: WebBridgeInAppMessageDelegate?

    /// 외부 인앱 메시지 콜백 (Flutter, React Native 등에서 등록)
    private static var externalInAppMessageCallback: ExternalInAppMessageCallback?
    /// 외부 웹브릿지가 활성화되었는지 여부
    private static var isExternalWebBridgeActive: Bool = false

    /// 인앱 메시지를 웹뷰에서 처리할지 여부 (false면 네이티브에서 처리)
    private let handleInAppInWebView: Bool

    /// 현재 진행 중인 웹 인앱 메시지의 캠페인 정보
    private var _currentCampaign: InAppCampaign?
    private var currentCampaign: InAppCampaign? {
        get { instanceLock.lock(); defer { instanceLock.unlock() }; return _currentCampaign }
        set { instanceLock.lock(); _currentCampaign = newValue; instanceLock.unlock() }
    }

    /// MarketapWebBridge 초기화
    /// - Parameter handleInAppInWebView: 인앱 메시지를 웹뷰에서 처리할지 여부 (기본값: true)
    @objc public init(handleInAppInWebView: Bool = true) {
        self.handleInAppInWebView = handleInAppInWebView
        super.init()
        MarketapPlugin.onWebBridgeConnected(handleInAppInWebView: handleInAppInWebView)
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
        case .setDeviceOptIn:
            handleSetDeviceOptIn(params: event.params)
        }
    }

    private func handleTrackEvent(params: [String: Any]?) {
        guard let eventName = params?["eventName"] as? String else {
            return
        }
        // 웹뷰에서 인앱 메시지를 처리하는 경우에만 활성 인스턴스로 등록
        if handleInAppInWebView {
            Self.registerActiveInstance(self)
        }
        let eventProperties = params?["eventProperties"] as? [String: Any]
        // 웹브릿지 컨텍스트 표시하여 track 호출
        MarketapPlugin.trackEvent(eventName: eventName, eventProperties: eventProperties)
    }

    private func handleIdentifyEvent(params: [String: Any]?) {
        guard let userId = params?["userId"] as? String else {
            return
        }
        let userProperties = params?["userProperties"] as? [String: Any]
        Marketap.identify(userId: userId, userProperties: userProperties)
    }

    private func handleBridgeCheck() {
        let projectId = Marketap.currentProjectId ?? "undefined"

        webView?.evaluateJavaScript("""
            window.postMessage({
                type: 'marketapBridgeAck',
                metadata: {
                    sdk_type: 'ios',
                    sdk_version: '\(MarketapConfig.nativeSdkVersion)',
                    platform: 'ios',
                    project_id: '\(projectId)'
                }
            }, '*');
        """)

        MarketapPlugin.onWebSdkInitialized()
    }

    // MARK: - 인앱 메시지 이벤트 핸들러

    private func handleInAppImpression(params: [String: Any]?) {
        guard let campaignId = params?["campaignId"] as? String,
              let messageId = params?["messageId"] as? String else {
            MarketapLogger.warn("inAppMessageImpression: missing required params")
            return
        }

        // 캠페인 정보가 있으면 impression 이벤트 전송
        if let campaign = currentCampaign, campaign.id == campaignId {
            MarketapPlugin.trackInAppImpression(
                campaignId: campaign.id,
                messageId: messageId,
                layoutSubType: campaign.layout.layoutSubType
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

        // 캠페인 정보가 있으면 클릭 이벤트 처리
        if let campaign = currentCampaign, campaign.id == campaignId {
            MarketapPlugin.trackInAppClick(
                campaignId: campaign.id,
                messageId: messageId,
                locationId: locationId,
                url: url,
                layoutSubType: campaign.layout.layoutSubType
            )
        }
    }

    private func handleInAppHide(params: [String: Any]?) {
        guard let campaignId = params?["campaignId"] as? String else {
            MarketapLogger.warn("inAppMessageHide: missing campaignId")
            return
        }

        let hideTypeString = params?["hideType"] as? String

        // 캠페인 숨김 처리
        MarketapPlugin.hideInAppMessage(campaignId: campaignId, hideType: hideTypeString)

        // 현재 캠페인 정보 클리어
        if currentCampaign?.id == campaignId {
            currentCampaign = nil
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

    private func handleSetDeviceOptIn(params: [String: Any]?) {
        let optIn = params?["optIn"] as? Bool
        Marketap.setDeviceOptIn(optIn: optIn)
    }

    private func handleInAppSetUserProperties(params: [String: Any]?) {
        guard let userProperties = params?["userProperties"] as? [String: Any] else {
            MarketapLogger.warn("inAppMessageSetUserProperties: missing userProperties")
            return
        }

        MarketapLogger.debug("Web InApp SetUserProperties")
        MarketapPlugin.setUserProperties(userProperties: userProperties)
    }
}

// MARK: - WebBridgeInAppMessageDelegate

extension MarketapWebBridge: WebBridgeInAppMessageDelegate {
    /// 캠페인을 웹으로 전달
    ///
    /// - Returns: 전달을 실제로 시작했는지. webView 가 사라졌거나 직렬화가 실패하면 false 다.
    ///   예전엔 이 경우 조용히 return 했는데, 호출자가 그걸 알 길이 없어 캠페인이 어디에도
    ///   안 뜬 채 빈도수만 소진됐다.
    func sendCampaignToWeb(campaign: InAppCampaign, messageId: String) -> Bool {
        guard let webView = webView else {
            MarketapLogger.warn("sendCampaignToWeb: webView is nil")
            return false
        }

        // 캠페인 정보를 JSON으로 직렬화
        guard let campaignData = try? JSONEncoder().encode(campaign),
              let campaignJson = String(data: campaignData, encoding: .utf8) else {
            MarketapLogger.error("sendCampaignToWeb: failed to encode campaign")
            return false
        }

        // 직렬화까지 성공한 뒤에 기록한다. 실패해서 폴백할 캠페인을 "진행 중"으로 남기면
        // 웹이 보내오는 impression/click 이 엉뚱한 캠페인에 붙는다.
        self.currentCampaign = campaign

        let shouldHandleUrlRouting = Self.shouldHandleUrlRouting

        MarketapLogger.debug("Sending campaign to web: \(campaign.id), shouldHandleUrlRouting: \(shouldHandleUrlRouting)")

        DispatchQueue.main.async {
            webView.evaluateJavaScript("""
                window.postMessage({
                    type: 'marketapShowInAppMessage',
                    campaign: \(campaignJson),
                    messageId: '\(messageId)',
                    shouldHandleUrlRouting: \(shouldHandleUrlRouting)
                }, '*');
            """) { _, error in
                if let error = error {
                    MarketapLogger.error("sendCampaignToWeb failed: \(error)")
                }
            }
        }

        return true
    }

    /// 웹에서 클릭 URL 라우팅을 직접 처리할지 여부.
    ///
    /// 전달 경로가 external(래퍼 콜백)/native(웹뷰) 둘로 갈리는데, 같은 정책을 봐야 한다.
    /// 각자 계산하면 조용히 어긋난다.
    static var shouldHandleUrlRouting: Bool {
        !Marketap.customHandlerStore.customized && ServerTimeManager.useWebClickRouting
    }

    /// 웹뷰가 살아있으면 전달을 시도할 수 있다.
    var canDeliver: Bool { webView != nil }

    /// 이 브릿지를 활성 브릿지로 등록한다. 웹에서 track 이 올 때마다 갱신된다.
    static func registerActiveInstance(_ bridge: WebBridgeInAppMessageDelegate) {
        stateLock.lock()
        activeInstance = bridge
        stateLock.unlock()
    }

    /// 선점했다가 못 쓴 네이티브 브릿지를 되돌린다. 그 사이 새로 등록된 게 있으면 건드리지 않는다.
    static func restoreActiveInstance(_ bridge: WebBridgeInAppMessageDelegate) {
        guard bridge.canDeliver else { return }
        stateLock.lock()
        if activeInstance == nil { activeInstance = bridge }
        stateLock.unlock()
    }

    /// 선점했다가 못 쓴 외부 arm 을 되돌린다. 그 사이 래퍼가 새로 arm 했으면 그대로 둔다.
    static func restoreExternalArm() {
        stateLock.lock()
        isExternalWebBridgeActive = true
        stateLock.unlock()
    }

    /// 웹브릿지 전달 권리를 **확인과 동시에 소비**한다. 성공한 쪽만 값을 받는다.
    ///
    /// 예전에는 `hasActiveWebBridge()` 로 확인한 뒤 따로 전달을 불렀는데, 전달이 브릿지를
    /// 소비하므로 두 체인이 동시에 확인을 통과하면 뒤쪽은 impression 만 남기고 전달은 아무
    /// 일도 안 일어났다(모달 폴백도 없어 복구 불가). 검사-후-사용을 하나로 합친다.
    ///
    /// 표시 권리 선점(`claimDisplay`)과 같은 모델이다: 선점에 성공한 쪽만 노출로 가고,
    /// 실패한 쪽은 다른 경로로 폴백한다.
    ///
    /// - Returns: 선점한 전달 대상. nil 이면 쓸 수 있는 웹브릿지가 없으니 호출자가
    ///   네이티브 모달로 폴백해야 한다.
    static func claimActiveWebBridge() -> WebBridgeClaim? {
        stateLock.lock()

        // 외부 웹브릿지(Flutter/RN). arm 은 1회용이라 콜백 유무와 무관하게 소비한다
        // (예전 sendCampaignToActiveWeb 과 같은 수명). 받을 콜백이 없으면 전달해도 아무 데도
        // 안 가므로 선점하지 않고, 아래 네이티브 경로 → 없으면 모달로 폴백한다.
        if isExternalWebBridgeActive {
            isExternalWebBridgeActive = false
            if let callback = externalInAppMessageCallback {
                stateLock.unlock()
                return .external(callback)
            }
        }

        // 네이티브 웹브릿지. 살아있는지 확인하기 전에 먼저 떼어낸다(웹뷰가 죽은 인스턴스는
        // 어차피 치워야 한다). 락 안에서 인스턴스 락을 겹쳐 잡지 않도록 여기서 푼다.
        let bridge = activeInstance
        activeInstance = nil
        stateLock.unlock()

        guard let bridge = bridge, bridge.canDeliver else { return nil }
        return .native(bridge)
    }

    // MARK: - External Bridge Support

    /// 외부 인앱 메시지 콜백 등록 (Flutter, React Native 등에서 사용)
    /// - Parameter callback: 인앱 메시지를 받을 콜백 함수
    @objc public static func setExternalInAppMessageCallback(_ callback: ExternalInAppMessageCallback?) {
        stateLock.lock()
        externalInAppMessageCallback = callback
        stateLock.unlock()
    }

    /// 외부 웹브릿지 활성화 상태 설정
    /// 외부에서 trackFromWebBridge 호출 시 true로 설정
    @objc public static func setExternalWebBridgeActive(_ active: Bool) {
        stateLock.lock()
        isExternalWebBridgeActive = active
        stateLock.unlock()
    }
}
