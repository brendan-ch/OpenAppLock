//
//  UNMutableNotificationContent+URL.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.10.
//

import UserNotifications

extension UNMutableNotificationContent {
    func setURL(_ url: URL) {
        self.userInfo["url"] = url.absoluteString
    }
}
