// Application shell for interactive fixture browsing and --measure mode.
// Exports: PanelSwiftUISpikeApp and AppDelegate.
// Dependencies: SwiftUI, AppKit, FixtureLoader, PanelStore, PanelRootView, and MeasurementRunner.

import AppKit
import Darwin
import SwiftUI

struct PanelSwiftUISpikeApp: App {
    var body: some Scene {
        WindowGroup("Panel SwiftUI Spike") {
            FixtureBrowser()
        }
        .defaultSize(width: 760, height: 520)
    }
}

@MainActor
final class MeasurementAppDelegate: NSObject, NSApplicationDelegate {
    private let runner = MeasurementRunner()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        runner.run()
    }
}

@main
struct PanelSwiftUISpikeLauncher {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--measure") {
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                MeasurementRunner.printNotMeasured(reason: "AppKit window did not become interactive within 5 seconds")
                fflush(stdout)
                exit(EXIT_SUCCESS)
            }
            let app = NSApplication.shared
            let delegate = MeasurementAppDelegate()
            app.delegate = delegate
            app.run()
        } else {
            PanelSwiftUISpikeApp.main()
        }
    }
}

struct FixtureBrowser: View {
    @State private var selected = FixtureLoader.names.first ?? ""

    var body: some View {
        Group {
            if let fixture = try? FixtureLoader.load(name: selected), let spec = fixture.activeSpec {
                FixtureView(fixture: fixture, spec: spec)
            } else {
                ContentUnavailableView("Fixture unavailable", systemImage: "exclamationmark.triangle")
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Fixture", selection: $selected) {
                    ForEach(FixtureLoader.names, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }
}

struct FixtureView: View {
    let fixture: PanelFixture
    let spec: PanelSpec
    @StateObject private var store: PanelStore

    init(fixture: PanelFixture, spec: PanelSpec) {
        self.fixture = fixture
        self.spec = spec
        _store = StateObject(wrappedValue: PanelStore(fixture: fixture))
    }

    var body: some View {
        PanelRootView(spec: spec, store: store)
            .navigationTitle(fixture.title ?? "Fixture")
    }
}
