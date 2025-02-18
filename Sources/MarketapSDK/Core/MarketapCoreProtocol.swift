//
//  MarketapCoreProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

protocol MarketapCoreProtocol {
    func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?)
    func logout(eventProperties: [String: Any]?)
    func track(eventName: String, eventProperties: [String: Any]?, id: String?, timestamp: Date?)
    func trackPurchase(revenue: Double, eventProperties: [String: Any]?)
    func trackRevenue(eventName: String, revenue: Double, eventProperties: [String: Any]?)
    func trackPageView(eventProperties: [String: Any]?)
    func identify(userId: String, userProperties: [String: Any]?)
    func resetIdentity()
}
