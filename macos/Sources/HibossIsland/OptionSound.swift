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
    /// System sound names are proper names but still read through the catalog.
    var label: String {
        switch self {
        case .none: L("None")
        case .ping: L("Ping")
        case .glass: L("Glass")
        case .hero: L("Hero")
        case .submarine: L("Submarine")
        case .bottle: L("Bottle")
        case .blow: L("Blow")
        case .pop: L("Pop")
        case .sosumi: L("Sosumi")
        case .tink: L("Tink")
        case .funk: L("Funk")
        }
    }
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
