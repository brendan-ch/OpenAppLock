//
//  UNNotificationContent+URL.swift
//  OpenAppLock
//
//  Created by Brendan Chen on 2026.09.10.
//

import UserNotifications

extension UNNotificationContent {
    var url: URL? {
        if let stringContent = self.userInfo["url"] as? String {
            return URL(string: stringContent)
        }
        return nil
    }
}
