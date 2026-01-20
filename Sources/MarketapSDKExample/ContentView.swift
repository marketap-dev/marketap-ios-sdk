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


            WebView(url: URL(string: "http://localhost:8090/marketap-web-sdk/test_me.html?_ijt=qfmqoofflu4s3j5j7rn873l8cf&_ij_reload=RELOAD_ON_SAVE")!)
                .tabItem {
                    Label("Web", systemImage: "safari")
                }
        }
    }
}

#Preview {
    ContentView()
}
