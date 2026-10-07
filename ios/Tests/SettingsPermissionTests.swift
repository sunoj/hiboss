// Notification permission refresh and request failure remain actionable in Settings.
// Exports: SettingsPermissionTests with a controlled permission service and no APNs registration.
// Dependencies: XCTest, UserNotifications, PushStatusStore.

import UserNotifications
import XCTest
@testable import HiBoss

@MainActor
final class SettingsPermissionTests: XCTestCase {
    func testDeniedPermissionDirectsTheUserToSystemSettings() async {
        let store = PushStatusStore(permission: PermissionService(status: .denied), register: {})
        XCTAssertFalse(store.hasLoaded)
        await store.refresh()
        XCTAssertTrue(store.hasLoaded)
        XCTAssertTrue(store.mustOpenSystemSettings)
        XCTAssertFalse(store.isEnabled)
        XCTAssertEqual(store.label, String(localized: "Denied"))
    }

    func testFailedPermissionRequestFinishesAndKeepsAnActionableState() async {
        let store = PushStatusStore(permission: PermissionService(status: .notDetermined), register: {})
        store.request()
        XCTAssertTrue(store.isRequesting)
        while store.isRequesting { await Task.yield() }
        XCTAssertNotNil(store.failureMessage)
        XCTAssertFalse(store.isEnabled)
        XCTAssertFalse(store.mustOpenSystemSettings)
        XCTAssertTrue(store.hasLoaded)
    }

    func testProvisionalPermissionSaysNotificationsArriveQuietly() async {
        let store = PushStatusStore(permission: PermissionService(status: .provisional), register: {})
        await store.refresh()
        XCTAssertTrue(store.isEnabled)
        XCTAssertEqual(store.label, String(localized: "Delivering quietly"))
    }

    func testPermissionWaitEndsBeforePhoneRegistrationFinishes() async {
        var registration: CheckedContinuation<Void, Never>?
        let store = PushStatusStore(
            permission: PermissionService(status: .authorized, shouldFail: false),
            register: { await withCheckedContinuation { registration = $0 } }
        )
        store.request()
        while registration == nil { await Task.yield() }
        XCTAssertTrue(store.isRequesting)
        XCTAssertTrue(store.isEnabled)
        XCTAssertFalse(store.isWaitingForPermission)
        registration?.resume()
        while store.isRequesting { await Task.yield() }
    }
}

private struct PermissionService: SettingsNotificationPermission {
    let status: UNAuthorizationStatus
    var shouldFail = true
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return status == .authorized
    }
}
