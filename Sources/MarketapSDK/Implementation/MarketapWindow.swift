//
//  MarketapWindow.swift
//
//  Created by 이동현 on 2/11/25.
//

import WebKit
import UIKit

class MarketapWindow: UIWindow {
    
    // MARK: - Constants
    static let sdkURL = URL(string: "https://static.marketap.io/sdk/test-ios.html")!
    
    // MARK: - Properties
    private(set) var webView: WKWebView!
    
    // MARK: - Initialization
    init() {
        super.init(frame: UIScreen.main.bounds)
        windowLevel = UIWindow.Level.statusBar
        isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - WebView Configuration
    func configureWebView(scriptMessageHandler: WKScriptMessageHandler, navigationDelegate: WKNavigationDelegate) {
        DispatchQueue.main.async {
            let webView = self.createWebView(scriptMessageHandler: scriptMessageHandler, navigationDelegate: navigationDelegate)
            self.webView = webView
            self.addSubview(webView)
        }
    }
    
    private func createWebView(scriptMessageHandler: WKScriptMessageHandler, navigationDelegate: WKNavigationDelegate) -> WKWebView {
        let webConfig = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        
        // Register JavaScript message handlers
        MarketapJSMessage.allCases.forEach { message in
            contentController.add(scriptMessageHandler, name: message.name)
        }
        contentController.add(scriptMessageHandler, name: "print")
        
        webConfig.websiteDataStore = WKWebsiteDataStore.default()
        webConfig.userContentController = contentController
        
        let webView = WKWebView(frame: bounds, configuration: webConfig)
        webView.navigationDelegate = navigationDelegate
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.load(URLRequest(url: MarketapWindow.sdkURL))
        
        return webView
    }
    
    // MARK: - WebView Visibility
    func showWebView() {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                self.windowScene = windowScene
            }
            self.isHidden = false
        }
    }

    func hideWebView() {
        DispatchQueue.main.async {
            self.isHidden = true
        }
    }
}
