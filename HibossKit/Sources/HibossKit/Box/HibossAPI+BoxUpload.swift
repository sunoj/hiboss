// Creates Box items with JSON or disk-backed multipart uploads and byte progress.
// Exports HibossAPI BoxUploading conformance; retries use the caller's stable key.
// Dependencies: Foundation URLSession, BoxUpload and existing authentication helpers.

import Foundation

extension HibossAPI: BoxUploading {
    public func createBoxItem(
        _ upload: BoxUpload, idempotencyKey: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BoxItem {
        var request = authorizedRequest(
            url: config.serverURL.appendingPathComponent("api/box/items"), method: "POST"
        )
        request.timeoutInterval = 120
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        let delegate = BoxUploadProgress(progress)
        let result: (Data, URLResponse)
        if let media = upload.media {
            let boundary = "HiBoss-\(UUID().uuidString)"
            let bodyURL = try multipartBody(upload, media: media, boundary: boundary)
            defer { try? FileManager.default.removeItem(at: bodyURL) }
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            result = try await session.upload(for: request, fromFile: bodyURL, delegate: delegate)
        } else {
            result = try await session.upload(
                for: request, from: JSONEncoder().encode(upload), delegate: delegate)
        }
        try validate(result.1)
        let item = try decoder.decode(BoxItem.self, from: result.0)
        progress(1)
        return item
    }

    private func multipartBody(_ upload: BoxUpload, media: BoxUpload.Media, boundary: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let metadata = try JSONEncoder().encode(upload)
        let filename = media.fileURL.lastPathComponent
            .replacingOccurrences(of: "\r", with: "%0D")
            .replacingOccurrences(of: "\n", with: "%0A")
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\\", with: "%5C")
        var header = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"meta\"\r\n\r\n".utf8)
        header.append(metadata)
        header.append(Data(("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; "
            + "filename=\"\(filename)\"\r\nContent-Type: \(media.contentType)\r\n\r\n").utf8))
        #if os(macOS)
        try header.write(to: url, options: .atomic)
        #else
        try header.write(to: url, options: [.atomic, .completeFileProtection])
        #endif
        do {
            let output = try FileHandle(forWritingTo: url)
            defer { try? output.close() }
            try output.seekToEnd()
            let input = try FileHandle(forReadingFrom: media.fileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}

private final class BoxUploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let progress: @Sendable (Double) -> Void

    init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
