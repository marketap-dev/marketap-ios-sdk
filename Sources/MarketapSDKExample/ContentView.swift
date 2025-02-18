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
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")

            Button("구매하기") {
                Marketap.trackPageView(eventProperties: nil)

            }
        }
        .padding()
        .onAppear {
            Marketap.trackPurchase(revenue: 10000, eventProperties: nil)
        }
    }
}

#Preview {
    ContentView()
}
