import Foundation

/// 인앱 메시지를 띄운 이벤트가 들어온 웹뷰. `handleInAppInWebView` 가 켜진 웹브릿지만 출처가 된다.
/// `isWebViewVisible`·창 감시는 메인 스레드에서만 부른다.
protocol InAppWebOrigin: AnyObject {
    var isWebViewVisible: Bool { get }
    /// 이 웹뷰에서 `addressChanged` 를 한 번이라도 받았는지.
    var hasReceivedAddressChange: Bool { get }
    func openInWebView(url: String)
    /// 웹뷰가 창에서 떨어지면 `onLeave` 를 부른다. 이미 창에 없으면 감시하지 않고 false.
    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool
    func endWatchingWindow(owner: AnyObject)
}

enum PageFloatingPolicy {
    /// 출처 웹뷰의 페이지를 벗어나면 닫는 바인지. 출처 없는 "이 페이지에서만" 바는 닫을 때까지 유지한다.
    static func isBoundToOrigin(floatingScope: String?, hasOrigin: Bool) -> Bool {
        floatingScope == "PAGE" && hasOrigin
    }

    /// `addressChanged` 를 보낸 적 없는 웹뷰(구버전 웹 SDK)는 페이지뷰 이벤트를 주소 변경으로 본다.
    static func eventLeavesPage(eventName: String, originReceivedAddressChange: Bool) -> Bool {
        eventName == MarketapEvent.view.rawValue && !originReceivedAddressChange
    }

    static func closes(
        floatingScope: String?,
        floatingOriginId: ObjectIdentifier?,
        leavingOriginId: ObjectIdentifier
    ) -> Bool {
        isBoundToOrigin(floatingScope: floatingScope, hasOrigin: floatingOriginId != nil)
            && floatingOriginId == leavingOriginId
    }
}

enum InAppClickRoute: Equatable {
    case webView
    case app

    static func of(url: String?, customized: Bool, useWebClickRouting: Bool, originVisible: Bool) -> InAppClickRoute {
        guard url != nil, !customized, useWebClickRouting, originVisible else { return .app }
        return .webView
    }
}

/// 래퍼(Flutter·RN) 웹뷰를 대신하는 호스트. 창 소속을 알 수 없어 붙어 있는지와 해제만 본다.
final class ExternalWebViewHost: InAppWebOrigin {
    static let shared = ExternalWebViewHost()

    typealias Command = (_ type: String, _ payload: [String: Any]) -> Void

    private let lock = NSLock()
    private var _attached = false
    private var _command: Command?
    private var _hasReceivedAddressChange = false

    var attached: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _attached }
        set { lock.lock(); _attached = newValue; lock.unlock() }
    }

    var command: Command? {
        get { lock.lock(); defer { lock.unlock() }; return _command }
        set { lock.lock(); _command = newValue; lock.unlock() }
    }

    var hasReceivedAddressChange: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _hasReceivedAddressChange }
        set { lock.lock(); _hasReceivedAddressChange = newValue; lock.unlock() }
    }

    var isWebViewVisible: Bool { attached && command != nil }

    func openInWebView(url: String) {
        send("openUrl", ["url": url])
    }

    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool { true }

    func endWatchingWindow(owner: AnyObject) {}

    private func send(_ type: String, _ payload: [String: Any]) {
        guard let command = command else { return }
        if Thread.isMainThread {
            command(type, payload)
        } else {
            DispatchQueue.main.async { command(type, payload) }
        }
    }
}

enum JavaScriptLiteral {
    /// 문자열을 JS 소스에 넣을 수 있는 따옴표 포함 리터럴로 만든다.
    static func string(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8),
              array.count >= 2 else { return nil }
        return String(array.dropFirst().dropLast())
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
