import Foundation

/// 공유 웹뷰에 올라간 문서가 어느 팝업의 것인지 추적한다. 메인 스레드 전용.
///
/// 스크립트 메시지는 문서를 가리지 않고 도착하므로, 팝업 문서의 내비게이션이 커밋된 뒤에만 그 팝업의 것으로 받는다.
struct InAppDocumentGate {
    /// 웹뷰에 마지막으로 올린 팝업 문서의 표시 권리 번호. 빈 페이지·껍데기를 올리면 nil.
    private(set) var loadedClaim: Int?
    /// 스크립트 메시지를 받을 수 있는 권리 번호. `loadedClaim` 의 문서가 커밋된 뒤에만 값이 있다.
    private(set) var committedClaim: Int?
    private(set) var pendingNavigation: AnyObject?

    /// - Parameter navigation: `loadHTMLString` 이 돌려준 내비게이션. nil 이면 커밋을 알 수 없어 곧바로 커밋된 것으로 본다.
    mutating func didStartLoading(claim: Int, navigation: AnyObject?) {
        loadedClaim = claim
        pendingNavigation = navigation
        committedClaim = navigation == nil ? claim : nil
    }

    mutating func didStartLoadingNonCampaign() {
        loadedClaim = nil
        committedClaim = nil
        pendingNavigation = nil
    }

    mutating func didCommit(navigation: AnyObject?) {
        guard let pending = pendingNavigation, pending === navigation else { return }
        pendingNavigation = nil
        committedClaim = loadedClaim
    }
}
