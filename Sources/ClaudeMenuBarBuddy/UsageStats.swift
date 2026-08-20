import BuddyCore
import Foundation

// Reads Claude Code's local session transcripts (~/.claude/projects/**/*.jsonl)
// to derive usage/status info. No network calls, no Claude Desktop API needed —
// these are the same JSONL files community dashboards like claude-usage read.

struct ActiveSession {
    var projectPath: String   // best-effort decoded folder path, for display + "reveal in Finder"
    var lastActivity: Date
}

/// What a turn in flight is actually waiting on, per the last thing written
/// to its transcript. `tool` = Claude asked for a tool and the tool is
/// running; `model` = the last record was input FOR Claude (a tool result or
/// a prompt), so the model itself is what we're waiting on.
enum TurnActivity {
    case tool
    case model
}

struct UsageSnapshot {
    var tokensToday: Int = 0
    var activeSessions: [ActiveSession] = []
    var lastActivity: Date? = nil
    var fiveHourPct: Int? = nil
    var weeklyPct: Int? = nil
    // When Claude Desktop last sampled the plan limits. Only Claude Desktop
    // writes that file, so with Desktop closed the percentages freeze —
    // consumers must treat old samples as unknown, not as current truth.
    var planUsageDate: Date? = nil
    // Most recently written transcript, for the tail read that tells
    // thinking from working. Kept as url+size (both already stat'ed here) so
    // the read only happens when a turn is actually in flight.
    var newestTranscript: URL? = nil
    var newestTranscriptSize: UInt64 = 0
    // Recent plan-limit readings, for the burn-rate fit (see BurnRate.swift).
    var planSamples: [UsageReader.PlanSample] = []
}

enum UsageReader {
    static let projectsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    // Claude Desktop writes its own plan-usage polling results here — same
    // numbers shown in its "Plan usage" panel (5-hour rolling limit, weekly
    // limit). "fh" = five-hour %, "sd" = seven-day (weekly) %.
    static let planUsageURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")

    /// One reading of the plan limits, as Claude Desktop recorded it (the
    /// type lives in BuddyCore beside the burn-rate math that consumes it).
    /// The history keeps ~100 of these at a ~15-minute cadence.
    typealias PlanSample = BuddyCore.PlanSample

    /// The latest reading AND the recent samples, from ONE read of the file.
    /// Both come out of the same JSON and snapshot() runs every ~5s, so
    /// opening and parsing it twice per refresh was paying double for the
    /// same bytes. Samples are the last `within` seconds, oldest first —
    /// anything older is history no burn rate should be fitting through.
    static func readPlanHistory(within: TimeInterval = 3 * 3600)
        -> (fiveHour: Int?, weekly: Int?, sampled: Date?, samples: [PlanSample]) {
        guard let data = try? Data(contentsOf: planUsageURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = obj["samples"] as? [[String: Any]] else { return (nil, nil, nil, []) }

        let cutoff = Date().addingTimeInterval(-within)
        var recent: [PlanSample] = []
        for sample in samples {
            // "t" is epoch milliseconds.
            guard let t = sample["t"] as? Double,
                  let u = sample["u"] as? [String: Any],
                  let fh = u["fh"] as? Int else { continue }
            let date = Date(timeIntervalSince1970: t / 1000)
            guard date >= cutoff else { continue }
            recent.append(PlanSample(date: date, fiveHour: fh, weekly: u["sd"] as? Int ?? 0))
        }

        guard let last = samples.last, let u = last["u"] as? [String: Any] else {
            return (nil, nil, nil, recent.sorted { $0.date < $1.date })
        }
        let sampled = (last["t"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return (u["fh"] as? Int, u["sd"] as? Int, sampled, recent.sorted { $0.date < $1.date })
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
                    result.newestTranscript = url
                    result.newestTranscriptSize = UInt64(attrs.fileSize ?? 0)
                }
            }
        }
        let plan = readPlanHistory()
        result.fiveHourPct = plan.fiveHour
        result.weeklyPct = plan.weekly
        result.planUsageDate = plan.sampled
        result.planSamples = plan.samples
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

    // Tail-read cache: the answer can only change when the file grows, so a
    // long tool run costs one read instead of one per 5s refresh tick.
    private static var turnActivityCache: (path: String, size: UInt64, activity: TurnActivity?)?

    /// Reads the last complete record of a transcript to tell "a tool is
    /// running" from "Claude is thinking". Both look identical from the
    /// outside — the file goes quiet either way — but the record that went
    /// quiet says which one it is.
    static func turnActivity(in url: URL, size: UInt64) -> TurnActivity? {
        if let cached = turnActivityCache, cached.path == url.path, cached.size == size {
            return cached.activity
        }
        let activity = readTurnActivity(in: url, size: size)
        turnActivityCache = (url.path, size, activity)
        return activity
    }

    private static func readTurnActivity(in url: URL, size: UInt64) -> TurnActivity? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // 64KB is enough for several records but not for every tool result —
        // hence walking backwards until a line parses, rather than trusting
        // the last one.
        let window: UInt64 = 64 * 1024
        if size > window { try? handle.seek(toOffset: size - window) }
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }

        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true).reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            switch type {
            case "assistant":
                // A tool_use block as the newest record means Claude handed
                // off and is waiting — that's a tool running right now.
                let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                return content.contains { $0["type"] as? String == "tool_use" } ? .tool : .model
            case "user":
                // A prompt or a tool result — either way the ball is in the
                // model's court.
                return .model
            default:
                continue  // summaries, meta records: keep walking back
            }
        }
        return nil
    }

    private static func tokensFromLine(_ data: Data) -> Int {
        // Cheap pre-filter before paying for full JSON parsing.
        guard let s = String(data: data, encoding: .utf8), s.contains("\"usage\"") else { return 0 }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let out = usage["output_tokens"] as? Int else { return 0 }
        noteToolNames(in: message)
        return out
    }

    // MARK: - Which tools actually run

    /// Tool names seen in assistant records, and when each was first noticed.
    ///
    /// Harvested here because this line has already been read off disk and
    /// parsed for its token count — the marginal cost is walking an array
    /// that's in memory anyway. Scanning for this separately would mean
    /// re-reading ~95MB of transcripts, which is exactly the kind of thing
    /// this file's caches exist to avoid.
    ///
    /// The point is the setup check: a tool Claude Code starts asking
    /// permission for, that isn't in our matcher list, silently bypasses the
    /// card. AskUserQuestion did that for weeks. This is how the next one
    /// announces itself instead of being noticed by accident.
    /// Read back by BuddyHealth's "tools going around the card" check.
    private static var seenTools: [String: String] = loadSeenTools()

    private static var seenToolsURL: URL { dirURL.appendingPathComponent("seen_tools.json") }

    private static func loadSeenTools() -> [String: String] {
        guard let data = try? Data(contentsOf: seenToolsURL),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return map
    }

    private static func noteToolNames(in message: [String: Any]) {
        guard let content = message["content"] as? [[String: Any]] else { return }
        var added = false
        for block in content where block["type"] as? String == "tool_use" {
            guard let name = block["name"] as? String, seenTools[name] == nil else { continue }
            seenTools[name] = ISO8601DateFormatter().string(from: Date())
            added = true
        }
        // Written only when a name shows up for the first time, which happens
        // a handful of times in the life of an install — not on every parse.
        guard added,
              let data = try? JSONSerialization.data(
                withJSONObject: seenTools, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: seenToolsURL, options: [.atomic])
    }
}
