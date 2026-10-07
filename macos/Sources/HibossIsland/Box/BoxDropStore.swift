// Owns a drop draft, upload state and stable per-item retry identities.
// Exports BoxDropStore; successful items are skipped after a partial failure.
// Dependencies: Combine and the HibossKit Box create contract.

import Combine
import Foundation
import HibossKit

@MainActor
final class BoxDropStore: ObservableObject {
    enum Phase: Equatable { case loading, ready, uploading, failed, rejected, saved }
    typealias Sender = @MainActor (BoxCreate, BoxUpload?, String) async throws -> Void

    @Published private(set) var phase: Phase = .loading
    @Published var note = ""
    @Published private(set) var error: String?
    @Published private(set) var payloads: [BoxDropPayload] = []
    @Published private(set) var completed = 0
    private(set) var keys: [String] = []
    private var savedNote: String?
    private let send: Sender

    init(send: @escaping Sender) { self.send = send }

    func prepare(_ inputs: [BoxDropInput]) async {
        do {
            let payloads = try await Task.detached {
                try BoxDropPayload.load(inputs)
            }.value
            self.payloads = payloads
            keys = payloads.map { _ in UUID().uuidString }
            phase = .ready
        } catch {
            reject(error)
        }
    }

    func reject(_ error: Error) {
        self.error = (error as? BoxDropError)?.localizedDescription
            ?? BoxDropError.unreadable.localizedDescription
        phase = .rejected
    }

    var noteLocked: Bool { savedNote != nil || phase != .ready }

    func save() async {
        guard phase == .ready || phase == .failed else { return }
        guard note.utf8.count <= 16 * 1024 else {
            error = BoxDropError.noteLimit.localizedDescription
            return
        }
        if savedNote == nil { savedNote = note }
        error = nil
        phase = .uploading
        do {
            while completed < payloads.count {
                let payload = payloads[completed]
                try await send(BoxCreate(text: payload.text, url: payload.url,
                    note: savedNote?.isEmpty == false ? savedNote : nil, source: .macDrop),
                    payload.upload, keys[completed])
                completed += 1
            }
            phase = .saved
        } catch {
            self.error = L("Couldn't save to Box. Check your connection and retry.")
            phase = .failed
        }
    }
}
