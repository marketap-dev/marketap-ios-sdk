//
//  MarketapCacheProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol MarketapCacheProtocol {
    var device: Device { get }
    var userId: String? { get }
    var projectId: String { get }

    func saveUserId(_ userId: String?)
    func updateDevice(pushToken: String?)
    func saveCodableObject<T: Codable>(_ object: T, key: String)
    func loadCodableObject<T: Codable>(forKey key: String) -> T?
    func clearObject(forKey key: String)
}
