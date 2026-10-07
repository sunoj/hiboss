// Native share form with retained previews, optional metadata and upload states.
// Exports ShareSheet, used by the extension and the debug-only host.
// Dependencies: SwiftUI, ShareViewModel and SharePreviewRow.

import SwiftUI

struct ShareSheet: View {
    @ObservedObject var model: ShareViewModel
    let cancel: () -> Void
    let complete: () -> Void
    let reload: () -> Void
    @State private var showsProgress = false
    @State private var slow = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                if model.state == .disconnected {
                    Section { Text("Open HiBoss to connect") }
                } else {
                    Section("Preview") {
                        ForEach(model.attachments) { SharePreviewRow(item: $0) }
                    }
                    Section("Note") {
                        TextField("Optional note", text: $model.note, axis: .vertical)
                            .lineLimit(3...6).accessibilityIdentifier("share-note")
                    }
                    Section("Project") {
                        Picker("Project", selection: $model.project) {
                            Text("No project").tag("")
                            ForEach(model.projects) { project in
                                Text(verbatim: project.projectIdentity.displayName).tag(project.slug)
                            }
                        }
                        if model.projectFailure {
                            Text("Projects unavailable. You can save without a project.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    status
                }
            }
            .navigationTitle("Save to Box")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        saveTask?.cancel()
                        cancel()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { action }
        }
        .task(id: model.state) { await trackState() }
        .onDisappear { saveTask?.cancel() }
        .alert("Open HiBoss to connect", isPresented: disconnected) {
            Button("OK") { cancel() }
        }
    }

    @ViewBuilder private var status: some View {
        if model.state == .done {
            Section { Label("Saved to Box", systemImage: "checkmark.circle") }
        } else if model.state == .failure {
            Section {
                Text(verbatim: model.failure).accessibilityIdentifier("share-error")
                Text("Retry keeps the original note and project for items already submitted.")
                    .foregroundStyle(.secondary)
            }
        } else if showsProgress {
            Section {
                switch model.state {
                case .compressing: ProgressView("Compressing attachments…")
                case .uploading: ProgressView("Uploading to Box…", value: model.progress)
                default: ProgressView("Loading attachments…")
                }
                if slow {
                    Text("This is taking longer than usual. You can retry or cancel.")
                    Button("Retry") {
                        let previous = saveTask
                        previous?.cancel()
                        saveTask = Task {
                            await previous?.value
                            startSave()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var action: some View {
        if model.state != .disconnected && model.state != .done {
            Button(action: startSave) {
                if model.state == .failure { Text("Retry") }
                else { Text("Save") }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .frame(maxWidth: .infinity).padding()
            .disabled(model.isBusy || model.attachments.isEmpty && model.state != .failure)
            .accessibilityIdentifier("share-save")
        }
    }

    private var disconnected: Binding<Bool> {
        Binding(get: { model.state == .disconnected }, set: { _ in })
    }

    private func startSave() {
        if model.attachments.isEmpty { reload() }
        else { saveTask = Task { await model.save() } }
    }

    private func trackState() async {
        showsProgress = false
        slow = false
        do {
            if model.state == .done {
                try await Task.sleep(for: .milliseconds(900))
                complete()
            } else if model.isBusy {
                try await Task.sleep(for: .milliseconds(300))
                showsProgress = true
                try await Task.sleep(for: .milliseconds(7700))
                slow = true
            }
        } catch {}
    }
}
