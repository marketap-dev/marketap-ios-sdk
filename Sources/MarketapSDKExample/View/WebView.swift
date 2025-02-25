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
        return WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)

        webView.configuration.userContentController.add(
            MarketapWebBridge(),
            name: MarketapWebBridge.name
        )
    }
}
