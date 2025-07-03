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
            Logger.verbose("[MarketapAPI] \(title): No data")
            return
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)

            if let jsonString = String(data: prettyData, encoding: .utf8) {
                Logger.verbose("[MarketapAPI] \(title):\n\(jsonString)")
            } else {
                Logger.verbose("[MarketapAPI] \(title): Unable to convert to string")
            }
        } catch {
            Logger.verbose("[MarketapAPI] \(title): Failed to parse JSON - \(error)")
        }
    }

    func logRequest(_ request: URLRequest, body: Encodable?) {
        Logger.verbose("[MarketapAPI] HTTP Request")
        Logger.verbose("[MarketapAPI] URL: \(request.url?.absoluteString ?? "Unknown URL")")
        Logger.verbose("[MarketapAPI] Method: \(request.httpMethod ?? "Unknown Method")")

        if let headers = request.allHTTPHeaderFields {
            Logger.verbose("[MarketapAPI] Headers: \(headers)")
        }

        if let body = body, let encodedBody = try? JSONEncoder().encode(body) {
            logJSON("Request Body", encodedBody)
        }

        Logger.verbose("---------------------------------------------------")
    }

    func logResponse(_ response: URLResponse?, data: Data?) {
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.verbose("[MarketapAPI] Invalid response received")
            return
        }

        Logger.verbose("[MarketapAPI] HTTP Response")
        Logger.verbose("[MarketapAPI] URL: \(httpResponse.url?.absoluteString ?? "Unknown URL")")
        Logger.verbose("[MarketapAPI] Status Code: \(httpResponse.statusCode)")

        Logger.verbose("[MarketapAPI] Headers: \(httpResponse.allHeaderFields)")

        logJSON("Response Body", data)

        Logger.verbose("---------------------------------------------------")
    }
}
