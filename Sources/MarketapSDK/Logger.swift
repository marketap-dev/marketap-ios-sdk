//
//  Logger.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

import Foundation
#if canImport(os)
import os
#endif

public enum Logger {
    private static let subsystem = "com.marketap.sdk"
    private static let prefix = "[MarketapSDK]"

    public static func error(_ message: String) {
        log(message, level: .error)
    }

    public static func warning(_ message: String) {
        log(message, level: .default)
    }

    public static func info(_ message: String) {
        log(message, level: .info)
    }

    public static func debug(_ message: String) {
        log(message, level: .debug)
    }

    private static func log(_ message: String, level: OSLogType) {
        #if canImport(os)
        if #available(iOS 14.0, *) {
            let logger = os.Logger(subsystem: subsystem, category: "\(level)")
            switch level {
            case .error:
                logger.error("\(message)")
            case .info:
                logger.info("\(message)")
            case .debug:
                logger.debug("\(message)")
            default:
                logger.log("\(message)") // `.default` 로그
            }
        } else {
            os_log("%{public}s %{public}s", type: level, prefix, message)
        }
        #else
        print(message)
        #endif
    }
}
