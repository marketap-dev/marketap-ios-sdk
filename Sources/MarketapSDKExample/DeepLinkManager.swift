//
//  DeepLinkManager.swift
//  MarketapSDKExample
//
//  Created by 이동현 on 2/25/25.
//

import Foundation
import MarketapSDK

enum DeepLinkDestination: Equatable {
    case home
    case web(url: String?)
    case cart
    case user
    case product(name: String)
    case category(name: String)
}

class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    @Published var destination: DeepLinkDestination?
    @Published var selectedTab: Int = 0

    private init() {}

    func handle(url: URL) {
        guard url.scheme == "marketap" else { return }

        let host = url.host
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let params = queryItems?.reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        } ?? [:]

        switch host {
        case "home":
            selectedTab = 0
            destination = .home

        case "web":
            selectedTab = 1
            if let urlString = params["url"] {
                destination = .web(url: urlString)
            } else {
                destination = .web(url: nil)
            }

        case "cart":
            selectedTab = 0
            destination = .cart

        case "user":
            selectedTab = 0
            destination = .user

        case "product":
            selectedTab = 0
            if let name = params["name"] {
                destination = .product(name: name)
            }

        case "category":
            selectedTab = 0
            if let name = params["name"] {
                destination = .category(name: name)
            }

        case "track":
            // 테스트용 이벤트 트래킹
            let eventName = params["event"] ?? "test_deeplink_event"
            var eventProperties: [String: Any] = ["source": "deeplink"]
            for (key, value) in params where key != "event" {
                eventProperties[key] = value
            }
            Marketap.track(eventName: eventName, eventProperties: eventProperties)

        case "identify":
            // 테스트용 사용자 식별
            if let userId = params["userId"] {
                var userProperties: [String: Any] = [:]
                for (key, value) in params where key != "userId" {
                    userProperties[key] = value
                }
                Marketap.identify(userId: userId, userProperties: userProperties.isEmpty ? nil : userProperties)
            }

        default:
            break
        }
    }

    func clearDestination() {
        destination = nil
    }
}
