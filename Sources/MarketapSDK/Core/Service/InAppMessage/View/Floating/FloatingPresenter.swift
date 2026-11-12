import UIKit

/// 플로팅 자리 하나를 관리한다. 모든 호출은 메인 스레드에서.
final class FloatingPresenter {
    static let shared = FloatingPresenter()

    private let makeWindow: (FloatingContainerView) -> FloatingWindow?
    private(set) var session: FloatingSession?
    private var window: FloatingWindow?

    init(makeWindow: @escaping (FloatingContainerView) -> FloatingWindow? = FloatingPresenter.makeSceneWindow) {
        self.makeWindow = makeWindow
    }

    private static func makeSceneWindow(_ container: FloatingContainerView) -> FloatingWindow? {
        guard let scene = FloatingScreenFinder.keyWindow()?.windowScene else { return nil }
        return FloatingWindow(windowScene: scene, container: container)
    }

    var isShowing: Bool { session != nil }
    var isWindowVisible: Bool { window.map { !$0.isHidden } ?? false }

    /// 앱 창 위 플로팅 전용 창에 띄운다. `impressionAt` 은 템플릿 타이머(`timerStartAt`)의 기준 시각.
    @discardableResult
    func show(html: String, impressionAt: Date, delegate: FloatingSessionDelegate?) -> FloatingSession? {
        guard session == nil else { return nil }
        let newSession = FloatingSession()
        guard let newWindow = makeWindow(newSession.container) else { return nil }
        newSession.delegate = delegate
        newSession.onClosed = { [weak self, weak newSession] in
            guard let self = self, self.session === newSession else { return }
            self.session = nil
            self.window?.isHidden = true
            self.window = nil
        }
        newWindow.isHidden = false
        session = newSession
        window = newWindow
        newSession.load(campaignHTML: html, timerStartAt: impressionAt)
        MarketapLogger.verbose("floating window shown")
        return newSession
    }

    func dismiss() {
        session?.close(reason: .dismissed)
    }
}
