import AppKit
import BuddyCore

/// Plays the buddy's sounds. Every NSSound is loaded the first time it is
/// needed and then kept, so at rest this costs nothing.
final class SoundPlayer {
    /// The loaded sounds, by catalog id.
    private var sounds: [String: NSSound] = [:]
    /// The sound last played for each event, so the rule in `eventsToStop`
    /// knows what to stop before the next one starts.
    private var lastPlayed: [SoundEvent: NSSound] = [:]

    /// Plays the sound resolved from the stored value for an event. A silent
    /// choice, or a sound that won't load, leaves the event mute without
    /// crashing.
    func play(_ event: SoundEvent, stored: String?) {
        for other in SoundCatalog.eventsToStop(before: event) {
            lastPlayed[other]?.stop()
        }
        guard case .sound(let option) = SoundCatalog.resolve(stored: stored, for: event),
              let sound = load(option) else { return }
        play(sound, gain: option.gain)
        lastPlayed[event] = sound
    }

    /// Plays an option once, for the menu preview. Doesn't touch what any
    /// event last played.
    func preview(_ option: SoundOption) {
        guard let sound = load(option) else { return }
        play(sound, gain: option.gain)
    }

    /// Whether macOS ships a sound by that name. Checked on disk so building
    /// the menu doesn't load all fourteen.
    static func systemSoundExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: "/System/Library/Sounds/\(name).aiff")
    }

    /// stop() first: play() on a sound that is still playing does nothing, and
    /// that is why a second card in a row used to arrive mute.
    private func play(_ sound: NSSound, gain: Float) {
        sound.stop()
        sound.volume = gain
        sound.play()
    }

    /// Loads an option's sound, caching it. Returns nil when it won't load.
    private func load(_ option: SoundOption) -> NSSound? {
        if let cached = sounds[option.id] { return cached }
        let sound: NSSound?
        switch option.source {
        case .bundled(let file, let ext):
            sound = Bundle.module
                .url(forResource: file, withExtension: ext, subdirectory: "Resources/Sounds")
                .flatMap { NSSound(contentsOf: $0, byReference: true) }
        case .system(let name):
            // NSSound(named:) hands out one shared instance to everyone, so the
            // buddy's gain would leak into whatever else plays that sound.
            sound = NSSound(named: name)?.copy() as? NSSound
        }
        guard let sound else { return nil }
        sounds[option.id] = sound
        return sound
    }
}
