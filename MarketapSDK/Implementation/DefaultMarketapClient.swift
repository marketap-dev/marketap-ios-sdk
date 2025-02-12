//
//  DefaultMarketapClient.swift
//
//  Created by 이동현 on 2/11/25.
//

import WebKit

enum MarketapJSMessage: String, CaseIterable {
    case onInAppMessageShow
    case onInAppMessageHide

    var name: String {
        return self.rawValue
    }

    var jsFunctionDefinition: String {
        return """
        \(name): function() {
            window.webkit.messageHandlers.\(name).postMessage(null);
        }
        """
    }
}

class DefaultMarketapClient: NSObject, MarketapClient, WKNavigationDelegate, WKScriptMessageHandler {
    
    // MARK: - Properties
    private let window = MarketapWindow()
    private var webView: WKWebView! {
        window.webView
    }
    
    private var webViewLoaded = false
    private var pendingJSExecutions: [(String, [Any])] = []
    
    // MARK: - Initialization
    override init() {
        super.init()
        window.configureWebView(scriptMessageHandler: self, navigationDelegate: self)
    }
    
    // MARK: - WebView Navigation Delegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webViewLoaded = true
        processPendingJSExecutions()
        registerMarketapNative()
    }
    
    // MARK: - JavaScript Bridge Registration
    private func registerMarketapNative() {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        
        let topSafeArea = keyWindow?.safeAreaInsets.top ?? 0
        let bottomSafeArea = keyWindow?.safeAreaInsets.bottom ?? 0

        let eventHandlers = MarketapJSMessage.allCases.map { $0.jsFunctionDefinition }.joined(separator: ",\n  ")

        let jsScript = """
        window._marketap_native = {
          \(eventHandlers),
          topSafeArea: \(topSafeArea),
          bottomSafeArea: \(bottomSafeArea)
        };
        """

        executeJSFunction("window.eval", withArguments: jsScript)
        Marketap.initialize(config: ["projectId": "xziewjm"])
    }
    
    // MARK: - JavaScript Message Handling
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let jsEvent = MarketapJSMessage(rawValue: message.name) else {
            return
        }
        
        switch jsEvent {
        case .onInAppMessageShow:
            presentViewController()
        case .onInAppMessageHide:
            dismissViewController()
        }
    }

    // MARK: - WebView Presentation
    private func presentViewController() {
        window.showWebView()
    }

    private func dismissViewController() {
        window.hideWebView()
    }

    // MARK: - JavaScript Execution
    private func executeJSFunction(_ function: String, withArguments args: Any...) {
        let formattedArgs = args.map { formatJSArgument($0) }.joined(separator: ", ")
        let jsScript = "await window._marketap_core.\(function)(\(formattedArgs));"
                
        if webViewLoaded {
            webView.callAsyncJavaScript(jsScript, arguments: [:], in: nil, in: .page)
        } else {
            pendingJSExecutions.append((function, args))
        }
    }
    
    private func processPendingJSExecutions() {
        guard webViewLoaded else { return }
        
        for (function, args) in pendingJSExecutions {
            executeJSFunction(function, withArguments: args)
        }
        pendingJSExecutions.removeAll()
    }
    
    // MARK: - JSON Utilities
    private func jsonString(from dictionary: [String: Any]?) -> String {
        guard let dictionary = dictionary,
              let jsonData = try? JSONSerialization.data(withJSONObject: dictionary, options: []) else {
            return "{}"
        }
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
    
    private func formatJSArgument(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string == "null" ? "null" : "\"\(string)\""
        case let number as NSNumber:
            return "\(number)"
        case let array as [Any]:
            return "[\(array.map { formatJSArgument($0) }.joined(separator: ", "))]"
        case let dictionary as [String: Any]:
            return jsonString(from: dictionary)
        case Optional<Any>.none:
            return "null"
        default:
            return "\"\(value)\""
        }
    }

    // MARK: - SDK Core Methods
    func initialize(config: [String: Any]) {
        executeJSFunction("initialize", withArguments: config)
        setDevice(additionalInfo: nil)
    }

    func setPushToken(token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        setDevice(additionalInfo: ["token": tokenString])
    }

    func setDevice(additionalInfo: [String: Any]?) {
        let deviceInfo = getDeviceInfo().merging(additionalInfo ?? [:]) { _, new in new }
        executeJSFunction("setDevice", withArguments: deviceInfo)
    }

    // MARK: - User Authentication
    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?) {
        executeJSFunction("login", withArguments: userId, userProperties ?? [:], eventProperties ?? [:])
    }

    func logout(properties: [String: Any]?) {
        executeJSFunction("logout", withArguments: properties ?? [:])
    }

    // MARK: - Event Tracking
    func track(name: String, properties: [String: Any]?, id: String?, timestamp: Date?) {
        let timestampString = timestamp.map { "\($0.timeIntervalSince1970)" } ?? "null"
        executeJSFunction("track", withArguments: name, properties ?? [:], id ?? "null", timestampString)
    }

    func trackPurchase(revenue: Double, properties: [String: Any]?) {
        executeJSFunction("trackPurchase", withArguments: revenue, properties ?? [:])
    }

    func trackRevenue(name: String, revenue: Double, properties: [String: Any]?) {
        executeJSFunction("trackRevenue", withArguments: name, revenue, properties ?? [:])
    }

    func trackPageView(properties: [String: Any]?) {
        executeJSFunction("trackPageView", withArguments: properties ?? [:])
    }

    // MARK: - User Profile Management
    func identify(userId: String, properties: [String: Any]?) {
        executeJSFunction("identify", withArguments: userId, properties ?? [:])
    }

    func resetIdentity() {
        executeJSFunction("resetIdentity")
    }
}
