// Proves the four input components reach the assembled answer, not just the screen.
// Exports: PanelInputBindingTests for text, multiple selection, and slider bindings.
// Dependencies: XCTest, PanelStore, PanelExampleFixtures.

import XCTest
@testable import HibossIsland

@MainActor
final class PanelInputBindingTests: XCTestCase {
    private func intakeStore() throws -> PanelStore {
        let fixtures = try PanelExampleFixtures.load()
        let intake = try XCTUnwrap(fixtures.first { $0.title.localizedCaseInsensitiveContains("intake") })
        return PanelStore(fixture: intake)
    }

    func testEveryInputTypeReachesTheSubmittedAnswer() throws {
        let store = try intakeStore()
        store.setString("Which review step costs the most time?", at: "/form/researchQuestion")
        store.setString("Two teams disagree about where the delay is.", at: "/form/background")
        store.setStrings(["benchmarks", "interviews"], at: "/form/evidenceTypes")
        store.setNumber(0.85, at: "/form/confidence")

        store.perform(PanelAction(action: "submitRequest", params: nil))
        let answer = try XCTUnwrap(store.submittedAnswerText)

        XCTAssertTrue(answer.contains("Which review step costs the most time?"), answer)
        XCTAssertTrue(answer.contains("Two teams disagree about where the delay is."), answer)
        XCTAssertTrue(answer.contains("benchmarks"), answer)
        XCTAssertTrue(answer.contains("interviews"), answer)
        XCTAssertFalse(answer.contains("literature-review"), "the replaced default must not survive: \(answer)")
        XCTAssertTrue(answer.contains("0.85"), answer)
    }

    func testANumericLookingAnswerStaysText() throws {
        let store = try intakeStore()
        store.setString("2024", at: "/form/researchQuestion")
        store.perform(PanelAction(action: "submitRequest", params: nil))
        let answer = try XCTUnwrap(store.submittedAnswerText)
        XCTAssertTrue(answer.contains("\"2024\""), "free text that parses as a number must stay a string: \(answer)")
    }

    func testMultipleSelectionCarriesEveryChoiceAsAnArray() throws {
        let store = try intakeStore()
        store.setStrings([], at: "/form/evidenceTypes")
        store.perform(PanelAction(action: "submitRequest", params: nil))
        let cleared = try XCTUnwrap(store.submittedAnswerText)
        XCTAssertTrue(cleared.contains("[") && cleared.contains("]"), "an empty selection stays an array: \(cleared)")

        store.setStrings(["a", "b", "c"], at: "/form/evidenceTypes")
        store.perform(PanelAction(action: "submitRequest", params: nil))
        let filled = try XCTUnwrap(store.submittedAnswerText)
        for id in ["a", "b", "c"] { XCTAssertTrue(filled.contains(id), filled) }
    }

    func testTaskReplacementLeavesFormDraftUntouched() throws {
        let store = try intakeStore()
        let before = store.state

        store.replaceTask(.object(["status": .string("running")]))

        XCTAssertEqual(panelValue(at: "/form", in: store.state), panelValue(at: "/form", in: before))
    }
}
