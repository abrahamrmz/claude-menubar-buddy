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
    /// The grant field exactly as the line carries it. An auto line without
    /// the field predates session grants and counts as "auto".
    public let grant: String?

    public init(ts: Double, tool: String, project: String, decision: String, isAuto: Bool,
                grant: String? = nil) {
        self.ts = ts
        self.tool = tool
        self.project = project
        self.decision = decision
        self.isAuto = isAuto
        self.grant = grant
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
                               isAuto: isAuto,
                               grant: object["grant"] as? String)
        }
    }

    /// The newest `limit` lines across both logs.
    public static func latest(_ human: [HistoryLine], _ auto: [HistoryLine], limit: Int) -> [HistoryLine] {
        Array((human + auto).sorted { $0.ts > $1.ts }.prefix(limit))
    }
}

extension DecisionHistory {
    /// The glyph for an auto line, by how it passed. Human lines get nil,
    /// whatever their grant: the menu gives them their own icons, and the
    /// click that creates a grant is a human "allow" with grant "session"
    /// that is not a pass by grant.
    public static func glyph(for line: HistoryLine) -> String? {
        guard line.isAuto else { return nil }
        switch line.grant {
        case "session": return "\u{21C9}"
        case "concesion": return "\u{25E6}"
        default: return "\u{26A1}\u{FE0E}"
        }
    }
}
