// Delays refresh status without changing cached content or failure health.
// Exports RefreshStatus for workspace and Today labels.
// Dependencies: Combine observation and Swift task cancellation.

import Combine
import Foundation

@MainActor
final class RefreshStatus: ObservableObject {
    @Published private(set) var showsUpdating = false

    func update(isRefreshing: Bool) async {
        showsUpdating = false
        guard isRefreshing else { return }
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard !Task.isCancelled else { return }
        showsUpdating = true
    }
}
