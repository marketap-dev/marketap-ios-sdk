Pod::Spec.new do |spec|
  spec.name         = "MarketapSDK"
  spec.version      = "1.0.0-beta.11"
  spec.summary      = "MarketapSDK collects data and runs campaigns for Marketap Console."
  spec.description  = "MarketapSDK integrates with Marketap Console to collect user data, track events, and run personalized campaigns."

  spec.homepage     = "https://github.com/marketap-dev/marketap-ios-sdk.git"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Donghyun Lee" => "donghyun.lee@marketap.io" }
  spec.platform     = :ios, "13.0"
  spec.source       = { :git => "https://github.com/marketap-dev/marketap-ios-sdk.git", :tag => spec.version }
  spec.swift_version = "5.3"
  spec.requires_arc  = true

  spec.source_files = "Sources/MarketapSDK/**/*"
  spec.public_header_files = "Sources/MarketapSDK/**/*.h"
  spec.vendored_frameworks = "MarketapSDKCore.xcframework"
  spec.frameworks = "AdSupport", "CoreTelephony", "Network", "WebKit", "UserNotifications"
end
