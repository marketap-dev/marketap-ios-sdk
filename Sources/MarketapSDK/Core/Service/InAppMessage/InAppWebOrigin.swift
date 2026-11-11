import Foundation

/// 인앱 메시지를 띄운 이벤트가 들어온 웹뷰. `handleInAppInWebView` 가 켜진 웹브릿지만 출처가 된다.
/// `isWebViewVisible`·창 감시는 메인 스레드에서만 부른다.
protocol InAppWebOrigin: AnyObject {
    var isWebViewVisible: Bool { get }
    func openInWebView(url: String)
    /// 웹뷰가 창에서 떨어지면 `onLeave` 를 부른다. 이미 창에 없으면 감시하지 않고 false.
    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool
    func endWatchingWindow(owner: AnyObject)
}

enum PageFloatingPolicy {
    /// 출처 웹뷰의 페이지를 벗어나면 닫는 바인지.
    static func isBoundToOrigin(floatingScope: String?, hasOrigin: Bool) -> Bool {
        floatingScope == "PAGE" && hasOrigin
    }

    /// 웹뷰에서 온 페이지뷰 이벤트는 페이지 이동이다. 쿼리만 바뀐 페이지도 페이지뷰를 보내면 이동으로 본다.
    static func eventLeavesPage(eventName: String) -> Bool {
        eventName == MarketapEvent.view.rawValue
    }

    /// `screenChanged()` 에 닫히는 바인지. "이 페이지에서만"은 웹·앱 어느 화면에서 떴든 닫는다.
    static func closesOnAppScreenChange(floatingScope: String?) -> Bool {
        floatingScope == "PAGE"
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

/// 래퍼(Flutter·RN) 웹뷰 하나를 대신하는 호스트. 창 소속을 알 수 없어 붙어 있는지와 해제만 본다.
final class ExternalWebViewHost: InAppWebOrigin {
    typealias Command = (_ type: String, _ payload: [String: Any]) -> Void

    /// 웹뷰를 구분하지 않는 래퍼가 쓰는 id.
    static let defaultId = ""
    static let shared = ExternalWebViewHost(id: defaultId)

    private static let lock = NSLock()
    private static var hosts: [String: ExternalWebViewHost] = [defaultId: shared]
    private static var _command: Command?

    static var command: Command? {
        get { lock.lock(); defer { lock.unlock() }; return _command }
        set { lock.lock(); _command = newValue; lock.unlock() }
    }

    static func host(for id: String) -> ExternalWebViewHost {
        lock.lock()
        defer { lock.unlock() }
        if let host = hosts[id] { return host }
        let host = ExternalWebViewHost(id: id)
        hosts[id] = host
        return host
    }

    static func existingHost(for id: String) -> ExternalWebViewHost? {
        lock.lock()
        defer { lock.unlock() }
        return hosts[id]
    }

    /// 해제된 웹뷰의 호스트를 지운다. 기본 호스트는 남긴다.
    static func remove(id: String) {
        guard id != defaultId else { return }
        lock.lock()
        hosts[id] = nil
        lock.unlock()
    }

    let id: String
    private var _attached = false

    private init(id: String) {
        self.id = id
    }

    var attached: Bool {
        get { Self.lock.lock(); defer { Self.lock.unlock() }; return _attached }
        set { Self.lock.lock(); _attached = newValue; Self.lock.unlock() }
    }

    var isWebViewVisible: Bool { attached && Self.command != nil }

    func openInWebView(url: String) {
        var payload: [String: Any] = ["url": url]
        if id != Self.defaultId { payload["webViewId"] = id }
        send("openUrl", payload)
    }

    func beginWatchingWindow(owner: AnyObject, onLeave: @escaping () -> Void) -> Bool { true }

    func endWatchingWindow(owner: AnyObject) {}

    private func send(_ type: String, _ payload: [String: Any]) {
        guard let command = Self.command else { return }
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
