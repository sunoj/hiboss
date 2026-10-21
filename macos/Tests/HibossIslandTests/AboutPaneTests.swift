// Logic tests for the About pane's notices and the bundled update-feed defaults.
// Covers: the verbatim Sparkle license and the Info.plist Sparkle/version keys.
// Dependencies: XCTest, Foundation, and the macos/Resources/Info.plist on disk.

import Foundation
import XCTest
@testable import HibossIsland

final class AboutPaneTests: XCTestCase {
    func testAboutCarriesTheCompleteSparkleLicense() {
        let license = Acknowledgements.sparkleLicense
        XCTAssertTrue(license.hasPrefix("Copyright (c) 2006-2013 Andy Matuschak."))
        XCTAssertTrue(license.contains("Permission is hereby granted, free of charge"))
        for notice in ["Colin Percival", "Yuta Mori", "Orson Peters", "Mark Hamlin"] {
            XCTAssertTrue(license.contains(notice), "external license of \(notice) is missing")
        }
        XCTAssertEqual(Acknowledgements.sparkleURL?.absoluteString, "https://sparkle-project.org")
    }

    func testBundledInfoPlistDefaultsTheFeedToHibossOrgWithoutAKey() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: plistURL))
        XCTAssertEqual(plist["SUFeedURL"] as? String, "https://hiboss.org/updates/macos/appcast.xml")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertNil(plist["SUPublicEDKey"], "an empty key is invalid to Sparkle; release builds inject it")
    }
}
