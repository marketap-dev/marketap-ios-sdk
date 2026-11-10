import Foundation

/// 떠 있는 플로팅 캠페인 하나. 플로팅 자리의 표시 권리 자체이기도 하다(`activeFloating`).
final class FloatingCampaignSession: FloatingSessionDelegate {
    let campaign: InAppCampaign
    let messageId = UUID().uuidString
    private weak var service: InAppMessageService?

    init(campaign: InAppCampaign, service: InAppMessageService) {
        self.campaign = campaign
        self.service = service
    }

    func floatingDidClick(locationId: String, url: String?) {
        service?.onClick(campaign: campaign, locationId: locationId, messageId: messageId, url: url)
    }

    func floatingDidTrack(eventName: String, properties: [String: Any]?) {
        service?.onTrack(campaign: campaign, eventName: eventName, properties: properties)
    }

    func floatingDidSetUserProperties(_ properties: [String: Any]) {
        service?.onSetUserProperties(properties: properties)
    }

    func floatingDidClose(reason: FloatingCloseReason) {
        guard let service = service else { return }
        if case .hidden(let until) = reason {
            service.recordHidden(campaignId: campaign.id, until: until)
        }
        service.releaseFloating(self)
    }
}

extension InAppMessageService {

    var isFloatingClaimed: Bool {
        displayLock.lock()
        defer { displayLock.unlock() }
        return activeFloating != nil
    }

    /// 플로팅 자리를 선점하고 메인 스레드에서 붙인다. 자리가 이미 차 있으면 false.
    func presentFloating(campaign: InAppCampaign) -> Bool {
        guard let html = campaign.html else { return false }
        let floating = FloatingCampaignSession(campaign: campaign, service: self)

        displayLock.lock()
        if activeFloating != nil {
            displayLock.unlock()
            return false
        }
        activeFloating = floating
        displayLock.unlock()

        DispatchQueue.main.async {
            guard self.isActiveFloating(floating) else { return }
            let impressionAt = Date()
            guard self.floatingPresenter.show(
                html: html,
                impressionAt: impressionAt,
                delegate: floating
            ) != nil else {
                MarketapLogger.warn("failed to attach floating campaign: \(campaign.id)")
                self.releaseFloating(floating)
                return
            }
            MarketapLogger.verbose("presented floating campaign: \(campaign.id)")
            self.logImpression(campaignId: campaign.id, at: impressionAt)
            self.onImpression(campaign: campaign, messageId: floating.messageId)
        }
        return true
    }

    func releaseFloating(_ floating: FloatingCampaignSession) {
        displayLock.lock()
        if activeFloating === floating {
            activeFloating = nil
        }
        displayLock.unlock()
    }

    private func isActiveFloating(_ floating: FloatingCampaignSession) -> Bool {
        displayLock.lock()
        defer { displayLock.unlock() }
        return activeFloating === floating
    }
}
