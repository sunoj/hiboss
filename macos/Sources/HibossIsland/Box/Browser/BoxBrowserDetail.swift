// Persistent native detail pane for every Box kind, plus the note editing sheet.
// Exports: BoxBrowserDetail and BoxNoteEditor; actions share the row context menu contract.
// Dependencies: SwiftUI, HibossKit, authenticated media and BoxPaneActions.

import HibossKit
import SwiftUI

struct BoxBrowserDetail: View {
    let item: BoxItem?
    @ObservedObject var media: BoxBrowserMedia
    let busy: Bool
    let copied: Bool
    let perform: (BoxPaneAction) -> Void

    var body: some View {
        Group {
            if let item {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if item.kind == .text {
                                textContent(item)
                            } else {
                                preview(item)
                                Text(verbatim: item.displayTitle).font(.title2).textSelection(.enabled)
                            }
                            if let note = item.detailNote {
                                Text(verbatim: note).textSelection(.enabled)
                            }
                            GroupBox(L("Information")) {
                                information(item).padding(8).frame(maxWidth: .infinity)
                            }.frame(maxWidth: .infinity).layoutProbe("box.information")
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    actions(item).padding(12)
                }
                .id(item.id)
                .accessibilityIdentifier("box.detail.\(item.id)")
            } else {
                ContentUnavailableView(L("Select a Box item"), systemImage: "archivebox",
                    description: Text(L("Select an item to see its preview and information.")))
                    .accessibilityIdentifier("box.detail.empty")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func actions(_ item: BoxItem) -> some View {
        HStack(spacing: 8) {
            BoxPaneActions(item: item, busy: busy, perform: perform, actions: [.open, .copy])
            Menu(L("More")) {
                BoxPaneActions(item: item, busy: busy, perform: perform,
                    actions: [.quickLook, .share, .editNote])
                Divider()
                BoxPaneActions(item: item, busy: busy, perform: perform, actions: [.delete])
            }.layoutProbe("box.more")
            if busy { ProgressView().controlSize(.small) }
            if copied { Text(L("Copied")).font(.caption).foregroundStyle(.secondary) }
        }.buttonStyle(.bordered).controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
            .layoutProbe("box.actions")
    }

    private func information(_ item: BoxItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(L("Author"), value: item.authorTitle)
            if let project = item.project { LabeledContent(L("Project"), value: project) }
            if !item.tags.isEmpty { LabeledContent(L("Tags"), value: item.tags.joined(separator: ", ")) }
            if let format = item.detailFormat { LabeledContent(L("Format"), value: format) }
            LabeledContent(L("Added")) {
                TimelineView(.periodic(from: .now, by: 60)) { tick in
                    Text(verbatim: BoxTime.absolute(item.createdAt, now: tick.date))
                        .frame(width: 180, alignment: .trailing)
                }
            }
        }.font(.callout).textSelection(.enabled).frame(maxWidth: .infinity)
    }

    private func textContent(_ item: BoxItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: item.displayTitle).font(.title2).textSelection(.enabled)
            if let body = item.detailBody {
                Text(verbatim: body).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private func preview(_ item: BoxItem) -> some View {
        if item.hasImageMedia || item.kind == .video {
            VStack(spacing: 8) {
                if let image = media.thumbnails[item.id] {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 320)
                } else if let error = media.errors[item.id] {
                    Text(verbatim: error).foregroundStyle(.secondary)
                    Button(L("Retry")) { Task { _ = await media.load(item) } }
                } else if media.files[item.id] != nil {
                    Image(systemName: item.kindSymbol).font(.largeTitle)
                } else { ProgressView() }
                if item.kind == .video {
                    Label(item.durationTitle ?? L("Video"), systemImage: "play.circle")
                }
            }.frame(maxWidth: .infinity, minHeight: 140)
                .task(id: item.id) { _ = await media.load(item) }
        } else {
            GroupBox {
                VStack(spacing: 12) {
                    Image(systemName: item.kindSymbol).font(.largeTitle).foregroundStyle(.secondary)
                    Text(verbatim: item.kind == .link ? item.url ?? "" : item.fileExtension)
                        .foregroundStyle(item.kind == .link ? Color.accentColor : Color.secondary)
                        .textSelection(.enabled)
                }.padding(24).frame(maxWidth: .infinity)
            }
        }
    }
}

struct BoxNoteEditor: View {
    let item: BoxItem
    @ObservedObject var store: BoxBrowserStore
    @State private var note: String
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(item: BoxItem, store: BoxBrowserStore) {
        self.item = item
        self.store = store
        _note = State(initialValue: item.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Edit note…")).font(.headline)
            Text(verbatim: item.displayTitle).foregroundStyle(.secondary)
            TextEditor(text: $note).frame(minHeight: 120).border(Color(nsColor: .separatorColor))
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save")) {
                    saving = true
                    Task {
                        if await store.updateNote(note, for: item) { dismiss() }
                        saving = false
                    }
                }.keyboardShortcut(.defaultAction)
            }.disabled(saving)
        }.padding(20).frame(width: 420)
    }
}
