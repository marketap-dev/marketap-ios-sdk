//
//  MarketapCacheManager.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

class MarketapCache: MarketapCacheProtocol {
    enum CacheKey {
        static let userIdKey = "MarketapCache_userId"
        static let configKey = "MarketapCache_config"
        static let deviceKey = "MarketapCache_device"
        static let localIdKey = "MarketapCache_localId"
        static let pushTokenKey = "MarketapCache_pushToken"
        static let deviceRequestKey = "MarketapCache_deviceRequest"
    }

    private let userDefaults: UserDefaults

    let sessionId = UUID().uuidString
    let config: MarketapConfig
    var projectId: String {
        config.projectId
    }

    private let userIdQueue = DispatchQueue(label: "com.marketap.userIdQueue", attributes: .concurrent)
    private let deviceQueue = DispatchQueue(label: "com.marketap.deviceQueue", attributes: .concurrent)
    private let localIdQueue = DispatchQueue(label: "com.marketap.localIdQueue", attributes: .concurrent)

    private var _device: Device?

    init(config: MarketapConfig, userDefaults: UserDefaults = .standard) {
        self.config = config
        self.userDefaults = userDefaults
    }

    var localId: String {
        get {
            localIdQueue.sync {
                if let savedLocalID: String = loadCodableObject(forKey: CacheKey.localIdKey) {
                    return savedLocalID
                }
                let newLocalID = UUID().uuidString
                saveCodableObject(newLocalID, key: CacheKey.localIdKey)
                return newLocalID
            }
        }
    }

    var device: Device {
        get {
            deviceQueue.sync {
                if let existingDevice = _device {
                    return existingDevice
                }
                let newDevice = getDeviceInfo()
                _device = newDevice
                return newDevice
            }
        }
        set {
            deviceQueue.async(flags: .barrier) {
                self._device = newValue
            }
        }
    }

    var userId: String? {
        get {
            userIdQueue.sync {
                loadCodableObject(forKey: CacheKey.userIdKey)
            }
        }
        set {
            userIdQueue.async(flags: .barrier) {
                if let newValue {
                    self.saveCodableObject(newValue, key: CacheKey.userIdKey)
                } else {
                    self.userDefaults.removeObject(forKey: CacheKey.userIdKey)
                }
            }
        }
    }

    func saveUserId(_ userId: String?) {
        self.userId = userId
    }

    func updateDevice(pushToken: String? = nil) -> Device {
        deviceQueue.sync {
            var updatedDevice = getDeviceInfo(pushToken: pushToken)
            if let pushToken {
                updatedDevice.token = pushToken
                saveCodableObject(pushToken, key: CacheKey.pushTokenKey)
            }
            self.device = updatedDevice
            return updatedDevice
        }
    }

    func saveCodableObject<T: Codable>(_ object: T, key: String) {
        do {
            let data = try JSONEncoder().encode(object)
            self.userDefaults.set(data, forKey: key)
        } catch {
            Logger.error("Failed to save \(key): \(error.localizedDescription)")
        }
    }

    func loadCodableObject<T: Codable>(forKey key: String) -> T? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.error("Failed to load \(key): \(error.localizedDescription)")
            return nil
        }
    }

    func clearObject(forKey key: String) {
        self.userDefaults.removeObject(forKey: key)
    }
}

