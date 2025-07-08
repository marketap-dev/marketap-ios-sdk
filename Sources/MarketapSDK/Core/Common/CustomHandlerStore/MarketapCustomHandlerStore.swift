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

    var customized: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "MarketapClickCustomized") as? NSNumber)?.boolValue ?? false
    }

    func handleClick(_ event: MarketapClickEvent) {
        if customized {
            if let handler = clickHandler {
                Logger.debug("custom handler: \(event.campaignType) clicked with url \(event.url ?? "null")")
                handler(event)
            } else {
                Logger.debug("custom handler not set, store event: \(event.campaignType) \(event.url ?? "null")")
                storedEvent = event
            }
        } else {
            Logger.debug("default handler: \(event.campaignType) clicked with url \(event.url ?? "null")")
            if let urlString = event.url, let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
    }

    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void) {
        guard customized else {
            Logger.warn("MarketapClickCustomized is not set. Please set this key in Info.plist to enable the custom click handler.")
            return
        }

        self.clickHandler = handler
        if let event = storedEvent {
            self.storedEvent = nil
            handleClick(event)
        }
    }

}
