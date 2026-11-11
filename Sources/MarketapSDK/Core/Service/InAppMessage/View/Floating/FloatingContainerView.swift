import UIKit
import WebKit

final class FloatingContainerView: UIView {
    let webView: WKWebView
    var isExpanded = false
    /// 접힌 동안 터치를 받는 영역(컨테이너 좌표). 바깥 터치는 아래 화면으로 넘긴다.
    var touchableRect: CGRect = .zero
    var onLayout: (() -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .clear
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func acceptsTouch(at point: CGPoint, bounds: CGRect, isExpanded: Bool, touchableRect: CGRect) -> Bool {
        guard bounds.contains(point) else { return false }
        return isExpanded || touchableRect.contains(point)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        Self.acceptsTouch(at: point, bounds: bounds, isExpanded: isExpanded, touchableRect: touchableRect)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event), hit.isDescendant(of: self) else { return nil }
        if hit === self && !isExpanded { return nil }
        return hit
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onLayout?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
