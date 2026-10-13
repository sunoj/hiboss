// Serves square avatar and landscape fixtures for Progress cropping screenshots.
// Exports: ProgressPolishMediaServer with an isolated temporary root and loopback port.
// Dependencies: AppKit, SwiftUI, XCTest, Foundation Process and Python's HTTP server.

import AppKit
import SwiftUI
import XCTest

@MainActor
final class ProgressPolishMediaServer {
    private let process = Process()
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("progress-media-\(UUID().uuidString)", isDirectory: true)
    private(set) var baseURL = ""

    func start() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fixture(square: true, name: "square")
        try fixture(square: false, name: "wide")
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
        baseURL = "http://127.0.0.1:\(try String(contentsOf: portURL, encoding: .utf8))"
    }

    func stop() {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture(square: Bool, name: String) throws {
        let renderer = ImageRenderer(content: ZStack {
            Color.white
            if square { Circle().fill(Color.orange).padding(12) }
            VStack {
                Image(systemName: square ? "sparkles" : "house").font(.largeTitle)
                Text(square ? "Square avatar" : "Complete landscape").font(.title2)
            }
            .foregroundStyle(.black)
        }.frame(width: square ? 400 : 480, height: square ? 400 : 320))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
