//
//  IsolatedDefaults.swift
//  MarketapSDK
//
//  테스트가 UserDefaults.standard 를 직접 쓰면 시뮬레이터에 값이 영구히 남아, 다음 실행과
//  옆 테스트가 그 잔재를 본다. 실제로 세션 테스트 하나는 "통과"하고 있었는데 그건 로직이
//  맞아서가 아니라 이전 실행이 남긴 marketap_last_event_time 덕분이었다. 매 테스트가 빈
//  저장소에서 시작하도록 격리된 suite 를 만든다.
//

import Foundation
import XCTest

/// 테스트마다 고유한 빈 UserDefaults 를 만들고, 끝나면 통째로 지운다.
func makeIsolatedDefaults(_ testCase: XCTestCase, function: String = #function) -> UserDefaults {
    let suiteName = "marketap.tests.\(type(of: testCase)).\(function).\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("격리된 UserDefaults suite 를 만들지 못했다: \(suiteName)")
    }
    testCase.addTeardownBlock {
        defaults.removePersistentDomain(forName: suiteName)
    }
    return defaults
}

/// 조건이 참이 될 때까지 폴링한다.
///
/// 고정 지연 뒤에 한 번만 확인하면, 스위트 전체를 돌릴 때처럼 머신이 바쁠 땐 아직 진행 중인
/// 시점에 확인해서 산발적으로 실패한다(실제로 그렇게 깨졌다). 최종 상태를 기다린다.
func waitUntil(
    _ testCase: XCTestCase,
    timeout: TimeInterval = 4,
    _ description: String,
    condition: @escaping () -> Bool
) {
    let expectation = testCase.expectation(description: description)
    let queue = DispatchQueue(label: "marketap.tests.poll")
    let interval: TimeInterval = 0.05

    func poll(_ remaining: Int) {
        if condition() {
            expectation.fulfill()
            return
        }
        guard remaining > 0 else { return }
        queue.asyncAfter(deadline: .now() + interval) { poll(remaining - 1) }
    }
    queue.async { poll(Int(timeout / interval)) }

    testCase.wait(for: [expectation], timeout: timeout + 1)
}
