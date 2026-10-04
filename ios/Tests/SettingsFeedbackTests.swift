// Settings feedback: the Copy Link confirmation window and the unapprovable device-request note.
// Exports: SettingsFeedbackTests covering CopyFeedback and DeviceRequestsView.approvalNote.
// Dependencies: XCTest, HibossKit JoinRequest, and the HiBoss app target.

import HibossKit
import XCTest
@testable import HiBoss

final class SettingsFeedbackTests: XCTestCase {
    func testCopyShowsConfirmationUntilItsOwnWindowExpires() {
        var feedback = CopyFeedback()
        XCTAssertFalse(feedback.isShowing)
        XCTAssertEqual(feedback.count, 0)

        feedback.copied()
        let first = feedback.count
        feedback.copied()
        XCTAssertTrue(feedback.isShowing)
        XCTAssertEqual(feedback.count, 2, "every copy re-triggers the haptic")

        feedback.expire(copy: first)
        XCTAssertTrue(feedback.isShowing, "a stale window does not hide a newer copy")
        feedback.expire(copy: feedback.count)
        XCTAssertFalse(feedback.isShowing)
        XCTAssertEqual(CopyFeedback.duration, .seconds(2))
    }

    func testOnlyARequestWithoutACodeCarriesTheCannotApproveNote() throws {
        let approvable = JoinRequest(id: "a", deviceLabel: "mini", verificationCode: "482913")
        let missing = JoinRequest(id: "b", deviceLabel: "ci-runner", verificationCode: nil)
        let blank = JoinRequest(id: "c", deviceLabel: "old", verificationCode: "  ")

        XCTAssertNil(DeviceRequestsView.approvalNote(approvable))
        let note = try XCTUnwrap(DeviceRequestsView.approvalNote(missing))
        XCTAssertEqual(String(localized: note), String(localized: "No verification code — can’t be approved"))
        XCTAssertNotNil(DeviceRequestsView.approvalNote(blank), "a blank code is no code")
    }
}
