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
                Logger.debug("[MarketapCustomHandlerStore] default handler - \(event.campaignType) clicked with url: \(event.url ?? "")")
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    func handleClick(_ event: MarketapClickEvent) {
        Logger.verbose("[MarketapCustomHandlerStore] handle click")
        clickHandler(event)
    }

    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void) {
        Logger.verbose("[MarketapCustomHandlerStore] set click handler")
        self.clickHandler = { event in
            Logger.debug("[MarketapCustomHandlerStore] custom handler - \(event.campaignType) clicked with url: \(event.url ?? "")")
            handler(event)
        }
    }

}
