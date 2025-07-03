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
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }

    func handleClick(_ event: MarketapClickEvent) {
        clickHandler(event)
    }

    func setClickHandler(_ handler: @escaping (MarketapClickEvent) -> Void) {
        self.clickHandler = handler
    }

}
