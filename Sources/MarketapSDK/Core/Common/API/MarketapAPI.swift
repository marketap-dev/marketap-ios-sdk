//
//  MarketapAPI.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

class MarketapAPI {
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
            completion?(.failure(.encodingError(error)))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion?(.failure(.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion?(.failure(.noData))
                return
            }
            
            do {
                let decodedResponse = try JSONDecoder().decode(responseType, from: data)
                completion?(.success(decodedResponse))
            } catch {
                completion?(.failure(.decodingError(error)))
            }
        }
        task.resume()
    }

    /// ✅ 응답 형식과 관계없이 `Result<Void, MarketapError>` 반환
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
            completion?(.failure(.encodingError(error)))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion?(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion?(.failure(.noData))
                return
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                completion?(.success(())) // ✅ 응답 없이 성공 처리
            } else {
                completion?(.failure(.serverError(statusCode: httpResponse.statusCode)))
            }
        }
        task.resume()
    }
}
