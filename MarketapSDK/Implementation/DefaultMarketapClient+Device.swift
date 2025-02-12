//
//  DefaultMarketapClient+Device.swift
//
//  Created by 이동현 on 2/11/25.
//

import UIKit
import AdSupport
import AppTrackingTransparency
import CoreTelephony
import Network

extension DefaultMarketapClient {
    
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
    private var totalStorage: Int64? {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let totalSize = attributes[.systemSize] as? Int64 {
            return totalSize
        }
        return nil
    }
    
    // MARK: - Current Network Type
    private var networkType: String? {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue.global(qos: .background)
        var result: String?

        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            if path.usesInterfaceType(.wifi) {
                result = "WiFi"
            } else if path.usesInterfaceType(.cellular) {
                result = "Cellular"
            }
            monitor.cancel()
            semaphore.signal()
        }
        monitor.start(queue: queue)
        semaphore.wait()
        
        return result
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
    private var screenInfo: [String: Any] {
        let screenSize = UIScreen.main.bounds.size
        return [
            "width": Int(screenSize.width),
            "height": Int(screenSize.height),
            "pixel_ratio": UIScreen.main.scale
        ]
    }
    
    // MARK: - Device Information
    func getDeviceInfo() -> [String: Any] {
        let device = UIDevice.current
        let battery = batteryInfo

        let info: [String: Any?] = [
            "idfa": idfa,
            "idfv": idfv,
            "platform": "ios",
            "os": "\(device.systemName) \(device.systemVersion)",
            "os_version": device.systemVersion,
            "model": device.model,
            "manufacturer": "Apple",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            "app_build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            "timezone": TimeZone.current.identifier,
            "locale": Locale.current.identifier,
            "screen": screenInfo,
            "cpu_arch": "arm64",
            "storage_total": totalStorage,
            "battery_level": battery.level,
            "is_charging": battery.isCharging,
            "network_type": networkType,
            "carrier": carrier,
            "has_sim": hasSIMCard,
            "max_touch_points": 5,
            "session_id": UUID().uuidString
        ]
        
        return info.compactMapValues { $0 }
    }
}
