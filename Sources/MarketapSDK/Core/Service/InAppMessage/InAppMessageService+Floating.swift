import Foundation

/// 떠 있는 플로팅 캠페인 하나. 플로팅 자리의 표시 권리 자체이기도 하다(`activeFloating`).
final class FloatingCampaignSession: FloatingSessionDelegate {
    let campaign: InAppCampaign
    let messageId = UUID().uuidString
    private(set) weak var origin: InAppWebOrigin?
    /// 서비스의 `displayLock` 으로 지킨다.
    private(set) var originId: ObjectIdentifier?
    /// 메인 스레드에서만 쓴다.
    weak var view: FloatingSession?
    private weak var service: InAppMessageService?

    /// 이 바가 화면에 나타난 시각(단조 시계). 아직 나타나지 않았으면 nil. 서비스의 `displayLock` 으로 지킨다.
    var shownAt: TimeInterval?

    init(campaign: InAppCampaign, service: InAppMessageService, origin: InAppWebOrigin? = nil) {
        self.campaign = campaign
        self.service = service
        self.origin = origin
        self.originId = origin.map { ObjectIdentifier($0) }
    }

    /// 출처 웹뷰가 이미 화면에 없을 때 부른다. 이후로는 앱 화면에서 뜬 메시지처럼 다룬다.
    func forgetOrigin() {
        origin = nil
        originId = nil
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
                self.displayLock.lock()
                floating.forgetOrigin()
                self.displayLock.unlock()
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
            self.displayLock.lock()
            floating.shownAt = self.monotonicNow()
            self.displayLock.unlock()
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
            self?.originDidDisappear(originId)
        }
    }

    func originDidLeavePage(_ originId: ObjectIdentifier) {
        closeOriginMessages(originId, because: "origin web view moved to another page")
    }

    func originDidDisappear(_ originId: ObjectIdentifier) {
        closeOriginMessages(originId, because: "origin web view disappeared")
    }

    /// 그 웹뷰에서 시작돼 이미 나타난 "이 페이지에서만" 바와 팝업만 닫는다. 나타나기 전 메시지는 그대로 띄운다.
    private func closeOriginMessages(_ originId: ObjectIdentifier, because cause: String) {
        closeFloating(because: cause) {
            $0.shownAt != nil
                && PageFloatingPolicy.closes(
                    floatingScope: $0.campaign.floatingScope,
                    floatingOriginId: $0.originId,
                    leavingOriginId: originId
                )
        }
        closePopup(because: cause) { origin, shownAt in
            shownAt != nil && origin.map { ObjectIdentifier($0) } == originId
        }
    }

    /// 앱 화면이 바뀌었다. 보호 시간보다 먼저 화면에 나타난 "이 페이지에서만" 바와 팝업을 닫는다.
    /// 아직 나타나지 않은 메시지는 닫지 않는다.
    func screenChanged() {
        screenChanged(at: monotonicNow())
    }

    func screenChanged(at signalTime: TimeInterval) {
        let cutoff = signalTime - screenChangeGraceSeconds
        closeFloating(because: "app screen changed") {
            guard let shownAt = $0.shownAt else { return false }
            return PageFloatingPolicy.closesOnAppScreenChange(floatingScope: $0.campaign.floatingScope)
                && shownAt < cutoff
        }
        closePopup(because: "app screen changed") { _, shownAt in
            guard let shownAt = shownAt else { return false }
            return shownAt < cutoff
        }
    }

    private func closeFloating(because cause: String, if shouldClose: (FloatingCampaignSession) -> Bool) {
        displayLock.lock()
        guard let floating = activeFloating, shouldClose(floating) else {
            displayLock.unlock()
            return
        }
        activeFloating = nil
        displayLock.unlock()
        MarketapLogger.verbose("\(cause), closing floating: \(floating.campaign.id)")
        if Thread.isMainThread {
            floating.view?.close(reason: .dismissed)
        } else {
            DispatchQueue.main.async {
                floating.view?.close(reason: .dismissed)
            }
        }
    }
}
