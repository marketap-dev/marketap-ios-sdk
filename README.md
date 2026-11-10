# MarketapSDK

[![Version](https://img.shields.io/cocoapods/v/MarketapSDK.svg?style=flat)](https://cocoapods.org/pods/MarketapSDK)
[![License](https://img.shields.io/cocoapods/l/MarketapSDK.svg?style=flat)](https://cocoapods.org/pods/MarketapSDK)
[![Platform](https://img.shields.io/cocoapods/p/MarketapSDK.svg?style=flat)](https://cocoapods.org/pods/MarketapSDK)

## 문서
[Marketap iOS SDK 문서](https://docs.marketap.io/t3ZS4WXNMj0HK27EtIMV/developer/push-notification/integration/ios)

## 클라이언트 키와 App Group 설정

프로젝트에 클라이언트 키가 필요한 경우 `Marketap.initialize(projectId:clientKey:)`로 키를 전달합니다. 푸시 노출 이벤트를 보내는 Notification Service Extension은 별도 프로세스이므로 App Group으로 키를 공유합니다.

1. 앱 타깃과 Notification Service Extension 타깃 모두 Signing & Capabilities에서 App Groups capability를 켜고 같은 그룹(예: `group.com.example.app`)을 선택합니다. 두 타깃의 `com.apple.security.application-groups` entitlement가 같아야 합니다.
2. 두 타깃의 Info.plist에 같은 그룹 ID를 `MarketapAppGroupIdentifier` 키(String)로 추가합니다.
3. 앱에서 `Marketap.initialize(projectId:clientKey:)`를 호출하면 SDK가 projectId별로 키를 App Group에 저장하고, Extension이 푸시 payload의 projectId로 읽어 `X-Marketap-Client-Key` 헤더에 붙입니다.

설정이 없거나 읽을 수 없으면 Extension은 키 없이 전송합니다.
