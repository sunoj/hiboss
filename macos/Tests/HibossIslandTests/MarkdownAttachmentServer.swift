// Serves extensionless Markdown and failure responses for native attachment integration tests.
// Exports: MarkdownAttachmentServer with an ephemeral loopback endpoint.
// Dependencies: Foundation Process, Python stdlib, and the native test wait helper.

import Foundation

@MainActor
final class MarkdownAttachmentServer {
    private let process = Process()
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("markdown-media-\(UUID().uuidString)", isDirectory: true)
    private(set) var baseURL = ""

    static let source = """
    # Release notes

    **Ready** for review.

    | Package | Budget |
    | --- | ---: |
    | Alpha | 345 |

    ```sh
    swift test
    ```
    """

    func start() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.source.write(to: directory.appendingPathComponent("report.md"),
            atomically: true, encoding: .utf8)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", Self.script, directory.path]
        try process.run()
        let port = directory.appendingPathComponent("port")
        try await waitForCondition { FileManager.default.fileExists(atPath: port.path) }
        baseURL = "http://127.0.0.1:\(try String(contentsOf: port, encoding: .utf8))"
    }

    func stop() {
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: directory)
    }

    private static let script = """
    import http.server, pathlib, sys
    root = pathlib.Path(sys.argv[1])
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_HEAD(self): self.respond(False)
        def do_GET(self): self.respond(True)
        def respond(self, body):
            if self.path == '/unavailable':
                self.send_error(503)
                return
            data = b'\\xff' if self.path == '/binary.md' else (root / 'report.md').read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', "attachment; filename*=UTF-8''report%20final.md")
            size = 2097153 if self.path == '/large.md' else len(data)
            self.send_header('Content-Length', str(size))
            self.end_headers()
            if body: self.wfile.write(data)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    (root / 'port').write_text(str(server.server_port))
    server.serve_forever()
    """
}
