//
//  ServerResponse.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/18/25.
//

struct ServerResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T
}
