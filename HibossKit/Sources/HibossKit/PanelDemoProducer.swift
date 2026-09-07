// Simulated producer schedules for the seven-panel wall demonstration.
// Exports: PanelDemoProducer and PanelDemoProducer.catalog.
// Dependencies: Foundation Duration-compatible nanosecond intervals.

import Foundation

public struct PanelDemoProducer: Identifiable, Sendable {
    public static let clockIntervalNanoseconds: UInt64 = 1_000_000_000

    public let id: String
    public let name: String
    public let intervalNanoseconds: UInt64
    public let startDelayNanoseconds: UInt64
    public let pushLimit: Int?

    public static let catalog: [PanelDemoProducer] = [
        PanelDemoProducer(id: "release-bot", name: "Release Bot", intervalNanoseconds: 1_400_000_000, startDelayNanoseconds: 0, pushLimit: nil),
        PanelDemoProducer(id: "checkout-runner", name: "Checkout Runner", intervalNanoseconds: 1_800_000_000, startDelayNanoseconds: 250_000_000, pushLimit: nil),
        PanelDemoProducer(id: "benchmark-lab", name: "Benchmark Lab", intervalNanoseconds: 2_200_000_000, startDelayNanoseconds: 500_000_000, pushLimit: nil),
        PanelDemoProducer(id: "image-api-watch", name: "Image API Watch", intervalNanoseconds: 2_600_000_000, startDelayNanoseconds: 750_000_000, pushLimit: nil),
        PanelDemoProducer(id: "research-desk", name: "Research Desk", intervalNanoseconds: 1_600_000_000, startDelayNanoseconds: 1_000_000_000, pushLimit: 3),
        PanelDemoProducer(id: "rollout-control", name: "Rollout Control", intervalNanoseconds: 2_400_000_000, startDelayNanoseconds: 1_250_000_000, pushLimit: nil),
        PanelDemoProducer(id: "task-metrics", name: "Task Metrics", intervalNanoseconds: 2_000_000_000, startDelayNanoseconds: 1_500_000_000, pushLimit: nil),
    ]
}
