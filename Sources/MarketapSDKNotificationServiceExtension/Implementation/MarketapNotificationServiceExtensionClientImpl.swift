//
//  MarketapNotificationServiceExtensionClientImpl.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import UserNotifications

class MarketapNotificationServiceExtensionClientImpl: MarketapNotificationServiceExtensionClient {
    struct MarketapNotification {
        let imageURL: URL?
        
        init(imageURL: URL?) {
            self.imageURL = imageURL
        }
    }
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    private func getMarketapNotification(request: UNNotificationRequest) -> MarketapNotification? {
        guard let info = request.content.userInfo["marketap"] as? [String: Any] else { return nil }
        
        return MarketapNotification(
            imageURL: (info["imageUrl"] as? String).map { URL(string: $0) } ?? nil
        )
    }
    
    private func downloadMedia(url: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { location, _, _ in
            guard let location = location else {
                completion(nil)
                return
            }
            let tempDirectory = FileManager.default.temporaryDirectory
            let localURL = tempDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.moveItem(at: location, to: localURL)
            completion(localURL)
        }
        task.resume()
    }

    func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) -> Bool {
        guard let notification = getMarketapNotification(request: request) else {
            self.contentHandler = nil
            self.bestAttemptContent = nil
            return false
        }
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            return false
        }

        if let imageURL = notification.imageURL {
            downloadMedia(url: imageURL) { localURL in
                if let localURL = localURL {
                    let attachment = try? UNNotificationAttachment(identifier: "image", url: localURL, options: nil)
                    if let attachment = attachment {
                        bestAttemptContent.attachments = [attachment]
                        bestAttemptContent.categoryIdentifier = "MESSAGE_CATEGORY"
                    }
                }
                contentHandler(bestAttemptContent)
            }
        } else {
            contentHandler(bestAttemptContent)
        }
        return true
    }

    func serviceExtensionTimeWillExpire() -> Bool {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
            return true
        }
        return false
    }
}
