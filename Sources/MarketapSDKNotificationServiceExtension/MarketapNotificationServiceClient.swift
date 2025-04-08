//
//  MarketapNotificationServiceExtensionClient.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import UserNotifications
import Foundation

class MarketapNotificationServiceClient: MarketapNotificationServiceClientProtocol {
    struct MarketapNotification {
        let userId: String?
        let deviceId: String?
        let projectId: String?
        let campaignId: String?
        let messageId: String?
        let serverProperties: [String: String]?

        let imageUrl: URL?
    }
    
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    
    private func getMarketapNotification(request: UNNotificationRequest) -> MarketapNotification? {
        guard let info = request.content.userInfo["marketap"] as? [String: Any] else { return nil }
        
        return MarketapNotification(
            userId: info["userId"] as? String,
            deviceId: info["deviceId"] as? String,
            projectId: info["projectId"] as? String,
            campaignId: info["campaignId"] as? String,
            messageId: info["messageId"] as? String,
            serverProperties: {
                guard let propertiesString = info["serverProperties"] as? String,
                      let data = propertiesString.data(using: .utf8),
                      let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                      let dict = jsonObject as? [String: String] else {
                    return nil
                }
                return dict
            }(),
            imageUrl: (info["imageUrl"] as? String).map { URL(string: $0) } ?? nil
        )
    }
    
    private func downloadMedia(url: URL, completion: @escaping (URL?) -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { location, _, _ in
            guard let location = location else {
                completion(nil)
                return
            }
            let tempDirectory = FileManager.default.temporaryDirectory
            let localUrl = tempDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.moveItem(at: location, to: localUrl)
            completion(localUrl)
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

        if let imageUrl = notification.imageUrl {
            downloadMedia(url: imageUrl) { localUrl in
                if let localUrl = localUrl {
                    let attachment = try? UNNotificationAttachment(identifier: "marketap_attachment", url: localUrl, options: nil)
                    if let attachment = attachment {
                        bestAttemptContent.attachments = [attachment]
                    }
                }
                contentHandler(bestAttemptContent)
            }
        } else {
            contentHandler(bestAttemptContent)
        }
        handleImpression(notification)

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

extension MarketapNotificationServiceClient {
    func handleImpression(_ notification: MarketapNotification) {
        guard let userId = notification.userId,
              let projectId = notification.projectId,
              let deviceId = notification.deviceId,
              let campaignId = notification.campaignId,
              let messageId = notification.messageId else {
            return
        }

        let urlString = "https://event.marketap.io/v1/client/events?project_id=\(projectId)"
        guard let url = URL(string: urlString) else {
            return
        }

        let request = ImpressionRequest(
            name: "mkt_push_impression",
            userId: userId,
            device: Device(deviceId: deviceId),
            properties: ImpressionRequestProperties(
                campaignId: campaignId,
                messageId: messageId,
                serverProperties: notification.serverProperties
            ),
            timestamp: Date()
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try? JSONEncoder().encode(request)

        let task = URLSession.shared.dataTask(with: urlRequest)
        task.resume()
    }
}
