import Foundation

// Which mood the limit ladder produces, and which GIF a (species, mood) pair
// resolves to. Pure policy: the app hands in a closure saying whether a GIF
// exists in its bundle, and the tests hand in the repo's Resources directory
// — so "4 species × 13 moods, no dead combination" is checked on every
// `swift test` instead of by hand at every pet retirement.

public enum MoodPolicy {
    /// Every mood the app can ask a pet to wear — the keys of MOODS plus
    /// GESTURES in generate_pets.py, which is the source of truth for the
    /// art. The tests audit this list against the shipped GIFs; a mood added
    /// in one place but not the other fails there instead of showing up as a
    /// pet frozen on its previous pose.
    ///
    /// The last three are gestures: only the koala has art for them, and the
    /// chains below carry the rest. That asymmetry is deliberate — a gesture
    /// gets tried on one pet before it's bought for four.
    public static let allMoods = [
        "idle", "pending", "working", "thinking", "tired", "stressed",
        "critical", "asleep", "heart", "celebrate", "sad", "excited", "meditate",
        "greet", "yawn", "dance",
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
        // The three gestures. A wave is a greeting with its hand up, so a pet
        // without one still greets — it just does it with its face.
        case "greet": return ["greet", "excited", "celebrate", "heart"]
        case "dance": return ["dance", "celebrate", "heart"]
        // Nothing stands in for a yawn: it is a flourish on top of doing
        // nothing, so a pet without the art simply carries on doing nothing.
        // Anything else would turn "idle for a while" into a visible event on
        // pets that have no way to express it.
        case "yawn": return ["yawn", "idle"]
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

    /// The menu line for a mood: plain text, deliberately emoji-free — the
    /// pet already carries the feeling in pixels, and the menu keeps it as
    /// words (which is also what VoiceOver reads, unmangled).
    public static func moodLine(_ mood: String) -> String {
        switch mood {
        case "thinking": return "Thinking it over..."
        case "working": return "Working — running tools"
        case "tired": return "Getting tired..."
        case "stressed": return "Feeling the pressure (70% of the 5h limit)"
        case "critical": return "Running on fumes (85% of the 5h limit)"
        case "asleep": return "Fast asleep (5h limit reached)"
        case "sad": return "Aw, denied"
        case "excited", "greet": return "A new session said hi!"
        case "meditate": return "Meditating — compacting context"
        case "yawn": return "Nothing to do…"
        case "dance": return "Back in business!"
        // Species-neutral on purpose: this line follows whichever pet is
        // selected, and a koala announcing itself with a panda face was a
        // leftover from when the panda was the only pet.
        default: return "Active and happy"
        }
    }

    /// What a mood transition is worth saying out loud at the pet. Nil for
    /// the moods that are either self-explanatory (heart — you just petted
    /// it) or too frequent to narrate (idle/working/thinking would bubble
    /// all day). celebrate gets its own line instead of moodLine because
    /// that helper has no celebrate case and would fall through to "Active
    /// and happy" — wrong words at the right moment. A yawn stays silent on
    /// purpose: it exists to give idle time some texture, and narrating it
    /// would turn "nothing is happening" into an announcement.
    public static func bubbleLine(_ mood: String) -> String? {
        switch mood {
        case "meditate", "tired", "stressed", "critical", "asleep", "excited", "greet", "sad":
            return moodLine(mood)
        case "celebrate", "dance": return "Back in business!"
        default: return nil
        }
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
