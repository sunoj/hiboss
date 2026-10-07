// Debug-only host for the exact extension sheet without the system share menu.
// Exports DemoShareHost with offline save/retry fixtures and screenshot support.
// Dependencies: SwiftUI, HibossKit and ShareCore.

#if DEBUG
import HibossKit
import SwiftUI

struct DemoShareHost: View {
    @StateObject private var model: ShareViewModel
    @State private var dismissed = false

    init() {
        let flags = ProcessInfo.processInfo.environment
        _model = StateObject(wrappedValue: ShareViewModel(
            api: flags["HIBOSS_DEMO_SHARE"] == "disconnected" ? nil : DemoShareUpload(),
            attachments: [ShareAttachment.text("https://example.com/design-reference"),
                ShareAttachment.text("A reference to keep for the next project.")]
        ))
    }

    var body: some View {
        if dismissed { Text("Saved to Box") }
        else {
            ShareSheet(model: model, cancel: { dismissed = true }, complete: { dismissed = true }, reload: {})
        }
    }
}

private actor DemoShareUpload: BoxUploading {
    private var failed = false

    func createBoxItem(
        _ upload: BoxUpload, idempotencyKey: String, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BoxItem {
        for step in 1...4 {
            try await Task.sleep(for: .milliseconds(200))
            progress(Double(step) / 4)
        }
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_SHARE"] == "failure" && !failed {
            failed = true
            throw URLError(.networkConnectionLost)
        }
        return BoxItem(id: idempotencyKey, bossID: "demo", bossName: "Demo", kind: .text,
            text: upload.text, url: upload.url, note: upload.note, createdAt: "2026-10-08T00:00:00Z")
    }
}
#endif
