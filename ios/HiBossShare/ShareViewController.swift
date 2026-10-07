// Hosts the native share sheet and finishes or cancels the extension request.
// Exports ShareViewController, the HiBossShare principal class.
// Dependencies: UIKit, SwiftUI, HibossKit and the read-only share connection.

import HibossKit
import SwiftUI
import UIKit

@MainActor
final class ShareViewController: UIViewController {
    private var loadTask: Task<Void, Never>?
    private var model: ShareViewModel?
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func viewDidLoad() {
        super.viewDidLoad()
        let api = ShareConnection.read().map { HibossAPI(config: $0) }
        let model = ShareViewModel(api: api)
        self.model = model
        let sheet = ShareSheet(model: model,
            cancel: { [weak self] in self?.finish(cancelled: true) },
            complete: { [weak self] in self?.finish(cancelled: false) },
            reload: { [weak self] in self?.load(api: api) })
        let host = UIHostingController(rootView: sheet)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        load(api: api)
    }

    private func load(api: HibossAPI?) {
        loadTask?.cancel()
        guard let model, let api else { return }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        loadTask = Task {
            await model.load(providers, directory: directory)
            await model.loadProjects(using: api)
        }
    }

    private func finish(cancelled: Bool) {
        loadTask?.cancel()
        try? FileManager.default.removeItem(at: directory)
        if cancelled { extensionContext?.cancelRequest(withError: CancellationError()) }
        else { extensionContext?.completeRequest(returningItems: nil) }
    }
}
