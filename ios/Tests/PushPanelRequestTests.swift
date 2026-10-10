// Verifies panel notification decoding and routing to the matching detail.
// Exports: PushPanelRequestTests for payload validation and route replacement.
// Dependencies: XCTest, HibossKit, PushPanelRequest, and AppRouter.

import HibossKit
import XCTest
@testable import HiBoss

final class PushPanelRequestTests: XCTestCase {
    func testRequestPayloadNeedsPanelAndRequestButNoMessageID() throws {
        let request = try XCTUnwrap(PushPanelRequest.decode(from: [
            "category": "HIBOSS_REQUEST", "panelId": "panel-1", "requestId": "request-1",
        ]))
        XCTAssertEqual(request.panelID, "panel-1")
        XCTAssertEqual(request.requestID, "request-1")
    }

    func testRejectsMalformedRequestPayload() {
        let malformed: [[AnyHashable: Any]] = [
            ["panelId": "panel-1"], ["requestId": "request-1"],
            ["panelId": 42, "requestId": "request-1"],
            ["panelId": "panel-1", "requestId": 42],
            ["panelId": " ", "requestId": "request-1"],
            ["panelId": "panel-1", "requestId": ""],
        ]
        for info in malformed {
            XCTAssertNil(PushPanelRequest.decode(from: info))
        }
    }

    @MainActor
    func testRequestSelectsThePanelDetailTile() async throws {
        let model = PanelsModel(demoMode: true)
        let tile = try XCTUnwrap(model.tiles.first)
        let request = try XCTUnwrap(PushPanelRequest.decode(from: [
            "panelId": tile.id, "requestId": "request-1",
        ]))
        let opened = await model.openWhenLoaded(request.panelID)
        XCTAssertTrue(opened)
        XCTAssertEqual(model.selectedTile?.id, tile.id)
        model.closeDetail()
    }

    @MainActor
    func testMissingRequestPanelDoesNotPresentADetail() async {
        let model = PanelsModel(demoMode: true)
        let opened = await model.openWhenLoaded("missing-panel")
        XCTAssertFalse(opened)
        XCTAssertNil(model.selectedTile)
    }

    @MainActor
    func testRequestRouteDoesNotOpenMessageInboxAndPreservesNewerRequest() {
        let router = AppRouter.shared
        let message = router.pendingMessage
        let first = PushPanelRequest(panelID: "panel-1", requestID: "request-1")
        let second = PushPanelRequest(panelID: "panel-1", requestID: "request-2")
        router.open(panel: first)
        XCTAssertEqual(router.pendingPanel, first)
        XCTAssertEqual(router.pendingMessage, message)
        router.open(panel: second)
        router.finishOpening(first)
        XCTAssertEqual(router.pendingPanel, second)
        router.finishOpening(second)
        XCTAssertNil(router.pendingPanel)
    }
}
