# Changelog

## 1.6.2 (2026-11-24)

이벤트 플로우와 이벤트 횟수 조건을 같이 쓸 때, 도달을 센 뒤 진입 이벤트가 다시 와도 쌓인 횟수가 초기화되지 않도록 수정

## What's Changed
* release: 1.6.1 by @marketap-sdk-release[bot] in https://github.com/marketap-dev/marketap-ios-sdk/pull/42
* [NT-1139] 플로우에서 도달 횟수를 센 뒤의 진입 이벤트를 무시 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/43


**Full Changelog**: https://github.com/marketap-dev/marketap-ios-sdk/compare/1.6.1...1.6.2


## 1.6.1 (2026-11-23)

## What's Changed
* release: 1.6.0 by @marketap-sdk-release[bot] in https://github.com/marketap-dev/marketap-ios-sdk/pull/29
* [NT-1046] 느린 CI 에서 흔들리던 테스트 2개 수정 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/30
* release: 1.6.1-beta.1 by @marketap-sdk-release[bot] in https://github.com/marketap-dev/marketap-ios-sdk/pull/31
* fix: CocoaPods trunk 타임아웃 후 반영 대기 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/32
* release: 1.6.1-beta.2 by @marketap-sdk-release[bot] in https://github.com/marketap-dev/marketap-ios-sdk/pull/33
* fix: CocoaPods trunk push 재시도 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/34
* [NT-1111] 인앱 팝업을 전용 창에 띄우는 Braze 방식으로 전환 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/35
* [NT-1111] 백그라운드 shutdown 테스트를 전용 스레드에서 호출 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/36
* [NT-1151] 세션 UTM 자동 처리 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/37
* [NT-1152] 인앱 트리거 "또는" 조건 지원 및 캠페인 API v3 전환 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/38
* [NT-1111] 앱 인앱 지연 노출·이벤트 횟수 조건·N분 타이머 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/39
* [NT-1139] 앱 인앱 이벤트 플로우 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/40
* [NT-1144] iOS SDK 안정성 점검 후속 수정 by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/41


**Full Changelog**: https://github.com/marketap-dev/marketap-ios-sdk/compare/1.6.0...1.6.1


## 1.6.1-beta.2 (2026-11-12)

배포 경로 점검용 베타 (trunk 반영 대기 확인)

## What's Changed
* release: 1.6.1-beta.1 by @marketap-sdk-release[bot] in https://github.com/marketap-dev/marketap-ios-sdk/pull/31
* fix: CocoaPods trunk 타임아웃 후 반영 대기 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/32


**Full Changelog**: https://github.com/marketap-dev/marketap-ios-sdk/compare/1.6.1-beta.1...1.6.1-beta.2


## 1.6.1-beta.1 (2026-11-12)

배포 경로 점검용 베타

## What's Changed
* release: 1.6.0 by @marketap-sdk-release[bot] in https://github.com/marketap-dev/marketap-ios-sdk/pull/29
* [NT-1046] 느린 CI 에서 흔들리던 테스트 2개 수정 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/30


**Full Changelog**: https://github.com/marketap-dev/marketap-ios-sdk/compare/1.6.0...1.6.1-beta.1


## 1.6.0 (2026-11-12)

## What's Changed
* [NT-1046] 릴리즈 workflow 추가 (SPM + CocoaPods, NSE 같은 번호) by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/23
* [NT-1046] release PR 기준 커밋 입력 제거 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/24
* release: 1.5.1-beta.1 by @marketap-sdk-release[bot] in https://github.com/marketap-dev/marketap-ios-sdk/pull/25
* [NT-1046] trunk push 에서 --synchronous 제거 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/26
* [NT-1046] trunk push 시간 초과여도 실제로 올라갔으면 성공 처리 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/27
* [NT-1046] SDK 클라이언트 키 · 식별 헤더 · 원격 중지 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/22
* [NT-1111] 앱 인앱 플로팅·화면 이동 처리 (iOS) by @yumin-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/28

## New Contributors
* @jiwon-marketap made their first contribution in https://github.com/marketap-dev/marketap-ios-sdk/pull/23
* @marketap-sdk-release[bot] made their first contribution in https://github.com/marketap-dev/marketap-ios-sdk/pull/25

**Full Changelog**: https://github.com/marketap-dev/marketap-ios-sdk/compare/1.5.0...1.6.0


## 1.5.1-beta.1 (2026-11-11)

릴리즈 흐름 테스트

## What's Changed
* [NT-1046] 릴리즈 workflow 추가 (SPM + CocoaPods, NSE 같은 번호) by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/23
* [NT-1046] release PR 기준 커밋 입력 제거 by @jiwon-marketap in https://github.com/marketap-dev/marketap-ios-sdk/pull/24

## New Contributors
* @jiwon-marketap made their first contribution in https://github.com/marketap-dev/marketap-ios-sdk/pull/23

**Full Changelog**: https://github.com/marketap-dev/marketap-ios-sdk/compare/1.5.0...1.5.1-beta.1

