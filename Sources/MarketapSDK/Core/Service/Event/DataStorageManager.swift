//
//  DataStorageManager.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/20/25.
//

import Foundation

class DataStorageManager<T: Codable> {
    private let queue: DispatchQueue
    private var storedData: [T] {
        didSet {
            cache.saveCodableObject(storedData, key: storageKey)
        }
    }

    private let storageKey: String
    private let cache: MarketapCacheProtocol
    private let maxStorageSize: Int

    init(cache: MarketapCacheProtocol, storageKey: String, queueLabel: String, maxStorageSize: Int = 100) {
        self.cache = cache
        self.storageKey = storageKey
        self.maxStorageSize = maxStorageSize
        self.queue = DispatchQueue(label: queueLabel, attributes: .concurrent)
        self.storedData = cache.loadCodableObject(forKey: storageKey) ?? []
    }

    func saveData(_ data: T) {
        _saveDate([data])
    }

    func getStoredData() -> [T] {
        queue.sync { storedData }
    }

    func getAndClearData() -> [T] {
        queue.sync(flags: .barrier) {
            let snapshot = storedData
            storedData = []
            return snapshot
        }
    }

    func restoreFailedData(_ data: [T]) {
        _saveDate(data)
    }

    private func _saveDate(_ data: [T]) {
        queue.async(flags: .barrier) {
            var newData = self.storedData + data

            if newData.count > self.maxStorageSize {
                newData.removeFirst(newData.count - self.maxStorageSize)
            }

            self.storedData = newData
        }
    }
}
