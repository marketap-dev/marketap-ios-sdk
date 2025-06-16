//
//  Marketap.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/11/25.
//

import Foundation

/// Marketap SDK - SDK 사용을 위한 정적 메서드를 제공합니다.
@objcMembers
public class Marketap: NSObject {

    private override init() {}
    static var _client: MarketapClientProtocol?
    static let coldStartNotificationHandler = ColdStartNotificationHandler()

    /// Marketap SDK의 클라이언트 인스턴스를 제공합니다.
    ///
    /// - 사용자가 `initialize(projectId:)`를 호출하여 SDK를 초기화해야 합니다.
    /// - 초기화되지 않은 상태에서 접근하면 `nil`을 반환하며, 경고 로그가 출력됩니다.
    ///
    /// - Note: 테스트 환경에서 `client`를 교체하여 Mock을 주입할 수 있습니다.
    public static var client: MarketapClientProtocol? {
        get {
            guard let _client else {
                Logger.error("Marketap SDK is not initialized. Make sure to call Marketap.initialize(projectId:) before using the SDK.")
                return nil
            }
            return _client
        }
        set {
            _client = newValue
        }
    }

    /// SDK를 설정값과 함께 초기화합니다.
    ///
    /// - Parameter projectId: Marketap 콘솔에서 제공하는 프로젝트 ID.
    ///
    /// - Important: `initialize`를 호출하기 전에는 `client`를 사용할 수 없습니다.
    @objc public static func initialize(projectId: String) {
        let config = MarketapConfig(projectId: projectId)
        let api = MarketapAPI()
        let cache = MarketapCache(config: config)
        let eventService = EventService(api: api, cache: cache)
        let inAppMessageService = InAppMessageService(api: api, cache: cache)
        let core = MarketapCore(eventService: eventService, inAppMessageService: inAppMessageService)
        eventService.delegate = core
        inAppMessageService.delegate = core
        client = core
        Logger.info("Marketap SDK initialized successfully with projectId: \(projectId)")

        coldStartNotificationHandler.didInitializeClient(client: core)
    }
}
