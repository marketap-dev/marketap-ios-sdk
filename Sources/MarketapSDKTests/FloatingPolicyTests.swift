import XCTest
import UIKit
import WebKit
@testable import MarketapSDK

final class FloatingScreenFinderTests: XCTestCase {
    func testNavigationStackReturnsTopViewController() {
        let first = UIViewController()
        let second = UIViewController()
        let navigation = UINavigationController(rootViewController: first)
        navigation.setViewControllers([first, second], animated: false)

        XCTAssertTrue(FloatingScreenFinder.topMostViewController(from: navigation) === second)
    }

    func testTabBarDescendsIntoSelectedNavigation() {
        let home = UIViewController()
        let detail = UIViewController()
        let other = UIViewController()
        let homeNavigation = UINavigationController(rootViewController: home)
        homeNavigation.setViewControllers([home, detail], animated: false)
        let tab = UITabBarController()
        tab.setViewControllers([homeNavigation, other], animated: false)

        tab.selectedIndex = 0
        XCTAssertTrue(FloatingScreenFinder.topMostViewController(from: tab) === detail)
        tab.selectedIndex = 1
        XCTAssertTrue(FloatingScreenFinder.topMostViewController(from: tab) === other)
    }

    func testPlainRootAndNil() {
        let root = UIViewController()
        XCTAssertTrue(FloatingScreenFinder.topMostViewController(from: root) === root)
        XCTAssertNil(FloatingScreenFinder.topMostViewController(from: nil))
    }

    func testAlertsAreTransient() {
        XCTAssertTrue(FloatingScreenFinder.isTransientPresentation(UIAlertController(title: nil, message: nil, preferredStyle: .alert)))
        XCTAssertFalse(FloatingScreenFinder.isTransientPresentation(UIViewController()))
        XCTAssertFalse(FloatingScreenFinder.isTransientPresentation(UINavigationController()))
    }

    func testPresentedScreenIsTop() {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        defer { window.isHidden = true }

        let sheet = UIViewController()
        sheet.modalPresentationStyle = .fullScreen
        root.present(sheet, animated: false)
        XCTAssertTrue(FloatingScreenFinder.topMostViewController(from: root) === sheet)
        XCTAssertTrue(FloatingScreenFinder.topMostViewController(in: window) === sheet)

        sheet.dismiss(animated: false)
    }
}

final class FloatingTouchTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let bar = CGRect(x: 16, y: 732, width: 358, height: 60)

    func testCollapsedAcceptsOnlyBar() {
        XCTAssertTrue(FloatingContainerView.acceptsTouch(at: CGPoint(x: 100, y: 760), bounds: bounds, isExpanded: false, touchableRect: bar))
        XCTAssertFalse(FloatingContainerView.acceptsTouch(at: CGPoint(x: 100, y: 700), bounds: bounds, isExpanded: false, touchableRect: bar))
        XCTAssertFalse(FloatingContainerView.acceptsTouch(at: CGPoint(x: 100, y: 760), bounds: bounds, isExpanded: false, touchableRect: .zero))
    }

    func testExpandedAcceptsWholeBounds() {
        XCTAssertTrue(FloatingContainerView.acceptsTouch(at: CGPoint(x: 10, y: 10), bounds: bounds, isExpanded: true, touchableRect: bar))
        XCTAssertFalse(FloatingContainerView.acceptsTouch(at: CGPoint(x: 10, y: 900), bounds: bounds, isExpanded: true, touchableRect: bar))
    }

    func testHitTestReturnsOwnDescendantsOnly() {
        let container = FloatingContainerView(webView: WKWebView())
        container.frame = bounds
        container.layoutIfNeeded()
        container.touchableRect = bar

        XCTAssertNil(container.hitTest(CGPoint(x: 100, y: 100), with: nil))
        let barHit = container.hitTest(CGPoint(x: 100, y: 760), with: nil)
        XCTAssertNotNil(barHit)
        XCTAssertTrue(barHit?.isDescendant(of: container) == true)

        container.isExpanded = true
        let expandedHit = container.hitTest(CGPoint(x: 100, y: 100), with: nil)
        XCTAssertTrue(expandedHit?.isDescendant(of: container) == true)
    }
}

final class FloatingLayoutTests: XCTestCase {
    func testParsesStateAndRect() {
        let update = FloatingLayoutUpdate(body: ["state": "expanded", "rect": [1, 2, 3, 4]])
        XCTAssertEqual(update, FloatingLayoutUpdate(isExpanded: true, touchableRect: CGRect(x: 1, y: 2, width: 3, height: 4)))
    }

    func testMissingRectIsZeroAndUnknownStateIsCollapsed() {
        XCTAssertEqual(FloatingLayoutUpdate(body: ["state": NSNull(), "rect": NSNull()]),
                       FloatingLayoutUpdate(isExpanded: false, touchableRect: .zero))
        XCTAssertEqual(FloatingLayoutUpdate(body: ["state": "collapsed", "rect": [1, 2]]),
                       FloatingLayoutUpdate(isExpanded: false, touchableRect: .zero))
        XCTAssertNil(FloatingLayoutUpdate(body: "invalid"))
    }

    func testDocumentCarriesInsetsTimerAndWatcher() {
        let html = FloatingDocument.html(
            campaignHTML: "<div id=\"x\"></div>",
            insets: FloatingInsets(top: 59, bottom: 83),
            timerStartAt: Date(timeIntervalSince1970: 1_800_000_000.5)
        )
        XCTAssertTrue(html.contains("topSafeArea: 59"))
        XCTAssertTrue(html.contains("bottomSafeArea: 83"))
        XCTAssertTrue(html.contains("timerStartAt: 1800000000500"))
        XCTAssertTrue(html.contains("messageHandlers.\(FloatingDocument.layoutMessageName)"))
        XCTAssertTrue(html.contains("<div id=\"x\"></div>"))
    }
}

final class FloatingInsetsTests: XCTestCase {
    func testUsesSafeArea() {
        let safeArea = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
        XCTAssertEqual(FloatingInsets(safeArea: safeArea), FloatingInsets(top: 62, bottom: 34))
    }
}
