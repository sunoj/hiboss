// Observable states published by OptionFlowStore: connection, presentation, history, reply feedback.
// Exports: ConnectionState, PresentationState, HistoryState, ReplyFeedback.
// Dependencies: kitL localization.

import Foundation

public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    public var label: String {
        switch self {
        case .disconnected: kitL("Disconnected")
        case .connecting: kitL("Connecting")
        case .connected: kitL("Listening")
        case .failed: kitL("Connection failed")
        }
    }

    /// The failure reason for `.failed`, if any — surfaced where space allows.
    public var detail: String? {
        if case let .failed(message) = self, !message.isEmpty { return message }
        return nil
    }
}

public enum PresentationState: Equatable {
    case idle
    case ready
    case submitting(String)
    /// The decision was answered elsewhere; briefly show the choice + source.
    case resolved(answer: String?, source: String?)
}

public enum HistoryState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Why a reply to one message did not land as the boss's answer, keyed by that message's id.
public enum ReplyFeedback: Equatable, Sendable {
    /// The server refused it (409): another client already answered. The local choice did not win.
    case alreadyAnswered
    /// The request failed and can be retried.
    case failed(String)
}
