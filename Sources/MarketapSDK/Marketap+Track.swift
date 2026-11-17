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

    /// 광고·메시지 링크의 UTM을 세션 UTM(`mkt_session_utm_*`)으로 넘깁니다. 링크를 받는 곳에서 호출합니다.
    /// 이벤트를 보내지 않고, 다음 이벤트부터 같은 세션의 이벤트에 붙습니다. 30분 안에 이벤트가 없으면 버립니다.
    /// SDK 초기화 전에 호출해도 됩니다.
    /// - Parameter url: `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content` 쿼리 파라미터가 있는 링크
    @objc public static func setUtm(fromUrl url: String) {
        setUtmValues(SessionUtmStore.utm(fromUrl: url))
    }

    /// UTM 값을 세션 UTM(`mkt_session_utm_*`)으로 넘깁니다. MMP(AppsFlyer 등) 콜백처럼 링크 없이 값만 받을 때 씁니다.
    /// 동작은 `setUtm(fromUrl:)` 과 같습니다. 빈 값과 nil 은 없는 것으로 봅니다.
    @objc public static func setUtm(source: String?, medium: String? = nil, campaign: String? = nil, term: String? = nil, content: String? = nil) {
        var utm: [String: String] = [:]
        for (key, value) in zip(SessionUtmStore.utmKeys, [source, medium, campaign, term, content]) {
            if let value = value, !value.isEmpty { utm[key] = value }
        }
        setUtmValues(utm)
    }

    private static let utmLock = NSLock()
    private static var utmBeforeInit: [String: String]?

    private static func setUtmValues(_ utm: [String: String]) {
        guard !utm.isEmpty else { return }
        if let core = _client as? MarketapCore {
            core.setUtm(utm)
        } else {
            utmLock.lock(); utmBeforeInit = utm; utmLock.unlock()
        }
    }

    static func takeUtmBeforeInit() -> [String: String]? {
        utmLock.lock(); defer { utmLock.unlock() }
        let utm = utmBeforeInit
        utmBeforeInit = nil
        return utm
    }

    /// 앱 화면이 바뀔 때마다 호출합니다. 탭 전환, 전체 화면·모달을 닫고 돌아올 때도 포함합니다.
    /// 서버로 이벤트를 보내지 않으며, "이 페이지에서만" 플로팅과 팝업을 닫는 데 씁니다.
    @objc public static func screenChanged() {
        client?.screenChanged()
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
}
