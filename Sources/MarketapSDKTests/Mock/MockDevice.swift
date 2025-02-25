//
//  MockDevice.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

@testable import MarketapSDK

class MockDevice {
    var idfa: String? = "mock_idfa"
    var idfv: String? = "mock_idfv"
    var appSetId: String? = nil
    var appLocalId: String = "mock_app_local_id"
    var platform: String = "ios"
    var os: String = "iOS"
    var osVersion: String? = "18.1"
    var libraryVersion: String? = "1.0.0"
    var model: String? = "iPhone 14"
    var manufacturer: String? = "Apple"
    var brand: String? = "Apple"
    var token: String? = "mock_token"

    var appVersion: String? = "1.0.0"
    var appBuildNumber: String? = "100"

    var browserName: String? = nil
    var browserVersion: String? = nil
    var userAgent: String? = nil

    var timezone: String = "Asia/Seoul"
    var locale: String = "ko_KR"

    var screen: ScreenInfo = ScreenInfo(width: 390, height: 844, pixelRatio: 3.0)

    var cpuArch: String? = "arm64"
    var memoryTotal: Int? = 4096
    var storageTotal: Int? = 128_000
    var batteryLevel: Int? = 95
    var isCharging: Bool? = false

    var networkType: String? = "WiFi"
    var carrier: String? = "SKT"
    var hasSim: Bool? = true
    var maxTouchPoints: Int? = 5

    var permissions: Permissions = Permissions(camera: true, microphone: true, location: true, notifications: true)

    func toDevice() -> Device {
        return Device(
            idfa: idfa,
            idfv: idfv,
            appLocalId: appLocalId,
            platform: platform,
            os: os,
            osVersion: osVersion,
            libraryVersion: libraryVersion,
            model: model,
            manufacturer: manufacturer,
            token: token,
            appVersion: appVersion,
            appBuildNumber: appBuildNumber,
            timezone: timezone,
            locale: locale,
            screen: screen,
            cpuArch: cpuArch,
            memoryTotal: memoryTotal,
            storageTotal: storageTotal,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            networkType: networkType,
            carrier: carrier,
            hasSim: hasSim,
            maxTouchPoints: maxTouchPoints,
            permissions: permissions
        )
    }
}
