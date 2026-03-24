//
//  MarketapConfig.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import Foundation

struct MarketapConfig: Codable, Equatable {
    static let nativeSdkVersion = "1.4.0"
    static let nativeSdkType = "ios"
    let projectId: String
    let sdkType: String
    let sdkVersion: String
}
