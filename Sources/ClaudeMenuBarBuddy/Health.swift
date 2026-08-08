import Foundation

// What the buddy can verify about its own installation, by reading the world
// rather than by restating SKILL.md.
//
// The install path is "open the repo in Claude Code and ask it to run
// SKILL.md" — so by the time this app runs for the first time, the hook, the
// settings.json entries and the LaunchAgent are already in place. That makes
// a walkthrough-installer close to useless. What isn't useless is a check
// that answers the one question the app can't otherwise answer for you: *why
// isn't the card appearing?* Every failure below is silent otherwise — the
// hook simply never fires, and the buddy sits there looking idle and healthy.
//
// Nothing here writes anything. Repairing the wiring means editing
// ~/.claude/settings.json, and the buddy never touches Claude Code's config;
// the remedies are text you can hand to Claude Code or run yourself.
struct BuddyHealth {
    struct Check {
        let title: String
        let ok: Bool
        /// What was actually found, in the user's own paths.
        let detail: String
        /// Only shown when `ok` is false.
        let remedy: String?
        /// Failing this doesn't stop approvals from working.
        var optional: Bool = false
    }

    let checks: [Check]

    /// Problems that actually break approvals, as opposed to nice-to-haves.
    var blockingProblems: [Check] { checks.filter { !$0.ok && !$0.optional } }
    var isHealthy: Bool { blockingProblems.isEmpty }

    /// Matchers SKILL.md wires up. Bash/Write/Edit/WebFetch/NotebookEdit are
    /// permission decisions; the last two are the card answering a question
    /// instead (a plan to accept three ways, and a multiple-choice ask).
    static let expectedMatchers = ["Bash", "Write", "Edit", "WebFetch",
                                   "NotebookEdit", "ExitPlanMode", "AskUserQuestion"]

    static var hookURL: URL { dirURL.appendingPathComponent("hook.sh") }
    static var notifyURL: URL { dirURL.appendingPathComponent("notify-done.sh") }
    static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// `claudeSettings` is a parameter only so the wiring check — the one
    /// piece of real parsing in here — can be exercised against crafted
    /// configs instead of only against whatever this machine happens to have.
    static func inspect(claudeSettings: URL? = nil) -> BuddyHealth {
        BuddyHealth(checks: [
            hookScriptCheck(),
            hookWiringCheck(settingsURL: claudeSettings ?? claudeSettingsURL),
            jqCheck(),
            hookFreshnessCheck(),
            notifyCheck(),
        ])
    }

    // MARK: - Individual checks

    private static func hookScriptCheck() -> Check {
        let fm = FileManager.default
        let path = hookURL.path
        guard fm.fileExists(atPath: path) else {
            return Check(
                title: "Hook script installed",
                ok: false,
                detail: "Nothing at \(path)",
                remedy: "From the repo: cp hook.sh \(path) && chmod +x \(path)")
        }
        guard fm.isExecutableFile(atPath: path) else {
            return Check(
                title: "Hook script installed",
                ok: false,
                detail: "Present but not executable — Claude Code can't run it",
                remedy: "chmod +x \(path)")
        }
        return Check(title: "Hook script installed", ok: true,
                     detail: path, remedy: nil)
    }

