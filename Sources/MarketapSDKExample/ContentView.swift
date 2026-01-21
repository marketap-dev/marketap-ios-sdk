//
//  ContentView.swift
//  MarketapSDKExample
//
//  Created by 이동현 on 2/16/25.
//

import SwiftUI
import MarketapSDK

struct ContentView: View {
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @State private var webViewUrl: URL = URL(string: "https://static.marketap.io/sdk/dev/test_me.html")!

    var body: some View {
        TabView(selection: $deepLinkManager.selectedTab) {
            ShoppingHomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            WebView(url: webViewUrl)
                .tabItem {
                    Label("Web", systemImage: "safari")
                }
                .tag(1)
        }
        .onChange(of: deepLinkManager.destination) { destination in
            guard let destination = destination else { return }
            if case .web(let urlString) = destination,
               let urlString = urlString,
               let url = URL(string: urlString) {
                webViewUrl = url
            }
        }
    }
}

#Preview {
    ContentView()
}
