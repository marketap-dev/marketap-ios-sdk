// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "MarketapSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "MarketapSDK",
            targets: ["MarketapSDK"]
        ),
        .library(
            name: "MarketapSDKNotificationServiceExtension",
            targets: ["MarketapSDKNotificationServiceExtension"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MarketapSDK",
            dependencies: [],
            path: "Sources/MarketapSDK"
        ),
        .target(
            name: "MarketapSDKNotificationServiceExtension",
            dependencies: [],
            path: "Sources/MarketapSDKNotificationServiceExtension"
        ),
        .testTarget(
            name: "MarketapSDKTests",
            dependencies: ["MarketapSDK"],
            path: "Sources/MarketapSDKTests"
        )
    ]
)
