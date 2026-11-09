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

    @Test func autoLinesKeepTheirGrant() {
        let lines = DecisionHistory.parse(jsonLines: """
        {"ts":1,"agent":"claude","project":"p","cwd":"/p","tool":"Bash","hint":"python3 x.py","category":"ejecuta","grant":"session","session":"ses-a"}
        {"ts":2,"agent":"claude","project":"p","cwd":"/p","tool":"Edit","hint":"h","category":"edicion","grant":"auto","session":"ses-a"}
        {"ts":3,"agent":"claude","project":"p","cwd":"/p","tool":"sesión","hint":"encendida: Bash: ls","category":"concesion","grant":"concesion","session":"ses-a"}
        {"ts":4,"agent":"opencode","project":"p","cwd":"/p","tool":"edit","hint":"h","category":"edicion"}
        """, isAuto: true)
        #expect(lines == [
            HistoryLine(ts: 1, tool: "Bash", project: "p", decision: "allow", isAuto: true, grant: "session"),
            HistoryLine(ts: 2, tool: "Edit", project: "p", decision: "allow", isAuto: true, grant: "auto"),
            HistoryLine(ts: 3, tool: "sesión", project: "p", decision: "allow", isAuto: true, grant: "concesion"),
            HistoryLine(ts: 4, tool: "edit", project: "p", decision: "allow", isAuto: true),
        ])
    }

    @Test func humanLinesKeepTheirGrantToo() {
        let lines = DecisionHistory.parse(jsonLines: #"{"ts":5,"tool":"Bash","project":"p","decision":"allow","grant":"session","session":"ses-a"}"#,
                                          isAuto: false)
        #expect(lines == [HistoryLine(ts: 5, tool: "Bash", project: "p", decision: "allow", isAuto: false, grant: "session")])
    }

    /// Written as escapes on purpose: "\u{26A1}\u{FE0E}" is the ⚡︎ Menus.swift
    /// draws today, variation selector included.
    @Test func glyphs() {
        func line(isAuto: Bool, grant: String?, decision: String = "allow") -> HistoryLine {
            HistoryLine(ts: 1, tool: "Bash", project: "", decision: decision, isAuto: isAuto, grant: grant)
        }
        #expect(DecisionHistory.glyph(for: line(isAuto: true, grant: "session")) == "\u{21C9}")          // ⇉
        #expect(DecisionHistory.glyph(for: line(isAuto: true, grant: "auto")) == "\u{26A1}\u{FE0E}")
        #expect(DecisionHistory.glyph(for: line(isAuto: true, grant: nil)) == "\u{26A1}\u{FE0E}")       // old line
        #expect(DecisionHistory.glyph(for: line(isAuto: true, grant: "algo-nuevo")) == "\u{26A1}\u{FE0E}")
        #expect(DecisionHistory.glyph(for: line(isAuto: true, grant: "concesion")) == "\u{25E6}")        // ◦
    }

    /// Human lines keep the icons the menu gives them today, whatever their
    /// grant: the click that creates a grant writes a human "allow" with
    /// grant "session" in decisions.jsonl, and that is not a pass by grant.
    @Test func humanLinesHaveNoGlyphWhateverTheirGrant() {
        for grant in [nil, "session", "auto", "concesion"] as [String?] {
            for decision in ["allow", "deny", "pass"] {
                let human = HistoryLine(ts: 1, tool: "Bash", project: "", decision: decision, isAuto: false, grant: grant)
                #expect(DecisionHistory.glyph(for: human) == nil, "grant \(grant ?? "nil"), \(decision)")
            }
        }
    }
}
