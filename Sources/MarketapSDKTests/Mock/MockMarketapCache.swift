//
//  MockMarketapCache.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation
@testable import MarketapSDK

class MockMarketapCache: MarketapCacheProtocol {
    private var mockStorage: [String: Data] = [:]

    var sessionId: String = UUID().uuidString
    var projectId: String = "mock_project"
    var userId: String?
    var device: Device = Device(
        idfa: nil,
        idfv: "mock_idfv",
        appLocalId: "mock_app_local_id",
        sdkType: "ios",
        sdkVersion: "1.0.0",
        platform: "iOS",
        os: "iOS",
        osVersion: "16.0",
        libraryVersion: "1.0",
        model: "iPhone",
        manufacturer: "Apple",
        token: nil,
        optIn: nil,
        appVersion: "1.0",
        appBuildNumber: "100",
        timezone: "Asia/Seoul",
        locale: "en_KR",
        screen: nil,
        maxTouchPoints: 5,
        environment: "develop"
    )

    var failedEvents: [BulkEvent] {
        get { loadCodableObject(forKey: EventService.failedEventsKey) ?? [] }
        set { saveCodableObject(newValue, key: EventService.failedEventsKey) }
    }

    func saveUserId(_ userId: String?) {
        self.userId = userId
    }

    func updateDevice(pushToken: String? = nil, optIn: Bool? = nil) {
        if let pushToken = pushToken {
            device.token = pushToken
        }
        if let optIn = optIn {
            device.optIn = optIn
        }
    }

    func saveCodableObject<T: Codable>(_ object: T, key: String) {
        do {
            let data = try JSONEncoder().encode(object)
            mockStorage[key] = data
        } catch {
            print("❌ [MockMarketapCache] Failed to save \(key): \(error.localizedDescription)")
        }
    }

    func loadCodableObject<T: Codable>(forKey key: String) -> T? {
        guard let data = mockStorage[key] else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ [MockMarketapCache] Failed to load \(key): \(error.localizedDescription)")
            return nil
        }
    }

    func clearObject(forKey key: String) {
        mockStorage.removeValue(forKey: key)
    }

    // 프로토콜에 updateDevice 가 추가됐는데 이 mock 이 안 따라가서 테스트 타깃 전체가
    // 빌드 실패했다(컴파일 에러라 InApp 테스트도 못 돌았다). 테스트에서 device 상태를
    // 볼 일이 있으면 여기에 반영한다.
    func updateDevice(pushToken: String?, optIn: Bool?, clearOptIn: Bool) {
        if let pushToken = pushToken {
            device.token = pushToken
        }
        if clearOptIn {
            device.optIn = nil
        } else if let optIn = optIn {
            device.optIn = optIn
        }
    }
}
