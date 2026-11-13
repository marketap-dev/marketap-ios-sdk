import UIKit

/// 앱 창과 플로팅 창 위에 띄우는 팝업 전용 창. 화면 전체의 터치를 받고, key window 가 되지 않는다.
final class InAppPopupWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        setUp()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        windowLevel = .normal + 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS 15.0, *)
    override var canBecomeKey: Bool { false }
}
