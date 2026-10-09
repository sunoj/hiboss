// Native session list summary: session, status, agent and latest activity.
// Exports: SessionRow and TodaySession localization for Activity.
// Dependencies: SwiftUI, HibossKit TodaySession and Theme.

import HibossKit
import SwiftUI

extension TodaySession {
    var localizedLabel: String {
        id == SessionGrouping.directSessionID ? String(localized: "Direct") : projectLabel
    }
}

struct SessionRow: View {
    let session: TodaySession
    let tint: Color
    let fill: Color
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(session.localizedLabel.prefix(2)).uppercased())
                .font(.footnote.bold()).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(fill, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: [session.localizedLabel, session.branch].compactMap { $0 }
                    .joined(separator: " / ")).font(.headline)
                Text(verbatim: session.statusText).font(.subheadline).foregroundStyle(Theme.ink2)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if let agent = session.agentName {
                    Text(verbatim: agent).font(.caption).foregroundStyle(Theme.ink2)
                }
                if let date = session.lastActivityDate {
                    Text(date, style: .relative).font(.caption).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
