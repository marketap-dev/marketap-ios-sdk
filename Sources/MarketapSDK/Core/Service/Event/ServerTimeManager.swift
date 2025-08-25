//
//  ServerTimeManager.swift
//  MarketapSDK
//
//  Created by 이동현 on 8/25/25.
//

import Foundation

protocol ServerTimeManagerProtocol {
    func withServerTime(completion: @escaping (Date?) -> Void)
}

class ServerTimeManager: ServerTimeManagerProtocol {
    // MARK: - Thread-safety
    private static let timeSyncQueue = DispatchQueue(label: "marketap.time-sync")
    private var q: DispatchQueue { Self.timeSyncQueue }

    private struct Cache {
        var lastFetchedTime: Date?
        var lastFetchedAt: Date?
    }
    private static var _cache = Cache()
    private static var _isFetching = false
    private static var _pending: [((Date?) -> Void)] = []

    private var cacheDuration: TimeInterval { 300 }
    private let api: MarketapAPIProtocol

    init(api: MarketapAPIProtocol) {
        self.api = api
    }

    func withServerTime(completion: @escaping (Date?) -> Void) {
        q.async { [weak self] in
            guard let self = self else { return }

            if let last = Self._cache.lastFetchedTime,
               let at = Self._cache.lastFetchedAt,
               Date().timeIntervalSince(at) < self.cacheDuration {
                return DispatchQueue.main.async { completion(last) }
            }

            if Self._isFetching {
                Self._pending.append(completion)
                return
            }

            Self._isFetching = true
            Self._pending.append(completion)

            let now = Date()
            let localMs = now.unixTime
            let startMs = localMs

            self.api.get(
                baseURL: .crm,
                path: "/api/v1/meta/server-info",
                queryItems: [URLQueryItem(name: "client_time", value: String(localMs))],
                responseType: SyncDateResponse.self
            ) { [weak self] result in
                guard let self = self else { return }
                let endMs = Date().unixTime
                let rttMs = endMs - startMs

                self.q.async {
                    let completions = Self._pending
                    Self._pending.removeAll()
                    Self._isFetching = false

                    switch result {
                    case .success(let data):
                        let adjustedMs = Date().unixTime + data.serverTimeOffset - rttMs / 2
                        let adjustedDate = Date(timeIntervalSince1970: Double(adjustedMs) / 1000)

                        Self._cache.lastFetchedTime = adjustedDate
                        Self._cache.lastFetchedAt = Date()

                        DispatchQueue.main.async {
                            completions.forEach { $0(adjustedDate) }
                        }

                    case .failure(let error):
                        Logger.warn("Failed to fetch server time: \(error.localizedDescription)")
                        let fallback = Self._cache.lastFetchedTime ?? Date()
                        DispatchQueue.main.async {
                            completions.forEach { $0(fallback) }
                        }
                    }
                }
            }
        }
    }
}

extension Date {
    var unixTime: Int { Int(timeIntervalSince1970 * 1000) } // ms
}
