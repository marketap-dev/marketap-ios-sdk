//
//  SdkIntegrationState.swift
//  MarketapSDK
//

import Foundation

enum SdkIntegrationState {
    static var handleInAppInWebView: Bool?
    static var isClickHandlerCustomized: Bool?
    static var isClickHandlerSet: Bool?
    static var isWebSdkInitialized: Bool?

    static func toJsonString() -> String {
        let payload = Payload(
            handleInAppInWebView: handleInAppInWebView,
            isClickHandlerCustomized: isClickHandlerCustomized,
            isClickHandlerSet: isClickHandlerSet,
            isWebSdkInitialized: isWebSdkInitialized
        )
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private struct Payload: Encodable {
        let handleInAppInWebView: Bool?
        let isClickHandlerCustomized: Bool?
        let isClickHandlerSet: Bool?
        let isWebSdkInitialized: Bool?

        enum CodingKeys: String, CodingKey {
            case handleInAppInWebView = "handle_in_app_in_web_view"
            case isClickHandlerCustomized = "is_click_handler_customized"
            case isClickHandlerSet = "is_click_handler_set"
            case isWebSdkInitialized = "is_web_sdk_initialized"
        }
    }
}
