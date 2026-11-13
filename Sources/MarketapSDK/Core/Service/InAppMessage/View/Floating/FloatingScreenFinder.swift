import UIKit

enum FloatingScreenFinder {
    /// 앱의 key window. 플로팅·팝업 창은 앱 화면이 아니므로 제외한다.
    static func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap { $0.windows }
            .filter { !($0 is FloatingWindow) && !($0 is InAppPopupWindow) }
        return windows.first { $0.isKeyWindow } ?? windows.first { !$0.isHidden && $0.windowLevel == .normal }
    }

    static func topMostViewController() -> UIViewController? {
        keyWindow().flatMap { topMostViewController(in: $0) }
    }

    static func topMostViewController(in window: UIWindow) -> UIViewController? {
        topMostViewController(from: window.rootViewController)
    }

    /// 플로팅을 붙일 화면. 알림창처럼 화면이 아닌 present 는 건너뛴다.
    static func topMostViewController(from root: UIViewController?) -> UIViewController? {
        var current = root
        while let controller = current {
            if let presented = controller.presentedViewController,
               !presented.isBeingDismissed,
               !isTransientPresentation(presented) {
                current = presented
            } else if let navigation = controller as? UINavigationController,
                      let top = navigation.topViewController {
                current = top
            } else if let tab = controller as? UITabBarController,
                      let selected = tab.selectedViewController {
                current = selected
            } else {
                return controller
            }
        }
        return nil
    }

    static func isTransientPresentation(_ controller: UIViewController) -> Bool {
        controller is UIAlertController
            || controller is UIActivityViewController
    }
}
