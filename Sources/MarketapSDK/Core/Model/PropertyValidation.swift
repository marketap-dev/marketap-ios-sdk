import Foundation

/// 속성 값으로 보낼 수 있는지 판정한다.
/// 보낼 수 있는 값은 문자열, 정수, 유한한 실수, 불리언, null 과 이들로 이루어진 배열·딕셔너리다.
enum PropertyValidation {
    static func isSupported(_ value: Any) -> Bool {
        return (try? JSONEncoder().encode([AnyCodable(value)])) != nil
    }

    /// 보낼 수 없는 값을 가진 첫 속성 이름(이름순). 없으면 nil.
    static func unsupportedPropertyName(in properties: [String: Any]?) -> String? {
        guard let properties = properties else { return nil }
        return properties.keys.sorted().first { key in
            guard let value = properties[key] else { return false }
            return !isSupported(value)
        }
    }

    /// 보낼 수 없는 값을 가진 속성만 뺀 딕셔너리. 뺀 속성 이름은 onUnsupported 로 알린다.
    static func supportedProperties(
        _ properties: [String: Any],
        onUnsupported: (String) -> Void
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for key in properties.keys.sorted() {
            guard let value = properties[key] else { continue }
            if isSupported(value) {
                result[key] = value
            } else {
                onUnsupported(key)
            }
        }
        return result
    }
}
