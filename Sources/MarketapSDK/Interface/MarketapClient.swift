//
//  MarketapClient.swift
//  IOSPushTest
//
//  Created by 이동현 on 2/11/25.
//

import Foundation

/// Defines the required methods for integrating Marketap SDK.
public protocol MarketapClient {
    
    /// Registers the push token for the device.
    /// - Parameter token: The device's push notification token.
    func setPushToken(token: Data)

    // MARK: - SDK Initialization
    
    /// Initializes the SDK with a configuration.
    /// - Parameter config: Dictionary containing configuration settings.
    func initialize(config: [String: Any])

    // MARK: - User Authentication
    
    /// Logs in the user and associates them with their properties.
    /// - Parameters:
    ///   - userId: The unique identifier of the user.
    ///   - userProperties: Additional properties related to the user.
    ///   - eventProperties: Event-specific properties (optional).
    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?)

    /// Logs out the user and optionally tracks logout properties.
    /// - Parameter properties: Additional properties to track upon logout (optional).
    func logout(properties: [String: Any]?)

    // MARK: - Event Tracking
    
    /// Tracks a custom event.
    /// - Parameters:
    ///   - name: The event name.
    ///   - properties: Additional properties associated with the event.
    ///   - id: Optional unique identifier for the event.
    ///   - timestamp: Optional timestamp for the event.
    func track(name: String, properties: [String: Any]?, id: String?, timestamp: Date?)

    /// Tracks a purchase event.
    /// - Parameters:
    ///   - revenue: The revenue amount for the purchase.
    ///   - properties: Additional properties related to the purchase (optional).
    func trackPurchase(revenue: Double, properties: [String: Any]?)

    /// Tracks general revenue-related events.
    /// - Parameters:
    ///   - name: The name of the revenue event.
    ///   - revenue: The revenue amount.
    ///   - properties: Additional properties associated with the event (optional).
    func trackRevenue(name: String, revenue: Double, properties: [String: Any]?)

    /// Tracks a page view event.
    /// - Parameter properties: Additional properties related to the page view (optional).
    func trackPageView(properties: [String: Any]?)

    // MARK: - User Profile Management
    
    /// Updates the user's profile with new properties.
    /// - Parameters:
    ///   - userId: The unique identifier of the user.
    ///   - properties: The properties to update.
    func identify(userId: String, properties: [String: Any]?)

    /// Resets the user's profile, either logging them out or anonymizing their data.
    func resetIdentity()
}
