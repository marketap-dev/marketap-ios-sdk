//
//  MarketapAPIProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol MarketapAPIProtocol {
    func get<T: Decodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        queryItems: [URLQueryItem]?,
        responseType: T.Type,
        completion: ((Result<T, MarketapError>) -> Void)?
    )

    func request<T: Decodable, U: Encodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        body: U,
        responseType: T.Type,
        completion: ((Result<T, MarketapError>) -> Void)?
    )

    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        body: U,
        completion: ((Result<Void, MarketapError>) -> Void)?
    )
}

extension MarketapAPIProtocol {
    func requestWithoutResponse<U: Encodable>(
        baseURL: MarketapAPI.BaseURL,
        path: String,
        body: U
    ) {
        requestWithoutResponse(baseURL: baseURL, path: path, body: body, completion: nil)
    }
}
