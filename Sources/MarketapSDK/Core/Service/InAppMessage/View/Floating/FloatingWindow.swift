import UIKit

/// 앱 창 위에 따로 띄우는 플로팅 전용 창. 바 영역(펼침이면 전체) 밖의 터치는 아래 앱 창으로 넘긴다.
final class FloatingWindow: UIWindow {
    let container: FloatingContainerView

    init(windowScene: UIWindowScene, container: FloatingContainerView) {
        self.container = container
        super.init(windowScene: windowScene)
        setUp()
    }

    init(frame: CGRect, container: FloatingContainerView) {
        self.container = container
        super.init(frame: frame)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        windowLevel = .normal
        let root = FloatingRootViewController()
        rootViewController = root
        container.frame = root.view.bounds
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS 15.0, *)
    override var canBecomeKey: Bool { false }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event), hit.isDescendant(of: container) else { return nil }
        return hit
    }
}

private final class FloatingRootViewController: AppFollowingViewController {
    override var followedAppScreen: UIViewController? { FloatingScreenFinder.topMostViewController() }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
    }
}
