//
//  EventServiceDelegate.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation

protocol EventServiceDelegate: AnyObject {
    /// - Parameter fromAnonymous: 익명에서 로그인한 경우 true. 이때는 같은 사람으로 보고 인앱 지연 예약·누적 횟수를 유지한다.
    func handleUserIdChanged(fromAnonymous: Bool)
    func onEvent(eventRequest: IngestEventRequest, device: Device, origin: InAppWebOrigin?)
}
