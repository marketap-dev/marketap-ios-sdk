//
//  InAppMessageWebViewController.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/14/25.
//

import UIKit
import WebKit

protocol InAppMessageWebViewControllerDelegate: AnyObject, WKNavigationDelegate {
    func onClick(campaign: InAppCampaign, locationId: String, messageId: String, url: String?)
    func hideCampaign(campaignId: String, until: TimeInterval)
    func onImpression(campaign: InAppCampaign, messageId: String)
}

final class InAppMessageWebViewController: UIViewController {
    var campaign: InAppCampaign? {
        didSet {
            if let campaign = campaign {
                self.updateCampaignContent(campaignHTML: campaign.html)
            }
        }
    }
    var webView: WKWebView!

    weak var delegate: InAppMessageWebViewControllerDelegate?
    private let messageId = UUID().uuidString

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let webView = createWebView()
        self.webView = webView

        view.addSubview(webView)
    }

    func updateCampaignContent(campaignHTML: String) {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        let topSafeArea = keyWindow?.safeAreaInsets.top ?? 0
        let bottomSafeArea = keyWindow?.safeAreaInsets.bottom ?? 0

        let eventHandlers = MarketapJSMessage.allCases.map { $0.jsFunctionDefinition }.joined(separator: ",\n  ")
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <script>
                window._marketap_native = {
                    \(eventHandlers),
                    topSafeArea: \(topSafeArea),
                    bottomSafeArea: \(bottomSafeArea)
                };
            </script>
        </head>
        <body>
            \(campaignHTML)
        </body>
        </html>
        """

        webView.loadHTMLString(htmlContent, baseURL: nil)
    }


    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let campaign = campaign {
            delegate?.onImpression(campaign: campaign, messageId: messageId)
        }
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
        let htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">
        </head>
        <body>
        </body>
        </html>
        """

        webView.loadHTMLString(htmlContent, baseURL: nil)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        return webView
    }
}

extension InAppMessageWebViewController: WKScriptMessageHandler {

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Logger.verbose("receive message: \(campaign?.id ?? "null"), name: \(message.name), body: \(message.body)")
        guard let campaign = campaign, let jsEvent = MarketapJSMessage(rawValue: message.name) else {
            return
        }

        switch jsEvent {
        case .click:
            if let body = message.body as? [String], let locationId = body.first {
                delegate?.onClick(campaign: campaign, locationId: locationId, messageId: messageId, url: body.last)
            }
        case .hide:
            self.dismiss(animated: false)
            if let body = message.body as? [String],
               let hideTypeString = body.first,
               let hideType = CampaignHideType(rawValue: hideTypeString) {
                delegate?.hideCampaign(campaignId: campaign.id, until: hideType.hideDuration)
            } else {
                delegate?.hideCampaign(campaignId: campaign.id, until: 0)
            }
        }
    }
}
