// Exercises lifecycle rendering and wall transitions across real panel definitions.
// Exports end-to-end model flows and a mutable protocol-v2 service fixture.
// Dependencies: XCTest, SwiftUI ImageRenderer, HibossKit, and shared JSON fixtures.

import AppKit
import HibossKit
import SwiftUI
import XCTest

@MainActor
final class PanelLifecycleFlowTests: XCTestCase {
    func testFinishReloadPreservesStoreAndSelectionThenRetainsUnreadResult() async throws {
        let service = try LifecycleService(names: ["download-progress"])
        let model = PanelsModel(api: service, demoMode: false, autoload: false)
        await model.load()
        let original = try XCTUnwrap(model.tiles.first)
        model.open(original.id)
        await service.end(original.id, state: "completed", dismissAt: Date().addingTimeInterval(-1))
        await model.load()
        let completed = try XCTUnwrap(model.tiles.first)
        XCTAssertTrue(original.store === completed.store)
        XCTAssertEqual(model.selectedTile?.id, original.id)
        XCTAssertEqual(completed.lifecycle.taskState, .completed)
        XCTAssertTrue(model.visibleTiles.isEmpty)
        XCTAssertEqual(model.unreadResults, 1)
        model.section = .results
        XCTAssertEqual(model.visibleTiles.count, 1)
        await model.setPreference(completed, seen: 2)
        XCTAssertEqual(model.unreadResults, 0)
        await model.setPreference(completed, placement: .pinned)
        model.section = .active
        XCTAssertEqual(model.visibleTiles.count, 1)
    }

    func testArchiveDoesNotStopMonitorAndFailedResultRequiresAcknowledgement() async throws {
        let service = try LifecycleService(names: ["service-monitor"])
        let model = PanelsModel(api: service, demoMode: false, autoload: false)
        await model.load()
        let tile = try XCTUnwrap(model.tiles.first)
        await model.setPreference(tile, placement: .archived)
        XCTAssertTrue(model.visibleTiles.isEmpty)
        XCTAssertEqual(model.tiles.first?.lifecycle.taskState, .running)
        model.section = .archived
        XCTAssertEqual(model.visibleTiles.count, 1)
        await model.setPreference(tile, placement: .automatic)
        await service.end(tile.id, state: "failed")
        await model.load()
        model.section = .active
        XCTAssertEqual(model.visibleTiles.count, 1)
        await model.setPreference(try XCTUnwrap(model.tiles.first), acknowledge: true)
        XCTAssertTrue(model.visibleTiles.isEmpty)
        model.section = .results
        XCTAssertEqual(model.visibleTiles.count, 1)
    }

    func testFreshnessUsesServerClockAndHeartbeatCannotRefreshObservation() async throws {
        let service = try LifecycleService(names: ["service-monitor"])
        let model = PanelsModel(api: service, demoMode: false, autoload: false)
        await model.load()
        let tile = try XCTUnwrap(model.tiles.first)
        let server = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = PanelRelaySnapshot(panelID: tile.id, definitionRevision: 1, epoch: "live", sequence: 0,
            task: panelValue(at: "/task", in: tile.store.state) ?? .null, observationVersion: 1,
            lastObservedAt: server.ISO8601Format(), staleAt: server.addingTimeInterval(15).ISO8601Format(),
            leaseExpiresAt: server.addingTimeInterval(45).ISO8601Format(), serverTime: 1_700_000_000_000)
        model.receive(.snapshot(snapshot), for: tile.id)
        if case .live = model.freshness(for: tile) {} else { XCTFail("Client wall-clock skew must not mark data stale") }
        if case .stale = model.freshness(for: tile, at: Date().addingTimeInterval(16)) {} else { XCTFail("Observation deadline must expire") }
        if case .offline = model.freshness(for: tile, at: Date().addingTimeInterval(46)) {} else { XCTFail("Lease deadline must expire") }
    }

    func testDifferentCardTypesRenderTheirLifecycleInBothAppearances() async throws {
        let names = ["download-progress", "e2e-test-run", "benchmark-sweep", "service-monitor"]
        let states = ["completed", "failed", "cancelled", "paused"]
        let service = try LifecycleService(names: names)
        for (name, state) in zip(names, states) { await service.end(name, state: state) }
        let model = PanelsModel(api: service, demoMode: false, autoload: false)
        await model.load()
        XCTAssertEqual(model.tiles.count, 4)
        for (tile, state) in zip(model.tiles, states) { XCTAssertEqual(tile.lifecycle.taskState.rawValue, state) }
        for scheme in [ColorScheme.dark, .light] {
            let renderer = ImageRenderer(content: VStack(spacing: 16) {
                HStack(spacing: 16) { card(model.tiles[0], model); card(model.tiles[1], model) }
                HStack(spacing: 16) { card(model.tiles[2], model); card(model.tiles[3], model) }
            }.padding(24).background(scheme == .dark ? Color.black : Color.white).environment(\.colorScheme, scheme))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertGreaterThan(image.size.height, 600)
            if let directory = ProcessInfo.processInfo.environment["HIBOSS_PANEL_SNAPSHOTS"], let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("lifecycle-\(scheme).png"))
            }
        }
    }
    private func card(_ tile: PanelTile, _ model: PanelsModel) -> some View {
        PanelDashboardCard(tile: tile, freshness: model.freshness(for: tile), pendingCount: model.pendingCount(for: tile)) {}.frame(width: 430, height: 320)
    }
}

