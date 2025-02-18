//
//  MarketapError.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

enum MarketapError: Error {
    case invalidURL
    case noData
    case encodingError(Error)
    case decodingError(Error)
    case networkError(Error)
    case serverError(statusCode: Int)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL provided."
        case .noData:
            return "No data received from server."
        case .encodingError(let error):
            return "Encoding failed: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let statusCode):
            return "Server error with status code: \(statusCode)"
        }
    }
}
