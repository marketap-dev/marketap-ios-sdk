//
//  Marketap+Track.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/12/25.
//

import Foundation
import UIKit

extension Marketap {
         
    // MARK: - SDK 초기화
    
    /// 디바이스의 푸시 토큰을 설정합니다.
    /// - Parameter token: 디바이스의 푸시 알림 토큰
    @objc public static func setPushToken(token: Data) {
        client.setPushToken(token: token)
    }
    
    /// SDK를 설정값과 함께 초기화합니다.
    /// - Parameter config: SDK 설정 정보를 담은 딕셔너리
    @objc public static func initialize(config: [String: Any]) {
        client.initialize(config: config)
    }

    // MARK: - 유저 인증
    
    /// 유저 로그인 및 유저/이벤트 속성을 설정합니다.
    /// - Parameters:
    ///   - userId: 유저의 고유 ID
    ///   - userProperties: 유저 속성
    ///   - eventProperties: 이벤트 속성 (선택)
    @objc public static func login(userId: String, userProperties: [String: Any]?, eventProperties: [String: Any]?) {
        client.login(userId: userId, userProperties: userProperties, eventProperties: eventProperties)
    }

    /// 유저 로그아웃을 수행하며, 이벤트 속성을 설정할 수 있습니다.
    /// - Parameter properties: 로그아웃 시 기록할 이벤트 속성 (선택)
    @objc public static func logout(properties: [String: Any]?) {
        client.logout(properties: properties)
    }

    // MARK: - 이벤트 트래킹
    
    /// 커스텀 이벤트를 트래킹합니다.
    /// - Parameters:
    ///   - name: 이벤트 이름.
    ///   - properties: 이벤트 속성 (선택)
    ///   - id: 이벤트의 고유 ID (선택)
    ///   - timestamp: 이벤트 발생 시간 (선택)
    @objc public static func track(name: String, properties: [String: Any]?, id: String?, timestamp: Date?) {
        client.track(name: name, properties: properties, id: id, timestamp: timestamp)
    }

    /// 구매 이벤트를 트래킹합니다.
    /// - Parameters:
    ///   - revenue: 구매 금액
    ///   - properties: 구매 관련 이벤트 속성 (선택)
    @objc public static func trackPurchase(revenue: Double, properties: [String: Any]?) {
        client.trackPurchase(revenue: revenue, properties: properties)
    }

    /// 구매 외 일반 매출 관련 이벤트를 트래킹합니다.
    /// - Parameters:
    ///   - name: 매출 이벤트 이름
    ///   - revenue: 매출 금액
    ///   - properties: 이벤트 속성 (선택)
    @objc public static func trackRevenue(name: String, revenue: Double, properties: [String: Any]?) {
        client.trackRevenue(name: name, revenue: revenue, properties: properties)
    }

    /// 페이지뷰 이벤트를 트래킹합니다.
    /// - Parameter properties: 페이지뷰 관련 이벤트 속성 (선택)
    @objc public static func trackPageView(properties: [String: Any]?) {
        client.trackPageView(properties: properties)
    }

    // MARK: - 유저 프로필 관리
    
    /// 유저 프로필을 업데이트합니다.
    /// - Parameters:
    ///   - userId: 유저의 고유 ID
    ///   - properties: 업데이트할 유저 속성
    @objc public static func identify(userId: String, properties: [String: Any]?) {
        client.identify(userId: userId, properties: properties)
    }

    /// 유저 프로필을 초기화합니다 (로그아웃 또는 익명화)
    @objc public static func resetIdentity() {
        client.resetIdentity()
    }

}
