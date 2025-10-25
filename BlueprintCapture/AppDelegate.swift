//
//  AppDelegate.swift
//  BlueprintCapture
//
//  Created by Nijel A. Hunt on 10/21/25.
//

import UIKit
import FirebaseCore
import UserNotifications
import FirebaseAuth
import Foundation
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationService = NotificationService()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        // Present notifications while app is foregrounded
        UNUserNotificationCenter.current().delegate = self
        notificationService.registerCategories()
        // Ensure SwiftUI List (UITableView) backgrounds are transparent so our gradient shows through
        let tableAppearance = UITableView.appearance()
        tableAppearance.backgroundColor = .clear
        let cellAppearance = UITableViewCell.appearance()
        cellAppearance.backgroundColor = .clear

        // Ensure a device-local user exists and print the doc
        UserDeviceService.ensureTemporaryUser()
        UserDeviceService.printLocalUser()

        // Start a new app session
        AppSessionService.shared.startIfNeeded()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppSessionService.shared.end(reasonCrash: false)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppSessionService.shared.end(reasonCrash: false)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show alert/sound in foreground as well
        completionHandler([.banner, .sound, .badge, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        switch response.actionIdentifier {
        case NotificationService.actionDirections:
            if let lat = userInfo["lat"] as? Double,
               let lng = userInfo["lng"] as? Double,
               let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d") {
                UIApplication.shared.open(url)
            }
        case NotificationService.actionCheckIn:
            NotificationCenter.default.post(name: .blueprintNotificationAction, object: nil, userInfo: [
                "action": "checkin",
                "targetId": userInfo["targetId"] as Any
            ])
        default:
            break
        }
        completionHandler()
    }
}

#if canImport(GoogleSignIn)
extension AppDelegate {
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        return false
    }
}
#endif
