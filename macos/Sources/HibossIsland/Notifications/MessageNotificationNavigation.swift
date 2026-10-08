// Opens the main window by scene id and routes notification clicks into History.
// Exports: MessageNotificationNavigation and NotificationMessageDetail.
// Dependencies: SwiftUI, AppKit, HibossAPI targeted message lookup, and HistoryMessageDetail.

import AppKit
import HibossKit
import SwiftUI

struct NotificationMessageTarget: Identifiable {
    let id: MessageID
}

/// A request to show Device Requests, optionally with one request's approval sheet open.
struct DeviceRequestsFocus: Identifiable, Equatable {
    let id = UUID()
    let requestID: String?
}

/// Opens the main window by scene id. `title` is the current destination, so a window
/// lookup by title fails; the SwiftUI opener reopens a closed window, also without a Dock icon.
@MainActor
final class MessageNotificationNavigation: ObservableObject {
    @Published var target: NotificationMessageTarget?
    @Published var deviceRequestsFocus: DeviceRequestsFocus?
    private var openWindow: (@MainActor () -> Void)?
    private var opensWhenInstalled = false
    private let activate: () -> Void

    init(activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.activate = activate
    }

    /// Installs the scene-id opener. A request made before installation is replayed once,
    /// asynchronously, because installation happens while SwiftUI evaluates the app's commands.
    func install(_ opener: @escaping @MainActor () -> Void) {
        openWindow = opener
        guard opensWhenInstalled else { return }
        opensWhenInstalled = false
        Task { opener() }
    }

    func openMainWindow() {
        activate()
        guard let openWindow else {
            opensWhenInstalled = true
            return
        }
        openWindow()
    }

    func open(_ id: MessageID) {
        target = NotificationMessageTarget(id: id)
        openMainWindow()
    }

    func openDeviceRequests(requestID: String? = nil) {
        deviceRequestsFocus = DeviceRequestsFocus(requestID: requestID)
        openMainWindow()
    }
}

struct NotificationMessageDetail: View {
    let messageID: MessageID
    let settings: AppSettings
    @ObservedObject var reply: AttentionReplyState
    /// Sends a reply for a message id; nil means accepted, as in `OptionFlowStore.answer`.
    let onReply: (String, MessageID) async -> ReplyFeedback?
    @State private var message: HistoryMessage?
    @State private var replies: [HistoryMessage] = []
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let message {
                loadedDetail(message, replies: replies)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(L("History Unavailable"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button(L("Retry")) { Task { await load() } }
                    Button(L("Close")) { dismiss() }
                }
            } else {
                ProgressView(L("Loading messages…"))
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .task(id: messageID) { await load() }
    }

    /// Replies go to the loaded message's own id, never the notification's requested id.
    func loadedDetail(_ message: HistoryMessage, replies: [HistoryMessage] = []) -> HistoryMessageDetail {
        HistoryMessageDetail(message: message, reply: reply,
            onChoose: { await onReply($0, message.id) }, replies: replies)
    }

    private func load() async {
        message = nil
        replies = []
        errorMessage = nil
        await settings.loadToken()
        do {
            let config = try settings.connectionConfig().get()
            let detail = try await HibossAPI(config: config).fetchMessage(messageID)
            try Task.checkCancellation()
            message = detail.message
            replies = detail.replies
        } catch where Task.isCancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
