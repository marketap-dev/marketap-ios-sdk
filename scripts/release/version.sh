#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PODSPECS=(MarketapSDK.podspec MarketapSDKNotificationServiceExtension.podspec)
SWIFT=(Sources/MarketapSDK/Core/Model/MarketapConfig.swift)
grep -q 'nativeSdkVersion = "' Sources/MarketapSDKNotificationServiceExtension/MarketapNotificationServiceClient.swift &&
  SWIFT+=(Sources/MarketapSDKNotificationServiceExtension/MarketapNotificationServiceClient.swift)
versions() {
  sed -nE 's/^ *spec\.version *= *"([^"]+)".*/\1/p' "${PODSPECS[@]}"
  sed -nE 's/.*static let nativeSdkVersion = "([^"]+)".*/\1/p' "${SWIFT[@]}"
}
case "${1:-}" in
  get) sed -nE 's/^ *spec\.version *= *"([^"]+)".*/\1/p' MarketapSDK.podspec ;;
  set)
    perl -pi -e "s/^( *spec\.version *= *\")[^\"]*/\${1}$2/" "${PODSPECS[@]}"
    perl -pi -e "s/(static let nativeSdkVersion = \")[^\"]*/\${1}$2/" "${SWIFT[@]}"
    ;;
  files) printf '%s\n' "${PODSPECS[@]}" "${SWIFT[@]}" ;;
  check) [ "$(versions | wc -l)" -eq $((${#PODSPECS[@]} + ${#SWIFT[@]})) ] && [ "$(versions | sort -u | wc -l)" -eq 1 ] ;;
  *) exit 2 ;;
esac
