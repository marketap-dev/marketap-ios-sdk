//
//  AppDelegate.swift
//  MarketapSDK
//
//  Created by 이동현 on 2/16/25.
//

import UIKit
import MarketapSDK

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        Marketap.setLogLevel(.debug)
        Marketap.initialize(projectId: "kx43pz7")
        Marketap.setClickHandler { event in
            if let urlString = event.url, let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
        Marketap.application(application, didFinishLaunchingWithOptions: launchOptions)
        Marketap.requestAuthorizationForPushNotifications()

        if let name: String = UserDefaults.standard.string(forKey: "userName"),
           let email: String = UserDefaults.standard.string(forKey: "userEmail"),
           let phone: String = UserDefaults.standard.string(forKey: "userPhone") {
            var cartValue: [[String: Any]] = []
            if let savedData = UserDefaults.standard.data(forKey: "cartItems"),
               let decoded = try? JSONDecoder().decode([CartItem].self, from: savedData) {
                cartValue = decoded.map { item in
                    return [
                        "mkt_product_id": item.name,
                        "mkt_product_name": item.name,
                        "mkt_product_price": item.price,
                        "mkt_quantity": 1
                    ]
                }
            }
            Marketap.identify(
                userId: phone,
                userProperties: [
                    "mkt_name": name,
                    "mkt_email": email,
                    "mkt_phone_number": phone,
                    "mkt_cart": cartValue
                ]
            )
        }

        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Marketap.setPushToken(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("Open url: \(url.absoluteString)")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {

        let configuration = UISceneConfiguration(
                                name: nil,
                                sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = SceneDelegate.self
        }
        return configuration
    }

    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if Marketap.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) {
            return
        }

        completionHandler([.banner, .sound, .badge])
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
}
