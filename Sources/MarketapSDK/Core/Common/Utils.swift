//
//  Utils.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

/// ✅ Device에서 유효한 ID를 가져오는 함수
func getDeviceId(from device: Device) -> String {
    if let idfa = device.idfa {
        return "idfa:\(idfa)"
    } else if let idfv = device.idfv {
        return "idfv:\(idfv)"
    } else if let gaid = device.gaid {
        return "gaid:\(gaid)"
    } else if let appSetId = device.appSetId {
        return "app_set_id:\(appSetId)"
    } else if let cookieId = device.cookieId {
        return "cookie_id:\(cookieId)"
    } else if let appLocalId = device.appLocalId {
        return "app_local_id:\(appLocalId)"
    }

    return "anonymous:\(UUID().uuidString)" // ✅ 임시 ID 생성
}

extension Device {
    func makeRequest(removeUserId: Bool = false) -> UpdateDeviceRequest {
        let device = self
        var screen: String? = nil
        if let screenInfo = device.screen {
            screen = "\(screenInfo.width)x\(screenInfo.height)"
            if let colorDepth = screenInfo.colorDepth {
                screen! += "x\(colorDepth)"
            }
        }

        var browser: String? = nil
        if let browserName = device.browserName, let browserVersion = device.browserVersion {
            browser = "\(browserName) \(browserVersion)"
        }

        return UpdateDeviceRequest(
            deviceId: getDeviceId(from: device),
            cookieId: device.cookieId,
            idfa: device.idfa,
            idfv: device.idfv,
            gaid: device.gaid,
            appSetId: device.appSetId,
            appLocalId: device.appLocalId,
            platform: device.platform,
            token: device.token,
            properties: [
                "os": AnyEncodable(device.os),
                "os_version": AnyEncodable(device.osVersion),
                "library_version": AnyEncodable(device.libraryVersion),
                "browser": AnyEncodable(browser),
                "user_agent": AnyEncodable(device.userAgent),
                "timezone": AnyEncodable(device.timezone),
                "screen": AnyEncodable(screen),
                "max_touch_points": AnyEncodable(device.maxTouchPoints),
                "locale": AnyEncodable(device.locale),
                "brand": AnyEncodable(device.brand),
                "model": AnyEncodable(device.model),
                "cpu_arch": AnyEncodable(device.cpuArch),
                "memory_total": AnyEncodable(device.memoryTotal),
                "storage_total": AnyEncodable(device.storageTotal),
                "battery_level": AnyEncodable(device.batteryLevel),
                "network_type": AnyEncodable(device.networkType),
                "carrier": AnyEncodable(device.carrier)
            ],
            removeUserId: removeUserId
        )
    }

}
