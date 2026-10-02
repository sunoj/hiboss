// Tests for Settings chrome derived from live state and the system symbol set.
// Covers: per-state connection titles, failure reasons, live tint, and pane icons.
// Dependencies: XCTest, AppKit symbols, HibossKit ConnectionState, SettingsModels.

import AppKit
import HibossKit
import XCTest
@testable import HibossIsland

@MainActor
final class SettingsChromeTests: XCTestCase {
    private let states: [ConnectionState] = [.disconnected, .connecting, .connected, .failed("Token rejected")]

    func testStatusTitleIsTheStateLabelForEveryState() {
        XCTAssertEqual(states.map { SettingsConnectionStatus($0).title }, states.map(\.label))
        XCTAssertEqual(Set(states.map { SettingsConnectionStatus($0).title }).count, states.count)
    }

    func testOnlyConnectedReadsAsListeningAndLive() {
        let listening = ConnectionState.connected.label
        for state in states where state != .connected {
            let status = SettingsConnectionStatus(state)
            XCTAssertNotEqual(status.title, listening, "\(state)")
            XCTAssertFalse(status.isLive, "\(state)")
        }
        XCTAssertTrue(SettingsConnectionStatus(.connected).isLive)
    }

    func testFailureReasonIsShownOnlyForAFailureThatHasOne() {
        XCTAssertEqual(SettingsConnectionStatus(.failed("Token rejected")).detail, "Token rejected")
        XCTAssertNil(SettingsConnectionStatus(.failed("")).detail)
        for state in [ConnectionState.disconnected, .connecting, .connected] {
            XCTAssertNil(SettingsConnectionStatus(state).detail, "\(state)")
        }
    }

    func testEverySettingsPaneIconExistsInTheSystemSymbolSet() {
        XCTAssertEqual(SettingsPane.devices.icon, "laptopcomputer.and.iphone")
        for pane in SettingsPane.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: pane.icon, accessibilityDescription: nil), pane.icon)
        }
    }
}
