//
//  Utils.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

extension Device {
    func makeRequest(removeUserId: Bool = false) -> UpdateDeviceRequest {
        let screen = screen.map { "\($0.width)x\($0.height)" }
        let deviceId = {
            if let idfv = idfv {
                return "idfv:\(idfv)"
            }
            return "app_local_id:\(appLocalId)"
        }()

        let properties: [String: AnyCodable] = [
            "os": AnyCodable(os),
            "os_version": AnyCodable(osVersion),
            "library_version": AnyCodable(libraryVersion),
            "timezone": AnyCodable(timezone),
            "screen": AnyCodable(screen),
            "max_touch_points": AnyCodable(maxTouchPoints),
            "locale": AnyCodable(locale),
            "model": AnyCodable(model),
            "environment": AnyCodable(environment),
            "app_version": AnyCodable(appVersion),
            "app_build_number": AnyCodable(appBuildNumber)
        ]

        return UpdateDeviceRequest(
            deviceId: deviceId,
            idfa: idfa,
            idfv: idfv,
            appLocalId: appLocalId,
            platform: platform,
            token: token,
            properties: properties,
            removeUserId: removeUserId
        )
    }
}
