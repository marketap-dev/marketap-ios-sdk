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

    private var totalStorage: Int? {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let totalSize = attributes[.systemSize] as? Int {
            return totalSize
        }
        return nil
    }

    func getCPUArchitecture() -> String {
    #if arch(arm)
        return "arm"
    #elseif arch(arm64)
        return "arm64"
    #elseif arch(i386)
        return "i386"
    #elseif arch(powerpc64)
        return "powerpc64"
    #elseif arch(powerpc64le)
        return "powerpc64le"
    #elseif arch(s390x)
        return "s390x"
    #elseif arch(wasm32)
        return "wasm32"
    #elseif arch(x86_64)
        return "x86_64"
    #else
        return "unknown_machine_architecture"
    #endif
    }

    private var batteryInfo: (level: Int?, isCharging: Bool) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel >= 0 ? Int(device.batteryLevel * 100) : nil
        let isCharging = device.batteryState == .charging || device.batteryState == .full
        return (level, isCharging)
    }

    private var screenInfo: ScreenInfo {
        let screenSize = UIScreen.main.bounds.size
        return ScreenInfo(
            width: screenSize.width,
            height: screenSize.height,
            pixelRatio: UIScreen.main.scale
        )
    }

    private var sdkVersion: String? {
        let bundle = Bundle(for: MarketapCache.self)
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var totalMemory: Int {
        return Int(ProcessInfo.processInfo.physicalMemory) // 단위: 바이트(Byte)
    }

    func getDeviceInfo(pushToken: String? = nil) -> Device {
        let device = UIDevice.current
        let battery = batteryInfo

        let result = Device(
            idfa: idfa,
            idfv: idfv,
            appLocalId: localId,
            platform: "ios",
            os: "\(device.systemName) \(device.systemVersion)",
            osVersion: device.systemVersion,
            libraryVersion: sdkVersion,
            model: device.model,
            manufacturer: "Apple",
            token: pushToken ?? loadCodableObject(forKey: CacheKey.pushTokenKey),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appBuildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            screen: screenInfo,
            cpuArch: getCPUArchitecture(),
            memoryTotal: totalMemory,
            storageTotal: totalStorage,
            batteryLevel: battery.level,
            isCharging: battery.isCharging,
            networkType: nil,
            carrier: nil,
            hasSim: nil,
            maxTouchPoints: 5,
            permissions: nil
        )

        return result
    }
}
