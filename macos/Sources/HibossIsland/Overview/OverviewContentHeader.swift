// Gives each selected category a clear title, count, and short explanation.
// Exports: OverviewContentHeader.
// Dependencies: SwiftUI, OverviewSnapshot and OverviewDestination.

import SwiftUI

struct OverviewContentHeader: View {
    let destination: OverviewDestination
    let snapshot: OverviewSnapshot
    let countsAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.title(for: destination))
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(countsAvailable ? "\(snapshot.messages(for: destination).count)" : "—")
                    .font(.largeTitle.bold()).monospacedDigit()
            }
            .foregroundStyle(.primary)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var subtitle: String {
        switch destination {
        case .category(.needsYou): L("Questions that need a decision.")
        case .category(.automatic): L("The default runs when the timer ends.")
        case .category(.waiting): L("Agents waiting for your answer.")
        case .category(.urgent): L("Priority questions that need your attention.")
        case .category(.all): L("Recent messages across your sessions.")
        case .category(.completed): L("Answered and expired questions.")
        case .session: L("Recent messages in this session.")
        case .panels: L("Fixture-driven panel preview.")
        }
    }
}
