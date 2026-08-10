import Defaults
import Foundation

// Persisted settings, typed via Defaults. Key names match the raw
// UserDefaults keys the app used before adopting the package, so existing
// user values carry over untouched (Defaults stores primitives natively in
// UserDefaults.standard under the same names).
extension Defaults.Keys {
    static let floatingPetVisible = Key<Bool>("floatingPetVisible", default: true)
    static let selectedSpecies = Key<String>("selectedSpecies", default: "buddy")
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
}

extension AppDelegate {
    var floatingPetVisible: Bool {
        get { Defaults[.floatingPetVisible] }
        set { Defaults[.floatingPetVisible] = newValue }
    }

    var selectedSpecies: String {
        get { Defaults[.selectedSpecies] }
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

    func readAlwaysAllow() -> [String] {
        guard let data = try? Data(contentsOf: alwaysAllowURL),
              let list = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return list
    }

    func writeAlwaysAllow(_ list: [String]) {
        if let data = try? JSONSerialization.data(withJSONObject: list.sorted(), options: [.prettyPrinted]) {
            try? data.write(to: alwaysAllowURL, options: [.atomic])
        }
    }
}
