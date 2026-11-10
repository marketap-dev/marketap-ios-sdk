import Foundation

/// 떠 있는 플로팅 캠페인 하나. 플로팅 자리의 표시 권리 자체이기도 하다(`activeFloating`).
final class FloatingCampaignSession: FloatingSessionDelegate {
    let campaign: InAppCampaign
    let messageId = UUID().uuidString
    private(set) weak var origin: InAppWebOrigin?
    let originId: ObjectIdentifier?
    /// 메인 스레드에서만 쓴다.
    weak var view: FloatingSession?
    private weak var service: InAppMessageService?

    init(campaign: InAppCampaign, service: InAppMessageService, origin: InAppWebOrigin? = nil) {
        self.campaign = campaign
        self.service = service
        self.origin = origin
        self.originId = origin.map { ObjectIdentifier($0) }
    }

    var isBoundToOrigin: Bool {
        PageFloatingPolicy.isBoundToOrigin(floatingScope: campaign.floatingScope, hasOrigin: originId != nil)
    }

    func floatingDidClick(locationId: String, url: String?) {
        service?.onClick(campaign: campaign, locationId: locationId, messageId: messageId, url: url, origin: origin, closingPopup: false)
    }

    func floatingDidTrack(eventName: String, properties: [String: Any]?) {
        service?.onTrack(campaign: campaign, eventName: eventName, properties: properties)
    }

    func floatingDidSetUserProperties(_ properties: [String: Any]) {
        service?.onSetUserProperties(properties: properties)
    }

    func floatingDidClose(reason: FloatingCloseReason) {
        origin?.endWatchingWindow(owner: self)
        guard let service = service else { return }
        if case .hidden(let until) = reason {
            service.recordHidden(campaignId: campaign.id, until: until)
        }
        service.releaseFloating(self)
    }
}

extension InAppMessageService {

    /// 플로팅 자리를 선점하고 메인 스레드에서 붙인다. 자리가 이미 차 있으면 false.
    func presentFloating(campaign: InAppCampaign, origin: InAppWebOrigin? = nil) -> Bool {
        guard let html = campaign.html else { return false }
        let floating = FloatingCampaignSession(campaign: campaign, service: self, origin: origin)

        displayLock.lock()
        if activeFloating != nil {
            displayLock.unlock()
            return false
        }
        activeFloating = floating
        displayLock.unlock()

        DispatchQueue.main.async {
            guard self.isActiveFloating(floating) else { return }
            if floating.isBoundToOrigin, !self.watchOrigin(of: floating) {
                MarketapLogger.verbose("origin web view left before floating was attached: \(campaign.id)")
                self.releaseFloating(floating)
                return
            }
            let impressionAt = Date()
            guard let view = self.floatingPresenter.show(
                html: html,
                impressionAt: impressionAt,
                delegate: floating
            ) else {
                MarketapLogger.warn("failed to attach floating campaign: \(campaign.id)")
                floating.origin?.endWatchingWindow(owner: floating)
                self.releaseFloating(floating)
                return
            }
            floating.view = view
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

    private func watchOrigin(of floating: FloatingCampaignSession) -> Bool {
        guard let origin = floating.origin, let originId = floating.originId else { return false }
        return origin.beginWatchingWindow(owner: floating) { [weak self] in
            self?.originDidLeavePage(originId)
        }
    }

    func originDidLeavePage(_ originId: ObjectIdentifier) {
        displayLock.lock()
        guard let floating = activeFloating,
              PageFloatingPolicy.closes(
                floatingScope: floating.campaign.floatingScope,
                floatingOriginId: floating.originId,
                leavingOriginId: originId
              ) else {
            displayLock.unlock()
            return
        }
        activeFloating = nil
        displayLock.unlock()
        MarketapLogger.verbose("origin web view left the page, closing floating: \(floating.campaign.id)")
        DispatchQueue.main.async {
            floating.view?.close(reason: .dismissed)
        }
    }
}
