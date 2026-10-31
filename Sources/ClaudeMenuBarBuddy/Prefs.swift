import BuddyCore
import Defaults
import Foundation

// Persisted settings, typed via Defaults. Key names match the raw
// UserDefaults keys the app used before adopting the package, so existing
// user values carry over untouched (Defaults stores primitives natively in
// UserDefaults.standard under the same names).
extension Defaults.Keys {
    static let floatingPetVisible = Key<Bool>("floatingPetVisible", default: true)
    // Was "buddy" while the hand-drawn panda shipped. Anyone who picked one
    // of the retired pets still has that name stored, so the accessor below
    // checks the art exists rather than trusting it.
    static let selectedSpecies = Key<String>("selectedSpecies", default: "koala")
    // Thresholds match ClaudeBar's scheme (see the community-project survey):
    // <50% used = healthy, 50-80% = warning, >80% = critical. Persist the
    // highest threshold already notified-for per limit so we don't re-fire
    // the same notification every time the menu happens to be opened.
    static let notifiedFiveHour = Key<Int>("notifiedFiveHour", default: 0)
    static let notifiedWeekly = Key<Int>("notifiedWeekly", default: 0)
    // NSStringFromPoint-encoded origin of the floating pet window.
    static let floatingPetOrigin = Key<String>("floatingPetOrigin", default: "")
    // "small" | "medium" | "large" — see floatingPetSide for why those three
    // point sizes and not a free slider.
    static let floatingPetSize = Key<String>("floatingPetSize", default: "medium")
    // Turns shorter than this don't get a finish toast — you were watching
    // anyway. (The macOS banner threshold lives in notify-done.sh; this one
    // is deliberately lower because a toast at the pet is less intrusive.)
    static let toastMinSeconds = Key<Int>("toastMinSeconds", default: 15)
    // Whether the burn rate is allowed to warn about a limit you haven't hit
    // yet but are on pace for.
    static let projectedWarnings = Key<Bool>("projectedWarnings", default: true)
    // Kill-switch for the floating pet's ambient motion (bob, squash, cursor
    // reaction) — the GIFs still animate, the pet just holds still between
    // frames. See Fidgets.swift.
    static let calmPet = Key<Bool>("calmPet", default: false)
    // The pet's occasional one-line speech bubble (SpeechBubble.swift).
    static let speechBubbles = Key<Bool>("speechBubbles", default: true)
    // Which CardPalette the card, the finish toast and the speech bubble are
    // painted from. Stored by id and resolved on read (CardPalette.resolve),
    // so an id left behind by a retired palette falls back instead of
    // leaving a card with no colors.
    static let cardPalette = Key<String>("cardPalette", default: CardPalette.masko.id)
    // The sound chosen for each SoundEvent, by SoundCatalog id ("none" is
    // silence). Resolved on read (SoundCatalog.resolve), so an id left
    // behind by a retired sound plays the default instead of nothing.
    static let cardSound = Key<String>(SoundEvent.cardArrived.defaultsKey, default: SoundEvent.cardArrived.defaultSoundID)
    static let turnDoneSound = Key<String>(SoundEvent.turnDone.defaultsKey, default: SoundEvent.turnDone.defaultSoundID)
    static let petClickSound = Key<String>(SoundEvent.petClicked.defaultsKey, default: SoundEvent.petClicked.defaultSoundID)
    static let blockedSound = Key<String>(SoundEvent.hotKeyBlocked.defaultsKey, default: SoundEvent.hotKeyBlocked.defaultSoundID)
}

extension AppDelegate {
    var floatingPetVisible: Bool {
        get { Defaults[.floatingPetVisible] }
        set { Defaults[.floatingPetVisible] = newValue }
    }

    /// The chosen pet, or the default when that pet's art is gone.
    ///
    /// Retiring the hand-drawn panda and the eighteen firmware species left
    /// their names sitting in real users' preferences, and an unchecked one
    /// resolves to a GIF that isn't in the bundle — setGif returns early and
    /// the pet is simply invisible, with nothing on screen to explain why.
    /// Checked on read rather than migrated once at launch, so retiring any
    /// future pet heals itself the same way.
    var selectedSpecies: String {
        get {
            MoodPolicy.resolvedSpecies(stored: Defaults[.selectedSpecies],
                                       fallback: Defaults.Keys.selectedSpecies.defaultValue,
                                       available: bundleHasGif)
        }
        set { Defaults[.selectedSpecies] = newValue }
    }

