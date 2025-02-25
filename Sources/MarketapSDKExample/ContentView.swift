//
//  ContentView.swift
//  MarketapSDKExample
//
//  Created by 이동현 on 2/16/25.
//

import SwiftUI
import MarketapSDK

struct ContentView: View {
    var body: some View {
        TabView {
            ShoppingHomeView().tabItem {
                Label("Home", systemImage: "house.fill")
            }


            WebView(url: URL(string: "https://marketap.cafe24.com/shop2")!)
                .tabItem {
                    Label("Web", systemImage: "safari")
                }
        }
    }
}

#Preview {
    ContentView()
}
