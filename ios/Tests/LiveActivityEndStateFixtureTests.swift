// The server's Live Activity end-event content-state must decode as the app's ContentState.
// Exports: LiveActivityEndStateFixtureTests over docs/fixtures/live-activity-end-state.json.
// Dependencies: XCTest, DecisionActivityAttributes (shared Live Activity contract).

import XCTest
@testable import HiBoss

final class LiveActivityEndStateFixtureTests: XCTestCase {
    func testEveryFixtureStateDecodes() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "live-activity-end-state",
                                                           withExtension: "json"))
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), ["replied", "auto_default", "expired"])
        let states = try raw.mapValues {
            try JSONDecoder().decode(DecisionActivityAttributes.ContentState.self,
                                     from: JSONSerialization.data(withJSONObject: $0))
        }
        XCTAssertEqual(states["replied"]?.completion, .answeredElsewhere("Ship"))
        XCTAssertEqual(states["auto_default"]?.completion, .autoSelected("Hold"))
        XCTAssertNil(states["expired"]?.completion)
        for state in states.values {
            XCTAssertEqual(state.body, "")
            XCTAssertEqual(state.options, [])
            XCTAssertEqual(state.priority, "normal")
            XCTAssertNil(state.deadline)
            XCTAssertNil(state.submitting)
        }
    }

    /// A reply with no text is sent as an empty case object.
    func testAnswerWithoutTextDecodes() throws {
        let json = #"{"body":"","options":[],"priority":"normal","completion":{"answeredElsewhere":{}}}"#
        let state = try JSONDecoder().decode(DecisionActivityAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.completion, .answeredElsewhere(nil))
    }
}
