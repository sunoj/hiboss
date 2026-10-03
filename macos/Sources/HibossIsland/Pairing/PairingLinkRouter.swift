// Routes a clicked hiboss://pair link, or the Pair with Code button, to the redeem sheet.
// Exports: PairingLinkRouter, PairingSheetRequest, and the pure PairWithCodeForm state.
// Dependencies: AppKit activation, Foundation, and HibossKit's PairingPayload parser.

import AppKit
import Foundation
import HibossKit

struct PairingSheetRequest: Identifiable, Equatable {
    let id = UUID()
    /// The raw link to pre-fill; empty when the boss opened the sheet by hand.
    let link: String
}

/// Holds the pending redeem request and opens Settings by scene id. It never redeems:
/// the sheet does that only after the boss clicks a confirm button naming the server host.
@MainActor
final class PairingLinkRouter: ObservableObject {
    @Published var request: PairingSheetRequest?
    private var openSettings: (@MainActor () -> Void)?
    private var opensWhenInstalled = false
    private let activate: () -> Void

    init(activate: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.activate = activate
    }

    /// Installs the Settings opener; a link received before installation is replayed once.
    func install(_ opener: @escaping @MainActor () -> Void) {
        openSettings = opener
        guard opensWhenInstalled else { return }
        opensWhenInstalled = false
        Task { opener() }
    }

    /// Accepts only `hiboss://pair…`; any other URL is left for someone else.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "hiboss", url.host()?.lowercased() == "pair" else { return false }
        present(link: url.absoluteString)
        return true
    }

    func present(link: String = "") {
        request = PairingSheetRequest(link: link)
        activate()
        guard let openSettings else {
            opensWhenInstalled = true
            return
        }
        openSettings()
    }
}

/// The sheet's fields: a pasted link fills server + code; either source yields one payload.
struct PairWithCodeForm: Equatable {
    var link = ""
    var server = ""
    var code = ""
    private(set) var linkError: PairingPayloadError?

    init(link: String = "") {
        self.link = link
        applyLink()
    }

    mutating func applyLink() {
        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            linkError = nil
            return
        }
        switch PairingPayload.parse(link) {
        case let .success(payload):
            server = payload.serverURL.absoluteString
            code = payload.code
            linkError = nil
        case let .failure(error):
            linkError = error
        }
    }

    var validation: Result<PairingPayload, PairingPayloadError> {
        PairingPayload.make(server: server, code: code)
    }

    var payload: PairingPayload? { try? validation.get() }

    /// What to tell the boss; nothing while every field is still empty.
    var issue: PairingPayloadError? {
        if let linkError { return linkError }
        let untouched = server.trimmingCharacters(in: .whitespaces).isEmpty
            && code.trimmingCharacters(in: .whitespaces).isEmpty
        guard !untouched, case let .failure(error) = validation else { return nil }
        return error
    }
}
