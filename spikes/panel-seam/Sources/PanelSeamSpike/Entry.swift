// Application shell for the interactive mixed panel and automated seam probe.
// Exports: PanelSeamSpikeApp and SeamSession.
// Dependencies: SwiftUI, AppKit, PanelStore, PanelRootView, WebLeafModel, and Probe.

import AppKit
import SwiftUI

@main
struct PanelSeamSpikeApp: App {
    @StateObject private var session = SeamSession()

    var body: some Scene {
        WindowGroup("Panel Seam Spike") {
            SeamWindow(session: session)
        }
        .defaultSize(width: 560, height: 440)
    }
}

struct SeamWindow: View {
    @ObservedObject var session: SeamSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.fixture.title).font(.headline)
                Spacer()
                Button("Run seam probe") { session.runProbe() }
            }
            Text("Native: Select, NumberInput, Button · Web: LineChart display leaf")
                .font(.caption).foregroundStyle(.secondary)
            PanelRootView(spec: session.fixture.formSpec, store: session.store, webModel: session.webModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(session.logLines.suffix(5).joined(separator: "\n"))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(minWidth: 520, idealWidth: 560, minHeight: 400, idealHeight: 440)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            session.attachWindow(NSApp.keyWindow)
        }
    }
}

@MainActor
final class SeamSession: ObservableObject {
    let fixture: PanelFixture
    let store: PanelStore
    let webModel = WebLeafModel()
    @Published private(set) var logLines: [String] = []
    private weak var window: NSWindow?
    private var probeStarted = false

    init() {
        do {
            fixture = try FixtureLoader.load()
        } catch {
            fatalError("Unable to load mixed-panel fixture: \(error.localizedDescription)")
        }
        store = PanelStore(fixture: fixture)
        webModel.onFailure = { [weak self] message in self?.rendererDied(message) }
        if ProcessInfo.processInfo.environment["HIBOSS_SEAM_AUTO"] == "1" || UserDefaults.standard.bool(forKey: "HIBOSS_SEAM_AUTO") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.runProbe() }
        }
    }

    func attachWindow(_ window: NSWindow?) { self.window = window ?? NSApp.keyWindow }

    func runProbe() {
        guard !probeStarted else { return }
        probeStarted = true
        attachWindow(NSApp.keyWindow)
        runSeamProbe(session: self)
    }

    func append(_ line: String) {
        logLines = Array((logLines + [line]).suffix(12))
        print(line)
        fflush(stdout)
    }

    func rendererDied(_ message: String) {
        append("renderer_failure=\(message)")
        append("native_draft_after_kill=\(store.draftDescription())")
        append("window_visible_after_renderer_death=\(window?.isVisible == true)")
        append("leaf_slot=\(webModel.failureMessage ?? "none")")
    }

    var targetWindow: NSWindow? { window ?? NSApp.keyWindow }
}
