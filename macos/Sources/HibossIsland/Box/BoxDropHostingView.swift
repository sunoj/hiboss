// Bridges native drag pasteboards into the Island's anchored note popover.
// Exports BoxDropHostingView while preserving the IslandView hosting root.
// Dependencies: AppKit, SwiftUI, AppSettings and the existing HibossAPI credential.

import AppKit
import Combine
import HibossKit
import SwiftUI

final class BoxDropHostingView: NSHostingView<IslandView>, NSPopoverDelegate {
    private let settings: AppSettings
    let popover = NSPopover()
    private(set) var dropStore: BoxDropStore?
    var activityDidChange: ((Bool, Bool) -> Void)?
    private var phaseObservation: AnyCancellable?

    init(rootView: IslandView, settings: AppSettings) {
        self.settings = settings
        super.init(rootView: rootView)
        registerForDraggedTypes(BoxDropInput.pasteboardTypes)
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @available(*, unavailable)
    required init(rootView: IslandView) { fatalError("Use init(rootView:settings:)") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropStore == nil && sender.draggingPasteboard.canReadItem(withDataConformingToTypes:
            BoxDropInput.pasteboardTypes.map(\.rawValue)) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard dropStore == nil else { return false }
        receive(sender.draggingPasteboard)
        return true
    }

    func receive(_ pasteboard: NSPasteboard) {
        guard dropStore == nil else { return }
        var api: HibossAPI?
        let store = BoxDropStore { [settings] upload, key in
            if api == nil {
                let config = try settings.activeClientConfig ?? settings.connectionConfig().get()
                api = HibossAPI(config: config)
            }
            _ = try await api?.createBoxItem(upload, idempotencyKey: key, progress: { _ in })
        }
        dropStore = store
        let hosting = NSHostingController(rootView: BoxDropPopover(store: store) { [weak self] in
            self?.popover.close()
        })
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        phaseObservation = store.$phase.sink { [weak self] phase in
            guard let self else { return }
            activityDidChange?(popover.isShown, phase == .uploading)
            if !popover.isShown && phase != .uploading { dropStore = nil }
        }
        hosting.view.window?.makeKey()
        do {
            let items = pasteboard.pasteboardItems ?? []
            guard (1...4).contains(items.count) else { throw BoxDropError.itemCount }
            let inputs = try items.map(BoxDropInput.read)
            Task { await store.prepare(inputs) }
        } catch {
            store.reject(error)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        let uploading = dropStore?.phase == .uploading
        if !uploading {
            dropStore = nil
            phaseObservation = nil
        }
        activityDidChange?(false, uploading)
    }
}
