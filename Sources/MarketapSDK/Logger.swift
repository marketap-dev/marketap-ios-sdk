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

public enum MarketapLogLevel: Int {
    case verbose, debug, info, warn, error, none

    var osLogType: OSLogType? {
        switch self {
        case .verbose, .debug:
            return .debug
        case .info:
            return .info
        case .warn:
            return .error
        case .error:
            return .fault
        case .none:
            return nil
        }
    }
}

enum Logger {
    static var level = MarketapLogLevel.info
    private static let subsystem = "com.marketap.sdk"
    private static let prefix = "[MarketapSDK]"

    public static func error(_ message: String) {
        log(message, level: .error)
    }

    public static func warn(_ message: String) {
        log(message, level: .warn)
    }

    public static func info(_ message: String) {
        log(message, level: .info)
    }

    public static func debug(_ message: String) {
        log(message, level: .debug)
    }

    public static func verbose(_ message: String) {
        log(message, level: .verbose)
    }

    private static func log(_ message: String, level: MarketapLogLevel) {
        if level.rawValue < Self.level.rawValue { return }

        #if canImport(os)
        if #available(iOS 14.0, *) {
            let logger = os.Logger(subsystem: subsystem, category: "\(level)")
            switch level {
            case .error:
                logger.critical("\(message)")
            case .info:
                logger.info("\(message)")
            case .debug:
                logger.debug("\(message)")
            case .warn:
                logger.warning("\(message)")
            default:
                logger.log("\(message)")
            }
        } else if let osLogType = level.osLogType {
            os_log("%{public}s %{public}s", type: osLogType, prefix, message)
        }
        #else
        print(message)
        #endif
    }
}

extension Encodable {
    func toJSONString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return "(encode failed)" }
        return String(data: data, encoding: .utf8) ?? "(encode failed)"
    }
}
