// Serves synthetic thumbnails on loopback for native History snapshot tests.
// Exports: HistorySnapshotMediaServer with a temporary directory and ephemeral port.
// Dependencies: Foundation Process, SwiftUI ImageRenderer, AppKit, and Python's stdlib.

import AppKit
import SwiftUI
import XCTest

@MainActor
final class HistorySnapshotMediaServer {
    private let process = Process()
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-media-\(UUID().uuidString)", isDirectory: true)
    private(set) var baseURL = ""

    func start() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, symbol) in [("ship", "paperplane"), ("hold", "pause.circle")] {
            let renderer = ImageRenderer(content: VStack(spacing: 12) {
                Image(systemName: symbol).font(.largeTitle)
                Text(name == "ship" ? "Release preview" : "Current layout").font(.title2)
            }.frame(width: 480, height: 320).background(Color.accentColor))
            let tiff = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        let script = """
        import http.server, os, pathlib, sys
        os.chdir(sys.argv[1])
        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *args): pass
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        pathlib.Path('port').write_text(str(server.server_port))
        server.serve_forever()
        """
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, directory.path]
        try process.run()
        let portURL = directory.appendingPathComponent("port")
        try await waitForCondition { FileManager.default.fileExists(atPath: portURL.path) }
        let port = try String(contentsOf: portURL, encoding: .utf8)
        baseURL = "http://127.0.0.1:\(port)"
    }

    func stop() {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: directory)
    }
}
