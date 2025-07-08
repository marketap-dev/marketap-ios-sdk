//
//  MarketapCustomHandlerStore.swift
//  MarketapSDK
//
//  Created by 이동현 on 6/19/25.
//

import Foundation
import UIKit

final class MarketapCustomHandlerStore: MarketapCustomHandlerStoreProtocol {
    var storedEvent: MarketapClickEvent?
    var clickHandler: ((MarketapClickEvent) -> Void)?

    func handleClick(_ event: MarketapClickEvent) {
        let customized = Bundle.main.object(forInfoDictionaryKey: "MarketapClickCustomized") as? Bool
        if customized == true {
            if let handler = clickHandler {
                Logger.debug("custom handler: \(event.campaignType) clicked with url \(event.url ?? "null")")
                handler(event)
            } else {
                Logger.debug("custom handler not set, store event: \(event.campaignType) \(event.url ?? "null")")
                storedEvent = event
            }
        } else {
            if let urlString = event.url, let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    Logger.debug("default handler: \(event.campaignType) clicked with url \(event.url ?? "null")")
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
    }

    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void) {
        self.clickHandler = handler
        if let event = storedEvent {
            self.storedEvent = nil
            handleClick(event)
        }
    }

}
