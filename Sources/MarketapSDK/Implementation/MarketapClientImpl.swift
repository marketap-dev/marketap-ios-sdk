//
//  MarketapClientImpl.swift
//
//  Created by 이동현 on 2/11/25.
//

import WebKit
import MarketapSDKCore

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

class MarketapClientImpl: NSObject, MarketapClient, WKNavigationDelegate, WKScriptMessageHandler {
    
    func initialize(config: [String : Any]) {
        
    }
    
        
    // MARK: - Properties
    let window = MarketapWindow()
    var webView: WKWebView? {
        window.webView
    }
    
    private var webViewLoaded = false
    private var pendingJSExecutions: [(String, [Any])] = []
    
    
    private lazy var core: MarketapCore = NativeMarketapCore(nativeConfig: self)
    
    // MARK: - Initialization
    override init() {
        super.init()
        
        let core = NativeMarketapCore(nativeConfig: self)
                
        window.configureWebView(scriptMessageHandler: self, navigationDelegate: self)
    }
    
    // MARK: - WebView Navigation Delegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webViewLoaded = true
        registerMarketapNative()
        processPendingJSExecutions()
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

        webView?.evaluateJavaScript(jsScript)
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
    func initialize(projectId: String) {
        core.initialize(config: MarketapConfig(projectId: projectId))
    }
}

extension MarketapClientImpl: NativeMarketapConfig {
    @objc func getDevice() -> Device {
        return getDeviceInfo()
    }
    
    @objc func hideInAppMessage() {
        window.showWebView()
    }
    
    @objc func showInAppMessage(html: String) {
        window.hideWebView()
    }
}
