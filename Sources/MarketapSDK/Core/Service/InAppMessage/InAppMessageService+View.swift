//
//  InAppMessageService+View.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/17/25.
//

import Foundation
import UIKit
import WebKit

extension InAppMessageService: InAppMessageWebViewControllerDelegate {

    func isCampaignHiden(campaign: InAppCampaign) -> Bool {
        if UserDefaults.standard.double(forKey: "hide_campaign_\(campaign.id)") > Date().timeIntervalSince1970 {
            return true
        }

        if let frequencyCap = campaign.triggerEventCondition.frequencyCap {
            let canShow = canShowCampaign(campaignId: campaign.id, frequencyCap: frequencyCap)
            return !canShow
        }

        return false
    }

    func hideCampaign(campaignId: String, until: TimeInterval) {
        isModalShown = false
        if until > 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970 + until, forKey: "hide_campaign_\(campaignId)")
        }
    }

    func canShowCampaign(campaignId: String, frequencyCap: FrequencyCap) -> Bool {
        let key = "impression_\(campaignId)"
        let now = Date().timeIntervalSince1970

        let timestamps = UserDefaults.standard.object(forKey: key) as? [TimeInterval] ?? []
        let validTimestamps = timestamps.filter { now - $0 <= TimeInterval(frequencyCap.durationMinutes * 60) }

        return validTimestamps.count < frequencyCap.limit
    }

    func logImpression(campaignId: String) {
        let key = "impression_\(campaignId)"
        let now = Date().timeIntervalSince1970

        var timestamps = UserDefaults.standard.object(forKey: key) as? [TimeInterval] ?? []
        timestamps.append(now)

        UserDefaults.standard.set(Array(timestamps.suffix(100)), forKey: key)
    }

    func showCampaignIfPossible(campaign: InAppCampaign) -> Bool {
        if isCampaignHiden(campaign: campaign) {
            return false
        }

        if isModalShown {
            return false
        }

        logImpression(campaignId: campaign.id)
        self.presentCampaignModal(campaign: campaign)

        return true
    }

    private func presentCampaignModal(campaign: InAppCampaign) {

        guard didFinishLoad else {
            pendingCampaign = campaign
            return
        }
        DispatchQueue.main.async {
            self.campaignViewController.campaign = campaign
            if let topViewController = self.getTopViewController() {
                self.isModalShown = true
                topViewController.present(self.campaignViewController, animated: false)
            }
        }
    }

    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { [.foregroundActive, .foregroundInactive].contains($0.activationState) }) as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }

        var topController = keyWindow.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }

    func onEvent(eventRequest: IngestEventRequest) {
        fetchCampaigns { [weak self] campaigns in
            guard let self else { return }
            for campaign in campaigns {
                if self.isEventTriggered(condition: campaign.triggerEventCondition, event: eventRequest) {
                    let didShowCampaign = self.showCampaignIfPossible(campaign: campaign)

                    if didShowCampaign { break }
                }
            }
        }
    }

    func onImpression(campaign: InAppCampaign, messageId: String) {
        delegate?.trackEvent(
            eventName: "mkt_delivery_message",
            eventProperties: [
                "mkt_campaign_id": campaign.id,
                "mkt_campaign_category": "ON_SITE",
                "mkt_channel_type": "IN_APP_MESSAGE",
                "mkt_sub_channel_type": campaign.layout.layoutSubType,
                "mkt_result_status": 200000,
                "mkt_result_message": "SUCCESS",
                "mkt_is_success": true,
                "mkt_message_id": messageId
            ]
        )
    }

    func onClick(campaign: InAppCampaign, locationId: String, messageId: String) {
        delegate?.trackEvent(
            eventName: "mkt_click_message",
            eventProperties: [
                "mkt_campaign_id": campaign.id,
                "mkt_campaign_category": "ON_SITE",
                "mkt_channel_type": "IN_APP_MESSAGE",
                "mkt_sub_channel_type": campaign.layout.layoutSubType,
                "mkt_result_status": 200000,
                "mkt_result_message": "SUCCESS",
                "mkt_location_id": locationId,
                "mkt_is_success": true,
                "mkt_message_id": messageId
            ]
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishLoad = true
        if let pendingCampaign {
            self.pendingCampaign = nil
            presentCampaignModal(campaign: pendingCampaign)
        }
    }
}
