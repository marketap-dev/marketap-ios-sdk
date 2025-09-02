//
//  Logger.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

import Foundation
import os

public enum MarketapLogLevel: Int {
    case verbose, debug, info, warn, error, none
}

private extension MarketapLogLevel {
    var osLogType: OSLogType? {
        switch self {
        case .verbose, .debug: return .debug
        case .info:            return .info
        case .warn:            return .error
        case .error:           return .fault
        case .none:            return nil
        }
    }
}

enum MarketapLogger {
    static var level = MarketapLogLevel.info
    private static let subsystem = "com.marketap.sdk"
    private static let oslog = OSLog(subsystem: subsystem, category: "SDK")

    static func error(_ message: @autoclosure () -> String,
                      file: String = #file, line: Int = #line) {
        log(message, file: file, line: line, level: .error)
    }
    static func warn(_ message: @autoclosure () -> String,
                     file: String = #file, line: Int = #line) {
        log(message, file: file, line: line, level: .warn)
    }
    static func info(_ message: @autoclosure () -> String,
                     file: String = #file, line: Int = #line) {
        log(message, file: file, line: line, level: .info)
    }
    static func debug(_ message: @autoclosure () -> String,
                      file: String = #file, line: Int = #line) {
        log(message, file: file, line: line, level: .debug)
    }
    static func verbose(_ message: @autoclosure () -> String,
                        file: String = #file, line: Int = #line) {
        log(message, file: file, line: line, level: .verbose)
    }

    private static func log(_ messageMaker: () -> String,
                            file: String, line: Int, level: MarketapLogLevel) {
        if level.rawValue < Self.level.rawValue { return }

        let fileName = (file as NSString).lastPathComponent
        let tag = "[\(fileName):\(line)]"
        let message = "\(tag) \(messageMaker())"

        guard let t = level.osLogType else { return } // .none
        os_log("%{public}@", log: oslog, type: t, message)
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

extension Dictionary where Key == AnyHashable, Value == Any {
    var prettyPrintedJSONString: String {
        guard JSONSerialization.isValidJSONObject(self),
              let data = try? JSONSerialization.data(withJSONObject: self, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "\(self)"
        }
        return jsonString
    }
}

extension Dictionary where Key == String, Value == Any {
    var prettyPrintedJSONString: String {
        guard JSONSerialization.isValidJSONObject(self),
              let data = try? JSONSerialization.data(withJSONObject: self, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "\(self)"
        }
        return jsonString
    }
}

extension Optional where Wrapped == [String: Any] {
    var prettyPrintedJSONString: String {
        guard let dict = self,
              JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return jsonString
    }
}
