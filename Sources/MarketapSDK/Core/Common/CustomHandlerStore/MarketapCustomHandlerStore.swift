//
//  MarketapCustomHandlerStore.swift
//  MarketapSDK
//
//  Created by 이동현 on 6/19/25.
//

import Foundation
import UIKit

final class MarketapCustomHandlerStore: MarketapCustomHandlerStoreProtocol {
    var clickHandler: (MarketapClickEvent) -> Void = { event in
        if let urlString = event.url, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                Logger.debug("default handler: \(event.campaignType) clicked with url \(event.url ?? "null")")
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    func handleClick(_ event: MarketapClickEvent) {
        Logger.verbose("handle click")
        clickHandler(event)
    }

    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void) {
        self.clickHandler = { event in
            Logger.debug("custom handler: \(event.campaignType) clicked with url \(event.url ?? "null")")
            handler(event)
        }
    }

}
