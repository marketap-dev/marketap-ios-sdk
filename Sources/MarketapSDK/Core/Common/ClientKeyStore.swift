import Foundation

enum ClientKeyStore {
    static let appGroupInfoPlistKey = "MarketapAppGroupIdentifier"
    static let defaultsKeyPrefix = "marketap_client_key."

    static func save(
        _ clientKey: String?,
        projectId: String,
        bundle: Bundle = .main,
        defaultsProvider: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) {
        guard let groupId = bundle.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String, !groupId.isEmpty,
              let defaults = defaultsProvider(groupId) else { return }
        let key = defaultsKeyPrefix + projectId
        if let clientKey = clientKey {
            defaults.set(clientKey, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
