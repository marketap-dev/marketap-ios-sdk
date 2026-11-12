import XCTest
import UIKit
@testable import MarketapSDK

private final class FloatingDelegateRecorder: FloatingSessionDelegate {
    var closeReasons: [FloatingCloseReason] = []

    func floatingDidClick(locationId: String, url: String?) {}
    func floatingDidTrack(eventName: String, properties: [String: Any]?) {}
    func floatingDidSetUserProperties(_ properties: [String: Any]) {}
    func floatingDidClose(reason: FloatingCloseReason) {
        closeReasons.append(reason)
    }
}

private let bar = CGRect(x: 16, y: 700, width: 358, height: 60)

final class FloatingWindowTests: XCTestCase {
    private func makeWindow() -> FloatingWindow {
        let session = FloatingSession()
        let window = FloatingWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844), container: session.container)
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    func testContainerFillsWindow() {
        let window = makeWindow()
        XCTAssertEqual(window.container.frame, window.bounds)
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func testCollapsedPassesTouchesOutsideBarToApp() {
        let window = makeWindow()
        window.container.touchableRect = bar

        XCTAssertNil(window.hitTest(CGPoint(x: 200, y: 300), with: nil))
        XCTAssertNotNil(window.hitTest(CGPoint(x: 200, y: 730), with: nil))
    }

    func testExpandedCapturesWholeWindow() {
        let window = makeWindow()
        window.container.isExpanded = true

        XCTAssertNotNil(window.hitTest(CGPoint(x: 200, y: 300), with: nil))
    }
}

final class FloatingSessionTests: XCTestCase {
    func testLayoutUpdateSetsTouchAreaAndExpansion() {
        let session = FloatingSession()
        session.handleLayout(FloatingLayoutUpdate(isExpanded: false, touchableRect: bar))
        XCTAssertEqual(session.container.touchableRect, bar)
        XCTAssertFalse(session.isExpanded)

        session.handleLayout(FloatingLayoutUpdate(isExpanded: true, touchableRect: .zero))
        XCTAssertTrue(session.isExpanded)
    }

    func testCloseNotifiesOnceAndRemovesContainer() {
        let recorder = FloatingDelegateRecorder()
        let session = FloatingSession()
        session.delegate = recorder
        let host = UIView()
        host.addSubview(session.container)

        session.close(reason: .dismissed)
        session.close(reason: .dismissed)

        XCTAssertEqual(recorder.closeReasons, [.dismissed])
        XCTAssertNil(session.container.superview)
        session.handleLayout(FloatingLayoutUpdate(isExpanded: true, touchableRect: .zero))
        XCTAssertFalse(session.isExpanded)
    }
}

final class FloatingPresenterTests: XCTestCase {
    private var presenter: FloatingPresenter!
    private var recorder: FloatingDelegateRecorder!
    private var windows: [FloatingWindow] = []

    override func setUp() {
        super.setUp()
        recorder = FloatingDelegateRecorder()
        windows = []
        presenter = FloatingPresenter(makeWindow: { [unowned self] container in
            let window = FloatingWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844), container: container)
            self.windows.append(window)
            return window
        })
    }

    override func tearDown() {
        presenter.dismiss()
        super.tearDown()
    }

    private func show() -> FloatingSession? {
        presenter.show(html: "<div></div>", impressionAt: Date(), delegate: recorder)
    }

    func testShowOpensOneVisibleWindowOnlyOnce() {
        let session = show()
        XCTAssertNotNil(session)
        XCTAssertNil(show())
        XCTAssertEqual(windows.count, 1)
        XCTAssertTrue(presenter.isShowing)
        XCTAssertTrue(presenter.isWindowVisible)
        XCTAssertTrue(session?.container.window === windows.first)
    }

    func testShowFailsWithoutWindow() {
        let noWindow = FloatingPresenter(makeWindow: { _ in nil })
        XCTAssertNil(noWindow.show(html: "<div></div>", impressionAt: Date(), delegate: recorder))
        XCTAssertFalse(noWindow.isShowing)
    }

    func testCloseHidesWindowAndFreesSlot() {
        let session = show()
        session?.close(reason: .hidden(until: 0))

        XCTAssertFalse(presenter.isShowing)
        XCTAssertFalse(presenter.isWindowVisible)
        XCTAssertTrue(windows.first?.isHidden ?? false)
        XCTAssertEqual(recorder.closeReasons, [.hidden(until: 0)])
        XCTAssertNotNil(show())
    }
}
