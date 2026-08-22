import AppKit
import BuddyCore

// The window itself — records, prune, merge, the today/week summaries —
// lives in BuddyCore (`DecisionWindow`), under test. This file is the I/O
// around it: seeding from the log off the main thread, and the debug dump.
//
// The log is the source of truth, but it is an append-only megabyte and the
// menu opens often, so the window lives in memory: seeded once at launch
// from the log (and its one rotation), kept current by writeDecision, and
// pruned as it goes. Opening the menu then costs arithmetic over a few
// hundred structs instead of parsing the file again.

typealias DecisionRecord = BuddyCore.DecisionRecord

extension AppDelegate {
    /// Reads the log and its rotation into the in-memory window. Off the main
    /// thread: up to two megabytes of JSON lines is not much, but it is not
    /// nothing either, and nothing on screen is waiting for it.
    func loadDecisionWindow() {
        let logURL = dirURL.appendingPathComponent("decisions.jsonl")
        let rotatedURL = dirURL.appendingPathComponent("decisions.1.jsonl")
        let cutoff = Date().timeIntervalSince1970 - decisions.span
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var loaded: [DecisionRecord] = []
            // Oldest file first, so the merged array is already in order.
            for url in [rotatedURL, logURL] {
                guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    guard let record = DecisionRecord(json: Data(line.utf8)), record.ts >= cutoff else { continue }
                    loaded.append(record)
                }
            }
            DispatchQueue.main.async {
                self?.decisions.merge(seeded: loaded)
            }
        }
    }

    func noteDecision(_ record: DecisionRecord) {
        decisions.note(record)
    }

    func decisionSummaryLines() -> [String] {
        decisions.summaryLines()
    }

    /// Sibling of the selfie flags, for a header that renders in a menu and so
    /// can't be screenshotted: `touch ~/.config/claude-menubar-buddy/
    /// capture_stats` → decision_stats.txt, with the window size so a wrong
    /// answer can be told apart from a window that never loaded.
    func captureDecisionStatsIfRequested() {
        guard debugFlagIsSet("capture_stats") else { return }
        try? FileManager.default.removeItem(at: dirURL.appendingPathComponent("capture_stats"))
        let dump = (["window: \(decisions.records.count) decisions"] + decisionSummaryLines())
            .joined(separator: "\n") + "\n"
        try? dump.write(to: dirURL.appendingPathComponent("decision_stats.txt"),
                        atomically: true, encoding: .utf8)
    }
}
