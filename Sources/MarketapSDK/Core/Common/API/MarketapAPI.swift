//
//  MarketapAPI.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

final class MarketapAPI: MarketapAPIProtocol {
    enum BaseURL: String {
        case event = "https://event.marketap.io"
        case crm = "https://crm.marketap.io"
    }

    func request<T: Decodable, U: Encodable>(
        baseURL: BaseURL = .event,
        path: String,
        body: U,
        responseType: T.Type,
        completion: ((Result<T, MarketapError>) -> Void)? = nil
    ) {
        let fullURLString = "\(baseURL.rawValue)\(path)"
        guard let url = URL(string: fullURLString) else {
            completion?(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            Logger.error("[MarketapAPI] encoding error: \(error.localizedDescription)")
            completion?(.failure(.encodingError(error)))
            return
        }

        logRequest(request, body: body)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.error("[MarketapAPI] response error: \(error.localizedDescription)")
                completion?(.failure(.networkError(error)))
                return
            }

            self.logResponse(response, data: data)

            guard let data = data else {
                Logger.error("[MarketapAPI] response error: no data")
                completion?(.failure(.noData))
                return
            }

            do {
                let wrappedResponse = try JSONDecoder().decode(ServerResponse<T>.self, from: data)
                completion?(.success(wrappedResponse.data))
            } catch {
                Logger.error("[MarketapAPI] decoding error: \(error.localizedDescription)")
                completion?(.failure(.decodingError(error)))
            }
        }
        task.resume()
    }

    func requestWithoutResponse<U: Encodable>(
        baseURL: BaseURL = .event,
        path: String,
        body: U,
        completion: ((Result<Void, MarketapError>) -> Void)? = nil
    ) {
        let fullURLString = "\(baseURL.rawValue)\(path)"
        guard let url = URL(string: fullURLString) else {
            completion?(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            Logger.error("[MarketapAPI] encoding error: \(error.localizedDescription)")
            completion?(.failure(.encodingError(error)))
            return
        }

        logRequest(request, body: body)

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                Logger.error("[MarketapAPI] response error: \(error.localizedDescription)")
                completion?(.failure(.networkError(error)))
                return
            }

            self.logResponse(response, data: nil)

            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("[MarketapAPI] response error: no data")
                completion?(.failure(.noData))
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                completion?(.success(()))
            } else {
                Logger.error("[MarketapAPI] status code invalid: \(httpResponse.statusCode)")
                completion?(.failure(.serverError(statusCode: httpResponse.statusCode)))
            }
        }
        task.resume()
    }
}
