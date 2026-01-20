//
//  Marketap+Track.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/12/25.
//

import Foundation
import UIKit

extension Marketap {

    /// 회원 가입, 유저 및 이벤트 속성을 설정합니다.
    /// - Parameters:
    ///   - userId: 유저의 고유 식별자 (ID)
    ///   - userProperties: 유저 속성 (선택)
    ///   - eventProperties: 기록할 이벤트 속성 (선택)
    ///   - persistUser: 가입 이후 로그인 상태 유지
    @objc public static func signup(
        userId: String,
        userProperties: [String: Any]? = nil,
        eventProperties: [String: Any]? = nil,
        persistUser: Bool = true
    ) {
        client?.signup(userId: userId, userProperties: userProperties, eventProperties: eventProperties, persistUser: persistUser)
    }

    /// 유저를 로그인 처리하고, 유저 및 이벤트 속성을 설정합니다.
    /// - Parameters:
    ///   - userId: 유저의 고유 식별자 (ID)
    ///   - userProperties: 유저 속성 (선택)
    ///   - eventProperties: 로그인과 함께 기록할 이벤트 속성 (선택)
    @objc public static func login(userId: String, userProperties: [String: Any]? = nil, eventProperties: [String: Any]? = nil) {
        client?.login(userId: userId, userProperties: userProperties, eventProperties: eventProperties)
    }

    /// 유저를 로그아웃 처리합니다.
    /// - Parameter eventProperties: 로그아웃과 함께 기록할 이벤트 속성 (선택)
    @objc public static func logout(eventProperties: [String: Any]? = nil) {
        client?.logout(eventProperties: eventProperties)
    }

    /// 커스텀 이벤트를 추적합니다.
    /// - Parameters:
    ///   - eventName: 추적할 이벤트 이름
    ///   - eventProperties: 이벤트 속성 (선택)
    @objc public static func track(eventName: String, eventProperties: [String: Any]? = nil) {
        client?.track(eventName: eventName, eventProperties: eventProperties, id: nil, timestamp: Date())
    }

    /// 구매 이벤트를 추적합니다.
    /// - Parameters:
    ///   - revenue: 구매 금액
    ///   - eventProperties: 구매 관련 속성 (선택)
    @objc public static func trackPurchase(revenue: Double, eventProperties: [String: Any]? = nil) {
        client?.trackPurchase(revenue: revenue, eventProperties: eventProperties)
    }

    /// 특정 매출 이벤트를 추적합니다.
    /// - Parameters:
    ///   - eventName: 매출과 관련된 이벤트 이름 (예: "구독 시작", "아이템 구매")
    ///   - revenue: 매출 금액
    ///   - eventProperties: 이벤트 속성 (선택)
    @objc public static func trackRevenue(eventName: String, revenue: Double, eventProperties: [String: Any]? = nil) {
        client?.trackRevenue(eventName: eventName, revenue: revenue, eventProperties: eventProperties)
    }

    /// 페이지 방문 이벤트를 추적합니다.
    /// - Parameter eventProperties: 페이지 방문과 관련된 추가 속성 (선택)
    @objc public static func trackPageView(eventProperties: [String: Any]? = nil) {
        client?.trackPageView(eventProperties: eventProperties)
    }

    /// 유저의 프로필을 업데이트합니다.
    /// - Parameters:
    ///   - userId: 유저의 고유 식별자 (ID)
    ///   - userProperties: 유저 속성
    @objc public static func identify(userId: String, userProperties: [String: Any]? = nil) {
        client?.identify(userId: userId, userProperties: userProperties)
    }

    /// 유저 프로필을 초기화하여 로그아웃 상태로 만들거나 익명 유저로 전환합니다.
    @objc public static func resetIdentity() {
        client?.resetIdentity()
    }

    /// 유저 속성을 업데이트합니다.
    /// - Parameter userProperties: 유저 속성
    @objc public static func setUserProperties(userProperties: [String: Any]) {
        client?.setUserProperties(userProperties: userProperties)
    }

    // MARK: - WebBridge Methods

    /// 웹브릿지에서 호출된 이벤트를 추적합니다.
    /// 인앱 캠페인이 웹으로 위임되어 처리됩니다.
    /// - Parameters:
    ///   - eventName: 추적할 이벤트 이름
    ///   - eventProperties: 이벤트 속성 (선택)
    @objc public static func trackFromWebBridge(eventName: String, eventProperties: [String: Any]? = nil) {
        client?.trackFromWebBridge(eventName: eventName, eventProperties: eventProperties)
    }
}
