// Recorded decision outcome, with timeout defaults kept separate from boss choices.
// Exports ResolvedBanner for thread and detail; timestamps are omitted without a receipt.
// Dependencies: DecisionSettlement, SwiftUI semantic type, and design-v4 Theme roles.

import SwiftUI

struct ResolvedBanner: View {
    let settlement: DecisionSettlement
    var date: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                if settlement.isAutoDefault { Text("Default picked · not approval") }
                else { Text("You chose \(settlement.answer)") }
            } icon: { Image(systemName: settlement.symbol) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(settlement.isAutoDefault ? Theme.ink2 : Theme.positive)
            if settlement.isAutoDefault { Text(verbatim: settlement.answer).font(.subheadline) }
            HStack {
                settlement.attribution
                if let date { RecordedTimeText(date: date) }
            }.font(.caption).foregroundStyle(Theme.ink2)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(settlement.isAutoDefault ? Theme.surface2 : Theme.settledSoft,
                    in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
