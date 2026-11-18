import Foundation

/// 세션에서 마지막으로 들어온 UTM.
///
/// 이벤트 속성의 `mkt_utm_*` 나 `setPending` 으로 UTM이 들어오면 그 세트로 통째로 교체하고,
/// 그 이벤트와 같은 세션의 이후 이벤트에 `mkt_session_utm_*` 로 붙인다. `mkt_utm_*` 는 건드리지 않는다.
/// 세션이 바뀌면 이전 UTM은 쓰지 않는다. 빈 값은 없는 것으로 본다.
///
/// 원격 정책 sessionUtm 이 중지면 `isEnabled` 가 false 이고, 그동안은 저장도 부착도 하지 않는다.
final class SessionUtmStore {
    /// 이벤트가 일어난 페이지의 UTM 속성 키. 서버의 표준 이벤트 속성 이름과 같다.
    static let utmKeys = [
        "mkt_utm_source",
        "mkt_utm_medium",
        "mkt_utm_campaign",
        "mkt_utm_term",
        "mkt_utm_content",
    ]

    /// 세션에서 마지막으로 들어온 UTM을 담는 속성 키. `utmKeys` 와 같은 순서로 대응한다.
    static let sessionUtmKeys = [
        "mkt_session_utm_source",
        "mkt_session_utm_medium",
        "mkt_session_utm_campaign",
        "mkt_session_utm_term",
        "mkt_session_utm_content",
    ]

    /// 보관한 UTM을 다음 이벤트에 넘길 수 있는 시간. 세션 만료 시간과 같다.
    static let pendingTTL: TimeInterval = 1800

    private struct Stored: Codable {
        let sessionId: String
        let utm: [String: String]
    }

    private struct Pending: Codable {
        let utm: [String: String]
        let at: Date
    }

    private static let storageKey = "marketap_session_utm"
    private static let pendingKey = "marketap_session_utm_pending"
    private let cache: MarketapCacheProtocol
    private let now: () -> Date
    private let isEnabled: () -> Bool

    init(cache: MarketapCacheProtocol, now: @escaping () -> Date = Date.init, isEnabled: @escaping () -> Bool = { true }) {
        self.cache = cache
        self.now = now
        self.isEnabled = isEnabled
    }

    /// 다음 이벤트에 넘길 UTM으로 보관한다. 이벤트를 보내지 않는다.
    func setPending(_ utm: [String: String]) {
        guard isEnabled() else { return }
        let picked = Self.pickUtm(utm)
        guard !picked.isEmpty else { return }
        cache.saveCodableObject(Pending(utm: picked, at: now()), key: Self.pendingKey)
    }

    /// 세션을 여는 이벤트가 세션 시작 이벤트에 넘겨줄 세션 UTM. 보관 중인 UTM을 소비하지 않는다.
    func openingSessionUtm(_ properties: [String: Any]) -> [String: String] {
        guard isEnabled() else { return [:] }
        let incoming = Self.pickUtm(properties)
        return Self.toSessionUtm(incoming.isEmpty ? readPending() : incoming)
    }

    func apply(_ properties: [String: Any], sessionId: String) -> [String: Any] {
        guard isEnabled() else { return properties }
        var incoming = Self.pickUtm(properties)
        if incoming.isEmpty { incoming = readPending() }
        if !incoming.isEmpty {
            cache.saveCodableObject(Stored(sessionId: sessionId, utm: incoming), key: Self.storageKey)
            cache.clearObject(forKey: Self.pendingKey)
            return properties.merging(Self.toSessionUtm(incoming)) { _, new in new }
        }

        guard let stored: Stored = cache.loadCodableObject(forKey: Self.storageKey),
              stored.sessionId == sessionId else {
            return properties
        }
        return properties.merging(Self.toSessionUtm(Self.pickUtm(stored.utm))) { _, new in new }
    }

    private func readPending() -> [String: String] {
        guard let pending: Pending = cache.loadCodableObject(forKey: Self.pendingKey) else { return [:] }
        guard now().timeIntervalSince(pending.at) <= Self.pendingTTL else {
            cache.clearObject(forKey: Self.pendingKey)
            return [:]
        }
        return Self.pickUtm(pending.utm)
    }

    static func pickUtm(_ source: [String: Any]) -> [String: String] {
        var utm: [String: String] = [:]
        for key in utmKeys {
            if let value = source[key] as? String, !value.isEmpty {
                utm[key] = value
            }
        }
        return utm
    }

    static func toSessionUtm(_ utm: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, sessionKey) in zip(utmKeys, sessionUtmKeys) {
            if let value = utm[key] { result[sessionKey] = value }
        }
        return result
    }

    /// 링크의 `utm_*` 쿼리 파라미터를 `mkt_utm_*` 키로 꺼낸다. 해석할 수 없는 링크면 빈 값이다.
    static func utm(fromUrl url: String) -> [String: String] {
        guard let items = URLComponents(string: url.trimmingCharacters(in: .whitespaces))?.queryItems else { return [:] }
        var utm: [String: String] = [:]
        for key in utmKeys {
            let name = String(key.dropFirst("mkt_".count))
            if let value = items.first(where: { $0.name == name })?.value, !value.isEmpty {
                utm[key] = value
            }
        }
        return utm
    }
}
