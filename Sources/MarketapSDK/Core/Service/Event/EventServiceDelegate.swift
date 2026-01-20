//
//  EventServiceDelegate.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol EventServiceDelegate: AnyObject {
    func handleUserIdChanged()
    func onEvent(eventRequest: IngestEventRequest, device: Device, fromWebBridge: Bool)
}
