//
//  MarketapClientImpl+Event.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import Foundation

extension MarketapClientImpl {
    func setDevice(additionalInfo: [String: Any]?) {

    }

    // MARK: - User Authentication
    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?) {
        
    }

    func logout(properties: [String: Any]?) {
        
    }

    // MARK: - Event Tracking
    func track(name: String, properties: [String: Any]?, id: String?, timestamp: Date?) {

    }

    func trackPurchase(revenue: Double, properties: [String: Any]?) {
        
    }

    func trackRevenue(name: String, revenue: Double, properties: [String: Any]?) {
        
    }

    func trackPageView(properties: [String: Any]?) {
        
    }

    // MARK: - User Profile Management
    func identify(userId: String, properties: [String: Any]?) {
        
    }

    func resetIdentity() {
        
    }
}
