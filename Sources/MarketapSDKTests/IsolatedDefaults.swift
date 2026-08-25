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

    // 조건이 끝내 참이 안 되면 wait 는 실패하고 테스트가 끝나는데, 예약된 폴링은 그대로
    // 남는다. 그 폴링이 tearDown 이 이미 nil 로 만든 프로퍼티를 건드리면 프로세스가 죽고
    // **스위트 전체가 0개 실행으로 날아간다**(실제로 CI 에서 그렇게 됐다).
    // 테스트가 끝나면 더 돌지 않도록 끊는다.
    let stopped = PollStopFlag()
    testCase.addTeardownBlock { stopped.stop() }

    func poll(_ remaining: Int) {
        if stopped.isStopped { return }
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

/// 폴링 중단 플래그. 폴링 큐와 tearDown 스레드에서 같이 만지므로 락으로 보호한다.
final class PollStopFlag {
    private let lock = NSLock()
    private var value = false

    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func stop() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
