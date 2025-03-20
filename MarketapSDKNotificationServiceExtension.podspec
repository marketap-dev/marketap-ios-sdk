Pod::Spec.new do |spec|
  spec.name         = "MarketapSDKNotificationServiceExtension"
  spec.version      = "1.0.2"
  spec.summary      = "Marketap SDK Notification Service Extension"
  spec.description  = "Marketap SDK's extension for handling notifications."

  spec.homepage     = "https://github.com/marketap-dev/marketap-ios-sdk.git"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Donghyun Lee" => "donghyun.lee@marketap.io" }
  spec.platform     = :ios, "13.0"
  spec.source       = { :git => "https://github.com/marketap-dev/marketap-ios-sdk.git", :tag => spec.version }
  spec.swift_version = "5.0"

  spec.source_files = "Sources/MarketapSDKNotificationServiceExtension/**/*"
  spec.public_header_files = "Sources/MarketapSDKNotificationServiceExtension/**/*.h"
end