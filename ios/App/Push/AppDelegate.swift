// UIApplication delegate bridging APNs registration callbacks, silent pushes and orientations.
// Exports: AppDelegate, attached via @UIApplicationDelegateAdaptor.
// Dependencies: UIKit, PushManager, ResolutionPush, KeychainRelayCredentialStore, OrientationPolicy.

import UIKit
import os

private let pushLog = Logger(subsystem: "ai.hiboss.app", category: "Push")

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PushManager.shared.configure()
        return true
    }

    /// Landscape only on a wide iPhone screen; see OrientationPolicy.
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationPolicy.mask(for: window?.windowScene)
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

    /// A silent resolution push retracts the ask on this phone; anything else is not ours.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let key = (try? KeychainRelayCredentialStore().read()).flatMap { Base64URL.decode($0.pushKey) }
        let notice = ResolutionPush.decode(userInfo, pushKey: key)
        Task { @MainActor in
            let handled = await ResolutionPush.handle(notice, effects: SystemResolutionEffects())
            completionHandler(handled ? .newData : .noData)
        }
    }
}
