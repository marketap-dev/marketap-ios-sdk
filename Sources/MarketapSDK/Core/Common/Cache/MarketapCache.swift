//
//  MarketapCacheManager.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

final class MarketapCache: MarketapCacheProtocol {
    enum CacheKey {
        static let userIdKey = "MarketapCache_userId"
        static let sessionIdKey = "MarketapCache_sessionId"
        static let configKey = "MarketapCache_config"
        static let deviceKey = "MarketapCache_device"
        static let localIdKey = "MarketapCache_localId"
        static let pushTokenKey = "MarketapCache_pushToken"
        static let deviceRequestKey = "MarketapCache_deviceRequest"
    }

    private let userDefaults: UserDefaults

    let config: MarketapConfig
    var projectId: String {
        config.projectId
    }

    private let sessionIdQueue = DispatchQueue(label: "com.marketap.sessionIdQueue", attributes: .concurrent)
    private let userIdQueue = DispatchQueue(label: "com.marketap.userIdQueue", attributes: .concurrent)
    private let deviceQueue = DispatchQueue(label: "com.marketap.deviceQueue", attributes: .concurrent)

    init(config: MarketapConfig, userDefaults: UserDefaults = .standard) {
        self.config = config
        self.userDefaults = userDefaults

        self._sessionId = loadCodableObject(forKey: CacheKey.sessionIdKey) ?? UUID().uuidString
        self.localId = {
            if let id: String = loadCodableObject(forKey: CacheKey.localIdKey) { return id }
            let newLocalID = UUID().uuidString
            saveCodableObject(newLocalID, key: CacheKey.localIdKey)
            return newLocalID
        }()
        self._userId = loadCodableObject(forKey: CacheKey.userIdKey)
        self._device = getDeviceInfo()
    }

    private var _sessionId: String!
    var sessionId: String {
        get {
            sessionIdQueue.sync {
                return _sessionId
            }
        }
        set {
            sessionIdQueue.async(flags: .barrier) {
                self._sessionId = newValue
                self.saveCodableObject(newValue, key: CacheKey.sessionIdKey)
            }
        }
    }

    var localId: String!

    private var _device: Device!
    var device: Device {
        get {
            deviceQueue.sync {
                return _device
            }
        }
        set {
            deviceQueue.async(flags: .barrier) {
                self._device = newValue
            }
        }
    }

    private var _userId: String?
    var userId: String? {
        get {
            userIdQueue.sync {
                return _userId
            }
        }
        set {
            userIdQueue.async(flags: .barrier) {
                self._userId = newValue
                if let newValue = newValue {
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

    func updateDevice(pushToken: String? = nil) {
        deviceQueue.async(flags: .barrier){
            var updatedDevice = self.getDeviceInfo(pushToken: pushToken)
            if let pushToken = pushToken {
                updatedDevice.token = pushToken
                self.saveCodableObject(pushToken, key: CacheKey.pushTokenKey)
            }
            Logger.verbose("updating device info:\n\(updatedDevice.toJSONString())")
            self._device = updatedDevice
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

