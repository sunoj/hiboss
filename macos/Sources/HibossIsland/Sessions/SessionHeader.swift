// Current activity for the open session, on the same ground as its messages.
// Exports: SessionHeader; the toolbar already names the session.
// Dependencies: SwiftUI, HibossKit, SessionContext, and design-v4 colours.

import HibossKit
import SwiftUI

struct SessionHeader: View {
    let context: SessionContext
    let connection: ConnectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 12) {
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TodayStyle.ink)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
                    .layoutProbe("session.title")
                    .layoutPriority(-1)
                connectionMark
            }
            if let meta = metaLine {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(TodayStyle.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("session.header")
    }

    private var activityText: String {
        trimmed(context.facts?.statusText)
    }

    private var headline: String {
        if !activityText.isEmpty { return activityText }
        let branch = trimmed(context.branch)
        return branch.isEmpty ? L("Session activity") : branch
    }

    /// The inspector already lists agent, machine, and branch. This line is only the activity state.
    private var metaLine: String? {
        let status = trimmed(context.facts?.status)
        return status.isEmpty ? nil : L("Status") + ": " + status
    }

    private var connectionMark: some View {
        HStack(spacing: 6) {
            Circle().fill(connectionColor).frame(width: 7, height: 7)
            Text(connection.label)
                .font(.caption)
                .foregroundStyle(TodayStyle.secondary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var connectionColor: Color {
        switch connection {
        case .connected: TodayStyle.live
        case .failed: TodayStyle.signal
        case .disconnected, .connecting: TodayStyle.tertiary
        }
    }

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
