// Native note composer with loading, item progress, confirmation and retry states.
// Exports BoxDropPopover, backed by a controller-owned drop store.
// Dependencies: SwiftUI, BoxDropStore and app localization.

import SwiftUI

struct BoxDropPopover: View {
    @ObservedObject var store: BoxDropStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Save to Box"), systemImage: "tray.and.arrow.down")
                .font(.headline)
            content
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(16)
        .frame(width: 320)
        .task(id: store.phase) {
            guard store.phase == .saved else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            close()
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView(L("Reading dropped items…"))
        case .rejected:
            EmptyView()
        case .saved:
            Label(L("Saved to Box"), systemImage: "checkmark.circle")
        default:
            ForEach(store.payloads.indices, id: \.self) { index in
                Text(verbatim: store.payloads[index].label)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TextField(L("Optional note"), text: $store.note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .disabled(store.noteLocked)
                .accessibilityIdentifier("box-drop-note")
            if store.phase == .uploading {
                ProgressView(value: Double(store.completed), total: Double(store.payloads.count))
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L("Uploading item \(store.completed + 1) of \(store.payloads.count)…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button(store.phase == .saved || store.phase == .rejected ? L("Done") : L("Cancel"), action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(store.phase == .uploading || store.phase == .loading)
            if store.phase == .ready || store.phase == .failed {
                Button(store.phase == .failed ? L("Retry") : L("Save")) {
                    Task { await store.save() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
