import Foundation

enum SdkMetadataProvider {
    static let nativeIntegrationInfo = MarketapIntegrationInfo(
        sdkType: MarketapConfig.nativeSdkType,
        sdkVersion: MarketapConfig.nativeSdkVersion
    )

    static func createNativeConfig(projectId: String) -> MarketapConfig {
        createConfig(projectId: projectId, integrationInfo: nativeIntegrationInfo)
    }

    static func createConfig(projectId: String, integrationInfo: MarketapIntegrationInfo) -> MarketapConfig {
        MarketapConfig(
            projectId: projectId,
            sdkType: integrationInfo.sdkType,
            sdkVersion: integrationInfo.sdkVersion
        )
    }
}
