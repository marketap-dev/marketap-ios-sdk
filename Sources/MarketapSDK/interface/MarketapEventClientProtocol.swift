//
//  MarketapEventClientProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import Foundation

public protocol MarketapEventClientProtocol {
    // MARK: - User Authentication

    /// - Parameters:
    ///   - userId: A unique identifier for the user.
    ///   - userProperties: A dictionary containing user-specific attributes (optional).
    ///   - eventProperties: Additional properties related to the event (optional).
    func signup(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?, persistUser: Bool)

    /// Logs in the user and associates them with their properties.
    /// This method sets the user ID and updates user-specific attributes.
    /// Optionally, an event can be tracked to log the login action.
    ///
    /// - Parameters:
    ///   - userId: A unique identifier for the user.
    ///   - userProperties: A dictionary containing user-specific attributes (optional).
    ///   - eventProperties: Additional properties related to the login event (optional).
    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?)

    /// Logs out the current user and removes their associated data.
    /// This method resets the stored user ID and optionally tracks a logout event.
    ///
    /// - Parameter eventProperties: Additional properties related to the logout event (optional).
    func logout(eventProperties: [String: Any]?)

    // MARK: - Event Tracking

    /// Tracks a custom event with optional metadata.
    /// This method allows tracking of user interactions, feature usage, or other relevant actions.
    ///
    /// - Parameters:
    ///   - eventName: The name of the event to track.
    ///   - eventProperties: A dictionary containing additional event-specific attributes (optional).
    ///   - id: A unique identifier for the event, useful for deduplication (optional).
    ///   - timestamp: The timestamp when the event occurred (optional, defaults to the current time).
    func track(eventName: String, eventProperties: [String: Any]?, id: String?, timestamp: Date?)

    /// Tracks a purchase event, recording revenue-related details.
    /// This method is specifically designed for e-commerce or transaction-based revenue tracking.
    ///
    /// - Parameters:
    ///   - revenue: The revenue amount generated from the purchase.
    ///   - eventProperties: Additional properties related to the purchase event (optional).
    func trackPurchase(revenue: Double, eventProperties: [String: Any]?)

    /// Tracks a revenue-related event, allowing flexibility beyond purchases.
    /// This method can be used to record any event associated with revenue generation.
    ///
    /// - Parameters:
    ///   - eventName: The name of the revenue-related event (e.g., "subscription_renewed").
    ///   - revenue: The amount of revenue generated.
    ///   - eventProperties: Additional properties related to the revenue event (optional).
    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String: Any]?)

    /// Tracks a page view event, useful for analytics and engagement tracking.
    /// This method is commonly used for logging screen views in mobile apps or web pages.
    ///
    /// - Parameter eventProperties: Additional properties related to the page view event (optional).
    func trackPageView(eventProperties: [String: Any]?)

    // MARK: - User Profile Management

    /// Identifies or updates a user's profile information.
    /// This method sets the user ID and updates user attributes for personalization or analytics.
    ///
    /// - Parameters:
    ///   - userId: The unique identifier for the user.
    ///   - userProperties: A dictionary containing properties to associate with the user (optional).
    func identify(userId: String, userProperties: [String: Any]?)

    /// Resets the user's identity by clearing their stored profile.
    /// This method is used for logging out a user or anonymizing their data for privacy compliance.
    func resetIdentity()

    // MARK: - Internal Methods (WebBridge)

    /// Tracks an event from the web bridge context.
    /// In-app campaigns will be delegated to web for display.
    /// - Parameters:
    ///   - eventName: The name of the event to track.
    ///   - eventProperties: Additional properties related to the event (optional).
    func trackFromWebBridge(eventName: String, eventProperties: [String: Any]?)

    /// Updates user properties without requiring a user ID.
    /// - Parameter userProperties: A dictionary containing properties to update.
    func setUserProperties(userProperties: [String: Any])
}
