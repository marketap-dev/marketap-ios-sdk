//
//  MarketapNotificationServiceExtensionClient.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/13/25.
//

import UserNotifications
import Foundation

class MarketapNotificationServiceClient: MarketapNotificationServiceClientProtocol {
    static let nativeSdkVersion = "1.6.0"

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

        guard Self.isPushTrackingAllowed(projectId: projectId) else { return }

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
        urlRequest.setValue("ios", forHTTPHeaderField: "X-Marketap-SDK-Platform")
        urlRequest.setValue(Self.nativeSdkVersion, forHTTPHeaderField: "X-Marketap-SDK-Version")
        urlRequest.setValue("nse", forHTTPHeaderField: "X-Marketap-SDK-Source")
        if let clientKey = Self.loadClientKey(projectId: projectId), !clientKey.isEmpty {
            urlRequest.setValue(clientKey, forHTTPHeaderField: "X-Marketap-Client-Key")
        }
        urlRequest.httpBody = try? JSONEncoder().encode(request)

        let task = URLSession.shared.dataTask(with: urlRequest)
        task.resume()
    }
}

extension MarketapNotificationServiceClient {
    static let appGroupInfoPlistKey = "MarketapAppGroupIdentifier"
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let formatter = ISO8601DateFormatter()
    static let clientKeyDefaultsKeyPrefix = "marketap_client_key."

    static func isPushTrackingAllowed(
        projectId: String,
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        defaultsProvider: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) },
        now: Date = Date()
    ) -> Bool {
        let storage: UserDefaults
        if let group = bundle.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String, !group.isEmpty,
           let shared = defaultsProvider(group) {
            storage = shared
        } else {
            storage = defaults
        }
        guard let data = storage.data(forKey: "marketap_sdk_policy." + projectId),
              let policy = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let block = policy["pushTracking"] as? [String: Any], block["mode"] as? String == "stop" else { return true }
        guard let expiresAt = block["expiresAt"] as? String else { return false }
        let expiry = fractionalFormatter.date(from: expiresAt) ?? formatter.date(from: expiresAt)
        return expiry.map { $0 <= now } ?? false
    }

    static func loadClientKey(projectId: String) -> String? {
        guard let groupId = Bundle.main.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String, !groupId.isEmpty else {
            return nil
        }
        return UserDefaults(suiteName: groupId)?.string(forKey: clientKeyDefaultsKeyPrefix + projectId)
    }
}
