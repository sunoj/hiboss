// Source names remain present after the eight-second escalation threshold.
// Exports PendingNoticeSourceTests for copy used by both native notice components.
// Dependencies: XCTest and the shared package localization resources.

import XCTest
@testable import HibossKit

final class PendingNoticeSourceTests: XCTestCase {
    func testSimplifiedChineseNamesTheOutstandingSource() throws {
        let url = try XCTUnwrap(kitResourceBundle.url(forResource: "zh-Hans", withExtension: "lproj"))
        let chinese = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(chinese.localizedString(forKey: "Requests are taking longer than expected.",
                                               value: nil, table: nil), "请求加载时间比预期更长。")
        XCTAssertEqual(chinese.localizedString(forKey: "Questionnaires are taking longer than expected.",
                                               value: nil, table: nil), "问卷加载时间比预期更长。")
        for source in PendingNoticeSource.allCases {
            XCTAssertNotEqual(chinese.localizedString(forKey: source.slowTitle, value: nil, table: nil),
                              source.slowTitle)
        }
    }

    func testSlowRefreshNamesTheOutstandingSource() {
        XCTAssertEqual(PendingNoticeSource.requests.slowTitle, "Requests are taking longer than expected.")
        XCTAssertEqual(PendingNoticeSource.panels.slowTitle, "Panels are taking longer than expected.")
        XCTAssertEqual(PendingNoticeSource.questionnaires.slowTitle,
                       "Questionnaires are taking longer than expected.")
        XCTAssertEqual(PendingNoticeSource.messages.slowTitle, "Messages are taking longer than expected.")
        XCTAssertEqual(PendingNoticeSource.preferences.slowTitle, "Preferences are taking longer than expected.")
        XCTAssertEqual(PendingNoticeSource.deviceRequests.slowTitle,
                       "Device requests are taking longer than expected.")
    }
}
