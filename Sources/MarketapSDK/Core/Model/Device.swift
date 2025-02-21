//
//  Device.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct Device: Codable {
    let idfa: String?
    let idfv: String?
    let appLocalId: String

    let platform: String
    let os: String
    let osVersion: String?
    let libraryVersion: String?
    let model: String?
    let manufacturer: String?
    var token: String?

    let appVersion: String?
    let appBuildNumber: String?
    
    let timezone: String
    let locale: String
    
    let screen: ScreenInfo?
    
    let cpuArch: String?
    let memoryTotal: Int?
    let storageTotal: Int?
    let batteryLevel: Int?
    let isCharging: Bool?
    
    let networkType: String?
    let carrier: String?
    let hasSim: Bool?
    let maxTouchPoints: Int?
    
    let permissions: Permissions?
    
    let sessionId: String?
    
    enum CodingKeys: String, CodingKey {
        case idfa, idfv
        case platform, os
        case osVersion = "os_version"
        case libraryVersion = "library_version"
        case model, manufacturer, token
        case appVersion = "app_version"
        case appBuildNumber = "app_build_number"
        case timezone, locale
        case screen
        case cpuArch = "cpu_arch"
        case memoryTotal = "memory_total"
        case storageTotal = "storage_total"
        case batteryLevel = "battery_level"
        case isCharging = "is_charging"
        case networkType = "network_type"
        case carrier
        case hasSim = "has_sim"
        case maxTouchPoints = "max_touch_points"
        case permissions
        case sessionId = "session_id"
        case appLocalId = "app_local_id"
    }
}

struct ScreenInfo: Codable {
    let width: Double
    let height: Double
    let pixelRatio: Double?

    enum CodingKeys: String, CodingKey {
        case width, height
        case pixelRatio = "pixel_ratio"
    }
}

struct Permissions: Codable {
    let camera: Bool?
    let microphone: Bool?
    let location: Bool?
    let notifications: Bool?

    enum CodingKeys: String, CodingKey {
        case camera, microphone, location, notifications
    }
}
