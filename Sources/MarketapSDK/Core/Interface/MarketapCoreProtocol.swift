//
//  MarketapCoreProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

protocol MarketapCoreProtocol {
    // Essential for tracking the connection of the user and the device
    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?)

    func logout(eventProperties: [String: Any]?)

    // Custom events
    func track(eventName: String, eventProperties: [String: Any]?, id: String?, timestamp: Date?)

    // Purchase event
    func trackPurchase(revenue: Double, eventProperties: [String: Any]?)

    // Event to track revenue (not purchase)
    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String: Any]?)

    // Page view event
    func trackPageView(eventProperties: [String: Any]?)

    // Default user properties
    func identify(userId: String, userProperties: [String: Any]?)

    // Resets user identity (for logout or anonymization)
    func resetIdentity()
}
