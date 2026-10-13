// Runs window regressions with the app executable's linked SDK compatibility behavior.
// Exports: BoxAppSDKTestHost; only a temporary copy of Xcode's XCTest host is adjusted.
// Dependencies: Foundation, XCTest, Quartz, vtool and codesign; the original host remains untouched.

import Foundation
import Quartz
import XCTest

@MainActor
enum BoxAppSDKTestHost {
    private static var preparedHost: URL?

    /// AppKit and SwiftUI select control geometry using the process's linked SDK, not the test bundle's.
    static func runHere(_ function: String) async throws -> Bool {
        // A preceding Box keyboard test can leave this process's shared Quick Look panel visible.
        if QLPreviewPanel.sharedPreviewPanelExists() { QLPreviewPanel.shared()?.orderOut(nil) }
        if ProcessInfo.processInfo.environment["HIBOSS_BOX_APP_SDK_HOST"] == "1" { return true }
        let bundle = Bundle(for: BoxMainWindowLayoutTests.self).bundleURL
        let app = bundle.deletingLastPathComponent().appendingPathComponent("HibossIsland")
        let sdk = try await linkedSDK(app)
        let original = URL(fileURLWithPath: try await command("/usr/bin/xcrun", ["--find", "xctest"]))
        if try await linkedSDK(original) == sdk { return true }
        let host = try await prepare(original: original, sdk: sdk)
        let selector = function.replacingOccurrences(of: "()", with: "")
        let process = Process()
        process.executableURL = host
        process.arguments = ["-XCTest", "HibossIslandTests.BoxMainWindowLayoutTests/\(selector)", bundle.path]
        var environment = ProcessInfo.processInfo.environment
        environment["HIBOSS_BOX_APP_SDK_HOST"] = "1"
        process.environment = environment
        let output = try await execute(process)
        print("Box app SDK \(sdk) host: \(selector)\n\(output)")
        XCTAssertTrue(output.contains("Executed 1 test"), "The app SDK host must execute the regression")
        XCTAssertEqual(process.terminationStatus, 0, "App SDK window regression failed: \(selector)")
        return false
    }

    private static func prepare(original: URL, sdk: String) async throws -> URL {
        if let preparedHost { return preparedHost }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hiboss-box-xctest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let host = directory.appendingPathComponent("xctest")
        _ = try await command("/usr/bin/xcrun", ["vtool", "-set-build-version", "macos", "14.0", sdk,
            "-replace", "-output", host.path, original.path])
        _ = try await command("/usr/bin/codesign", ["--force", "--sign", "-", host.path])
        let hostSDK = try await linkedSDK(host)
        XCTAssertEqual(hostSDK, sdk)
        preparedHost = host
        return host
    }

    private static func linkedSDK(_ executable: URL) async throws -> String {
        let output = try await command("/usr/bin/xcrun", ["vtool", "-show-build", executable.path])
        let sdk = output.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            return fields.first == "sdk" ? fields.last.map(String.init) : nil
        }.first
        return try XCTUnwrap(sdk, "No linked SDK in \(executable.lastPathComponent)")
    }

    private static func command(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = try await execute(process)
        XCTAssertEqual(process.terminationStatus, 0, "\(executable) failed")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func execute(_ process: Process) async throws -> String {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hiboss-box-host-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close(); try? FileManager.default.removeItem(at: outputURL) }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        try await waitForCondition(timeout: .seconds(60)) { !process.isRunning }
        return try String(contentsOf: outputURL, encoding: .utf8)
    }
}
