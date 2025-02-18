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

    var projectId: String = "mock_project"
    var userId: String?
    var device: Device = Device(
        idfa: nil,
        idfv: "mock_idfv",
        platform: "iOS",
        os: "iOS",
        osVersion: "16.0",
        libraryVersion: "1.0",
        model: "iPhone",
        manufacturer: "Apple",
        token: nil,
        appVersion: "1.0",
        appBuildNumber: "100",
        timezone: "Asia/Seoul",
        locale: "en_KR",
        screen: nil,
        cpuArch: "arm64",
        memoryTotal: nil,
        storageTotal: nil,
        batteryLevel: nil,
        isCharging: nil,
        networkType: "WiFi",
        carrier: nil,
        hasSim: true,
        maxTouchPoints: 5,
        permissions: nil,
        sessionId: "mock_session"
    )

    var failedEvents: [BulkEvent] {
        get { loadCodableObject(forKey: EventService.failedEventsKey) ?? [] }
        set { saveCodableObject(newValue, key: EventService.failedEventsKey) }
    }

    func saveUserId(_ userId: String?) {
        self.userId = userId
    }

    func updateDevice(pushToken: String? = nil) -> Device {
        if let pushToken {
            device.token = pushToken
        }
        return device
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
}
