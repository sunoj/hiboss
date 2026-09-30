// One quiet, collapsed row for a run of agent activity between conversation turns.
// Exports: SessionStepsRow. Expanding shows each step's existing system line.
// Dependencies: SwiftUI, HibossKit SessionEvent, SessionSystemLine.

import HibossKit
import SwiftUI

struct SessionStepsRow: View {
    let events: [SessionEvent]
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 0) {
                ForEach(events) { SessionSystemLine(event: $0) }
            }
        } label: {
            Label {
                Text("\(events.count) steps")
            } icon: {
                Image(systemName: "gearshape.2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("session-steps")
        }
        .tint(.secondary)
        .padding(.horizontal, 8)
    }
}
