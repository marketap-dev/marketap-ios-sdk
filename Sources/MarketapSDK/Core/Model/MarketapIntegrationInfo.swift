import Foundation

public struct MarketapIntegrationInfo: Codable, Equatable {
    public let sdkType: String
    public let sdkVersion: String

    public init(sdkType: String, sdkVersion: String) {
        self.sdkType = sdkType
        self.sdkVersion = sdkVersion
    }
}
