// Records native startup state with elapsed milliseconds from process creation.
// Exports StartupLog; callers supply only static state names and counts.
// Dependencies: Darwin process metadata and OSLog.

import Darwin
import Foundation
import OSLog

public enum StartupLog {
    private static let logger = Logger(subsystem: "ai.hiboss.app", category: "startup")
    private static let startUptime: TimeInterval = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let read = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        let started = read == 0
            ? TimeInterval(info.kp_proc.p_starttime.tv_sec)
                + TimeInterval(info.kp_proc.p_starttime.tv_usec) / 1_000_000
            : Date().timeIntervalSince1970
        return ProcessInfo.processInfo.systemUptime - (Date().timeIntervalSince1970 - started)
    }()

    public static func record(_ state: StaticString, count: Int = 0) {
        let ms = Int((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000)
        logger.notice("\(state.description, privacy: .public) elapsed_ms=\(ms) count=\(count)")
    }
}
