//
//  MarketapWebBridge.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/25/25.
//

import WebKit
import UIKit

/// 외부에서 인앱 메시지를 받기 위한 콜백 타입 (Flutter, React Native 등)
public typealias ExternalInAppMessageCallback = (_ campaign: [String: Any], _ messageId: String, _ hasCustomClickHandler: Bool) -> Void

@objc public class MarketapWebBridge: NSObject, WKScriptMessageHandler {
    public static let name = "marketap"

    private static let stateLock = NSLock()

    private let instanceLock = NSLock()

    private weak var _webView: WKWebView?
    private var webView: WKWebView? {
        get { instanceLock.lock(); defer { instanceLock.unlock() }; return _webView }
        set { instanceLock.lock(); _webView = newValue; instanceLock.unlock() }
    }

    /// 외부 인앱 메시지 콜백 (Flutter, React Native 등에서 등록)
    /// 외부 웹브릿지가 활성화되었는지 여부
    private static var isExternalWebBridgeActive: Bool = false
    private static var activeExternalWebViewId: String = ExternalWebViewHost.defaultId

    /// true 면 이 웹뷰에서 시작된 인앱 메시지의 링크를 이 웹뷰에서 열고, "이 페이지에서만" 플로팅을 페이지 이탈 때 닫는다.
    private let handleInAppInWebView: Bool

    private var pageWatcher: WebViewWindowWatcher?
    private weak var pageWatchOwner: AnyObject?

    /// 현재 진행 중인 웹 인앱 메시지의 캠페인 정보
    private var _currentCampaign: InAppCampaign?
    private var currentCampaign: InAppCampaign? {
        get { instanceLock.lock(); defer { instanceLock.unlock() }; return _currentCampaign }
        set { instanceLock.lock(); _currentCampaign = newValue; instanceLock.unlock() }
    }

    /// MarketapWebBridge 초기화
    /// - Parameter handleInAppInWebView: 이 웹뷰에서 시작된 인앱 메시지를 웹뷰와 연동할지 여부 (기본값: true)
    @objc public init(handleInAppInWebView: Bool = true) {
        self.handleInAppInWebView = handleInAppInWebView
        super.init()
        MarketapPlugin.onWebBridgeConnected(handleInAppInWebView: handleInAppInWebView)
    }

    deinit {
        let watcher = pageWatcher
        DispatchQueue.main.async { watcher?.detach() }
        if handleInAppInWebView {
            Self.inAppService?.originDidDisappear(ObjectIdentifier(self))
        }
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
        case .addressChanged:
            handleAddressChanged()
        case .setDeviceOptIn:
            handleSetDeviceOptIn(params: event.params)
        }
    }

    private func handleTrackEvent(params: [String: Any]?) {
        guard let eventName = params?["eventName"] as? String else {
            return
        }
        let eventProperties = params?["eventProperties"] as? [String: Any]
        (Marketap.client as? MarketapCore)?.trackFromWebBridge(
            eventName: eventName,
            eventProperties: eventProperties,
            origin: handleInAppInWebView ? self : nil
        )
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
                    project_id: '\(projectId)',
                    handles_address_change: true
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

    private func handleAddressChanged() {
        guard handleInAppInWebView else { return }
        Self.inAppService?.originDidLeavePage(ObjectIdentifier(self))
    }

    static var inAppService: InAppMessageServiceProtocol? {
        (Marketap._client as? MarketapCore)?.inAppMessageService
    }

    private func evaluateOnMain(_ script: String, label: String) {
        guard let webView = webView else { return }
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    MarketapLogger.error("\(label) failed: \(error)")
                }
            }
        }
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

// MARK: - Static bridge state

extension MarketapWebBridge {
    /// 래퍼가 `setExternalWebBridgeActive(true)` 로 표시한 이벤트면 그 래퍼 웹뷰를 출처로 돌려주고 표시를 지운다.
    static func consumeExternalOrigin() -> InAppWebOrigin? {
        stateLock.lock()
        let active = isExternalWebBridgeActive
        let webViewId = activeExternalWebViewId
        isExternalWebBridgeActive = false
        stateLock.unlock()
        guard active else { return nil }
        return ExternalWebViewHost.host(for: webViewId)
    }

    // MARK: - External Bridge Support

