//
//  MarketapCacheManager.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

class MarketapCache {
    private let userDefaults = UserDefaults.standard

    let userIdKey = "MarketapCache_userId"
    let configKey = "MarketapCache_config"
    let deviceKey = "MarketapCache_device"
    let storageKey = "MarketapCache_storage"
    let localIDKey = "MarketapCache_localID"

    private var localID: String {
        if let localID: String = loadCodableObject(forKey: localIDKey) {
            return localID
        }
        let localID = UUID().uuidString
        saveCodableObject(localID, key: localIDKey)
        return localID
    }
    private var device: Device?
    private var userId: String?

    let config: MarketapConfig
    init(config: MarketapConfig) {
        self.config = config
    }

    // ✅ `userId` 저장 & 불러오기
    func saveUserId(_ userId: String?) {
        self.userId = userId
        userDefaults.set(userId, forKey: userIdKey)
    }

    func loadUserId() -> String? {
        return userId ?? userDefaults.string(forKey: userIdKey)
    }

    func clearUserId() {
        userDefaults.removeObject(forKey: userIdKey)
    }

    // ✅ `config` 저장 & 불러오기
    func saveConfig(_ config: MarketapConfig) {
        saveCodableObject(config, key: configKey)
    }

    func loadConfig() -> MarketapConfig? {
        return loadCodableObject(forKey: configKey)
    }

    func clearConfig() {
        userDefaults.removeObject(forKey: configKey)
    }

    // ✅ `device` 저장 & 불러오기
    func saveDevice(_ device: Device) {
        self.device = device
        saveCodableObject(device, key: deviceKey)
    }

    func loadDevice() -> Device {
        if let device { return device }

        let device = loadCodableObject(forKey: deviceKey) ?? getDeviceInfo()
        self.device = device
        return device
    }

    func clearDevice() {
        userDefaults.removeObject(forKey: deviceKey)
    }

    // ✅ `storage` 저장 & 불러오기
    func saveStorage(_ storage: InternalStorage) {
        saveCodableObject(storage, key: storageKey)
    }

    func loadStorage() -> InternalStorage? {
        return loadCodableObject(forKey: storageKey)
    }

    func clearStorage() {
        userDefaults.removeObject(forKey: storageKey)
    }

    // ✅ `MarketapCache` 전체 삭제 (초기화)
    func clearAll() {
        clearUserId()
        clearConfig()
        clearDevice()
        clearStorage()
    }

    // ✅ `Codable` 객체를 JSON으로 변환하여 저장
    func saveCodableObject<T: Codable>(_ object: T, key: String) {
        do {
            let data = try JSONEncoder().encode(object)
            userDefaults.set(data, forKey: key)
        } catch {
            print("❌ Failed to save \(key): \(error.localizedDescription)")
        }
    }

    // ✅ 저장된 JSON 데이터를 `Codable` 객체로 변환하여 불러오기
    private func loadCodableObject<T: Codable>(forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ Failed to load \(key): \(error.localizedDescription)")
            return nil
        }
    }
}
