//
//  CampaignHideType.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

enum CampaignHideType: String {
    case hideForOneDay = "HIDE_FOR_ONE_DAY"
    case hideForSevenDays = "HIDE_FOR_SEVEN_DAYS"
    case hideForever = "HIDE_FOREVER"
    case close = "CLOSE"

    var hideDuration: TimeInterval {
        switch self {
        case .hideForOneDay:
            return 60 * 60 * 24
        case .hideForSevenDays:
            return 60 * 60 * 24 * 7
        case .hideForever:
            return .greatestFiniteMagnitude
        case .close:
            return 0
        }
    }
}
