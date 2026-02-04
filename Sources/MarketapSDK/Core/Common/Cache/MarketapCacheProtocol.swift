//
//  MarketapCacheProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol MarketapCacheProtocol: AnyObject {
    var device: Device { get }
    var userId: String? { get }
    var projectId: String { get }
    var sessionId: String { get set }

    func saveUserId(_ userId: String?)
    func updateDevice(pushToken: String?, optIn: Bool?, clearOptIn: Bool)
    func saveCodableObject<T: Codable>(_ object: T, key: String)
    func loadCodableObject<T: Codable>(forKey key: String) -> T?
    func clearObject(forKey key: String)
}
