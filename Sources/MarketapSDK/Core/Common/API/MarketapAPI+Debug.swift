//
//  MarketapAPI+Debug.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

import Foundation

extension MarketapAPI {
    private func logJSON(_ title: String, _ data: Data?) {
        guard let data = data else {
            MarketapLogger.verbose("\(title): No data")
            return
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)

            if let jsonString = String(data: prettyData, encoding: .utf8) {
                MarketapLogger.verbose("\(title):\n\(jsonString)")
            } else {
                MarketapLogger.verbose("\(title): Unable to convert to string")
            }
        } catch {
            MarketapLogger.verbose("\(title): Failed to parse JSON - \(error)")
        }
    }

    func logRequest(_ request: URLRequest, body: Encodable?) {
        MarketapLogger.verbose("HTTP Request")
        MarketapLogger.verbose("URL: \(request.url?.absoluteString ?? "Unknown URL")")
        MarketapLogger.verbose("Method: \(request.httpMethod ?? "Unknown Method")")

        if let headers = request.allHTTPHeaderFields {
            MarketapLogger.verbose("Headers:\n\(headers.toJSONString())")
        }

        if let body = body, let encodedBody = try? JSONEncoder().encode(body) {
            logJSON("Request Body", encodedBody)
        }

        MarketapLogger.verbose("---------------------------------------------------")
    }

    func logResponse(_ response: URLResponse?, data: Data?) {
        guard let httpResponse = response as? HTTPURLResponse else {
            MarketapLogger.verbose("Invalid response received")
            return
        }

        MarketapLogger.verbose("HTTP Response")
        MarketapLogger.verbose("URL: \(httpResponse.url?.absoluteString ?? "Unknown URL")")
        MarketapLogger.verbose("Status Code: \(httpResponse.statusCode)")

        MarketapLogger.verbose("Headers:\n\(httpResponse.allHeaderFields.prettyPrintedJSONString)")

        logJSON("Response Body", data)

        MarketapLogger.verbose("---------------------------------------------------")
    }
}
