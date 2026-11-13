//
//  InAppMessageWebViewController.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import UIKit
import WebKit

/// 팝업 콜백의 `claim` 은 그 팝업을 띄울 때 받은 표시 권리 번호다.
protocol InAppMessageWebViewControllerDelegate: AnyObject, WKNavigationDelegate {
    func onClick(campaign: InAppCampaign, locationId: String, messageId: String, url: String?, claim: Int)
    func hideCampaign(campaignId: String, until: TimeInterval, claim: Int)
    func onTrack(campaign: InAppCampaign, eventName: String, properties: [String: Any]?)
    func onSetUserProperties(properties: [String: Any])
}

final class InAppMessageWebViewController: AppFollowingViewController {
    private(set) var campaign: InAppCampaign?
    private(set) var documentGate = InAppDocumentGate()
    var webView: WKWebView!

    /// 웹뷰에 마지막으로 올린 팝업 문서의 표시 권리 번호.
    var claim: Int? { documentGate.loadedClaim }

    weak var delegate: InAppMessageWebViewControllerDelegate?
    let messageId = UUID().uuidString
    private weak var appWindow: UIWindow?

    override var followedAppScreen: UIViewController? {
        appWindow.flatMap { FloatingScreenFinder.topMostViewController(in: $0) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let webView = createWebView()
        self.webView = webView

        view.addSubview(webView)
    }

    /// 표시 권리 `claim` 으로 `appWindow` 위에 띄울 캠페인을 올린다. safe area 는 `appWindow` 에서 읽는다.
    func load(campaign: InAppCampaign, claim: Int, appWindow: UIWindow) {
        self.campaign = campaign
        self.appWindow = appWindow
        loadViewIfNeeded()
        guard let html = campaign.html else {
            documentGate.didStartLoadingNonCampaign()
            return
        }
        let navigation = updateCampaignContent(campaignHTML: html, safeArea: appWindow.safeAreaInsets)
        documentGate.didStartLoading(claim: claim, navigation: navigation)
    }

    func documentDidCommit(_ navigation: WKNavigation?) {
        documentGate.didCommit(navigation: navigation)
    }

    private func updateCampaignContent(campaignHTML: String, safeArea: UIEdgeInsets) -> WKNavigation? {
        let eventHandlers = MarketapJSMessage.allCases.map { $0.jsFunctionDefinition }.joined(separator: ",\n  ")
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <script>
                window._marketap_native = {
                    \(eventHandlers),
                    topSafeArea: \(safeArea.top),
                    bottomSafeArea: \(safeArea.bottom)
                };
            </script>
        </head>
        <body>
            \(campaignHTML)
        </body>
        </html>
        """

        return webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func blank() {
        documentGate.didStartLoadingNonCampaign()
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
    }

    /// 캠페인 html 이 붙기 전에 올려두는 빈 껍데기.
    private static let shellHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">
    </head>
    <body>
    </body>
    </html>
    """

    /// 껍데기를 다시 올린다. 콘텐츠 프로세스가 죽은 뒤 웹뷰를 되살리는 용도
    /// (loadHTMLString 이 프로세스를 다시 띄운다).
    func reloadShell() {
        documentGate.didStartLoadingNonCampaign()
        guard let webView = webView else { return }
        webView.loadHTMLString(Self.shellHTML, baseURL: nil)
    }

    private func createWebView() -> WKWebView {
        let webConfig = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Register JavaScript message handlers
        MarketapJSMessage.allCases.forEach { message in
            contentController.add(self, name: message.name)
        }

        webConfig.userContentController = contentController
        let webView = WKWebView(frame: view.bounds, configuration: webConfig)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.backgroundColor = .clear
        webView.isOpaque = false
        webView.navigationDelegate = delegate

        webView.loadHTMLString(Self.shellHTML, baseURL: nil)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        return webView
    }
}

extension InAppMessageWebViewController: WKScriptMessageHandler {

    private func parseJSON(_ jsonString: String) throws -> [String: Any] {
        guard let data = jsonString.data(using: .utf8) else {
            throw MarketapError.decodingError(
                DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Failed to convert JSON string to Data")
                )
            )
        }

        do {
            let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)
            return decoded.compactMapValues { $0.value }
        } catch {
            throw MarketapError.decodingError(error)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handleScriptMessage(name: message.name, body: message.body)
    }

    /// 커밋된 팝업 문서가 없으면 메시지를 버린다.
    func handleScriptMessage(name: String, body: Any) {
        MarketapLogger.verbose("receive message: \(campaign?.id ?? "null"), name: \(name), body: \(body)")
        guard let claim = documentGate.committedClaim else {
            MarketapLogger.verbose("dropping message from a document that is not the current popup's: \(name)")
            return
        }
        guard let campaign = campaign, let jsEvent = MarketapJSMessage(rawValue: name) else {
            return
        }

        switch jsEvent {
        case .click:
            if let body = body as? [String], let locationId = body.first {
                delegate?.onClick(campaign: campaign, locationId: locationId, messageId: messageId, url: body.last, claim: claim)
            }
        case .hide:
            let hideUntil: TimeInterval
            if let body = body as? [String],
               let hideTypeString = body.first,
               let hideType = CampaignHideType(rawValue: hideTypeString) {
                hideUntil = hideType.hideDuration
            } else {
                hideUntil = 0
            }
            delegate?.hideCampaign(campaignId: campaign.id, until: hideUntil, claim: claim)
        case .track:
            guard let body = body as? [Any],
                  let eventName = body.first as? String
            else {
                MarketapLogger.error("Invalid track message body: \(body)")
                return
            }
            var properties: [String: Any]?
            if body.count > 1, let propertiesJson = body[1] as? String {
                do {
                    properties = try parseJSON(propertiesJson)
                } catch {
                    MarketapLogger.error("Error parsing event properties JSON: \(propertiesJson)")
                    return
                }
            }
            
            delegate?.onTrack(campaign: campaign,eventName: eventName, properties: properties)
        case .setUserProperties:
            if let body = body as? [String],
               let propertiesJson = body.first {
                do {
                    let properties = try parseJSON(propertiesJson)
                    delegate?.onSetUserProperties(properties: properties)
                } catch {
                    MarketapLogger.error("Error parsing user properties JSON: \(propertiesJson)")
                }
            } else {
                MarketapLogger.warn("Invalid setUserProperties message body: \(body)")
            }
        }
    }
}
