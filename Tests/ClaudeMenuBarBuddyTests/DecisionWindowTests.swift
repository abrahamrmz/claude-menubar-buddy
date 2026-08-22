import Foundation
import Testing
import BuddyCore

// The rolling week of decisions behind the Decision History header. These
// pin the reasoning 6.1 documented but never tested: the midnight cut, the
// window forgetting what falls off the back, and the seed/live merge that
// must not double-count.
@Suite struct DecisionWindowTests {
    // UTC + epochs aligned to whole days, so "midnight" is where the test
    // says it is, not where the machine running the suite happens to be.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let day = 86_400.0
    private var todayStart: Double { day * 20_000 }
    private var noon: Date { Date(timeIntervalSince1970: todayStart + 12 * 3600) }

    private func record(ts: Double, tool: String = "Bash",
                        project: String = "api", decision: String = "allow") -> DecisionRecord {
        DecisionRecord(ts: ts, tool: tool, project: project, decision: decision)
    }

    @Test func midnightSeparatesTodayFromYesterday() {
        var window = DecisionWindow()
        window.note(record(ts: todayStart - 60), now: noon)   // yesterday 23:59
        window.note(record(ts: todayStart + 60), now: noon)   // today 00:01
        let lines = window.summaryLines(now: noon, calendar: utc)
        #expect(lines.first == "Today: 1 allowed")
        #expect(lines.dropFirst().first == "This week: 2 allowed")
    }

    @Test func theWindowForgetsWhatFellOffTheBack() {
        var window = DecisionWindow()
        window.note(record(ts: noon.timeIntervalSince1970 - 8 * day), now: noon)
        window.note(record(ts: noon.timeIntervalSince1970 - 60), now: noon)
        #expect(window.records.count == 1)
        #expect(window.records.first?.ts == noon.timeIntervalSince1970 - 60)
    }

    @Test func aRecordExactlyAtTheBoundarySurvives() {
        var window = DecisionWindow()
        window.note(record(ts: noon.timeIntervalSince1970 - window.span), now: noon)
        window.prune(now: noon)
        #expect(window.records.count == 1)
    }

    @Test func mergeDedupesOnTimestampAndSorts() {
        // The seed read the log while two live decisions landed; both are in
        // the file the seed read AND in the live window. Counting them twice
        // is the bug the dedup exists for.
        var window = DecisionWindow()
        window.note(record(ts: todayStart + 100), now: noon)
        window.note(record(ts: todayStart + 200), now: noon)
        window.merge(seeded: [record(ts: todayStart - 500), record(ts: todayStart + 100),
                              record(ts: todayStart + 200)])
        #expect(window.records.map(\.ts) == [todayStart - 500, todayStart + 100, todayStart + 200])
    }

    @Test func mergeKeepsALiveRecordTheSeedMissed() {
        // The race the other way: a decision written after the seed's read
        // finished must survive the replacement.
        var window = DecisionWindow()
        window.note(record(ts: todayStart + 300), now: noon)
        window.merge(seeded: [record(ts: todayStart + 100)])
        #expect(window.records.map(\.ts) == [todayStart + 100, todayStart + 300])
    }

    @Test func theFourDecisionsAreFourDifferentThings() {
        var window = DecisionWindow()
        for decision in ["allow", "allow", "deny", "pass", "answer", "unknown"] {
            window.note(record(ts: todayStart + Double(window.records.count),
                               decision: decision), now: noon)
        }
        let summary = window.summary(since: 0)
        #expect(summary.allowed == 2)
        #expect(summary.denied == 1)
        #expect(summary.passed == 1)
        #expect(summary.answered == 1)
    }

    @Test func zeroCategoriesAreLeftOutOfTheLine() {
        var summary = DecisionSummary()
        summary.count("deny")
        #expect(summary.line == "1 denied")
        #expect(DecisionSummary().line == "nothing yet")
    }

    @Test func busiestBreaksTiesOnTheNameNotOnLuck() {
        var window = DecisionWindow()
        window.note(record(ts: todayStart + 1, tool: "zsh"), now: noon)
        window.note(record(ts: todayStart + 2, tool: "awk"), now: noon)
        #expect(window.busiest({ $0.tool })?.name == "awk")
    }

    @Test func emptyProjectsDoNotCompeteForBusiest() {
        var window = DecisionWindow()
        window.note(record(ts: todayStart + 1, project: ""), now: noon)
        #expect(window.busiest({ $0.project }) == nil)
    }

    @Test func anEmptyWindowHasNoHeader() {
        var window = DecisionWindow()
        #expect(window.summaryLines(now: noon, calendar: utc).isEmpty)
    }

    @Test func todayLineIsOmittedWhenTodayIsEmpty() {
        var window = DecisionWindow()
        window.note(record(ts: todayStart - 3600), now: noon)   // yesterday only
        let lines = window.summaryLines(now: noon, calendar: utc)
        #expect(lines.first == "This week: 1 allowed")
    }

    @Test func recordParsingIsTolerantOfExtrasStrictOnEssentials() {
        let full = #"{"ts": 100.5, "tool": "Bash", "project": "api", "decision": "allow", "host": "vscode"}"#
        let record = DecisionRecord(json: Data(full.utf8))
        #expect(record?.tool == "Bash")
        #expect(record?.project == "api")

        let noProject = #"{"ts": 100.5, "tool": "Bash", "decision": "allow"}"#
        #expect(DecisionRecord(json: Data(noProject.utf8))?.project == "")

        let noDecision = #"{"ts": 100.5, "tool": "Bash"}"#
        #expect(DecisionRecord(json: Data(noDecision.utf8)) == nil)

        #expect(DecisionRecord(json: Data("not json".utf8)) == nil)
    }
}
