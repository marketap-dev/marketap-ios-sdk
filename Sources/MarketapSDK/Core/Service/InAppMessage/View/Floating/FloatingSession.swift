import UIKit
import WebKit

enum FloatingCloseReason: Equatable {
    /// 템플릿의 닫기·보지 않기. `until` 은 숨김 기간(초), 0 이면 숨김 없음.
    case hidden(until: TimeInterval)
    case dismissed
    case webContentTerminated
}

protocol FloatingSessionDelegate: AnyObject {
    func floatingDidClick(locationId: String, url: String?)
    func floatingDidTrack(eventName: String, properties: [String: Any]?)
    func floatingDidSetUserProperties(_ properties: [String: Any])
    func floatingDidClose(reason: FloatingCloseReason)
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

final class FloatingSession: NSObject {
    let container: FloatingContainerView
    let messageId = UUID().uuidString
    weak var delegate: FloatingSessionDelegate?
    var onClosed: (() -> Void)?

    private(set) var isClosed = false
    private var didFinishLoad = false
    private var appliedInsets: FloatingInsets?

    private static var messageNames: [String] {
        MarketapJSMessage.allCases.map { $0.name } + [FloatingDocument.layoutMessageName]
    }

    var isExpanded: Bool { container.isExpanded }

    override init() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        container = FloatingContainerView(webView: webView)
        super.init()

        let proxy = WeakScriptMessageHandler(self)
        Self.messageNames.forEach { contentController.add(proxy, name: $0) }
        webView.navigationDelegate = self
        container.onLayout = { [weak self] in self?.pushInsetsIfChanged() }
    }

    func load(campaignHTML: String, timerStartAt: Date) {
        container.superview?.layoutIfNeeded()
        let insets = currentInsets()
        appliedInsets = insets
        container.webView.loadHTMLString(
            FloatingDocument.html(campaignHTML: campaignHTML, insets: insets, timerStartAt: timerStartAt),
            baseURL: nil
        )
    }

    func close(reason: FloatingCloseReason) {
        guard !isClosed else { return }
        isClosed = true
        container.removeFromSuperview()
        let controller = container.webView.configuration.userContentController
        Self.messageNames.forEach { controller.removeScriptMessageHandler(forName: $0) }
        container.webView.navigationDelegate = nil
        container.webView.load(URLRequest(url: URL(string: "about:blank")!))
        MarketapLogger.verbose("floating closed: \(reason)")
        delegate?.floatingDidClose(reason: reason)
        onClosed?()
    }

    func handleLayout(_ update: FloatingLayoutUpdate) {
        guard !isClosed else { return }
        container.touchableRect = update.touchableRect
        if update.isExpanded != container.isExpanded {
            container.isExpanded = update.isExpanded
            pushInsetsIfChanged()
        }
    }

    func currentInsets() -> FloatingInsets {
        let safeArea = container.window?.safeAreaInsets ?? FloatingScreenFinder.keyWindow()?.safeAreaInsets ?? .zero
        return FloatingInsets(safeArea: safeArea)
    }

    private func pushInsetsIfChanged() {
        guard didFinishLoad, !isClosed else { return }
        let insets = currentInsets()
        guard insets != appliedInsets else { return }
        appliedInsets = insets
        container.webView.evaluateJavaScript(FloatingDocument.applyInsetsScript(insets), completionHandler: nil)
    }

    private static func parseJSON(_ jsonString: String) -> [String: Any]? {
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data) else { return nil }
        return decoded.compactMapValues { $0.value }
    }
}

extension FloatingSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isClosed else { return }
        didFinishLoad = true
        appliedInsets = nil
        pushInsetsIfChanged()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MarketapLogger.warn("floating webView content process terminated")
        close(reason: .webContentTerminated)
    }
}

extension FloatingSession: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == FloatingDocument.layoutMessageName {
            if let update = FloatingLayoutUpdate(body: message.body) {
                handleLayout(update)
            }
            return
        }
        guard let jsEvent = MarketapJSMessage(rawValue: message.name) else { return }
        switch jsEvent {
        case .hide:
            let hideType = (message.body as? [String])?.first.flatMap { CampaignHideType(rawValue: $0) }
            close(reason: .hidden(until: hideType?.hideDuration ?? 0))
        case .click:
            if let body = message.body as? [Any], let locationId = body.first as? String {
                delegate?.floatingDidClick(locationId: locationId, url: body.count > 1 ? body[1] as? String : nil)
            }
        case .track:
            guard let body = message.body as? [Any], let eventName = body.first as? String else {
                MarketapLogger.error("Invalid floating track message body: \(message.body)")
                return
            }
            var properties: [String: Any]?
            if body.count > 1, let json = body[1] as? String {
                guard let parsed = Self.parseJSON(json) else {
                    MarketapLogger.error("Error parsing floating event properties JSON: \(json)")
                    return
                }
                properties = parsed
            }
            delegate?.floatingDidTrack(eventName: eventName, properties: properties)
        case .setUserProperties:
            guard let json = (message.body as? [String])?.first, let properties = Self.parseJSON(json) else {
                MarketapLogger.warn("Invalid floating setUserProperties message body: \(message.body)")
                return
            }
            delegate?.floatingDidSetUserProperties(properties)
        }
    }
}
