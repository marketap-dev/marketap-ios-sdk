import UIKit

/// 화면에 띄운 팝업 하나. 메인 스레드 전용.
final class InAppPopupPresentation {
    /// 팝업을 띄울 자리. 팝업이 닫힐 때까지 `appWindow` 와 `scene` 을 고정한다.
    struct Target {
        let appWindow: UIWindow
        /// 고정한 scene. 종료 알림의 대상과 같은 객체인지만 비교한다.
        let scene: AnyObject?
        let window: InAppPopupWindow
    }

    enum State {
        case ready
        case shown
        case finishing
    }

    let claim: Int
    let campaignId: String
    let window: InAppPopupWindow
    let scene: AnyObject?
    let appWindow: UIWindow
    private(set) var state: State = .ready

    private let content: InAppMessageWebViewController
    private let notificationCenter: NotificationCenter
    private let onFinished: (InAppPopupPresentation) -> Void
    private var appWindowAccessibilityHidden = false
    private var disconnectObserver: NSObjectProtocol?

    /// 앱 key window 와 그 scene. scene 이 없으면 nil.
    static func sceneTarget() -> Target? {
        guard let appWindow = FloatingScreenFinder.keyWindow(), let scene = appWindow.windowScene else { return nil }
        return Target(appWindow: appWindow, scene: scene, window: InAppPopupWindow(windowScene: scene))
    }

    /// - Parameter onFinished: `finish` 의 마지막 단계. 표시 권리를 반납하는 곳이다.
    init(
        claim: Int,
        campaignId: String,
        target: Target,
        content: InAppMessageWebViewController,
        notificationCenter: NotificationCenter = .default,
        onFinished: @escaping (InAppPopupPresentation) -> Void
    ) {
        self.claim = claim
        self.campaignId = campaignId
        self.window = target.window
        self.scene = target.scene
        self.appWindow = target.appWindow
        self.content = content
        self.notificationCenter = notificationCenter
        self.onFinished = onFinished
    }

    func show() {
        guard state == .ready else { return }
        state = .shown
        appWindow.endEditing(true)
        appWindowAccessibilityHidden = appWindow.accessibilityElementsHidden
        appWindow.accessibilityElementsHidden = true
        window.rootViewController = content
        window.isHidden = false
        disconnectObserver = notificationCenter.addObserver(
            forName: UIScene.didDisconnectNotification, object: nil, queue: nil
        ) { [weak self] notification in
            self?.sceneDidDisconnect(notification.object)
        }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    deinit {
        guard state == .shown else { return }
        let window = window
        let appWindow = appWindow
        let accessibilityHidden = appWindowAccessibilityHidden
        let center = notificationCenter
        let observer = disconnectObserver
        let restore = {
            window.isHidden = true
            window.rootViewController = nil
            appWindow.accessibilityElementsHidden = accessibilityHidden
            observer.map(center.removeObserver)
        }
        if Thread.isMainThread {
            restore()
        } else {
            DispatchQueue.main.async(execute: restore)
        }
    }

    private func sceneDidDisconnect(_ object: Any?) {
        guard let scene = scene, (object as AnyObject?) === scene else { return }
        finish(claim: claim)
    }

    /// 팝업을 내리고 맨 끝에 `onFinished` 를 부른다. 다른 권리 번호이거나 이미 내리는 중이면 아무것도 하지 않는다.
    @discardableResult
    func finish(claim: Int) -> Bool {
        guard claim == self.claim, state == .shown else { return false }
        state = .finishing
        content.blank()
        window.isHidden = true
        window.rootViewController = nil
        appWindow.accessibilityElementsHidden = appWindowAccessibilityHidden
        if let observer = disconnectObserver {
            notificationCenter.removeObserver(observer)
            disconnectObserver = nil
        }
        onFinished(self)
        return true
    }
}
