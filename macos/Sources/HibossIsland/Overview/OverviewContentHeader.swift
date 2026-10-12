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
                Text(countText)
                    .font(.headline).monospacedDigit()
                Spacer(minLength: 8)
            }
            .foregroundStyle(.primary)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var countText: String {
        if case let .category(category) = destination, category.isAttention,
           !snapshot.answerability.isLoaded { return L("Loading") }
        return countsAvailable ? snapshot.messages(for: destination).count.formatted() : L("Loading")
    }

    private var subtitle: String {
        switch destination {
        case .category(.needsYou): L("Questions that need a decision.")
        case .category(.automatic): L("The default runs when the timer ends.")
        case .category(.waiting): L("Questions waiting for your answer.")
        case .category(.urgent): L("Priority questions that need your attention.")
        case .category(.all): L("Recent messages across your sessions.")
        case .category(.completed): L("Answered and expired questions.")
        case .session: L("Recent messages in this session.")
        case .today: L("Decisions and live panels.")
        case .deviceRequests: L("Machines waiting to join.")
        case .box: L("Box")
        case .progress: L("Progress")
        }
    }
}
