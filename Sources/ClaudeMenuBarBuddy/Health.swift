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

    /// Matchers SKILL.md wires up. The file-and-web tools are permission
    /// decisions; ExitPlanMode and AskUserQuestion are the card answering a
    /// question instead (a plan to accept three ways, and a multiple-choice
    /// ask). MultiEdit and WebSearch were the card's own blind spot for a
    /// while — both had an accent color and a fast path but no matcher, so
    /// their cards could never arrive.
    static let expectedMatchers = ["Bash", "Write", "Edit", "MultiEdit",
                                   "WebFetch", "WebSearch", "NotebookEdit",
                                   "ExitPlanMode", "AskUserQuestion"]

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
            claudeVersionCheck(),
            transcriptShapeCheck(),
            ungatedToolsCheck(),
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

    // MARK: - Surviving Claude Code updates
    //
    // Everything below watches the seams between this app and Claude Code.
    // Nothing here can break approvals — hooks are additive, so if ours fails
    // or times out the native prompt takes over. What these catch is the
    // quieter kind of damage: a contract we rely on shifting under us and the
    // buddy carrying on looking perfectly healthy while it stops being right.

    static var verifiedVersionURL: URL {
        dirURL.appendingPathComponent("verified_claude_version")
    }

    /// Cached because `claude --version` costs ~0.66s cold, and this runs on
    /// the main thread when the menu opens. Warmed in the background at
    /// launch; a nil cache just means the check hasn't got an answer yet.
    private static var cachedClaudeVersion: String??

    @discardableResult
    static func refreshClaudeVersion() -> String? {
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          FileManager.default.homeDirectoryForCurrentUser
                              .appendingPathComponent(".claude/local/claude").path]
        guard let binary = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            cachedClaudeVersion = .some(nil)
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else {
            cachedClaudeVersion = .some(nil)
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // "2.1.226 (Claude Code)" — take the version, drop the label.
        let text = String(data: data, encoding: .utf8) ?? ""
        let version = text.split(separator: " ").first.map(String.init)
        cachedClaudeVersion = .some(version)
        return version
    }

    /// Major.minor only. Claude Code ships patch releases constantly, and a
    /// check that cried wolf on every one of them would be trained away
    /// within a week. A minor bump is where the tool surface actually moves.
    private static func series(_ version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    static func markCurrentVersionVerified() {
        guard let current = cachedClaudeVersion ?? refreshClaudeVersion() else { return }
        try? series(current).write(to: verifiedVersionURL, atomically: true, encoding: .utf8)
    }

    private static func claudeVersionCheck() -> Check {
        let title = "Checked against this Claude Code"
        guard let current = cachedClaudeVersion ?? nil else {
            return Check(title: title, ok: true,
                         detail: "Skipped — couldn't read `claude --version`",
                         remedy: nil, optional: true)
        }
        let recorded = (try? String(contentsOf: verifiedVersionURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let recorded, !recorded.isEmpty else {
            // First run: record what we're looking at rather than nagging
            // about a comparison we've never had the chance to make.
            try? series(current).write(to: verifiedVersionURL, atomically: true, encoding: .utf8)
            return Check(title: title, ok: true, detail: "Claude Code \(current)", remedy: nil)
        }
        guard recorded != series(current) else {
            return Check(title: title, ok: true, detail: "Claude Code \(current)", remedy: nil)
        }
        return Check(
            title: title, ok: false,
            detail: "Claude Code moved \(recorded) → \(series(current)) since the buddy was last checked",
            remedy: "Nothing is broken — the other checks here still pass. But parts of "
                  + "the hook contract we rely on aren't documented, so this is worth "
                  + "a look after a version bump.",
            optional: true)
    }

    /// The transcripts are the buddy's other source of truth: token counts,
    /// and telling "a tool is running" from "Claude is thinking". Both read
    /// specific fields, and both fail quietly — the pet would just sit on
    /// idle forever rather than showing an error.
    private static func transcriptShapeCheck() -> Check {
        let title = "Transcripts still readable"
        guard let newest = newestTranscript() else {
            return Check(title: title, ok: true,
                         detail: "Skipped — no recent transcript to look at",
                         remedy: nil, optional: true)
        }
        guard let sample = lastAssistantRecord(in: newest) else {
            return Check(title: title, ok: false,
                         detail: "No parseable assistant record in \(newest.lastPathComponent)",
                         remedy: "Token counts and the working/thinking poses come from these "
                               + "files. Worth reporting if it persists.",
                         optional: true)
        }
        let message = sample["message"] as? [String: Any]
        let hasUsage = (message?["usage"] as? [String: Any])?["output_tokens"] is Int
        let hasContent = message?["content"] is [[String: Any]]
        guard hasUsage, hasContent else {
            var missing: [String] = []
            if !hasUsage { missing.append("message.usage.output_tokens (token counts)") }
            if !hasContent { missing.append("message.content[] (working vs thinking)") }
            return Check(title: title, ok: false,
                         detail: "Format changed — missing \(missing.joined(separator: ", "))",
                         remedy: "The buddy reads these directly; nothing warns when they move.",
                         optional: true)
        }
        return Check(title: title, ok: true,
                     detail: "\(newest.lastPathComponent) has the fields the buddy reads", remedy: nil)
    }

    /// Tools that ran without ever passing through the card. Most are
    /// read-only and belong here; the point is that a *new* one shows up in
    /// this list the first time you use it, instead of being discovered by
    /// noticing a card that never appeared.
    private static func ungatedToolsCheck() -> Check {
        let title = "Tools going around the card"
        // Read from the file UsageStats writes rather than calling into it:
        // everything in here inspects artifacts, which is what keeps these
        // checks runnable against fixtures instead of only against this Mac.
        let seenMap = (try? Data(contentsOf: dirURL.appendingPathComponent("seen_tools.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
        let seen = Set(seenMap.keys)
        guard !seen.isEmpty else {
            return Check(title: title, ok: true,
                         detail: "Skipped — no tool use recorded yet",
                         remedy: nil, optional: true)
        }
        let unwatched = seen
            .subtracting(expectedMatchers)
            .subtracting(deliberatelyUngated)
            .sorted()
        guard !unwatched.isEmpty else {
            return Check(title: title, ok: true,
                         detail: "Every tool you've used either routes through the card or reads only",
                         remedy: nil)
        }
        return Check(
            title: title, ok: false,
            detail: "Ran without a card: \(unwatched.joined(separator: ", "))",
            remedy: "If any of those should ask first, add it as a PreToolUse matcher "
                  + "alongside the others in ~/.claude/settings.json.",
            optional: true)
    }

    /// Tools we've looked at and decided don't need a card: they read, or they
    /// only touch the session's own bookkeeping. Agent is here because a
    /// subagent's own tool calls fire their own hooks — gating the spawn as
    /// well would ask twice for the same work.
    static let deliberatelyUngated: Set<String> = [
        "Read", "Glob", "Grep", "NotebookRead", "TodoWrite", "Task", "Agent",
        "Skill", "ToolSearch", "TaskOutput", "TaskStop", "SendMessage",
        "BashOutput", "KillShell", "SlashCommand",
    ]

    private static func newestTranscript() -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var newest: (URL, Date)?
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for url in files where url.pathExtension == "jsonl" {
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate else { continue }
                if newest == nil || mtime > newest!.1 { newest = (url, mtime) }
            }
        }
        return newest?.0
    }

    /// Reads backwards from the end rather than parsing the whole file —
    /// these run to tens of megabytes.
    private static func lastAssistantRecord(in url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 256 * 1024
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let tail = try? handle.readToEnd() else { return nil }
        let lines = tail.split(separator: 0x0A)
        for line in lines.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  obj["type"] as? String == "assistant" else { continue }
            return obj
        }
        return nil
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
