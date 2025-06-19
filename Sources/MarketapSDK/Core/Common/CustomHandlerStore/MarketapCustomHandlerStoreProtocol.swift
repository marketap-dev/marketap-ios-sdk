//
//  MarketapCustomHandlerStoreProtocol.swift
//  MarketapSDK
//
//  Created by 이동현 on 6/19/25.
//

import Foundation

protocol MarketapCustomHandlerStoreProtocol: AnyObject {
    func handleClick(_ event: MarketapClickEvent)
    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void)
}

