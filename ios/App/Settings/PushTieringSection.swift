// Push-tiering editor: per-priority delivery, sound, and interruption level.
// Exports: PushTieringSection as a native Form section bound to PreferencesStore.
// Dependencies: SwiftUI, HibossKit PushRule/PushLevel, priority tokens.

import HibossKit
import SwiftUI

struct PushTieringSection: View {
    @ObservedObject var store: PreferencesStore

    private let priorities: [HibossKit.MessagePriority] = [.critical, .high, .normal, .low]

    var body: some View {
        Section {
            ForEach(priorities, id: \.self) { priority in
                PushTieringRow(
                    priority: priority,
                    rule: store.pushRule(for: priority),
                    setRule: { store.setPushRule($0, for: priority) }
                )
            }
        } header: {
            Text("Push Tiering")
        } footer: {
            Text("How intrusive each priority's status push is. Decision requests always alert unless you turn off Alert on decisions above.")
        }
    }
}

private enum Tier: Hashable {
    case off, passive, active, timeSensitive

    init(_ rule: PushRule) {
        guard rule.deliver else { self = .off; return }
        switch rule.level {
        case .passive: self = .passive
        case .active: self = .active
        case .timeSensitive: self = .timeSensitive
        }
    }

    var label: String {
        switch self {
        case .off: "Off"
        case .passive: "Passive"
        case .active: "Active"
        case .timeSensitive: "Time-sensitive"
        }
    }
}

private struct PushTieringRow: View {
    let priority: HibossKit.MessagePriority
    let rule: PushRule
    let setRule: (PushRule) -> Void

    var body: some View {
        Menu {
            Picker("Delivery", selection: tierBinding) {
                Label("Off", systemImage: "bell.slash").tag(Tier.off)
                Label("Passive", systemImage: "bell").tag(Tier.passive)
                Label("Active", systemImage: "bell.badge").tag(Tier.active)
                Label("Time-sensitive", systemImage: "bell.badge.waveform").tag(Tier.timeSensitive)
            }
            Toggle("Sound", isOn: soundBinding)
                .disabled(!rule.deliver)
        } label: {
            HStack {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(priority.rawValue.capitalized)
                    .foregroundStyle(.primary)
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var summary: String {
        let tier = Tier(rule)
        guard tier != .off else { return "Off" }
        return rule.sound ? "\(tier.label) · Sound" : tier.label
    }

    private var tierBinding: Binding<Tier> {
        Binding(
            get: { Tier(rule) },
            set: { setRule(apply($0)) }
        )
    }

    private var soundBinding: Binding<Bool> {
        Binding(get: { rule.sound }, set: { setRule(rule.with(sound: $0)) })
    }

    private func apply(_ tier: Tier) -> PushRule {
        switch tier {
        case .off: rule.with(deliver: false)
        case .passive: rule.with(deliver: true, level: .passive)
        case .active: rule.with(deliver: true, level: .active)
        case .timeSensitive: rule.with(deliver: true, level: .timeSensitive)
        }
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