    /// 래퍼용. 앱이 캠페인을 웹으로 넘기지 않으므로 등록한 콜백은 호출되지 않는다.
    @objc public static func setExternalInAppMessageCallback(_ callback: ExternalInAppMessageCallback?) {
        MarketapLogger.debug("setExternalInAppMessageCallback: campaigns are not delivered to web (registered=\(callback != nil))")
    }

    /// 다음 `MarketapPlugin.trackEvent` 가 handleInAppInWebView 가 켜진 래퍼 웹뷰에서 왔는지 표시한다.
    @objc public static func setExternalWebBridgeActive(_ active: Bool) {
        setExternalWebBridgeActive(active, webViewId: ExternalWebViewHost.defaultId)
    }

    /// 다음 `MarketapPlugin.trackEvent` 가 handleInAppInWebView 가 켜진 래퍼 웹뷰 `webViewId` 에서 왔는지 표시한다.
    @objc public static func setExternalWebBridgeActive(_ active: Bool, webViewId: String) {
        stateLock.lock()
        isExternalWebBridgeActive = active
        activeExternalWebViewId = webViewId
        stateLock.unlock()
    }

    /// 앱이 래퍼 웹뷰에 보내는 명령을 받을 콜백. type 은 "openUrl"(payload `url`, 웹뷰를 구분하는 래퍼면 `webViewId`)이고 메인 스레드에서 불린다.
    @objc public static func setExternalWebViewCommandCallback(_ callback: ((String, [String: Any]) -> Void)?) {
        ExternalWebViewHost.command = callback
    }

    /// 래퍼 웹뷰 브리지가 생기면 true, 해제(dispose)되면 false 로 알린다.
    @objc public static func setExternalWebViewAttached(_ attached: Bool) {
        setExternalWebViewAttached(attached, webViewId: ExternalWebViewHost.defaultId)
    }

    /// 래퍼 웹뷰 `webViewId` 의 브리지가 생기면 true, 해제(dispose)되면 false 로 알린다.
    @objc public static func setExternalWebViewAttached(_ attached: Bool, webViewId: String) {
        if attached {
            ExternalWebViewHost.host(for: webViewId).attached = true
            return
        }
        guard let host = ExternalWebViewHost.existingHost(for: webViewId) else { return }
        host.attached = false
        ExternalWebViewHost.remove(id: webViewId)
        inAppService?.originDidDisappear(ObjectIdentifier(host))
    }

    /// 래퍼가 웹 SDK 에서 받은 주소 변경(addressChanged)을 전달한다.
    @objc public static func handleExternalAddressChanged() {
        handleExternalAddressChanged(webViewId: ExternalWebViewHost.defaultId)
    }

    /// 래퍼 웹뷰 `webViewId` 가 웹 SDK 에서 받은 주소 변경(addressChanged)을 전달한다.
    @objc public static func handleExternalAddressChanged(webViewId: String) {
        guard let host = ExternalWebViewHost.existingHost(for: webViewId) else { return }
        inAppService?.originDidLeavePage(ObjectIdentifier(host))
    }
}

// MARK: - InAppWebOrigin

extension MarketapWebBridge: InAppWebOrigin {
    var isWebViewVisible: Bool { webView?.window != nil }

    func openInWebView(url: String) {
        guard let literal = JavaScriptLiteral.string(url) else { return }
        evaluateOnMain("window.location.href = \(literal);", label: "openInWebView")
    }

    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool {
        guard let webView = webView, webView.window != nil else { return false }
        pageWatcher?.detach()
        let watcher = WebViewWindowWatcher { inWindow in
            if !inWindow { onLeave() }
        }
        webView.addSubview(watcher)
        pageWatcher = watcher
        pageWatchOwner = owner
        return true
    }

    func endWatchingWindow(owner: AnyObject) {
        guard pageWatchOwner === owner else { return }
        pageWatcher?.detach()
        pageWatcher = nil
        pageWatchOwner = nil
    }
}

/// 웹뷰에 붙여 창에서 떨어지는 순간을 받는 보이지 않는 뷰.
final class WebViewWindowWatcher: UIView {
    private var onWindowChange: ((Bool) -> Void)?

    init(onWindowChange: @escaping (Bool) -> Void) {
        self.onWindowChange = onWindowChange
        super.init(frame: .zero)
        isHidden = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }

    /// 떼어내는 것 자체가 창에서 떨어짐으로 읽히지 않도록 알림을 먼저 끊는다.
    func detach() {
        onWindowChange = nil
        removeFromSuperview()
    }
}
