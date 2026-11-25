// Covers the Today row identity line: no repeated branch, device instead of user@host.
// Exports TodayRowIdentityTests, built from the strings a real session list reported.
// Dependencies: XCTest and the HiBoss app target.

import XCTest
@testable import HiBoss

final class TodayRowIdentityTests: XCTestCase {
    func testLabelBranchAndAgentHostAreNotRepeated() {
        let identity = TodayRowIdentity.make(
            label: "fluid-liquidator/main", fallback: "fluid-liquidator", nickname: "seagrass",
            branch: "main", host: nil, agent: "mingsun-claude@Mings-MacBook-Air")
        XCTAssertEqual(identity.project, "fluid-liquidator")
        XCTAssertEqual(identity.detail, ["seagrass", "MacBook Air"])
        XCTAssertEqual(identity.text, "fluid-liquidator · seagrass · MacBook Air")
    }

    func testInventoryHostWinsAndFeatureBranchStaysVisible() {
        let identity = TodayRowIdentity.make(
            label: "hiboss/feat-x", fallback: "hiboss", nickname: nil, branch: "feat-x",
            host: "Mings-Mac-Mini.local", agent: "ming-claude@elsewhere")
        XCTAssertEqual(identity.project, "hiboss")
        XCTAssertEqual(identity.detail, ["feat-x", "Mac Mini"])
    }

    func testChosenAgentNameIsKeptOverTheHost() {
        for host in [nil, "Mac mini"] {
            let identity = TodayRowIdentity.make(
                label: nil, fallback: "prod-release", nickname: nil, branch: nil, host: host, agent: "worker-design")
            XCTAssertEqual(identity.text, "prod-release · worker-design")
        }
    }

    func testOtherHostNamesKeepTheirWords() {
        XCTAssertEqual(TodayRowIdentity.device(from: "work-mini-vm"), "work mini vm")
        XCTAssertEqual(TodayRowIdentity.device(from: "Mac mini"), "Mac mini")
        XCTAssertEqual(TodayRowIdentity.device(from: "Alices-iPhone"), "iPhone")
    }
}
