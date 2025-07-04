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
            Logger.verbose("\(title): No data")
            return
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)

            if let jsonString = String(data: prettyData, encoding: .utf8) {
                Logger.verbose("\(title):\n\(jsonString)")
            } else {
                Logger.verbose("\(title): Unable to convert to string")
            }
        } catch {
            Logger.verbose("\(title): Failed to parse JSON - \(error)")
        }
    }

    func logRequest(_ request: URLRequest, body: Encodable?) {
        Logger.verbose("HTTP Request")
        Logger.verbose("URL: \(request.url?.absoluteString ?? "Unknown URL")")
        Logger.verbose("Method: \(request.httpMethod ?? "Unknown Method")")

        if let headers = request.allHTTPHeaderFields {
            Logger.verbose("Headers:\n\(headers.toJSONString())")
        }

        if let body = body, let encodedBody = try? JSONEncoder().encode(body) {
            logJSON("Request Body", encodedBody)
        }

        Logger.verbose("---------------------------------------------------")
    }

    func logResponse(_ response: URLResponse?, data: Data?) {
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.verbose("Invalid response received")
            return
        }

        Logger.verbose("HTTP Response")
        Logger.verbose("URL: \(httpResponse.url?.absoluteString ?? "Unknown URL")")
        Logger.verbose("Status Code: \(httpResponse.statusCode)")

        Logger.verbose("Headers:\n\(httpResponse.allHeaderFields.prettyPrintedJSONString)")

        logJSON("Response Body", data)

        Logger.verbose("---------------------------------------------------")
    }
}