    /// Reads ~/.claude/settings.json and reports which tools actually route
    /// through our hook. A partial wiring is the nastiest failure mode there
    /// is: Bash prompts land on the card and Edit silently doesn't, which
    /// reads as a bug in the app rather than a gap in the config.
    private static func hookWiringCheck(settingsURL: URL) -> Check {
        let title = "Wired into Claude Code"
        let path = settingsURL.path
        guard let data = try? Data(contentsOf: settingsURL) else {
            return Check(title: title, ok: false,
                         detail: "Can't read \(path)",
                         remedy: "Ask Claude Code to run SKILL.md — step 4 wires the hook up.")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Check(title: title, ok: false,
                         detail: "\(path) isn't valid JSON — Claude Code ignores the whole file",
                         remedy: "python3 -c \"import json; json.load(open('\(path)'))\" will point at the syntax error.")
        }

        let hooks = root["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]] ?? []
        var wired: [String] = []
        for entry in preToolUse {
            guard let matcher = entry["matcher"] as? String,
                  let commands = entry["hooks"] as? [[String: Any]] else { continue }
            let usesOurHook = commands.contains { command in
                guard let text = command["command"] as? String else { return false }
                return text.contains("claude-menubar-buddy/hook.sh")
            }
            // One matcher can cover several tools ("Bash|Edit").
            if usesOurHook { wired.append(contentsOf: matcher.split(separator: "|").map(String.init)) }
        }

        guard !wired.isEmpty else {
            return Check(title: title, ok: false,
                         detail: "No PreToolUse hook in \(path) points at hook.sh",
                         remedy: "Ask Claude Code to read SKILL.md and do step 4. It never edits settings.json without your approval.")
        }
        let missing = expectedMatchers.filter { !wired.contains($0) }
        guard missing.isEmpty else {
            return Check(title: title, ok: false,
                         detail: "\(wired.count) of \(expectedMatchers.count) tools wired — missing \(missing.joined(separator: ", "))",
                         remedy: "Those tools will keep using Claude Code's own prompt. SKILL.md step 4 lists the entries to add.")
        }
        return Check(title: title, ok: true,
                     detail: "All \(expectedMatchers.count) tools route through the card", remedy: nil)
    }

    /// hook.sh parses tool JSON with jq. Looking this up in $PATH would lie:
    /// launchd hands this process a minimal PATH that usually has neither
    /// Homebrew prefix in it, while the hook runs with Claude Code's much
    /// richer environment. So probe the real locations instead.
    private static func jqCheck() -> Check {
        let title = "jq available"
        var candidates = ["/opt/homebrew/bin/jq", "/usr/local/bin/jq",
                          "/usr/bin/jq", "/opt/local/bin/jq"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/jq" }
        }
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return Check(title: title, ok: true, detail: found, remedy: nil)
        }
        return Check(title: title, ok: false,
                     detail: "Not found in the usual places — hook.sh can't parse tool input without it",
                     remedy: "brew install jq")
    }

    /// The installed copy is a snapshot: editing hook.sh in the repo changes
    /// nothing until it's copied across. That has bitten this project before —
    /// a feature lands, the card doesn't change, and the hook is the reason.
    private static func hookFreshnessCheck() -> Check {
        let title = "Installed hook is current"
        guard let repoHook = repoFileURL(named: "hook.sh"),
              let installed = try? Data(contentsOf: hookURL) else {
            // Either the source repo isn't where we can see it, or hook.sh
            // isn't installed at all — the first check already said so.
            return Check(title: title, ok: true,
                         detail: "Skipped — no repo copy to compare against",
                         remedy: nil, optional: true)
        }
        guard let source = try? Data(contentsOf: repoHook) else {
            return Check(title: title, ok: true, detail: "Skipped", remedy: nil, optional: true)
        }
        guard source != installed else {
            return Check(title: title, ok: true,
                         detail: "Matches \(repoHook.path)", remedy: nil)
        }
        return Check(title: title, ok: false,
                     detail: "Differs from \(repoHook.path) — the installed copy is stale",
                     remedy: "cp \(repoHook.path) \(hookURL.path)",
                     optional: true)
    }

    private static func notifyCheck() -> Check {
        let title = "Turn-finished notifications"
        guard FileManager.default.isExecutableFile(atPath: notifyURL.path) else {
            return Check(title: title, ok: false,
                         detail: "notify-done.sh not installed — no banner when a long turn ends",
                         remedy: "cp notify-done.sh \(notifyURL.path) && chmod +x \(notifyURL.path), then SKILL.md step 4b.",
                         optional: true)
        }
        return Check(title: title, ok: true, detail: notifyURL.path, remedy: nil)
    }

    // MARK: -

    /// Where this binary was built from, if it still looks like a checkout.
    /// The LaunchAgent runs `<repo>/.build/debug/ClaudeMenuBarBuddy`, so the
    /// repo root is three levels up — but only trust it if the file we want
    /// is actually sitting there.
    private static func repoFileURL(named name: String) -> URL? {
        guard let executable = Bundle.main.executablePath else { return nil }
        let root = URL(fileURLWithPath: executable)
            .deletingLastPathComponent()   // debug/
            .deletingLastPathComponent()   // .build/
            .deletingLastPathComponent()   // repo root
        let candidate = root.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
