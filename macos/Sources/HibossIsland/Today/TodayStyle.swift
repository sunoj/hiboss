// Design-v4 named resource colours and native primary decision controls.
// Exports: TodayStyle and shared AttentionGroup titles.
// Dependencies: SwiftUI, HibossKit, and the packaged colour asset catalog.

import HibossKit
import SwiftUI

enum TodayStyle {
    static let ink = Color("Ink", bundle: appResourceBundle) // i18n-exempt: asset name
    static let signal = Color("Signal", bundle: appResourceBundle) // i18n-exempt: asset name
    static let live = Color("Live", bundle: appResourceBundle) // i18n-exempt: asset name
    static let settled = Color("Settled", bundle: appResourceBundle) // i18n-exempt: asset name
    static let ground = Color("Ground", bundle: appResourceBundle) // i18n-exempt: asset name
    static let surface = Color("Surface", bundle: appResourceBundle) // i18n-exempt: asset name
    static let secondary = Color("SecondaryText", bundle: appResourceBundle) // i18n-exempt: asset name
    static let tertiary = Color("TertiaryText", bundle: appResourceBundle) // i18n-exempt: asset name
    static let hairline = Color("Hairline", bundle: appResourceBundle) // i18n-exempt: asset name
    static let signalSoft = Color("SignalSoft", bundle: appResourceBundle) // i18n-exempt: asset name
    static let liveSoft = Color("LiveSoft", bundle: appResourceBundle) // i18n-exempt: asset name
    static let settledSoft = Color("SettledSoft", bundle: appResourceBundle) // i18n-exempt: asset name
}

extension AttentionGroup {
    var title: String {
        switch self {
        case .autoDecision: L("Decides itself")
        case .waitingOnYou: L("Waiting on you")
        case .priority: L("Questions")
        }
    }
}

struct DecisionDefaultLine: View {
    let option: String
    let expiresAt: Date?
    let now: Date

    nonisolated static func text(option: String, expiresAt: Date?, now: Date) -> String {
        if let expiresAt {
            let time = AttentionClock.remaining(until: expiresAt, now: now)
            return L("No answer in \(time) picks “\(option)”. That is not approval.")
        }
        return L("Default: “\(option)”. No deadline. That is not approval.")
    }

    var body: some View {
        TimelineView(.periodic(from: now, by: 1)) { context in
            Text(Self.text(option: option, expiresAt: expiresAt, now: context.date))
                .font(.caption).foregroundStyle(TodayStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
