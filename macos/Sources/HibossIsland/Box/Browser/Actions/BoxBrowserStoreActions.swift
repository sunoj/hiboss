// Selection movement and note editing actions for the paged Box browser.
// Extends BoxBrowserStore using HibossKit and connection-scoped responses.

import HibossKit

extension BoxBrowserStore {
    func moveSelection(by offset: Int) {
        let rows = visibleItems
        guard !rows.isEmpty else {
            selection = nil
            return
        }
        let index = rows.firstIndex { $0.id == selection }
        let next = index.map { min(max($0 + offset, 0), rows.count - 1) }
            ?? (offset > 0 ? 0 : rows.count - 1)
        selection = rows[next].id
    }

    func requestDelete(_ item: BoxItem) { pendingDelete = item }

    func confirmDelete(_ item: BoxItem) async -> BoxItem? {
        pendingDelete = nil
        return await delete(item) ? item : nil
    }

    func updateNote(_ note: String, for item: BoxItem) async -> Bool {
        let current = connectionGeneration
        do {
            guard let api = apiProvider() else { throw BoxBrowserError.notConfigured }
            let updated = try await api.patchBoxItem(id: item.id, patch: BoxPatch(note: .value(note)))
            guard current == connectionGeneration,
                  let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
            items[index] = updated
            return true
        } catch {
            if current == connectionGeneration { actionError = error.localizedDescription }
            return false
        }
    }
}
