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
    let maxTouchPoints: Int?
    let environment: String

    
    enum CodingKeys: String, CodingKey {
        case idfa, idfv
        case platform, os, timezone, locale, screen, environment
        case osVersion = "os_version"
        case libraryVersion = "library_version"
        case model, manufacturer, token
        case appVersion = "app_version"
        case appBuildNumber = "app_build_number"
        case maxTouchPoints = "max_touch_points"
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
