//
//  EventServiceDelegate.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

protocol EventServiceDelegate: AnyObject {
    func handleUserIdChanged()
    func onEvent(eventRequest: IngestEventRequest, device: Device)
}
