// Application shell for interactive fixture browsing and --measure mode.
// Exports: PanelSwiftUISpikeApp and the @main launcher.
// Dependencies: SwiftUI, AppKit, FixtureLoader, PanelStore, PanelRootView, MeasurementRunner.

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
    static var retained: MeasurementAppDelegate?
    let runner = MeasurementRunner()

    func applicationDidFinishLaunching(_ notification: Notification) {
        runner.run()
    }
}

@main
struct PanelSwiftUISpikeLauncher {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--measure") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = MeasurementAppDelegate()
            MeasurementAppDelegate.retained = delegate
            app.delegate = delegate
            // Fallback if didFinishLaunching is skipped in this process environment.
            DispatchQueue.main.async {
                if !delegate.runner.hasStarted { delegate.runner.run() }
            }
            // Overall watchdog: only fires if the harness never finished printing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                guard !delegate.runner.hasFinished else { return }
                MeasurementRunner.printNotMeasured(reason: "measurement harness did not finish within 60 seconds")
                fflush(stdout)
                exit(EXIT_SUCCESS)
            }
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
