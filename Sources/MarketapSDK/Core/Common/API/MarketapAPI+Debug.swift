//
//  MarketapAPI+Debug.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

extension MarketapAPI {
    private func logJSON(_ title: String, _ data: Data?) {
        guard let data = data else {
            Logger.error("\(title): No data")
            return
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)

            if let jsonString = String(data: prettyData, encoding: .utf8) {
                Logger.info("\(title):\n\(jsonString)")
            } else {
                Logger.error("\(title): Unable to convert to string")
            }
        } catch {
            Logger.error("\(title): Failed to parse JSON - \(error)")
        }
    }

    func logRequest(_ request: URLRequest, body: Encodable?) {
        guard shouldLogRequests else { return }
        Logger.info("📡 HTTP Request")
        Logger.info("🌐 URL: \(request.url?.absoluteString ?? "Unknown URL")")
        Logger.info("🔹 Method: \(request.httpMethod ?? "Unknown Method")")

        if let headers = request.allHTTPHeaderFields {
            Logger.info("📌 Headers: \(headers)")
        }

        if let body = body, let encodedBody = try? JSONEncoder().encode(body) {
            logJSON("Request Body", encodedBody)
        }

        Logger.info("---------------------------------------------------")
    }

    func logResponse(_ response: URLResponse?, data: Data?) {
        guard shouldLogRequests else { return }
        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.error("❌ Response: Invalid response received")
            return
        }

        Logger.info("📡 HTTP Response")
        Logger.info("🌐 URL: \(httpResponse.url?.absoluteString ?? "Unknown URL")")
        Logger.info("🔹 Status Code: \(httpResponse.statusCode)")

        Logger.info("📌 Headers: \(httpResponse.allHeaderFields)")

        logJSON("Response Body", data)

        Logger.info("---------------------------------------------------")
    }
}
