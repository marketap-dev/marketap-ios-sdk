//
//  MarketapJSMessage.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

import Foundation

enum MarketapJSMessage: String, CaseIterable {
    case hide
    case click
    case track
    case setUserProperties

    var params: [String] {
        switch self {
        case .hide:
            return ["hide_type"]
        case .click:
            return ["mkt_location_id", "url"]
        case .track:
            return ["event_name", "event_properties_json"]
        case .setUserProperties:
            return ["user_properties_json"]
        }
    }

    var name: String {
        return self.rawValue
    }

    var jsFunctionDefinition: String {
        if params.isEmpty {
            return """
            \(name): function() {
                window.webkit.messageHandlers.\(name).postMessage();
            }
            """
        }

        let formattedParams = params.joined(separator: ", ")

        return """
        \(name): function(\(formattedParams)) {
            window.webkit.messageHandlers.\(name).postMessage([\(formattedParams)]);
        }
        """
    }
}
