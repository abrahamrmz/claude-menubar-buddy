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
    // "template" = drawn monochrome panda that follows the menu bar's
    // appearance; "emoji" = the literal 🐼 the app shipped with, for anyone
    // who wants the color back.
    static let iconStyle = Key<String>("iconStyle", default: "template")
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

    var iconStyle: String {
        get { Defaults[.iconStyle] }
        set { Defaults[.iconStyle] = newValue }
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

    // Flag file for auto-approve-edits mode; hook.sh fast-paths Edit/Write/
    // NotebookEdit while it exists. A file (not UserDefaults) so the hook
    // can read it without talking to the app.
    var autoEditsFlagURL: URL { dirURL.appendingPathComponent("auto_approve_edits") }
    var autoEditsEnabled: Bool { FileManager.default.fileExists(atPath: autoEditsFlagURL.path) }

    func readAlwaysAllow() -> AlwaysAllow {
        guard let data = try? Data(contentsOf: alwaysAllowURL),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return AlwaysAllow() }
        // The file was a bare array before grants had scopes. Everything in
        // one was granted everywhere, so that is where it stays: narrowing a
        // permission the user gave would be a surprise in the safe direction,
        // but a surprise, and a command that silently stopped being allowed
        // would just look like the buddy had broken.
        if let legacy = obj as? [String] { return AlwaysAllow(global: legacy) }
        guard let dict = obj as? [String: Any] else { return AlwaysAllow() }
        return AlwaysAllow(global: dict["global"] as? [String] ?? [],
                           projects: dict["projects"] as? [String: [String]] ?? [:])
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

/// The buddy's Bash allowlist, in two scopes: commands allowed everywhere,
/// and commands allowed only in the session that granted them.
///
/// Projects are keyed by the session's **absolute cwd**, not by its name.
/// Two checkouts can both be called `api`, and a grant leaking between them
/// is exactly the kind of thing nobody would ever notice. The match is exact
/// for the same reason a prefix would be wrong: `/repo` as a prefix also
/// covers `/repo-secrets`, and a grant that widens by accident is the one
/// failure this file exists to prevent.
struct AlwaysAllow {
    var global: [String] = []
    var projects: [String: [String]] = [:]

    /// Mirrors hook.sh's lookup — kept in Swift so the settings table can say
    /// what the hook would actually do, but the hook remains the authority
    /// (it decides with the app not running).
    func allows(_ base: String, in cwd: String?) -> Bool {
        if global.contains(base) { return true }
        guard let cwd = cwd, !cwd.isEmpty else { return false }
        return projects[cwd]?.contains(base) ?? false
    }
}
