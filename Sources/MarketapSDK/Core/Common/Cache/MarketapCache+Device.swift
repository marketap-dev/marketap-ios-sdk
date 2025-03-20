//
//  Cache+Device.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import UIKit
import AdSupport
import AppTrackingTransparency

extension MarketapCache {
    private var idfa: String? {
        if #available(iOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .authorized
                ? ASIdentifierManager.shared().advertisingIdentifier.uuidString
                : nil
        } else {
            return ASIdentifierManager.shared().isAdvertisingTrackingEnabled
                ? ASIdentifierManager.shared().advertisingIdentifier.uuidString
                : nil
        }
    }

    private var idfv: String? {
        UIDevice.current.identifierForVendor?.uuidString
    }

    private var environment: String {
        #if DEBUG
        return "debug"
        #elseif RELEASE
        return "release"
        #else
        return "production"
        #endif
    }

    private var screenInfo: ScreenInfo {
        let screenSize = UIScreen.main.bounds.size
        return ScreenInfo(
            width: screenSize.width,
            height: screenSize.height,
            pixelRatio: UIScreen.main.scale
        )
    }

    func getDeviceInfo(pushToken: String? = nil) -> Device {
        let device = UIDevice.current

        let result = Device(
            idfa: idfa,
            idfv: idfv,
            appLocalId: localId,
            platform: "ios",
            os: "\(device.systemName) \(device.systemVersion)",
            osVersion: device.systemVersion,
            libraryVersion: MarketapConfig.sdkVersion,
            model: device.model,
            manufacturer: "Apple",
            token: pushToken ?? loadCodableObject(forKey: CacheKey.pushTokenKey),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appBuildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            screen: screenInfo,
            maxTouchPoints: 5,
            environment: environment
        )

        return result
    }
}
