import Foundation

// How fast the 5-hour limit is being spent, and when it runs out at this
// pace. A percentage on its own tells you where you are; a slope tells you
// whether to keep going.
//
// Pure math only — the menu line, the notifications and the token-velocity
// fallback live in the app target (BurnRate.swift there), because they need
// AppKit and AppDelegate state. This half is here so `swift test` can hold
// it to the shapes real data produced (rollover, flat, recovering, short
// spread) without launching a menu bar app. `now` is a parameter with a
// default instead of a bare Date() for the same reason.

/// One reading of the plan limits, as Claude Desktop recorded it. The
/// history keeps ~100 of these at a ~15-minute cadence.
public struct PlanSample {
    public let date: Date
    public let fiveHour: Int
    public let weekly: Int

    public init(date: Date, fiveHour: Int, weekly: Int) {
        self.date = date
        self.fiveHour = fiveHour
        self.weekly = weekly
    }
}

public enum BurnRate {
    /// A drop this large between consecutive samples is the 5-hour window
    /// rolling over, not a measurement. Real data: 78% → 3% in nine minutes.
    /// Fitting across one of those would report a wildly negative slope.
    public static let resetDrop = 10

    /// Percentage points per hour, fit over samples from the last `window`
    /// seconds since the most recent rollover. nil when there isn't enough
    /// to say anything honest.
    public static func fiveHourSlope(from samples: [PlanSample],
                                     window: TimeInterval = 3600,
                                     now: Date = Date()) -> Double? {
        let cutoff = now.addingTimeInterval(-window)
        var recent = samples.filter { $0.date >= cutoff }
        // Keep only what's after the last rollover.
        if let lastReset = recent.indices.dropFirst().last(where: {
            recent[$0].fiveHour < recent[$0 - 1].fiveHour - resetDrop
        }) {
            recent = Array(recent[lastReset...])
        }
        guard recent.count >= 3,
              let first = recent.first, let last = recent.last,
              last.date.timeIntervalSince(first.date) >= 10 * 60 else { return nil }

        // Least squares on (hours since the first sample, percent).
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 3600 }
        let ys = recent.map { Double($0.fiveHour) }
        let n = Double(recent.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 1e-9 else { return nil }
        return (n * sumXY - sumX * sumY) / denominator
    }

    /// When `pct` reaches `target` at this slope. nil if it never will (flat
    /// or falling), or if it's already there.
    public static func projectedTime(pct: Int, target: Int, slope: Double,
                                     now: Date = Date()) -> Date? {
        guard slope > 0.5, pct < target else { return nil }
        let hours = Double(target - pct) / slope
        // Beyond a few hours the linear assumption is fiction — the 5-hour
        // window will have rolled long before then.
        guard hours <= 5 else { return nil }
        return now.addingTimeInterval(hours * 3600)
    }

    public static func formatClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
