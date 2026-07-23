// Push-tiering editor for per-priority delivery, sound, and interruption level.
// Exports: PushTieringSection bound to PreferencesStore push helpers.
// Dependencies: SwiftUI, HibossKit PushRule/PushLevel, theme and priority tokens.

import HibossKit
import SwiftUI

struct PushTieringSection: View {
    @ObservedObject var store: PreferencesStore

    private let priorities: [HibossKit.MessagePriority] = [.critical, .high, .normal, .low]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsSection(title: "PUSH TIERING") {
                ForEach(Array(priorities.enumerated()), id: \.element) { index, priority in
                    if index > 0 { SettingsDivider() }
                    PushTieringRow(
                        priority: priority,
                        rule: store.pushRule(for: priority),
                        setRule: { store.setPushRule($0, for: priority) }
                    )
                }
            }
            Text("Decision requests always alert, regardless of these push tiering rules.")
                .font(.hbFootnote).foregroundStyle(Theme.ink4).padding(.leading, 6)
        }
    }
}

private struct PushTieringRow: View {
    let priority: HibossKit.MessagePriority
    let rule: PushRule
    let setRule: (PushRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                priorityLabel
                Spacer(minLength: 8)
                Toggle("Push", isOn: deliverBinding)
                    .tint(Theme.positive)
                Toggle("Sound", isOn: soundBinding)
                    .tint(Theme.positive)
                    .disabled(!rule.deliver)
            }
            Picker("Level", selection: levelBinding) {
                ForEach(PushLevel.allCases, id: \.rawValue) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .disabled(!rule.deliver)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var priorityLabel: some View {
        HStack(spacing: 7) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(priority.rawValue.capitalized).font(.hbBody).foregroundStyle(Theme.ink)
        }
    }

    private var deliverBinding: Binding<Bool> {
        Binding(
            get: { rule.deliver },
            set: { setRule(rule.with(deliver: $0)) }
        )
    }

    private var soundBinding: Binding<Bool> {
        Binding(
            get: { rule.sound },
            set: { setRule(rule.with(sound: $0)) }
        )
    }

    private var levelBinding: Binding<PushLevel> {
        Binding(
            get: { rule.level },
            set: { setRule(rule.with(level: $0)) }
        )
    }

    private var dotColor: Color {
        switch priority {
        case .critical: PriorityColor.critical
        case .high: PriorityColor.high
        case .normal: PriorityColor.normal
        case .low: PriorityColor.low
        }
    }
}

private extension PushRule {
    func with(deliver: Bool? = nil, sound: Bool? = nil, level: PushLevel? = nil) -> PushRule {
        PushRule(
            deliver: deliver ?? self.deliver,
            sound: sound ?? self.sound,
            level: level ?? self.level
        )
    }
}

private extension PushLevel {
    var title: String {
        switch self {
        case .passive: "Passive"
        case .active: "Active"
        case .timeSensitive: "Time-sensitive"
        }
    }
}
