// 28-day activity heat grid for the Home activity card (native Grid, no charts).
// Exports: HomeActivityGrid and a compact 7-day delta row.
// Dependencies: SwiftUI, HibossKit HomeActivity, Theme tokens.

import HibossKit
import SwiftUI

struct HomeActivityGrid: View {
    let activity: HomeActivity

    private var maxTotal: Int {
        max(activity.days.map(\.total).max() ?? 0, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.hbH3)
                .foregroundStyle(Theme.ink)
            deltaRow
            grid
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var deltaRow: some View {
        HStack(spacing: 12) {
            deltaChip(label: "Posts", value: activity.delta.posts)
            deltaChip(label: "Decisions", value: activity.delta.decisions)
            deltaChip(label: "Messages", value: activity.delta.messages)
            Spacer(minLength: 0)
        }
        .font(.hbCaption)
    }

    private func deltaChip(label: String, value: Double?) -> some View {
        let text: String
        let tint: Color
        if let value {
            let pct = Int((value * 100).rounded())
            text = "\(pct >= 0 ? "+" : "")\(pct)%"
            tint = pct > 0 ? Theme.positive : (pct < 0 ? Theme.negative : Theme.ink3)
        } else {
            text = "—"
            tint = Theme.ink3
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(Theme.ink3)
            Text(text).foregroundStyle(tint).font(.hbBodyStrong)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) 7-day change \(text)")
    }

    /// 4 weeks × 7 days, oldest week first; days are already oldest→newest.
    private var grid: some View {
        let days = paddedDays
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<4, id: \.self) { week in
                GridRow {
                    ForEach(0..<7, id: \.self) { weekday in
                        let index = week * 7 + weekday
                        cell(days[index])
                    }
                }
            }
        }
        .accessibilityLabel("28-day activity heat grid")
    }

    private var paddedDays: [HomeActivityDay] {
        var days = activity.days
        if days.count < 28 {
            let missing = 28 - days.count
            let fillers = (0..<missing).map {
                HomeActivityDay(date: "pad-\($0)", posts: 0, decisions: 0, messages: 0)
            }
            days = fillers + days
        }
        return Array(days.suffix(28))
    }

    private func cell(_ day: HomeActivityDay) -> some View {
        let intensity = Double(day.total) / Double(maxTotal)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(cellColor(intensity: intensity))
            .frame(minWidth: 12, minHeight: 12)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("\(day.date): \(day.total) events")
    }

    private func cellColor(intensity: Double) -> Color {
        if intensity <= 0 { return Theme.surface2 }
        return Theme.positive.opacity(0.25 + 0.75 * min(intensity, 1))
    }
}
