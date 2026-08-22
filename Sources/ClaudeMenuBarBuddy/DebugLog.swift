import Foundation

// The opt-in flight recorder: with CLAUDE_BUDDY_DEBUG=1 in the app's
// environment, the poll's decisions land in <config>/debug.log so that
// "the card didn't show" can be diagnosed after it happened, instead of by
// reconstructing the moment with selfies and injected requests. Without the
// flag nothing is opened, written or even formatted — the same promise the
// capture flags make, enforced by the same global gate.
//
// Lines carry metadata — event, tool, request id, project — never the
// command or diff being approved. The trace needs to say what HAPPENED to a
// request; its contents are already in the request file while it's alive
// and in decisions.jsonl once decided.
enum DebugLog {
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Appends one line. Rotation mirrors decisions.jsonl: one .1 file at
    /// ~1 MB — a bounded flight recorder, not an archive. `@autoclosure` so
    /// the interpolation isn't even built when the flag is off.
    static func note(_ event: @autoclosure () -> String) {
        guard debugCapturesEnabled else { return }
        let line = "\(stamp.string(from: Date())) \(event())\n"
        let url = dirURL.appendingPathComponent("debug.log")
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
               as? Int, size > 1_000_000 {
            let rotated = dirURL.appendingPathComponent("debug.1.log")
            try? FileManager.default.removeItem(at: rotated)
            try? FileManager.default.moveItem(at: url, to: rotated)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
