import Foundation

/// Turns opencode's unified patches into the card's mini-diff, the shape
/// `hook.sh` already writes for Claude: a path, then `--- quita` with what
/// each hunk removes and `+++ pone` with what it adds.
public enum UnifiedDiff {
    /// opencode's unified patches → the card's mini-diff ("--- quita" / "+++ pone" sections, as hook.sh writes them).
    public static func buddyHint(files: [String], patches: [String]) -> String {
        var lines: [String] = []
        for (index, file) in files.enumerated() {
            lines.append(file)
            guard index < patches.count else { continue }
            lines.append(contentsOf: sections(from: patches[index]))
        }
        return lines.joined(separator: "\n")
    }

    private static func sections(from patch: String) -> [String] {
        var lines: [String] = []
        var removed: [String] = []
        var added: [String] = []
        var insideHunk = false

        // One hunk at a time: the removed and added lines are kept together so
        // each hunk emits its own "quita"/"pone" pair, in the patch's order.
        func flush() {
            guard insideHunk else { return }
            if !removed.isEmpty {
                lines.append("--- quita")
                lines.append(contentsOf: removed)
            }
            if !added.isEmpty {
                lines.append("+++ pone")
                lines.append(contentsOf: added)
            }
            removed = []
            added = []
        }

        for line in patch.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") {
                flush()
                insideHunk = true
                continue
            }
            guard insideHunk else { continue }
            // The "--- file" / "+++ file" headers (and any "Index:"/"===="
            // preamble) are not content; the hunk body starts after "@@".
            if line.hasPrefix("---") || line.hasPrefix("+++") { continue }
            if line.hasPrefix("-") {
                removed.append(String(line.dropFirst()))
            } else if line.hasPrefix("+") {
                added.append(String(line.dropFirst()))
            }
        }
        flush()
        return lines
    }
}
