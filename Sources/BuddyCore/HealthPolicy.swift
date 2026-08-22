import Foundation

// The pure halves of the setup check (Health.swift in the app): given what
// was read from disk, what does it mean? Reading files, running
// `claude --version` and composing remedies with the user's paths stay in
// the app — these run against fixtures, which is what lets the tests keep
// the three failure modes of 2.6 and the anchor transitions of 2.7 instead
// of re-verifying them by hand after every change.
public enum HealthPolicy {
    /// Matchers SKILL.md wires up. The file-and-web tools are permission
    /// decisions; ExitPlanMode and AskUserQuestion are the card answering a
    /// question instead (a plan to accept three ways, and a multiple-choice
    /// ask). MultiEdit and WebSearch were the card's own blind spot for a
    /// while — both had an accent color and a fast path but no matcher, so
    /// their cards could never arrive.
    public static let expectedMatchers = ["Bash", "Write", "Edit", "MultiEdit",
                                          "WebFetch", "WebSearch", "NotebookEdit",
                                          "ExitPlanMode", "AskUserQuestion"]

    /// Tools we've looked at and decided don't need a card: they read, or they
    /// only touch the session's own bookkeeping. Agent is here because a
    /// subagent's own tool calls fire their own hooks — gating the spawn as
    /// well would ask twice for the same work.
    public static let deliberatelyUngated: Set<String> = [
        "Read", "Glob", "Grep", "NotebookRead", "TodoWrite", "Task", "Agent",
        "Skill", "ToolSearch", "TaskOutput", "TaskStop", "SendMessage",
        "BashOutput", "KillShell", "SlashCommand",
    ]

    // MARK: - Hook wiring

    public enum Wiring: Equatable {
        /// The file exists but Claude Code would ignore all of it.
        case notJSON
        /// Valid config, but no PreToolUse entry points at our hook.
        case notWired
        /// Some tools route through the card and some silently don't —
        /// the nastiest failure mode there is.
        case partial(wired: Int, missing: [String])
        case complete(count: Int)
    }

    /// Which of `expected` actually route through the hook whose command
    /// contains `hookMarker`. Hooks belonging to other tooling are ignored —
    /// their presence proves nothing about ours. One matcher can cover
    /// several tools ("Edit|Write" counts as two).
    public static func wiring(settingsJSON: Data,
                              expected: [String] = expectedMatchers,
                              hookMarker: String = "claude-menubar-buddy/hook.sh") -> Wiring {
        guard let root = try? JSONSerialization.jsonObject(with: settingsJSON) as? [String: Any] else {
            return .notJSON
        }
        let hooks = root["hooks"] as? [String: Any]
        let preToolUse = hooks?["PreToolUse"] as? [[String: Any]] ?? []
        var wired: [String] = []
        for entry in preToolUse {
            guard let matcher = entry["matcher"] as? String,
                  let commands = entry["hooks"] as? [[String: Any]] else { continue }
            let usesOurHook = commands.contains { command in
                guard let text = command["command"] as? String else { return false }
                return text.contains(hookMarker)
            }
            if usesOurHook { wired.append(contentsOf: matcher.split(separator: "|").map(String.init)) }
        }
        guard !wired.isEmpty else { return .notWired }
        let missing = expected.filter { !wired.contains($0) }
        return missing.isEmpty ? .complete(count: expected.count)
                               : .partial(wired: wired.count, missing: missing)
    }

    // MARK: - Transcript shape

    /// The transcript fields the buddy reads, named the way the check reports
    /// them: token counts need `message.usage.output_tokens`, and telling
    /// "a tool is running" from "Claude is thinking" needs `message.content[]`.
    /// Empty means the shape still holds.
    public static func missingTranscriptFields(in record: [String: Any]) -> [String] {
        let message = record["message"] as? [String: Any]
        let hasUsage = (message?["usage"] as? [String: Any])?["output_tokens"] is Int
        let hasContent = message?["content"] is [[String: Any]]
        var missing: [String] = []
        if !hasUsage { missing.append("message.usage.output_tokens (token counts)") }
        if !hasContent { missing.append("message.content[] (working vs thinking)") }
        return missing
    }

    // MARK: - Tools going around the card

    /// Tools that ran without a card and aren't on the reviewed list —
    /// the whole AskUserQuestion class of problem, caught the first time a
    /// new tool is used instead of by noticing a card that never appeared.
    public static func unwatchedTools(seen: Set<String>,
                                      gated: [String] = expectedMatchers,
                                      reviewed: Set<String> = deliberatelyUngated) -> [String] {
        seen.subtracting(gated).subtracting(reviewed).sorted()
    }

    // MARK: - Version anchor

    /// Major.minor only. Claude Code ships patch releases constantly, and a
    /// check that cried wolf on every one of them would be trained away
    /// within a week. A minor bump is where the tool surface actually moves.
    public static func series(_ version: String) -> String {
        version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    public enum VersionAnchor: Equatable {
        /// Nothing recorded yet: record what we're looking at rather than
        /// nagging about a comparison we've never had the chance to make.
        case firstRun
        /// Same series as the last one a human marked as reviewed.
        case verified
        case moved(from: String, to: String)
    }

    public static func versionAnchor(recorded: String?, current: String) -> VersionAnchor {
        let currentSeries = series(current)
        guard let recorded, !recorded.isEmpty else { return .firstRun }
        return recorded == currentSeries ? .verified : .moved(from: recorded, to: currentSeries)
    }
}
