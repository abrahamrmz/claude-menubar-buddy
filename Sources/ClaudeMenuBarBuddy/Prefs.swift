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

    var notifiedFiveHour: Int {
        get { Defaults[.notifiedFiveHour] }
        set { Defaults[.notifiedFiveHour] = newValue }
    }

    var notifiedWeekly: Int {
        get { Defaults[.notifiedWeekly] }
        set { Defaults[.notifiedWeekly] = newValue }
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
