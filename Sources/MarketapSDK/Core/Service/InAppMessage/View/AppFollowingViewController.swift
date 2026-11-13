import UIKit

/// 상태 바·회전 설정을 앱의 최상위 화면에서 따르는 우리 창의 화면.
class AppFollowingViewController: UIViewController {
    /// 설정을 따를 앱 화면. 없으면 시스템 기본값을 쓴다.
    var followedAppScreen: UIViewController? { nil }

    private var appTop: UIViewController? {
        let top = followedAppScreen
        return top === self ? nil : top
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { appTop?.preferredStatusBarStyle ?? .default }
    override var prefersStatusBarHidden: Bool { appTop?.prefersStatusBarHidden ?? false }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        appTop?.supportedInterfaceOrientations ?? .all
    }
}
