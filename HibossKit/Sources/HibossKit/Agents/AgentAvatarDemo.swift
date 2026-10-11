// Bundled avatar fixture for native demo modes without a network dependency.
// Exports AgentAvatarDemo; uses the same successful-image presentation as downloaded avatars.
// Dependencies: SwiftUI and the HibossKit resource bundle.

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

public enum AgentAvatarDemo {
    public static let url = URL(string: "https://demo.hiboss.invalid/agent-avatar.png")
    public static var image: Image? {
        guard let file = Bundle.module.url(forResource: "demo-agent-avatar", withExtension: "png")
        else { return nil }
        #if os(iOS)
        return UIImage(contentsOfFile: file.path).map { Image(uiImage: $0) }
        #else
        return NSImage(contentsOf: file).map { Image(nsImage: $0) }
        #endif
    }

    public static func agent(name: String) -> BossAgent {
        BossAgent(id: "demo-agent", name: name, avatarURL: url)
    }
}
