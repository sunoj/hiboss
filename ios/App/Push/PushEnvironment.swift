// Resolves APNs routing from a provisioning profile's XML entitlement payload.
// Exports: PushEnvironment.resolve; depends only on Foundation.

import Foundation

enum PushEnvironment {
    static func resolve(profile: Data?, isSimulator: Bool) -> String {
        let fallback = isSimulator ? "sandbox" : "production"
        guard let profile,
              let start = profile.range(of: Data("<plist".utf8)),
              let end = profile.range(of: Data("</plist>".utf8),
                                      in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: profile.subdata(in: start.lowerBound..<end.upperBound),
                options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String
        else { return fallback }
        switch environment {
        case "development": return "sandbox"
        case "production": return "production"
        default: return fallback
        }
    }
}
