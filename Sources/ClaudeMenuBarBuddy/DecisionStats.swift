import AppKit

// A week of decisions, summarised for the Decision History submenu.
//
// The log is the source of truth, but it is an append-only megabyte and the
// menu opens often, so the window lives in memory: seeded once at launch from
// the log (and its one rotation), kept current by writeDecision, and pruned
// as it goes. Opening the menu then costs arithmetic over a few hundred
// structs instead of parsing the file again.
//
// A rolling window rather than day/week counters, deliberately: counters
// would have to notice when midnight happened and reset themselves, and one
// that quietly missed a rollover would report yesterday's number as today's
// forever. A window just forgets what fell off the back.

struct DecisionRecord {
    let ts: Double
    let tool: String
    let project: String
    let decision: String
}

/// Counts for one span. The four decisions are kept apart because they are
/// four different things — an answer to a question isn't an approval, and a
/// pass isn't a denial, it's the buddy declining to have an opinion.
struct DecisionSummary {
    var allowed = 0
    var denied = 0
    var passed = 0
    var answered = 0

    var isEmpty: Bool { allowed + denied + passed + answered == 0 }

    /// "12 allowed · 2 denied" — zero categories are left out entirely rather
    /// than shown as "0", which reads like a broken counter.
    var line: String {
        var parts: [String] = []
        if allowed > 0 { parts.append("\(allowed) allowed") }
        if denied > 0 { parts.append("\(denied) denied") }
        if passed > 0 { parts.append("\(passed) passed") }
        if answered > 0 { parts.append("\(answered) answered") }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " · ")
    }

    mutating func count(_ decision: String) {
        switch decision {
        case "allow": allowed += 1
        case "deny": denied += 1
        case "pass": passed += 1
        case "answer": answered += 1
        default: break
        }
    }
}

extension AppDelegate {
    /// How far back the window reaches. A week is the span that makes "am I
    /// approving more than usual?" answerable without the log becoming a
    /// dataset the app has to manage.
    var decisionWindow: TimeInterval { 7 * 24 * 60 * 60 }

    /// Reads the log and its rotation into the in-memory window. Off the main
    /// thread: up to two megabytes of JSON lines is not much, but it is not
    /// nothing either, and nothing on screen is waiting for it.
    func loadDecisionWindow() {
        let logURL = dirURL.appendingPathComponent("decisions.jsonl")
        let rotatedURL = dirURL.appendingPathComponent("decisions.1.jsonl")
        let cutoff = Date().timeIntervalSince1970 - decisionWindow
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var loaded: [DecisionRecord] = []
            // Oldest file first, so the merged array is already in order.
            for url in [rotatedURL, logURL] {
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    guard let record = Self.record(from: Data(line.utf8)), record.ts >= cutoff else { continue }
                    loaded.append(record)
                }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Anything writeDecision appended while this was reading is
                // already in the array and also on disk, so merging by hand
                // would double-count it. Dedupe on the timestamp, which is a
                // sub-millisecond Double taken per decision.
                var seen = Set(loaded.map { $0.ts })
                for record in self.recentDecisions where !seen.contains(record.ts) {
                    loaded.append(record)
                    seen.insert(record.ts)
                }
                self.recentDecisions = loaded.sorted { $0.ts < $1.ts }
            }
        }
    }

    static func record(from data: Data) -> DecisionRecord? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = obj["ts"] as? Double,
              let tool = obj["tool"] as? String,
              let decision = obj["decision"] as? String else { return nil }
        return DecisionRecord(ts: ts, tool: tool,
                              project: obj["project"] as? String ?? "", decision: decision)
    }

    func noteDecision(_ record: DecisionRecord) {
        recentDecisions.append(record)
        pruneDecisionWindow()
    }

    func pruneDecisionWindow() {
        let cutoff = Date().timeIntervalSince1970 - decisionWindow
        if let first = recentDecisions.first, first.ts < cutoff {
            recentDecisions.removeAll { $0.ts < cutoff }
        }
    }

    func summary(since cutoff: Double) -> DecisionSummary {
        var summary = DecisionSummary()
        for record in recentDecisions where record.ts >= cutoff { summary.count(record.decision) }
        return summary
    }

    /// The most frequent value of `field` over the window, with its count.
    /// Ties break on the name so the line doesn't flip between two equals
    /// every time the menu opens.
    func busiest(_ field: (DecisionRecord) -> String) -> (name: String, count: Int)? {
        var tally: [String: Int] = [:]
        for record in recentDecisions {
            let key = field(record)
            guard !key.isEmpty else { continue }
            tally[key, default: 0] += 1
        }
        guard let best = tally.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) else { return nil }
        return (best.key, best.value)
    }

    /// The summary rows that head the Decision History submenu. Empty when
    /// nothing has happened in a week — a header of zeroes is noise, and the
    /// "No decisions yet" row already says it.
    func decisionSummaryLines() -> [String] {
        pruneDecisionWindow()
        guard !recentDecisions.isEmpty else { return [] }
        let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        let today = summary(since: startOfToday)
        let week = summary(since: Date().timeIntervalSince1970 - decisionWindow)

        var lines: [String] = []
        if !today.isEmpty { lines.append("Today: \(today.line)") }
        lines.append("This week: \(week.line)")
        var trailing: [String] = []
        if let tool = busiest({ $0.tool }) { trailing.append("most asked \(tool.name) (\(tool.count))") }
        if let project = busiest({ $0.project }) { trailing.append("busiest \(project.name) (\(project.count))") }
        if !trailing.isEmpty { lines.append(trailing.joined(separator: " · ")) }
        return lines
    }

    /// Sibling of the selfie flags, for a header that renders in a menu and so
    /// can't be screenshotted: `touch ~/.config/claude-menubar-buddy/
    /// capture_stats` → decision_stats.txt, with the window size so a wrong
    /// answer can be told apart from a window that never loaded.
    func captureDecisionStatsIfRequested() {
        guard debugFlagIsSet("capture_stats") else { return }
        try? FileManager.default.removeItem(at: dirURL.appendingPathComponent("capture_stats"))
        let dump = (["window: \(recentDecisions.count) decisions"] + decisionSummaryLines())
            .joined(separator: "\n") + "\n"
        try? dump.write(to: dirURL.appendingPathComponent("decision_stats.txt"),
                        atomically: true, encoding: .utf8)
    }
}
