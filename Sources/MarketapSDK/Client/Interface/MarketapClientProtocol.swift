//
//  MarketapClientProtocol.swift
//  IOSPushTest
//
//  Created by 이동현 on 2/11/25.
//

import Foundation

/// Defines the required methods for integrating Marketap SDK.
public protocol MarketapClientProtocol: MarketapEventClientProtocol, MarketapNotificationClientProtocol {
    /// Initializes the SDK with a configuration.
    /// - Parameter config: Dictionary containing configuration settings.
    func initialize(config: [String: Any])
}
