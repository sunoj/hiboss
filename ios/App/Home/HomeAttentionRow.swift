// Actionable Home attention list with project, requester, wait, and choices.
// Exports: HomeAttentionSection and HomeAttentionRow.
// Dependencies: SwiftUI, HibossKit MessageID, AttentionItem, OptionButton, Theme.

import HibossKit
import SwiftUI

enum HomeAttentionAllClearStyle: Equatable {
    case compact
    case full
}

enum HomeAttentionLayout {
    static func allClearStyle(hasPanels: Bool) -> HomeAttentionAllClearStyle {
        hasPanels ? .compact : .full
    }
}

struct HomeAttentionSection: View {
    let snapshot: HomeAttentionSnapshot
    let hasPanels: Bool
    let status: String?
    let onChoose: (String, MessageID) -> Void
    let onOpen: (MessageID) -> Void
    let onOpenPanel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            if let status {
                Text(status).font(.hbCallout).foregroundStyle(Theme.ink2)
            }
            if snapshot.count == 0 && status == nil {
                allClear
            } else {
                ForEach(snapshot.groups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.group.title)
                            .font(.hbCaption.weight(.semibold))
                            .foregroundStyle(group.group == .blocked ? Theme.negative : Theme.ink2)
                            .textCase(.uppercase)
                        ForEach(group.items) { item in
                            HomeAttentionRow(
                                item: item,
                                onChoose: { onChoose($0, item.id) },
                                onOpen: { onOpen(item.id) }
                            )
                        }
                    }
                }
                ForEach(snapshot.questionnaires) { request in
                    questionnaireRow(request)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Needs you now")
                .font(.hbLargeTitle)
                .foregroundStyle(Theme.ink)
            if snapshot.count > 0 || status != nil || hasPanels {
                Text(verbatim: titleSubtitle)
                    .font(.hbCallout)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    private var titleSubtitle: String {
        let count = snapshot.count
        guard count > 0 else { return status == nil ? "Nothing is waiting on your call" : "Checking your attention queue" }
        return count == 1 ? "1 item waiting on your call" : String(count) + " items waiting on your call"
    }

    private func questionnaireRow(_ request: PendingQuestionnaire) -> some View {
        Button { onOpenPanel(request.panelId) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.title).font(.hbBodyStrong).foregroundStyle(Theme.ink)
                    Text(request.blocking ? "Questionnaire · Agent waiting" : "Questionnaire")
                        .font(.hbCaption).foregroundStyle(Theme.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.ink3)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-questionnaire-\(request.requestId)")
        .accessibilityHint("Opens the panel to answer this questionnaire")
    }

    private var allClear: some View {
        Group {
            switch HomeAttentionLayout.allClearStyle(hasPanels: hasPanels) {
            case .compact:
                // The section subtitle already says nothing is waiting; repeating it
                // here only pushes the panels the boss came to see further down.
                EmptyView()
            case .full:
                VStack(spacing: 14) {
                    AllClearIslandView()
                    Text("Nothing needs you")
                        .font(.hbH2)
                        .foregroundStyle(Theme.ink)
                    Text("Everything is settled. This is where an agent's next question will appear.")
                        .font(.hbCallout)
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct HomeAttentionRow: View {
    let item: AttentionItem
    let onChoose: (String) -> Void
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) { info }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-message-\(item.id.rawValue)")
            timing
            OptionMediaComparison(
                options: item.options,
                media: item.message.metadata?.optionMedia ?? []
            )
            choices
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18)
                .fill(tint)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(project) · \(item.message.displayName)")
                    .font(.hbCaption.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink4)
            }
            Text(item.message.body)
                .font(.hbBodyStrong)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let content = item.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty, content != item.message.body.trimmingCharacters(in: .whitespacesAndNewlines) {
                Text(content)
                    .font(.hbCaption)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var project: String {
        item.project ?? String(localized: "Unassigned session")
    }

    private var tint: Color {
        switch item.group {
        case .autoDecision: return Theme.warn
        case .blocked: return Theme.negative
        case .priority: return item.message.priorityValue == .critical ? Theme.negative : Theme.warn
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.group == .autoDecision, let deadline = item.expiresAt, let option = item.defaultOption {
                Text("Auto-selects “\(option)” when time runs out")
                Label { CountdownText(deadline: deadline, tint: tint) } icon: {
                    Image(systemName: "timer")
                }
            } else {
                Text(waitedText)
                if let deadline = item.expiresAt {
                    Text("Reply by \(deadline.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .font(.hbCaption)
        .foregroundStyle(Theme.ink2)
        .accessibilityElement(children: .combine)
    }

    private var waitedText: String {
        guard let date = item.message.createdDate else { return "Waiting" }
        return "Waiting \(RelativeTime.short(from: date))"
    }

    @ViewBuilder
    private var choices: some View {
        if item.options.isEmpty {
            OptionButton(title: "Reply…", controlSize: .regular, action: onOpen)
        } else if item.options.count == 2 && !dynamicTypeSize.isAccessibilitySize
                    && item.options.allSatisfy({ $0.count <= 28 && !$0.contains("\n") }) {
            HStack(spacing: 6) {
                choiceButton(item.options[0])
                choiceButton(item.options[1])
            }
        } else {
            VStack(spacing: 6) {
                ForEach(item.options, id: \.self) { option in
                    choiceButton(option, alignment: .leading)
                }
            }
        }
    }

    private func choiceButton(_ option: String, alignment: Alignment = .center) -> some View {
        OptionButton(
            title: option,
            style: .secondary,
            alignment: alignment,
            controlSize: .regular
        ) { onChoose(option) }
    }
}
