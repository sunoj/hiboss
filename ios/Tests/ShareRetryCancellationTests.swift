// Proves canceling a retry while its earlier upload finishes cannot start another POST.
// Exports ShareRetryCancellationTests with a held upload and inverted request expectation.
// Dependencies: XCTest, HibossKit and the HiBoss share view model.

import HibossKit
import XCTest
@testable import HiBoss

@MainActor
final class ShareRetryCancellationTests: XCTestCase {
    func testCancelWhileAwaitingEarlierUploadPreventsAnotherPost() async throws {
        let started = XCTestExpectation(description: "First upload started")
        let unexpected = XCTestExpectation(description: "No upload after cancel")
        unexpected.isInverted = true
        let api = HeldShareUpload(started: started, unexpected: unexpected)
        let model = ShareViewModel(api: api, attachments: [ShareAttachment.text("reference")])
        let first = Task { await model.save() }
        await fulfillment(of: [started], timeout: 5)
        first.cancel()
        let retry = Task { await model.retry(after: first) }
        retry.cancel()
        await api.release()
        await retry.value
        await fulfillment(of: [unexpected], timeout: 0.3)
        let calls = await api.calls
        XCTAssertEqual(calls, 1)
    }
}

private actor HeldShareUpload: BoxUploading {
    private let started: XCTestExpectation
    private let unexpected: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    var calls = 0

    init(started: XCTestExpectation, unexpected: XCTestExpectation) {
        self.started = started
        self.unexpected = unexpected
    }

    func createBoxItem(
        _ upload: BoxUpload, idempotencyKey: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BoxItem {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation {
                continuation = $0
                started.fulfill()
            }
        } else {
            unexpected.fulfill()
        }
        throw URLError(.networkConnectionLost)
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
