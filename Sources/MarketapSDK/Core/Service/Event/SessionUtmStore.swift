import Foundation

/// 세션 동안 유지하는 UTM.
///
/// 이벤트 속성에 UTM이 하나라도 있으면 그 세트로 통째로 교체하고 속성은 그대로 둔다.
/// 없으면 같은 세션에 저장된 UTM을 붙인다. 세션이 바뀌면 이전 UTM은 쓰지 않는다. 빈 값은 없는 것으로 본다.
final class SessionUtmStore {
    /// 세션 동안 유지하는 UTM 속성 키. 서버의 표준 이벤트 속성 이름과 같다.
    static let utmKeys = [
        "mkt_utm_source",
        "mkt_utm_medium",
        "mkt_utm_campaign",
        "mkt_utm_term",
        "mkt_utm_content",
    ]

    private struct Stored: Codable {
        let sessionId: String
        let utm: [String: String]
    }

    private static let storageKey = "marketap_session_utm"
    private let cache: MarketapCacheProtocol

    init(cache: MarketapCacheProtocol) {
        self.cache = cache
    }

    func apply(_ properties: [String: Any], sessionId: String) -> [String: Any] {
        let incoming = Self.pickUtm(properties)
        if !incoming.isEmpty {
            cache.saveCodableObject(Stored(sessionId: sessionId, utm: incoming), key: Self.storageKey)
            return properties
        }

        guard let stored: Stored = cache.loadCodableObject(forKey: Self.storageKey),
              stored.sessionId == sessionId else {
            return properties
        }
        let utm = Self.pickUtm(stored.utm)
        guard !utm.isEmpty else { return properties }
        return properties.merging(utm) { _, new in new }
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
}
