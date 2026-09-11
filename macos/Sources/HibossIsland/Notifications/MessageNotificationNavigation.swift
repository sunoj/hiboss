// Routes notification clicks into the main History surface, including older messages.
// Exports: MessageNotificationNavigation and NotificationMessageDetail.
// Dependencies: SwiftUI, AppKit, HibossAPI targeted message lookup, and HistoryMessageDetail.

import AppKit
import HibossKit
import SwiftUI

struct NotificationMessageTarget: Identifiable {
    let id: MessageID
}

@MainActor
final class MessageNotificationNavigation: ObservableObject {
    @Published var target: NotificationMessageTarget?
    var openWindow: (() -> Void)? {
        didSet { if target != nil { openWindow?() } }
    }

    func open(_ id: MessageID) {
        target = NotificationMessageTarget(id: id)
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct NotificationMessageDetail: View {
    let messageID: MessageID
    let settings: AppSettings
    @ObservedObject var reply: AttentionReplyState
    @State private var message: HistoryMessage?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let message {
                HistoryMessageDetail(message: message, reply: reply) { _ in false }
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

    private func load() async {
        message = nil
        errorMessage = nil
        await settings.loadToken()
        do {
            let config = try settings.connectionConfig().get()
            let detail = try await HibossAPI(config: config).fetchMessage(messageID)
            try Task.checkCancellation()
            message = detail.message
        } catch where Task.isCancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
