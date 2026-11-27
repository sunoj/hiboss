// Renders the catalog v2 inputs offscreen (no window) and, when asked, writes PNGs for review.
// Exports: PanelInputsV2RenderTests; HIBOSS_V2_SHOTS=<dir> writes light and dark images.
// Dependencies: SwiftUI ImageRenderer, XCTest, and the HibossKit v2 input views.

import SwiftUI
import XCTest
@testable import HibossKit

@MainActor
final class PanelInputsV2RenderTests: XCTestCase {
    private let follow = [("sync", "Fix the flaky sync test"), ("settings", "Split the settings screen"),
        ("avatars", "Cache the avatar images"), ("flag", "Rename the export flag")]
        .map { PanelOption(id: $0.0, label: $0.1, description: nil) }
    private let checks = [("changelog", "Changelog read end to end"), ("migration", "Migration rehearsed on a copy"),
        ("rollback", "Rollback steps tested"), ("support", "Support team told about the date")]
        .map { PanelOption(id: $0.0, label: $0.1, description: nil) }
    private let verdicts = [ReviewVerdict(id: "confirmed", label: "Confirmed", requiresNote: false),
        ReviewVerdict(id: "not_confirmed", label: "Cannot confirm", requiresNote: true)]

    private func formOf(_ json: String) throws -> AskForm {
        try XCTUnwrap(AskForm(try JSONDecoder().decode(PanelValue.self, from: Data(json.utf8))))
    }

    func testInputsRenderWithRealHeight() throws {
        var review = PanelValue.null
        review = ItemReviewAnswer.setting(review, item: "changelog", verdict: "confirmed", note: nil)
        review = ItemReviewAnswer.setting(review, item: "migration", verdict: "confirmed", note: nil)
        review = ItemReviewAnswer.setting(review, item: "rollback", verdict: "not_confirmed", note: "Only tried on the old schema")
        let views: [(String, AnyView)] = [
            ("ranked", AnyView(PanelRankedChoice(label: "Order the follow-ups for next week", options: follow,
                topK: nil, value: .constant(.array(["sync", "settings", "avatars", "flag"].map(PanelValue.string)))))),
            ("review", AnyView(PanelItemReview(label: "Pre-release checklist", items: checks,
                verdicts: verdicts, value: .constant(review)))),
            ("form-ready", AnyView(AskFormView(form: try formOf(#"{"catalogVersion":2,"input":{"type":"RankedChoice","props":{"label":"Order the follow-ups","value":{"$bindState":"/form/answer"},"options":[{"id":"a","label":"Fix the flaky sync test"},{"id":"b","label":"Split the settings screen"}]}}}"#),
                isSubmitting: false, onSubmit: { _, _ in true }))),
            ("form-incomplete", AnyView(AskFormView(form: try formOf(#"{"catalogVersion":2,"input":{"type":"ItemReview","props":{"label":"Checks","value":{"$bindState":"/form/answer"},"items":[{"id":"a","label":"Changelog read"}],"verdicts":[{"id":"ok","label":"Confirmed"},{"id":"no","label":"Cannot confirm"}]}}}"#),
                isSubmitting: false, onSubmit: { _, _ in true }))),
        ]
        for (name, view) in views {
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: view.padding(20).frame(width: 520)
                    .background(scheme == .dark ? Color.black : Color.white).environment(\.colorScheme, scheme))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertGreaterThan(image.height, 150, "\(name) rendered \(image.height) px high")
                if let directory = ProcessInfo.processInfo.environment["HIBOSS_V2_SHOTS"] {
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
                    CGImageDestinationAddImage(destination, image, nil)
                    XCTAssertTrue(CGImageDestinationFinalize(destination))
                }
            }
        }
    }
}
