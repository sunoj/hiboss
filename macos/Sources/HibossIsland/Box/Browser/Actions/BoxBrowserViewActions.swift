// Box browser action dispatch and authenticated media opening.
// Extends BoxBrowserView using its existing selection and presentation state.

import AppKit
import HibossKit
import SwiftUI

extension BoxBrowserView {
    func open(_ item: BoxItem) async {
        if item.hasImageMedia {
            store.selection = item.id
            previewImage = item
            return
        }
        guard !opening.contains(item.id) else { return }
        opening.insert(item.id)
        defer { opening.remove(item.id) }
        do {
            if let text = try await BoxBrowserActions.open(item, media: media) { copy(text, id: item.id) }
        } catch { store.actionError = error.localizedDescription }
    }

    func perform(_ action: BoxPaneAction, item: BoxItem) {
        if action == .delete {
            store.requestDelete(item)
            return
        }
        if action == .editNote {
            editingNote = item
            return
        }
        if action == .open {
            Task { await open(item) }
            return
        }
        Task {
            guard !opening.contains(item.id) else { return }
            opening.insert(item.id)
            defer { opening.remove(item.id) }
            do {
                switch action {
                case .quickLook: quickLookURL = try await BoxBrowserActions.previewURL(item, media: media)
                case .copy:
                    try await BoxBrowserActions.copy(item, media: media)
                    copied = item.id
                case .share: try await BoxBrowserActions.share(item, media: media)
                default: break
                }
            } catch { store.actionError = error.localizedDescription }
        }
    }

    func copy(_ text: String, id: String) {
        if BoxBrowserActions.copy(text) { copied = id }
        else { store.actionError = BoxBrowserError.cannotOpen.localizedDescription }
    }
}
