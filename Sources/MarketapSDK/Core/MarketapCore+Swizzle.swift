//
//  MarketapCore+Swizzle.swift
//  MarketapSDK
//
//  Created by 이동현 on 6/22/25.
//

import Foundation
import UIKit

final class MarketapSwizzler: NSObject, UNUserNotificationCenterDelegate {

    func enableSwizzlingIfNeeded() {
        let enabled = Bundle.main.object(forInfoDictionaryKey: "MarketapSwizzlingEnabled") as? Bool
        guard enabled != false else { return }

        UNUserNotificationCenter.current().delegate = self
        self.swizzle()
    }


    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if Marketap.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) {
            return
        }

        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if Marketap.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) {
            return
        }

        completionHandler()
    }

    private func swizzle() {
        guard let appDelegate = UIApplication.shared.delegate else { return }
        guard let appDelegateClass: AnyClass = object_getClass(appDelegate) else { return }

        let originalSelector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        let swizzledSelector = #selector(MarketapSwizzler.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        guard let swizzledMethod = class_getInstanceMethod(MarketapSwizzler.self, swizzledSelector) else {
            return
        }

        if let originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector) {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        } else {
            class_addMethod(
                appDelegateClass,
                originalSelector,
                method_getImplementation(swizzledMethod),
                method_getTypeEncoding(swizzledMethod)
            )
        }
    }

    @objc public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Marketap.setPushToken(token: deviceToken)
    }
}
