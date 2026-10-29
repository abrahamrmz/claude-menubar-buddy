import Foundation

/// One line of a decision log, whichever log it came from.
///
/// Two files record what happened: `decisions.jsonl` is what you answered, and
/// `auto_decisions.jsonl` is what the rule let through without asking. The
/// history menu shows them together, newest first, so reading it tells the
/// story rather than half of it.
public struct HistoryLine: Equatable {
    public let ts: Double
    public let tool: String
    public let project: String
    /// "allow", "deny" or "pass" for human lines; always "allow" for auto
    /// lines, which is what the rule did to them.
    public let decision: String
    public let isAuto: Bool

    public init(ts: Double, tool: String, project: String, decision: String, isAuto: Bool) {
        self.ts = ts
        self.tool = tool
        self.project = project
        self.decision = decision
        self.isAuto = isAuto
    }
}

public enum DecisionHistory {
    /// Parses JSON-lines, skipping whatever isn't a usable record: a line cut
    /// in half by the tail read, a blank line, or one written by an older
    /// version without a timestamp. A malformed log shouldn't empty the menu.
    public static func parse(jsonLines: String, isAuto: Bool) -> [HistoryLine] {
        jsonLines.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = object["ts"] as? Double,
                  let tool = object["tool"] as? String else { return nil }
            return HistoryLine(ts: ts,
                               tool: tool,
                               project: object["project"] as? String ?? "",
                               decision: isAuto ? "allow" : object["decision"] as? String ?? "",
                               isAuto: isAuto)
        }
    }

    /// The newest `limit` lines across both logs.
    public static func latest(_ human: [HistoryLine], _ auto: [HistoryLine], limit: Int) -> [HistoryLine] {
        Array((human + auto).sorted { $0.ts > $1.ts }.prefix(limit))
    }
}
