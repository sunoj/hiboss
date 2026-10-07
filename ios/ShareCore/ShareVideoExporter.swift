// Owns a configured AVAssetExportSession and bridges completion with cancellation.
// Exports ShareVideoExporter; configuration is immutable before export starts.
// Dependencies: AVFoundation and ShareError.

@preconcurrency import AVFoundation

final class ShareVideoExporter: @unchecked Sendable {
    private let session: AVAssetExportSession
    private let output: URL

    init(source: URL, output: URL) throws {
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source),
            presetName: AVAssetExportPresetMediumQuality) else { throw ShareError.preparation }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        self.session = session
        self.output = output
    }

    func run() async throws {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
        } onCancel: {
            session.cancelExport()
        }
        guard !Task.isCancelled, session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            if Task.isCancelled { throw CancellationError() }
            throw ShareError.preparation
        }
    }
}