    var floatingPetSize: String {
        get { Defaults[.floatingPetSize] }
        set { Defaults[.floatingPetSize] = newValue }
    }

    var notifiedFiveHour: Int {
        get { Defaults[.notifiedFiveHour] }
        set { Defaults[.notifiedFiveHour] = newValue }
    }

    var notifiedWeekly: Int {
        get { Defaults[.notifiedWeekly] }
        set { Defaults[.notifiedWeekly] = newValue }
    }

    var toastMinSeconds: Int {
        get { Defaults[.toastMinSeconds] }
        set { Defaults[.toastMinSeconds] = newValue }
    }

    var projectedWarnings: Bool {
        get { Defaults[.projectedWarnings] }
        set { Defaults[.projectedWarnings] = newValue }
    }

    var speechBubbles: Bool {
        get { Defaults[.speechBubbles] }
        set { Defaults[.speechBubbles] = newValue }
    }

    var cardPalette: String {
        get { Defaults[.cardPalette] }
        set { Defaults[.cardPalette] = newValue }
    }

    // MARK: - Sounds

    /// The stored catalog id for an event's sound (a SoundCatalog id, or
    /// "none" for silence).
    func storedSoundID(for event: SoundEvent) -> String {
        Defaults[soundKey(for: event)]
    }

    func setStoredSoundID(_ id: String, for event: SoundEvent) {
        Defaults[soundKey(for: event)] = id
    }

    private func soundKey(for event: SoundEvent) -> Defaults.Key<String> {
        switch event {
        case .cardArrived: return .cardSound
        case .turnDone: return .turnDoneSound
        case .petClicked: return .petClickSound
        case .hotKeyBlocked: return .blockedSound
        }
    }

    /// Plays the event's sound. The one way the app makes a sound.
    func playSound(_ event: SoundEvent) {
        soundPlayer.play(event, stored: storedSoundID(for: event))
    }

    // MARK: - Start at login

    /// The LaunchAgent that starts the buddy at login. Written/removed by the
    /// Settings toggle; the same plist SKILL.md installs.
    var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.claudemenubarbuddy.app.plist")
    }

    var startsAtLogin: Bool { FileManager.default.fileExists(atPath: launchAgentURL.path) }

    /// Writes or removes the plist and nothing else — deliberately no
    /// `launchctl`. Booting the job out would kill the very process running
    /// this code (the app IS that job), and bootstrapping it while an
    /// already-running copy was started by hand would put two pandas in the
    /// menu bar. The file alone is what launchd reads at the next login,
    /// which is exactly what the toggle claims to control.
    func setStartsAtLogin(_ enabled: Bool) {
        guard enabled else {
            try? FileManager.default.removeItem(at: launchAgentURL)
            return
        }
        guard let executable = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": "com.claudemenubarbuddy.app",
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": "/tmp/menubar_buddy.log",
            "StandardErrorPath": "/tmp/menubar_buddy.log",
        ]
        try? FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: launchAgentURL, options: [.atomic])
    }

    // MARK: - Buddy-managed flag files (shared with hook.sh)

    // Buddy-managed allowlist of Bash base commands, stored beside the
    // request files. hook.sh consults it BEFORE writing a request, so
    // always-allowed commands are approved instantly with no card at all.
    // Deliberately separate from ~/.claude/settings.json — the buddy never
    // edits Claude Code's own config.
    var alwaysAllowURL: URL { dirURL.appendingPathComponent("always_allow.json") }

    // Flag file for auto mode; buddy-rule reads it and lets routine work pass
    // without a card. A file (not UserDefaults) so the rule can read it
    // without talking to the app.
    var autoModeFlagURL: URL { dirURL.appendingPathComponent("auto_mode") }
    var autoModeEnabled: Bool { FileManager.default.fileExists(atPath: autoModeFlagURL.path) }

    func readAlwaysAllow() -> AlwaysAllow {
        AlwaysAllow.read(from: alwaysAllowURL)
    }

    func writeAlwaysAllow(_ list: AlwaysAllow) {
        // Projects that ran out of entries are dropped rather than left as
        // empty arrays — a path in the file reads as "this project has a
        // standing grant", and after the last Remove it doesn't.
        var projects: [String: [String]] = [:]
        for (path, commands) in list.projects where !commands.isEmpty {
            projects[path] = commands.sorted()
        }
        let payload: [String: Any] = ["global": list.global.sorted(), "projects": projects]
        if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: alwaysAllowURL, options: [.atomic])
        }
    }
}

