import Foundation

// A week of decisions, summarised for the Decision History submenu.
//
// A rolling window rather than day/week counters, deliberately: counters
// would have to notice when midnight happened and reset themselves, and one
// that quietly missed a rollover would report yesterday's number as today's
// forever. A window just forgets what fell off the back.
//
// Pure on purpose: the app owns reading the log and the dispatch queues;
// this owns what the numbers mean. `now` and `calendar` are injectable so
// the tests can put midnight wherever the case needs it.

public struct DecisionRecord {
    public let ts: Double
    public let tool: String
    public let project: String
    public let decision: String

    public init(ts: Double, tool: String, project: String, decision: String) {
        self.ts = ts
        self.tool = tool
        self.project = project
        self.decision = decision
    }

    /// One line of decisions.jsonl. Tolerant of extra fields (host, answers,
    /// reason — the log gains fields as features land) but strict about the
    /// three that make a record countable.
    public init?(json data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = obj["ts"] as? Double,
              let tool = obj["tool"] as? String,
              let decision = obj["decision"] as? String else { return nil }
        self.init(ts: ts, tool: tool,
                  project: obj["project"] as? String ?? "", decision: decision)
    }
}

/// Counts for one span. The four decisions are kept apart because they are
/// four different things — an answer to a question isn't an approval, and a
/// pass isn't a denial, it's the buddy declining to have an opinion.
public struct DecisionSummary {
    public var allowed = 0
    public var denied = 0
    public var passed = 0
    public var answered = 0

    public init() {}

    public var isEmpty: Bool { allowed + denied + passed + answered == 0 }

    /// "12 allowed · 2 denied" — zero categories are left out entirely rather
    /// than shown as "0", which reads like a broken counter.
    public var line: String {
        var parts: [String] = []
        if allowed > 0 { parts.append("\(allowed) allowed") }
        if denied > 0 { parts.append("\(denied) denied") }
        if passed > 0 { parts.append("\(passed) passed") }
        if answered > 0 { parts.append("\(answered) answered") }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " · ")
    }

    public mutating func count(_ decision: String) {
        switch decision {
        case "allow": allowed += 1
        case "deny": denied += 1
        case "pass": passed += 1
        case "answer": answered += 1
        default: break
        }
    }
}

public struct DecisionWindow {
    /// How far back the window reaches. A week is the span that makes "am I
    /// approving more than usual?" answerable without the log becoming a
    /// dataset the app has to manage.
    public let span: TimeInterval

    public private(set) var records: [DecisionRecord] = []

    public init(span: TimeInterval = 7 * 24 * 60 * 60) {
        self.span = span
    }

    public mutating func note(_ record: DecisionRecord, now: Date = Date()) {
        records.append(record)
        prune(now: now)
    }

    public mutating func prune(now: Date = Date()) {
        let cutoff = now.timeIntervalSince1970 - span
        if let first = records.first, first.ts < cutoff {
            records.removeAll { $0.ts < cutoff }
        }
    }

    /// Replaces the window with what the seed read from disk, keeping any
    /// record noted live while the read was in flight. Those are already in
    /// the seed too (writeDecision appends to the same file the seed reads),
    /// so the merge dedupes on the timestamp — a sub-millisecond Double
    /// taken per decision.
    public mutating func merge(seeded: [DecisionRecord]) {
        var merged = seeded
        var seen = Set(seeded.map { $0.ts })
        for record in records where !seen.contains(record.ts) {
            merged.append(record)
            seen.insert(record.ts)
        }
        records = merged.sorted { $0.ts < $1.ts }
    }

    public func summary(since cutoff: Double) -> DecisionSummary {
        var summary = DecisionSummary()
        for record in records where record.ts >= cutoff { summary.count(record.decision) }
        return summary
    }

    /// The most frequent value of `field` over the window, with its count.
    /// Ties break on the name so the line doesn't flip between two equals
    /// every time the menu opens.
    public func busiest(_ field: (DecisionRecord) -> String) -> (name: String, count: Int)? {
        var tally: [String: Int] = [:]
        for record in records {
            let key = field(record)
            guard !key.isEmpty else { continue }
            tally[key, default: 0] += 1
        }
        guard let best = tally.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }) else { return nil }
        return (best.key, best.value)
    }

    /// The summary rows that head the Decision History submenu. Empty when
    /// nothing has happened in a week — a header of zeroes is noise, and the
    /// "No decisions yet" row already says it. Mutating because it prunes
    /// first: a row about "this week" computed over a stale window would
    /// count what already fell off the back.
    public mutating func summaryLines(now: Date = Date(),
                                      calendar: Calendar = .current) -> [String] {
        prune(now: now)
        guard !records.isEmpty else { return [] }
        let startOfToday = calendar.startOfDay(for: now).timeIntervalSince1970
        let today = summary(since: startOfToday)
        let week = summary(since: now.timeIntervalSince1970 - span)

        var lines: [String] = []
        if !today.isEmpty { lines.append("Today: \(today.line)") }
        lines.append("This week: \(week.line)")
        var trailing: [String] = []
        if let tool = busiest({ $0.tool }) { trailing.append("most asked \(tool.name) (\(tool.count))") }
        if let project = busiest({ $0.project }) { trailing.append("busiest \(project.name) (\(project.count))") }
        if !trailing.isEmpty { lines.append(trailing.joined(separator: " · ")) }
        return lines
    }
}
