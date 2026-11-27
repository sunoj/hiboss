// Current activity for the open session, on the same ground as its messages.
// Exports: SessionHeader; the toolbar names the session and carries the connection chip.
// Dependencies: SwiftUI, HibossKit, SessionContext, and design-v4 colours.

import HibossKit
import SwiftUI

struct SessionHeader: View {
    let context: SessionContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(TodayStyle.ink)
                .lineLimit(2)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
                .layoutProbe("session.title")
            if let meta = metaLine {
                Text(verbatim: meta)
                    .font(.caption).foregroundStyle(TodayStyle.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            if let step = currentStep {
                Text(L("Current step: \(step)"))
                    .font(.callout).foregroundStyle(TodayStyle.secondary)
                    .lineLimit(2).textSelection(.enabled)
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

    /// The question waiting on the boss leads; otherwise what the agent is doing.
    private var headline: String {
        if let open = context.decisions.first {
            return L("Waiting on you: \(open.message.messageText.title)")
        }
        if !activityText.isEmpty { return activityText }
        let branch = trimmed(context.branch)
        return branch.isEmpty ? L("Session activity") : branch
    }

    /// The agent's own activity, shown under a waiting question so it is not lost.
    private var currentStep: String? {
        context.decisions.isEmpty || activityText.isEmpty ? nil : activityText
    }

    /// Who, where and since when: agent · machine · branch · started <time>.
    private var metaLine: String? {
        let facts = context.facts
        let started = facts?.startedAt.flatMap(ISODate.parse)
            .map { L("Started") + " " + SharedTimestamp.string($0, now: context.snapshot.now) }
        let parts = [facts?.agentName, facts?.host, context.branch, started]
            .map { trimmed($0) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
