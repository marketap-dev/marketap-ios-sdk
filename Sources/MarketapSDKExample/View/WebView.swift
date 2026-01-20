//
//  WebView.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/25/25.
//

import WebKit
import SwiftUI
import MarketapSDK

struct WebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)

        let uc = webView.configuration.userContentController
        uc.removeScriptMessageHandler(forName: MarketapWebBridge.name)
        uc.add(MarketapWebBridge(), name: MarketapWebBridge.name)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // 커스텀 스킴 처리 (marketap://)
            if url.scheme == "marketap" {
                DeepLinkManager.shared.handle(url: url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
