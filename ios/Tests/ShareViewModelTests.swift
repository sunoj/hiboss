// Exercises retained drafts, partial success and stable keys across ambiguous retries.
// Exports ShareViewModelTests with an actor-backed upload recorder.
// Dependencies: XCTest, HibossKit and the HiBoss share core.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class ShareViewModelTests: XCTestCase {
    func testRetryReusesKeyAndPayloadWithoutResendingCompletedAttachments() async throws {
        let api = ShareUploadRecorder()
        let items = [ShareAttachment.text("first"), ShareAttachment.text("second")]
        let model = ShareViewModel(api: api, attachments: items)
        model.note = "keep this note"
        model.project = "design"
        await model.save()
        XCTAssertEqual(model.state, .failure)
        XCTAssertEqual(model.note, "keep this note")
        XCTAssertEqual(model.project, "design")
        model.note = "a later draft"
        await model.save()
        let calls = await api.calls
        XCTAssertEqual(calls.map(\.key), [items[0].idempotencyKey, items[1].idempotencyKey,
            items[1].idempotencyKey])
        XCTAssertNotEqual(items[0].idempotencyKey, items[1].idempotencyKey)
        XCTAssertEqual(calls.map { $0.upload.note }, Array(repeating: "keep this note", count: 3))
        XCTAssertEqual(calls.map { $0.upload.source }, Array(repeating: .iosShare, count: 3))
        XCTAssertEqual(model.state, .done)
        XCTAssertEqual(model.progress, 1)
        await model.save()
        let count = await api.calls.count
        XCTAssertEqual(count, 3)
    }

    func testNoConnectionNeverCallsTheUploadAPI() async {
        let model = ShareViewModel(api: nil, attachments: [ShareAttachment.text("reference")])
        XCTAssertEqual(model.state, .disconnected)
        await model.save()
        XCTAssertEqual(model.state, .disconnected)
    }

    func testOversizedNoteKeepsDraftAndDoesNotUpload() async {
        let api = ShareUploadRecorder()
        let model = ShareViewModel(api: api, attachments: [ShareAttachment.text("reference")])
        model.note = String(repeating: "字", count: 6000)
        await model.save()
        XCTAssertEqual(model.state, .failure)
        XCTAssertEqual(model.note.count, 6000)
        let count = await api.calls.count
        XCTAssertEqual(count, 0)
    }

    func testPreparedMediaIsReusedOnRetryAndCompressionFailureNeverUploads() async throws {
        let file = BoxUpload.Media(fileURL: URL(fileURLWithPath: "/tmp/fixture.mp4"),
            contentType: "video/mp4")
        let item = ShareAttachment(kind: .video, title: "Clip", text: nil, url: nil, media: file)
        let api = ShareUploadRecorder(failAt: 1)
        let preparation = PreparationRecorder()
        let model = ShareViewModel(api: api, attachments: [item], prepare: { media, _ in
            await preparation.prepare(media)
        })
        await model.save()
        await model.save()
        let prepared = await preparation.count
        XCTAssertEqual(prepared, 1)
        XCTAssertEqual(model.state, .done)
        let refused = ShareViewModel(api: api, attachments: [item], prepare: { _, _ in
            throw ShareError.videoTooLarge
        })
        await refused.save()
        XCTAssertEqual(refused.state, .failure)
        XCTAssertTrue(refused.failure.contains("50 MB"))
        let count = await api.calls.count
        XCTAssertEqual(count, 2)
    }
}

private actor PreparationRecorder {
    var count = 0
    func prepare(_ media: BoxUpload.Media) -> BoxUpload.Media {
        count += 1
        return media
    }
}

private actor ShareUploadRecorder: BoxUploading {
    struct Call: Sendable {
        let key: String
        let upload: BoxUpload
    }
    var calls: [Call] = []
    private let failAt: Int
    init(failAt: Int = 2) { self.failAt = failAt }

    func createBoxItem(
        _ upload: BoxUpload, idempotencyKey: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BoxItem {
        calls.append(Call(key: idempotencyKey, upload: upload))
        if calls.count == failAt { throw URLError(.networkConnectionLost) }
        progress(0.5)
        return BoxItem(id: idempotencyKey, bossID: "fixture", bossName: "Fixture", kind: .text,
            createdAt: "2026-10-08T00:00:00Z")
    }
}
