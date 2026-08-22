import Foundation
import Testing
import BuddyCore

// The setup check's pure analyses. The wiring fixtures are the three failure
// modes 2.6 verified with throwaway configs; the anchor transitions and the
// around-the-card sweep are 2.7's harness, committed this time.
@Suite struct HealthPolicyTests {
    private func settings(_ json: String) -> Data { Data(json.utf8) }

    private func entry(matcher: String, command: String) -> String {
        #"{"matcher": "\#(matcher)", "hooks": [{"type": "command", "command": "\#(command)"}]}"#
    }

    private let ours = "/Users/x/.config/claude-menubar-buddy/hook.sh"

    private func config(entries: [String]) -> Data {
        settings(#"{"hooks": {"PreToolUse": [\#(entries.joined(separator: ", "))]}}"#)
    }

    // MARK: - Wiring: the three failure modes, plus the ones a refactor
    // would break quietly

    @Test func brokenJSONIsItsOwnDiagnosis() {
        #expect(HealthPolicy.wiring(settingsJSON: settings("{not json")) == .notJSON)
    }

    @Test func validConfigWithNoHooksIsNotWired() {
        #expect(HealthPolicy.wiring(settingsJSON: settings("{}")) == .notWired)
    }

    @Test func foreignHooksProveNothingAboutOurs() {
        // Somebody else's PreToolUse hook on the right matcher must not
        // count as our wiring — its presence proves nothing about the card.
        let json = config(entries: [entry(matcher: "Bash", command: "/somewhere/else/guard.sh")])
        #expect(HealthPolicy.wiring(settingsJSON: json) == .notWired)
    }

    @Test func partialWiringNamesWhatIsMissing() {
        let json = config(entries: [entry(matcher: "Bash", command: ours)])
        guard case .partial(let wired, let missing) = HealthPolicy.wiring(settingsJSON: json) else {
            Issue.record("expected .partial")
            return
        }
        #expect(wired == 1)
        #expect(missing.contains("Edit"))
        #expect(!missing.contains("Bash"))
    }

    @Test func aCombinedMatcherCountsAsEachOfItsTools() {
        // "Edit|Write" is two tools in one matcher; treating it as one
        // opaque string would report both as missing.
        let json = config(entries: [entry(matcher: "Edit|Write", command: ours)])
        guard case .partial(let wired, let missing) = HealthPolicy.wiring(settingsJSON: json) else {
            Issue.record("expected .partial")
            return
        }
        #expect(wired == 2)
        #expect(!missing.contains("Edit"))
        #expect(!missing.contains("Write"))
    }

    @Test func allNineWiredIsComplete() {
        let entries = HealthPolicy.expectedMatchers.map { entry(matcher: $0, command: ours) }
        #expect(HealthPolicy.wiring(settingsJSON: config(entries: entries))
                == .complete(count: HealthPolicy.expectedMatchers.count))
    }

    // MARK: - Transcript shape

    private func transcriptRecord(usage: Any?, content: Any?) -> [String: Any] {
        var message: [String: Any] = [:]
        if let usage { message["usage"] = usage }
        if let content { message["content"] = content }
        return ["type": "assistant", "message": message]
    }

    @Test func theShapeTheBuddyReadsPassesClean() {
        let record = transcriptRecord(usage: ["output_tokens": 42],
                                      content: [["type": "tool_use"]])
        #expect(HealthPolicy.missingTranscriptFields(in: record).isEmpty)
    }

    @Test func aMovedFieldIsNamedNotJustCounted() {
        let noUsage = transcriptRecord(usage: nil, content: [["type": "text"]])
        #expect(HealthPolicy.missingTranscriptFields(in: noUsage)
                == ["message.usage.output_tokens (token counts)"])

        // Content present but no longer an array of blocks: same failure as
        // absent — the working/thinking read walks blocks.
        let flatContent = transcriptRecord(usage: ["output_tokens": 1], content: "hello")
        #expect(HealthPolicy.missingTranscriptFields(in: flatContent)
                == ["message.content[] (working vs thinking)"])

        let empty: [String: Any] = ["type": "assistant"]
        #expect(HealthPolicy.missingTranscriptFields(in: empty).count == 2)
    }

    // MARK: - Tools going around the card

    @Test func aNewToolSurfacesTheFirstTimeItIsUsed() {
        // The AskUserQuestion/WebSearch class of problem: used, never carded,
        // and nothing anywhere said so until 2.7 started sweeping.
        let seen: Set<String> = ["Bash", "Read", "WebSearch", "BrandNewTool"]
        let unwatched = HealthPolicy.unwatchedTools(seen: seen,
                                                    gated: ["Bash"],
                                                    reviewed: ["Read"])
        #expect(unwatched == ["BrandNewTool", "WebSearch"])
    }

    @Test func fullyCoveredUsageReportsNothing() {
        let seen: Set<String> = ["Bash", "Edit", "Read", "Grep"]
        #expect(HealthPolicy.unwatchedTools(seen: seen).isEmpty)
    }

    // MARK: - Version anchor: the three transitions

    @Test func seriesIsMajorMinorOnly() {
        #expect(HealthPolicy.series("2.1.226") == "2.1")
        #expect(HealthPolicy.series("2.1") == "2.1")
    }

    @Test func theThreeAnchorTransitions() {
        #expect(HealthPolicy.versionAnchor(recorded: nil, current: "1.9.42") == .firstRun)
        #expect(HealthPolicy.versionAnchor(recorded: "", current: "1.9.42") == .firstRun)
        #expect(HealthPolicy.versionAnchor(recorded: "1.9", current: "1.9.77") == .verified)
        #expect(HealthPolicy.versionAnchor(recorded: "1.9", current: "2.1.0")
                == .moved(from: "1.9", to: "2.1"))
    }

    // MARK: - The lists themselves are policy

    @Test func theNineExpectedMatchersAreExactlyThese() {
        // Removing a matcher here silently un-wires a tool for every new
        // install — this pin makes that a red test instead of a quiet gap.
        #expect(HealthPolicy.expectedMatchers.sorted() == [
            "AskUserQuestion", "Bash", "Edit", "ExitPlanMode", "MultiEdit",
            "NotebookEdit", "WebFetch", "WebSearch", "Write",
        ])
    }

    @Test func noToolIsBothGatedAndDeliberatelyUngated() {
        // A tool on both lists is a contradiction: the sweep would excuse
        // what the wiring check demands.
        #expect(HealthPolicy.deliberatelyUngated.isDisjoint(with: HealthPolicy.expectedMatchers))
    }
}
