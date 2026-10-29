import Testing
import BuddyCore

@Suite struct DecisionHistoryTests {
    @Test func parsesBothShapesAndSkipsJunk() {
        let human = DecisionHistory.parse(jsonLines: """
        {"ts":10,"tool":"Bash","project":"p","decision":"deny"}
        not json
        {"tool":"Bash"}
        """, isAuto: false)
        #expect(human == [HistoryLine(ts: 10, tool: "Bash", project: "p", decision: "deny", isAuto: false)])
        let auto = DecisionHistory.parse(jsonLines: #"{"ts":20,"agent":"claude","project":"q","cwd":"/q","tool":"Edit","hint":"h","category":"edicion"}"#, isAuto: true)
        #expect(auto == [HistoryLine(ts: 20, tool: "Edit", project: "q", decision: "allow", isAuto: true)])
    }

    @Test func latestMergesNewestFirstAndLimits() {
        let h = [HistoryLine(ts: 1, tool: "A", project: "", decision: "allow", isAuto: false),
                 HistoryLine(ts: 5, tool: "B", project: "", decision: "deny", isAuto: false)]
        let a = [HistoryLine(ts: 3, tool: "C", project: "", decision: "allow", isAuto: true)]
        #expect(DecisionHistory.latest(h, a, limit: 2).map(\.tool) == ["B", "C"])
    }
}
