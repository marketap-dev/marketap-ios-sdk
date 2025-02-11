// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "MarketapSDK",
    platforms: [
        .iOS(.v14)  // 최소 지원 iOS 버전 설정
    ],
    products: [
        .library(
            name: "MarketapSDK",
            targets: ["MarketapSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MarketapSDK",
            dependencies: [],
            path: "Sources/MarketapSDK"
        )
    ]
)

