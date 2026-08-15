// Compact progress-post attribution: vendor monogram + model/agent label.
// Exports: ProgressAttributionChip.
// Dependencies: SwiftUI, HibossKit ProgressModelVendor. Drawn mark — no brand assets.

import HibossKit
import SwiftUI

struct ProgressAttributionChip: View {
    let agentLabel: String?
    let model: String?

    var body: some View {
        if let caption {
            HStack(spacing: 4) {
                monogram
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityCaption)
        }
    }

    private var caption: String? {
        switch (agentLabel, model) {
        case let (agent?, model?):
            "\(agent) · \(model)"
        case let (agent?, nil):
            agent
        case let (nil, model?):
            model
        case (nil, nil):
            nil
        }
    }

    private var accessibilityCaption: String {
        switch (agentLabel, model) {
        case let (agent?, model?):
            String(localized: "Attributed to \(agent), \(model)")
        case let (agent?, nil):
            String(localized: "Attributed to \(agent)")
        case let (nil, model?):
            String(localized: "Model \(model)")
        case (nil, nil):
            ""
        }
    }

    private var vendor: ProgressModelVendor {
        ProgressModelVendor.from(model: model)
    }

    private var monogram: some View {
        Text(vendor.monogram)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(monogramForeground)
            .frame(minWidth: 14, minHeight: 14)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(monogramBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
    }

    private var monogramForeground: Color {
        switch vendor {
        case .unknown: Color.secondary
        default: Color.white
        }
    }

    private var monogramBackground: Color {
        switch vendor {
        case .anthropic: Color.orange
        case .openAI: Color.green
        case .google: Color.blue
        case .xAI: Color.indigo
        case .unknown: Color(.tertiarySystemFill)
        }
    }
}
