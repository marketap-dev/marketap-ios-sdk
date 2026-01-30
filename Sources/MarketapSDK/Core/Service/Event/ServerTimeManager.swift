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
        var lastFetchedTimeMs: Int?
        var lastFetchedAtMs: Int?
    }
    private static var _cache = Cache()
    private static var _isFetching = false
    private static var _pending: [((Date?) -> Void)] = []

    private var cacheDurationMs: Int { 300_000 }
    private let api: MarketapAPIProtocol

    init(api: MarketapAPIProtocol) {
        self.api = api
    }

    func withServerTime(completion: @escaping (Date?) -> Void) {
        q.async { [weak self] in
            guard let self = self else { return }

            if let lastMs = Self._cache.lastFetchedTimeMs,
               let atMs = Self._cache.lastFetchedAtMs,
               Date().unixTime - atMs < self.cacheDurationMs {
                let elapsedMs = Date().unixTime - atMs
                let estimatedMs = lastMs + elapsedMs
                let estimated = Date(timeIntervalSince1970: Double(estimatedMs) / 1000)
                return DispatchQueue.main.async { completion(estimated) }
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

                        Self._cache.lastFetchedTimeMs = adjustedMs
                        Self._cache.lastFetchedAtMs = Date().unixTime

                        DispatchQueue.main.async {
                            completions.forEach { $0(adjustedDate) }
                        }

                    case .failure(let error):
                        MarketapLogger.warn("Failed to fetch server time: \(error.localizedDescription)")
                        let fallbackMs = Self._cache.lastFetchedTimeMs ?? Date().unixTime
                        let fallback = Date(timeIntervalSince1970: Double(fallbackMs) / 1000)
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
