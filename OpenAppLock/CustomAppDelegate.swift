//
//  CustomAppDelegate.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.10.
//

import UIKit

// see https://swiftwithmajid.com/2024/04/09/deep-linking-for-local-notifications-in-swiftui/

final class CustomAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

extension CustomAppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let url = response.notification.request.content.url else { return }
        await UIApplication.shared.open(url)
    }
}

