// Alert sounds played when a question arrives.
// Exports: OptionSound, SoundPlaying, and SystemSoundPlayer.
// Dependencies: AppKit NSSound and the sounds shipped in /System/Library/Sounds.

import AppKit

/// A macOS system alert sound. Raw values are the names under /System/Library/Sounds.
enum OptionSound: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case ping = "Ping"
    case glass = "Glass"
    case hero = "Hero"
    case submarine = "Submarine"
    case bottle = "Bottle"
    case blow = "Blow"
    case pop = "Pop"
    case sosumi = "Sosumi"
    case tink = "Tink"
    case funk = "Funk"

    static let fallback = OptionSound.glass

    var id: String { rawValue }
    var label: String { self == .none ? L("None") : rawValue }
}

protocol SoundPlaying: Sendable {
    func play(_ sound: OptionSound)
}

struct SystemSoundPlayer: SoundPlaying {
    func play(_ sound: OptionSound) {
        guard sound != .none else { return }
        NSSound(named: sound.rawValue)?.play()
    }
}