actor LifecycleService: PanelsServing {
    private var documents: [String: [String: PanelValue]] = [:]
    private let names: [String]
    init(names: [String]) throws {
        self.names = names
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in names {
            let data = try Data(contentsOf: root.appendingPathComponent("panel-runtime/fixtures/examples/\(name).json"))
            guard case var .object(definition) = try JSONDecoder().decode(PanelValue.self, from: data) else { throw HibossAPIError.invalidResponse }
            definition["definitionRevision"] = .number(1); definition["createdAt"] = .string(Date().ISO8601Format())
            documents[name] = ["panelId": .string(name), "agentId": .string("test-agent"), "agentName": .string("Lifecycle preview"),
                "targetBossId": .string("boss"), "taskKey": .string(name), "sessionId": .string("test-session"),
                "title": definition["title"] ?? .string(name), "catalogId": .string("hiboss.panel"), "catalogVersion": .number(1),
                "serverTime": .number(Double(Int64(Date().timeIntervalSince1970 * 1000))), "definitionRevision": .number(1), "metadataVersion": .number(1), "createdAt": .string(Date().ISO8601Format()),
                "summary": .object([:]), "definition": .object(definition), "lifecycle": try Self.value(PanelLifecycle.running),
                "preference": try Self.value(PanelPreference.automatic), "finalSnapshot": .null, "supersedesPanelId": .null]
        }
    }
    func fetchPanels() throws -> [PanelMetadata] { try names.map { try fetchPanel($0).metadata } }
    func fetchPanel(_ panelID: String) throws -> PanelDetail {
        guard let document = documents[panelID] else { throw HibossAPIError.invalidResponse }
        return try JSONDecoder().decode(PanelDetail.self, from: JSONEncoder().encode(PanelValue.object(document)))
    }
    func fetchPanelState(_ panelID: String) throws -> PanelRelaySnapshot {
        let detail = try fetchPanel(panelID)
        return detail.metadata.finalSnapshot ?? PanelRelaySnapshot(panelID: panelID, definitionRevision: 1, epoch: nil, sequence: 0,
            task: panelValue(at: "/task", in: detail.definition.initialState) ?? .null)
    }
    func updatePanelPreference(_ panelID: String, command: PanelPreferenceCommand) throws -> PanelPreference {
        var preference = try fetchPanel(panelID).metadata.preference
        guard preference.preferenceVersion == command.expectedPreferenceVersion else { throw HibossAPIError.invalidResponse }
        preference.preferenceVersion += 1
        if let placement = command.placement { preference.placement = placement }
        if let seen = command.seenTerminalVersion { preference.seenTerminalVersion = seen }
        if let acknowledged = command.acknowledgedTerminalVersion { preference.acknowledgedTerminalVersion = acknowledged }
        documents[panelID]?["preference"] = try Self.value(preference)
        return preference
    }
    func end(_ id: String, state: String, dismissAt: Date? = nil) {
        guard case var .object(lifecycle) = documents[id]?["lifecycle"] else { return }
        lifecycle["taskState"] = .string(state)
        lifecycle["terminalAt"] = state == "paused" ? .null : .string(Date().ISO8601Format())
        lifecycle["dismissAt"] = dismissAt.map { .string($0.ISO8601Format()) } ?? .null
        lifecycle["result"] = state == "paused" ? .null : .object(["title": .string("\(id) \(state)")])
        documents[id]?["lifecycle"] = .object(lifecycle); documents[id]?["metadataVersion"] = .number(2)
        if state != "paused", let snapshot = try? fetchPanelState(id) {
            var task = snapshot.task
            if id == "download-progress", state == "completed", case var .object(values) = task {
                values["fraction"] = .number(1); values["downloadedGiB"] = .number(10)
                values["remainingGiB"] = .number(0); values["etaMinutes"] = .number(0)
                task = .object(values)
            }
            let final = PanelRelaySnapshot(panelID: id, definitionRevision: 1, epoch: nil, sequence: 0, task: task)
            documents[id]?["finalSnapshot"] = try? Self.value(final)
        }
    }
    private static func value<T: Encodable>(_ value: T) throws -> PanelValue { try JSONDecoder().decode(PanelValue.self, from: JSONEncoder().encode(value)) }
}
