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

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
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
}
