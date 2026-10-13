// Connects workspace navigation, message snapshots, and the hosting window to local reads.
// Exports: SessionReadTracking; visible reads use a real window or an injected key-state binding.
// Dependencies: SwiftUI, OverviewStore, SessionReadStore, and SessionWindowKeyReader.

import SwiftUI

struct SessionReadTracking: ViewModifier {
    @ObservedObject var reads: SessionReadStore
    let account: SessionReadAccount?
    let destination: OverviewDestination
    @ObservedObject var overview: OverviewStore
    var windowIsKey: Binding<Bool>? = nil
    @State private var isKey = false

    private var canMarkVisibleRead: Bool { windowIsKey?.wrappedValue ?? isKey }

    func body(content: Content) -> some View {
        content
            .background {
                if windowIsKey == nil {
                    SessionWindowKeyReader(isKey: $isKey).frame(width: 0, height: 0)
                }
            }
            .onAppear {
                reads.activate(account)
                openedSession()
            }
            .onChange(of: account) {
                reads.activate(account)
            }
            .onChange(of: destination) { openedSession() }
            .onChange(of: canMarkVisibleRead) { updateVisibleSession() }
            .onReceive(overview.$snapshot) { snapshot in
                guard canMarkVisibleRead, case let .session(id) = destination,
                      !snapshot.messages(for: .session(id)).isEmpty else { return }
                reads.markRead(id, messages: snapshot.history)
            }
    }

    private func openedSession() {
        guard case let .session(id) = destination else { return }
        reads.markRead(id, messages: overview.snapshot.history)
    }

    private func updateVisibleSession() {
        if canMarkVisibleRead, case let .session(id) = destination {
            reads.markRead(id, messages: overview.snapshot.history)
        }
    }
}
