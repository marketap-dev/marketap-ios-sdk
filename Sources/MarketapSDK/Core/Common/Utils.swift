//
//  Utils.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

extension Device {
    func getDeviceId() -> String {
        if let idfa = idfa {
            return "idfa:\(idfa)"
        } else if let idfv = idfv {
            return "idfv:\(idfv)"
        }
        return "anonymous:\(UUID().uuidString)"
    }

    func makeRequest(removeUserId: Bool = false) -> UpdateDeviceRequest {
        let screen = screen.map { "\($0.width)x\($0.height)" }

        let properties: [String: AnyCodable] = [
            "os": AnyCodable(os),
            "os_version": AnyCodable(osVersion),
            "library_version": AnyCodable(libraryVersion),
            "timezone": AnyCodable(timezone),
            "screen": AnyCodable(screen),
            "max_touch_points": AnyCodable(maxTouchPoints),
            "locale": AnyCodable(locale),
            "model": AnyCodable(model),
            "cpu_arch": AnyCodable(cpuArch),
            "memory_total": AnyCodable(memoryTotal),
            "storage_total": AnyCodable(storageTotal),
            "battery_level": AnyCodable(batteryLevel),
            "network_type": AnyCodable(networkType),
            "carrier": AnyCodable(carrier)
        ]

        return UpdateDeviceRequest(
            deviceId: getDeviceId(),
            idfa: idfa,
            idfv: idfv,
            platform: platform,
            token: token,
            properties: properties,
            removeUserId: removeUserId
        )
    }
}
