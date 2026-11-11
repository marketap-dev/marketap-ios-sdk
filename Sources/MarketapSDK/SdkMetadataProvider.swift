import Foundation

enum SdkMetadataProvider {
    static let nativeIntegrationInfo = MarketapIntegrationInfo(
        sdkType: MarketapConfig.nativeSdkType,
        sdkVersion: MarketapConfig.nativeSdkVersion
    )

    static func createNativeConfig(projectId: String, clientKey: String? = nil) -> MarketapConfig {
        createConfig(projectId: projectId, integrationInfo: nativeIntegrationInfo, clientKey: clientKey)
    }

    static func createConfig(projectId: String, integrationInfo: MarketapIntegrationInfo, clientKey: String? = nil) -> MarketapConfig {
        MarketapConfig(
            projectId: projectId,
            sdkType: integrationInfo.sdkType,
            sdkVersion: integrationInfo.sdkVersion,
            clientKey: normalizeClientKey(clientKey)
        )
    }

    static func normalizeClientKey(_ clientKey: String?) -> String? {
        guard let key = clientKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            MarketapLogger.debug("[Marketap] Initialized without a client key.")
            return nil
        }
        guard key.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) == nil else { return key }
        MarketapLogger.warn("[Marketap] Invalid client key format. Requests will be sent without a client key.")
        return nil
    }
}
