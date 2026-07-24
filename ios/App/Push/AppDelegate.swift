// UIApplication delegate bridging APNs registration callbacks to PushManager.
// Exports: AppDelegate, attached via @UIApplicationDelegateAdaptor.
// Dependencies: UIKit, PushManager.

import UIKit
import os

private let pushLog = Logger(subsystem: "ai.hiboss.ios", category: "Push")

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushManager.shared.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushManager.shared.register(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushLog.error("APNs registration failed: \(error.localizedDescription)")
        Task { @MainActor in PushManager.shared.registrationFailed(error) }
    }
}
