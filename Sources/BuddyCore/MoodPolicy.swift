import Foundation

// Which mood the limit ladder produces, and which GIF a (species, mood) pair
// resolves to. Pure policy: the app hands in a closure saying whether a GIF
// exists in its bundle, and the tests hand in the repo's Resources directory
// — so "4 species × 13 moods, no dead combination" is checked on every
// `swift test` instead of by hand at every pet retirement.

public enum MoodPolicy {
    /// Every mood the app can ask a pet to wear — the keys of MOODS in
    /// generate_pets.py, which is the source of truth for the art. The tests
    /// audit this list against the shipped GIFs; a mood added in one place
    /// but not the other fails there instead of showing up as a pet frozen
    /// on its previous pose.
    public static let allMoods = [
        "idle", "pending", "working", "thinking", "tired", "stressed",
        "critical", "asleep", "heart", "celebrate", "sad", "excited", "meditate",
    ]

    // The pet's mood follows the 5-hour limit, not the weekly one — it's
    // the one that actually blocks you mid-session, so it's the one worth
    // dramatizing. The ladder: <50% used = active, 50% = tired, 70% =
    // stressed, 85% = critical, 100% = asleep.
    public static func petMood(forFiveHourPct pct: Int?) -> String {
        guard let pct = pct else { return "idle" }
        if pct >= 100 { return "asleep" }
        if pct >= 85 { return "critical" }
        if pct >= 70 { return "stressed" }
        if pct >= 50 { return "tired" }
        return "idle"
    }

    /// Where a mood goes when a pet has no art for it.
    ///
    /// All four shipped pets now draw all thirteen, so nothing in here fires
    /// today — but it stays, and stays tested, because it's what lets a pet
    /// arrive in pieces. Every one of them shipped its CORE ten first and its
    /// thinking/sad/excited weeks later, and during that gap these chains are
    /// the whole reason a piglet mid-turn looked busy instead of frozen.
    /// Ending at idle means a missing GIF never leaves the previous one stuck
    /// on screen.
    public static func gifCandidates(_ mood: String) -> [String] {
        switch mood {
        case "thinking": return ["thinking", "working"]
        case "excited": return ["excited", "celebrate", "heart"]
        case "sad": return ["sad", "tired"]
        // Species without meditation art sit compaction out looking
        // thoughtful — NOT asleep, whose Z means "limit reached" and would
        // read as a much worse thing than a tidy-up. Idle is spelled out as
        // the end of the chain rather than left to gifName's implicit
        // fallback, so this list reads as the complete policy.
        case "meditate": return ["meditate", "thinking", "idle"]
        default: return [mood]
        }
    }

    public static func gifName(species: String, mood: String,
                               available: (String) -> Bool) -> String {
        for candidate in gifCandidates(mood) where available("\(species)_\(candidate)") {
            return "\(species)_\(candidate)"
        }
        return "\(species)_idle"
    }

    /// The chosen pet, or the fallback when that pet's art is gone.
    ///
    /// Retiring the hand-drawn panda and the eighteen firmware species left
    /// their names sitting in real users' preferences, and an unchecked one
    /// resolves to a GIF that isn't in the bundle — setGif returns early and
    /// the pet is simply invisible, with nothing on screen to explain why.
    public static func resolvedSpecies(stored: String, fallback: String,
                                       available: (String) -> Bool) -> String {
        available("\(stored)_idle") ? stored : fallback
    }
}
