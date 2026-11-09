// Decision card header: project avatar, project · branch · agent meta line, deadline, question.
// Exports: DecisionCardInfo and DecisionMetaLine, which drops the branch before the agent.
// Dependencies: SwiftUI, HibossKit HistoryMessage, project inventory environment, Theme.

import HibossKit
import SwiftUI

struct DecisionCardInfo: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.projectSessions) private var inventory
    let message: HistoryMessage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .center, spacing: Space.xs) {
                ProjectAvatarView(project: inventory.first { $0.id == message.sessionId }?.avatarProject
                                  ?? inventory.project(slug: message.project ?? project),
                                  size: AvatarSize.compact)
                metadata
                    .font(.hbCaption.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: Space.xs)
                if !textSize.isAccessibilitySize { deadline }
            }
            if textSize.isAccessibilitySize { deadline }
            // The question is the reason the card exists: it wraps fully at every text size.
            Text(verbatim: message.messageText.title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: ControlMetric.minTap, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var deadline: some View {
        if let deadline = message.expirationDate {
            CountdownText(deadline: deadline, tint: Theme.warn).font(.footnote)
                .lineLimit(1).fixedSize()
        } else {
            Text("No deadline").font(.footnote).foregroundStyle(Theme.ink3)
                .lineLimit(1).fixedSize()
        }
    }

    /// The project is its own text and never truncates; the tail drops the branch before the agent,
    /// then project and tail stack.
    @ViewBuilder private var metadata: some View {
        let line = DecisionMetaLine(
            project: inventory.first { $0.id == message.sessionId }?.namedLabel ?? project,
            branch: message.sessionBranch, agent: message.displayName)
        if textSize.isAccessibilitySize {
            stacked(line)
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(line.tails.isEmpty ? [""] : line.tails, id: \.self) { tail in
                    HStack(spacing: Space.xxs) {
                        Text(verbatim: line.project).fixedSize()
                        if !tail.isEmpty {
                            Text(verbatim: "· " + tail).lineLimit(1)
                                .accessibilityLabel(Text(verbatim: "· " + (line.tails.first ?? tail)))
                        }
                    }
                }
                stacked(line)
            }
        }
    }

    private func stacked(_ line: DecisionMetaLine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: line.project).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                ForEach(line.tails, id: \.self) {
                    Text(verbatim: $0).lineLimit(1).accessibilityLabel(Text(verbatim: line.tails.first ?? $0))
                }
                if let agent = line.tails.last {
                    Text(verbatim: agent).fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(verbatim: line.tails.first ?? agent))
                }
            }
        }
    }

    private var project: String {
        [message.sessionLabel, message.sessionBranch].compactMap { value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return value
        }.first ?? String(localized: "Unassigned session")
    }
}

/// The meta line's candidates, most complete first. The branch is dropped before the agent,
/// and a branch that already names the project is not repeated.
struct DecisionMetaLine: Equatable {
    let project: String
    /// What follows the project: "branch · agent", then the agent alone.
    let tails: [String]

    init(project: String, branch: String?, agent: String?) {
        self.project = project
        let branch = Self.clean(branch).flatMap { $0 == project ? nil : $0 }
        let agent = Self.clean(agent)
        switch (branch, agent) {
        case let (branch?, agent?): tails = ["\(branch) · \(agent)", agent]
        case let (branch?, nil): tails = [branch]
        case let (nil, agent?): tails = [agent]
        case (nil, nil): tails = []
        }
    }

    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
