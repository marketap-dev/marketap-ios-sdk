Pod::Spec.new do |spec|
  spec.name         = "MarketapSDK"
  spec.version      = "1.0.0"
  spec.summary      = "Marketap SDK for iOS"
  spec.description  = "A powerful marketing SDK for in-app messaging."
  spec.homepage     = "https://github.com/marketap/MarketapSDK"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Your Name" => "your@email.com" }
  spec.platform     = :ios, "11.0"
  spec.source       = { :git => "https://github.com/marketap/MarketapSDK.git", :tag => spec.version }
  spec.swift_version = "5.3"

  spec.source_files  = "Sources/**/*.swift"
  spec.framework     = "Foundation"
end

