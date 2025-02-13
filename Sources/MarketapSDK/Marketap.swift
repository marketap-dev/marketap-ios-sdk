//
//  Marketap.swift
//  IOSPushTest
//
//  Created by 이동현 on 2/11/25.
//

import Foundation

/// Marketap SDK - SDK 사용을 위한 정적 메서드를 제공합니다.
@objcMembers
public class Marketap: NSObject {
    
    public static var client: MarketapClient = MarketapClientImpl()

    private override init() {}
}
