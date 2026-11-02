// In-memory notes for session demos, including unread and read receipts.
// Exports DemoBossAPI SessionNotesServing conformance; never contacts a server.
// Dependencies: HibossKit and Foundation.

import Foundation
import HibossKit

extension DemoBossAPI: SessionNotesServing {
    func canCreateSessionNotes() async throws -> Bool {
        ProcessInfo.processInfo.environment["HIBOSS_DEMO_NOTE_VIEWER"] != "1"
    }

    func listSessionNotes(sessionID: String) async throws -> [SessionNote] {
        if let notes = sessionNotes[sessionID] { return notes }
        let notes = [
            SessionNote(id: "note-pending", sessionID: sessionID, agentID: "worker-deploy",
                        bossName: "Alex", body: "Please check the release summary before continuing.",
                        status: .pending, createdAt: "2026-11-02 10:00:00"),
            SessionNote(id: "note-read", sessionID: sessionID, agentID: "worker-deploy",
                        bossName: "Alex", body: "Keep the rollout small for the first hour.", status: .read,
                        createdAt: "2026-11-02 09:00:00", readAt: "2026-11-02 09:05:00")
        ]
        sessionNotes[sessionID] = notes
        return notes
    }

    func createSessionNote(sessionID: String, body: String, idempotencyKey: String) async throws -> SessionNote {
        try await DemoDelay.wait("NOTE")
        if ProcessInfo.processInfo.environment["HIBOSS_DEMO_NOTE_FAILS"] == "1" {
            throw HibossAPIError.requestFailed(status: 503, message: "Unable to send note")
        }
        var notes = try await listSessionNotes(sessionID: sessionID)
        if let existing = notes.first(where: { $0.id == idempotencyKey }) { return existing }
        let note = SessionNote(id: idempotencyKey, sessionID: sessionID, agentID: "worker-deploy",
                               bossName: "Alex", body: body, status: .pending,
                               createdAt: Date().ISO8601Format())
        notes.insert(note, at: 0)
        sessionNotes[sessionID] = notes
        return note
    }
}
