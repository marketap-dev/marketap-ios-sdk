//
//  Cache+Device.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import UIKit
import AdSupport
import AppTrackingTransparency
import CoreTelephony
import Network

extension MarketapCache {
    // MARK: - Advertising Identifier (IDFA)
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

    // MARK: - Identifier for Vendor (IDFV)
    private var idfv: String? {
        UIDevice.current.identifierForVendor?.uuidString
    }

    // MARK: - Total Storage (Bytes)
    private var totalStorage: Int? {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let totalSize = attributes[.systemSize] as? Int {
            return totalSize
        }
        return nil
    }

    func getCPUArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)

        let machineMirror = Mirror(reflecting: sysinfo.machine)
        let identifier = machineMirror.children.compactMap { element in
            (element.value as? Int8).flatMap { UnicodeScalar(UInt8($0)).description }
        }.joined()

        return identifier
    }


    // MARK: - Current Network Type
    private var networkType: String? {
        let path = NWPathMonitor().currentPath

        if path.usesInterfaceType(.wifi) {
            return "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            return "Cellular"
        } else {
            return nil
        }
    }

    // MARK: - Carrier Information
    private var carrier: String? {
        let networkInfo = CTTelephonyNetworkInfo()

        if #available(iOS 16.0, *) {
            // iOS 16: `carrierName` is deprecated, use radio access technology instead
            return networkInfo.serviceCurrentRadioAccessTechnology?.isEmpty == false ? "Mobile Network" : nil
        } else {
            // iOS 15 and below: Use `carrierName`
            return networkInfo.serviceSubscriberCellularProviders?.values.first?.carrierName
        }
    }

    // MARK: - SIM Card Presence
    private var hasSIMCard: Bool {
        CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology?.isEmpty == false
    }

    // MARK: - Battery Information
    private var batteryInfo: (level: Int?, isCharging: Bool) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel >= 0 ? Int(device.batteryLevel * 100) : nil
        let isCharging = device.batteryState == .charging || device.batteryState == .full
        return (level, isCharging)
    }

    // MARK: - Screen Information
    private var screenInfo: ScreenInfo {
        let screenSize = UIScreen.main.bounds.size
        return ScreenInfo(
            width: screenSize.width,
            height: screenSize.height,
            colorDepth: nil,
            pixelRatio: UIScreen.main.scale
        )
    }

    // MARK: - Device Information
    func getDeviceInfo() -> Device {
        let device = UIDevice.current
        let battery = batteryInfo

        let result = Device(
            cookieId: "ios",
            idfa: nil,
            idfv: idfa,
            gaid: idfv,
            appSetId: nil,
            appLocalId: nil,
            platform: nil, // TODO: 추가하기
            os: "\(device.systemName) \(device.systemVersion)",
            osVersion: device.systemVersion,
            libraryVersion: nil,
            model: device.model,
            manufacturer: "Apple",
            brand: "Apple",
            token: nil,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            appBuildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            browserName: nil,
            browserVersion: nil,
            userAgent: nil,
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            screen: screenInfo,
            cpuArch: getCPUArchitecture(),
            memoryTotal: nil,
            storageTotal: totalStorage,
            batteryLevel: battery.level,
            isCharging: battery.isCharging,
            networkType: networkType,
            carrier: carrier,
            hasSim: hasSIMCard,
            maxTouchPoints: 5,
            permissions: nil,
            sessionId: UUID().uuidString
        )
        
        saveCodableObject(result, key: deviceKey)
        return result

    }
}
