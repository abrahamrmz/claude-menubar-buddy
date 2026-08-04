import Foundation

// Reads Claude Code's local session transcripts (~/.claude/projects/**/*.jsonl)
// to derive usage/status info. No network calls, no Claude Desktop API needed —
// these are the same JSONL files community dashboards like claude-usage read.

struct ActiveSession {
    var projectPath: String   // best-effort decoded folder path, for display + "reveal in Finder"
    var lastActivity: Date
}

struct UsageSnapshot {
    var tokensToday: Int = 0
    var activeSessions: [ActiveSession] = []
    var lastActivity: Date? = nil
    var fiveHourPct: Int? = nil
    var weeklyPct: Int? = nil
}

enum UsageReader {
    static let projectsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    // Claude Desktop writes its own plan-usage polling results here — same
    // numbers shown in its "Plan usage" panel (5-hour rolling limit, weekly
    // limit). "fh" = five-hour %, "sd" = seven-day (weekly) %.
    static let planUsageURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")

    static func readPlanUsage() -> (fiveHour: Int?, weekly: Int?) {
        guard let data = try? Data(contentsOf: planUsageURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = obj["samples"] as? [[String: Any]],
              let last = samples.last,
              let u = last["u"] as? [String: Any] else { return (nil, nil) }
        return (u["fh"] as? Int, u["sd"] as? Int)
    }

    /// Claude Code encodes a session's working directory into its project
    /// folder name by replacing "/" with "-" (e.g. a project at
    /// /Users/ray/Agent becomes a folder named "-Users-ray-Agent"). This is
    /// lossy if the real path itself contains "-", so treat the result as
    /// best-effort display text, not a guaranteed-correct path.
    static func decodeProjectFolderName(_ name: String) -> String {
        name.hasPrefix("-") ? "/" + name.dropFirst().replacingOccurrences(of: "-", with: "/") : name
    }

    /// Sums output_tokens from every `type: assistant` line whose message has
    /// a `usage` block, across every .jsonl file modified today. Streams each
    /// file line-by-line (FileHandle) rather than loading it fully into memory —
    /// these transcripts can be tens of MB.
    static func snapshot() -> UsageSnapshot {
        var result = UsageSnapshot()
        let fm = FileManager.default
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let now = Date()

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return result }

        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let projectPath = decodeProjectFolderName(projectDir.lastPathComponent)

            guard let files = try? fm.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for url in files {
                guard url.pathExtension == "jsonl" else { continue }
                guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let mtime = attrs.contentModificationDate else { continue }

                if mtime >= startOfToday {
                    result.tokensToday += sumOutputTokens(in: url, size: UInt64(attrs.fileSize ?? 0), mtime: mtime)
                }
                if now.timeIntervalSince(mtime) < 15 {
                    result.activeSessions.append(ActiveSession(projectPath: projectPath, lastActivity: mtime))
                }
                if result.lastActivity == nil || mtime > result.lastActivity! {
                    result.lastActivity = mtime
                }
            }
        }
        let plan = readPlanUsage()
        result.fiveHourPct = plan.fiveHour
        result.weeklyPct = plan.weekly
        return result
    }

    // Per-file token totals, so a snapshot() every ~5s costs a stat per file
    // instead of re-parsing every transcript touched today. Transcripts are
    // append-only JSONL, so on growth only the appended bytes are read.
    // Main-thread only (timer + menuWillOpen), hence the bare static var.
    private struct TokenCacheEntry {
        var size: UInt64
        var mtime: Date
        var offset: UInt64 // first byte after the last complete line counted
        var tokens: Int    // output tokens summed through `offset`
    }
    private static var tokenCacheByPath: [String: TokenCacheEntry] = [:]

    private static func sumOutputTokens(in url: URL, size: UInt64, mtime: Date) -> Int {
        let path = url.path
        if let cached = tokenCacheByPath[path], cached.size == size, cached.mtime == mtime {
            return cached.tokens
        }

        var total = 0
        var consumed: UInt64 = 0
        if let cached = tokenCacheByPath[path], size >= cached.offset {
            total = cached.tokens
            consumed = cached.offset
        } // else: shrunk/rotated file — full re-read from 0

        guard let handle = try? FileHandle(forReadingFrom: url) else { return total }
        defer { try? handle.close() }
        if consumed > 0 { try? handle.seek(toOffset: consumed) }

        var buffer = Data()
        let chunkSize = 1 << 20 // 1MB chunks

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                consumed += UInt64(newlineRange.upperBound - buffer.startIndex)
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                total += tokensFromLine(lineData)
            }
        }
        // The cache stops at the last complete line: a trailing partial line
        // is usually a record mid-write, so it's counted for this snapshot
        // but re-read (complete) on the next change.
        tokenCacheByPath[path] = TokenCacheEntry(size: size, mtime: mtime, offset: consumed, tokens: total)
        if !buffer.isEmpty { total += tokensFromLine(buffer) }
        return total
    }

    private static func tokensFromLine(_ data: Data) -> Int {
        // Cheap pre-filter before paying for full JSON parsing.
        guard let s = String(data: data, encoding: .utf8), s.contains("\"usage\"") else { return 0 }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let out = usage["output_tokens"] as? Int else { return 0 }
        return out
    }
}
