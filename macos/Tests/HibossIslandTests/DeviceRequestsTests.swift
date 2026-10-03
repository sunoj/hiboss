// Device Requests on macOS: one notification per new request ID, routing, and sheet rendering.
// Exports: DeviceRequestsTests; set HIBOSS_JOIN_SNAPSHOTS=<dir> to write the rendered sheets.
// Dependencies: XCTest, AppKit, SwiftUI, HibossKit join requests, and the macOS app target.

import AppKit
import HibossKit
import SwiftUI
import XCTest
@testable import HibossIsland

@MainActor
final class DeviceRequestsTests: XCTestCase {
    func testOneNotificationPerNewRequestID() async {
        let service = PendingJoinService(lists: [[Self.mini], [Self.mini], [Self.mini, Self.lab]])
        let model = JoinRequestsModel { service }
        let center = RecordingJoinCenter()
        let notifier = JoinRequestNotifier(center: center) { true }
        model.onNewRequests = { requests in Task { await notifier.announce(requests) } }

        for _ in 0..<3 {
            await model.refresh()
            await Task.yield()
        }
        model.reset()
        await model.refresh()
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(center.notices.map(\.requestID), ["jr-1", "jr-2"])
    }

    func testNoticeMirrorsThePushCopy() {
        let notice = JoinRequestNotice(request: Self.mini)
        XCTAssertEqual(notice.title, L("New device wants to join"))
        XCTAssertEqual(notice.body, "mini (claude, codex) · code 012345")
        XCTAssertEqual(JoinRequestNotice(request: Self.lab).body, "lab · code 999000")
    }

    func testUnauthorizedNotificationsAreNotPosted() async {
        let center = RecordingJoinCenter()
        await JoinRequestNotifier(center: center) { false }.announce([Self.mini])
        XCTAssertTrue(center.notices.isEmpty)
    }

    func testOpeningARequestFocusesDeviceRequestsAndOpensTheWindow() {
        var opens = 0
        let navigation = MessageNotificationNavigation(activate: {})
        navigation.install { opens += 1 }

        navigation.openDeviceRequests(requestID: "jr-1")

        XCTAssertEqual(navigation.deviceRequestsFocus?.requestID, "jr-1")
        XCTAssertEqual(opens, 1)
    }

    func testDeviceRequestsIsADestinationWithoutMessages() {
        let snapshot = OverviewSnapshot(history: [], live: nil, now: .now)
        XCTAssertEqual(snapshot.title(for: .deviceRequests), L("Device Requests"))
        XCTAssertTrue(snapshot.messages(for: .deviceRequests).isEmpty)
    }

    func testSheetAndListRenderOffscreen() async throws {
        let model = JoinRequestsModel { PendingJoinService(lists: [[Self.mini, Self.lab]]) }
        await model.refresh()
        let forbidden = JoinRequestsModel {
            PendingJoinService(lists: [], error: JoinRequestError.forbidden)
        }
        await forbidden.refresh()
        let views: [(String, AnyView, NSSize)] = [
            ("sheet", AnyView(JoinRequestSheet(requestID: "jr-1", model: model)), NSSize(width: 480, height: 600)),
            ("sheet-no-code", AnyView(JoinRequestSheet(requestID: "jr-3", model: Self.noCodeModel())),
             NSSize(width: 480, height: 600)),
            ("list", AnyView(DeviceRequestsView(model: model, focus: .constant(nil), onSettings: {})),
             NSSize(width: 760, height: 360)),
            ("forbidden", AnyView(DeviceRequestsView(model: forbidden, focus: .constant(nil), onSettings: {})),
             NSSize(width: 760, height: 360)),
        ]
        for (name, view, size) in views {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let bitmap = try await render(view, size: size, appearance: appearance)
                XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(size.width))
                write(bitmap, name: "\(name)-\(appearance == .aqua ? "light" : "dark")")
            }
        }
    }

    private func render(_ view: AnyView, size: NSSize, appearance: NSAppearance.Name) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func write(_ bitmap: NSBitmapImageRep, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["HIBOSS_JOIN_SNAPSHOTS"],
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("join-\(name).png"))
    }

    private static func noCodeModel() -> JoinRequestsModel {
        let request = JoinRequest(id: "jr-3", deviceLabel: "lab", verificationCode: nil)
        return JoinRequestsModel { PendingJoinService(lists: [[request]]) }
    }

    static let mini = JoinRequest(
        id: "jr-1", deviceLabel: "mini", deviceHost: "mini.local", inviterLabel: "Office Mac",
        verificationCode: "012345",
        profiles: [JoinRequestProfile(profile: "claude", name: "mini-claude"),
                   JoinRequestProfile(profile: "codex", name: "mini-codex")],
        createdAt: "2026-10-03 08:00:00"
    )
    static let lab = JoinRequest(id: "jr-2", deviceLabel: "lab", verificationCode: "999000")
}

@MainActor
private final class RecordingJoinCenter: JoinRequestNotifying {
    var notices: [JoinRequestNotice] = []
    func postJoinRequest(_ notice: JoinRequestNotice) async throws { notices.append(notice) }
}

private final class PendingJoinService: JoinRequestServing, @unchecked Sendable {
    private var lists: [[JoinRequest]]
    private let error: Error?

    init(lists: [[JoinRequest]], error: Error? = nil) {
        self.lists = lists
        self.error = error
    }

    func listPendingJoinRequests() async throws -> [JoinRequest] {
        if let error { throw error }
        return lists.count > 1 ? lists.removeFirst() : (lists.first ?? [])
    }

    func approveJoinRequest(id: String) async throws -> JoinApproval { throw JoinRequestError.notFound }
    func rejectJoinRequest(id: String) async throws { throw JoinRequestError.notFound }
}
