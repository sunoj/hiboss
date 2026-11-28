// Hosts the shared Live Activity presentations for simulator evidence.
// Exports DemoActivityStateView, selected only by the demo activity flag.
// Dependencies: SwiftUI, DecisionActivityCard, Theme and synthetic activity content.

import SwiftUI

struct DemoActivityStateView: View {
    @State private var page = 0
    @State private var askedAt = Date.now.addingTimeInterval(-360)
    @State private var deadline = Date.now.addingTimeInterval(1080)

    private let attributes = DecisionActivityAttributes(
        messageID: "demo-activity", project: "hiboss/main", agentName: "ming-claude", meta: ""
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            DecisionActivityCard(attributes: attributes, state: state)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black, in: cardShape)
                .overlay {
                    if page == 7 {
                        cardShape.strokeBorder(DecisionActivityPriority.color(state.priority), lineWidth: 2)
                    }
                }
                .environment(\.colorScheme, .dark)
            if page == 7 {
                islandStatus
            }
        }
        .padding(16)
        .background(Theme.paper)
    }

    private var header: some View {
        HStack {
            Text("Live Activity").font(.hbH2).foregroundStyle(Theme.ink)
            Spacer()
            Button {
                page = (page + 1) % 8
            } label: {
                Image(systemName: "chevron.forward.circle.fill").font(.title2)
            }
            .accessibilityLabel("Next")
            .accessibilityIdentifier("demo-activity-next")
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: page == 7 ? 32 : 22)
    }

    private var state: DecisionActivityAttributes.ContentState {
        var state = DecisionActivityAttributes.ContentState(
            body: "Project stages: apply the proposed mapping?",
            options: ["Apply as proposed", "Not now"], priority: "high",
            deadline: deadline, content: "Proposed stage mapping for five repositories. Changes stay local.",
            defaultOption: "Not now", askedAt: askedAt
        )
        switch page {
        case 1, 2:
            state.options.append("Review later")
            state.defaultOption = nil
            state.content = nil
            state.submitting = state.options.first
            state.submissionProgressVisible = true
            state.submissionIsSlow = page == 2
        case 3: state.replyFailed = true
        case 4: state.completion = .answered("Apply as proposed")
        case 5: state.completion = .autoSelected("Not now")
        case 6: state.completion = .answeredElsewhere("Review later")
        default: break
        }
        return state
    }

    private var islandStatus: some View {
        var untimed = state
        untimed.deadline = nil
        return HStack(spacing: 16) {
            compact(state)
            compact(untimed)
            demoTimerRing.padding(4).background(.black, in: Circle())
            DecisionActivityMinimalStatus(state: untimed).padding(4).background(.black, in: Circle())
        }
        .environment(\.colorScheme, .dark)
    }

    // Circular progress is determinate in WidgetKit. Draw its ring for the in-app fixture.
    private var demoTimerRing: some View {
        let tint = DecisionActivityPriority.color(state.priority)
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = deadline.timeIntervalSince(askedAt)
            let fraction = min(1, max(0, deadline.timeIntervalSince(context.date) / duration))
            Circle().strokeBorder(.white.opacity(0.14), lineWidth: 3)
                .overlay {
                    Circle().inset(by: 1.5).trim(from: 0, to: fraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel("Decision waiting")
    }

    private func compact(_ state: DecisionActivityAttributes.ContentState) -> some View {
        HStack(spacing: 8) {
            HiBossBrandIcon(size: 18)
            DecisionActivityCompactStatus(state: state)
        }
        .padding(8)
        .background(.black, in: Capsule())
    }
}
