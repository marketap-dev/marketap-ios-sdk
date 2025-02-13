Pod::Spec.new do |spec|
  spec.name         = "MarketapSDK"
  spec.version      = "1.0.0-beta.6"
  spec.summary      = "MarketapSDK collects data and runs campaigns for Marketap Console."
  spec.description  = "MarketapSDK integrates with Marketap Console to collect user data, track events, and run personalized campaigns."

  spec.homepage     = "https://github.com/marketap-dev/marketap-ios-sdk.git"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Donghyun Lee" => "donghyun.lee@marketap.io" }
  spec.platform     = :ios, "13.0"
  spec.source       = { :git => "https://github.com/marketap-dev/marketap-ios-sdk.git", :tag => spec.version }
  spec.swift_version = "5.3"
  spec.requires_arc  = true

  spec.subspec "Core" do |core|
    core.source_files = "Sources/MarketapSDK/**/*"
    core.public_header_files = "Sources/MarketapSDK/**/*.h"
    core.vendored_frameworks = "MarketapSDKCore.xcframework"
    core.frameworks = "AdSupport", "CoreTelephony", "Network", "WebKit", "UserNotifications"
  end

  spec.subspec "NotificationServiceExtension" do |extension|
    extension.source_files = "Sources/MarketapSDKNotificationServiceExtension/**/*"
    extension.public_header_files = "Sources/MarketapSDKNotificationServiceExtension/**/*.h"
    extension.frameworks = "UserNotifications"
  end

  spec.default_subspecs = "Core"
end
