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
    private var _cache = Cache()
    private var _isFetching = false
    private var _pending: [((Date?) -> Void)] = []
    private var _lastFailedAt: Date?

    static var useWebClickRouting = false

    private var cacheDurationMs: Int { 300_000 }
    private let api: MarketapAPIProtocol
    private let projectId: String
    private let policyStore: RemotePolicyStore
    private let now: () -> Date

    init(api: MarketapAPIProtocol, projectId: String, policyStore: RemotePolicyStore? = nil, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.projectId = projectId
        self.policyStore = policyStore ?? RemotePolicyStore(projectId: projectId)
        self.now = now
    }

    func withServerTime(completion: @escaping (Date?) -> Void) {
        q.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let retryDelayed = self._lastFailedAt.map { self.now().timeIntervalSince($0) < 60 } ?? false
            if let lastMs = self._cache.lastFetchedTimeMs,
               let atMs = self._cache.lastFetchedAtMs,
               retryDelayed || (Date().unixTime - atMs < self.cacheDurationMs && !self.policyStore.needsRefresh) {
                let elapsedMs = Date().unixTime - atMs
                let estimatedMs = lastMs + elapsedMs
                let estimated = Date(timeIntervalSince1970: Double(estimatedMs) / 1000)
                return DispatchQueue.main.async { completion(estimated) }
            }

            if retryDelayed {
                return DispatchQueue.main.async { completion(Date()) }
            }

            if self._isFetching {
                self._pending.append(completion)
                return
            }

            self._isFetching = true
            self._pending.append(completion)

            let now = Date()
            let localMs = now.unixTime
            let startMs = localMs

            self.api.get(
                baseURL: .crm,
                path: "/api/v2/meta/server-info",
                queryItems: [
                    URLQueryItem(name: "project_id", value: self.projectId),
                    URLQueryItem(name: "client_time", value: String(localMs))
                ],
                responseType: SyncDateResponse.self
            ) { result in
                let endMs = Date().unixTime
                let rttMs = endMs - startMs

                Self.timeSyncQueue.async {
                    let completions = self._pending
                    self._pending.removeAll()
                    self._isFetching = false

                    switch result {
                    case .success(let data):
                        self._lastFailedAt = nil
                        let adjustedMs = Date().unixTime + data.serverTimeOffset - rttMs / 2
                        let adjustedDate = Date(timeIntervalSince1970: Double(adjustedMs) / 1000)

                        self._cache.lastFetchedTimeMs = adjustedMs
                        self._cache.lastFetchedAtMs = Date().unixTime
                        Self.useWebClickRouting = data.useWebClickRouting
                        self.policyStore.received(data.sdkPolicy)

                        DispatchQueue.main.async {
                            completions.forEach { $0(adjustedDate) }
                        }

                    case .failure(let error):
                        MarketapLogger.warn("Failed to fetch server time: \(error.localizedDescription)")
                        self._lastFailedAt = self.now()
                        let fallbackMs = self._cache.lastFetchedTimeMs ?? Date().unixTime
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
