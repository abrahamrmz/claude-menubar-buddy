import AppKit
import BuddyCore

// The burn line in the menu and its notifications. The math itself
// (BurnRate.fiveHourSlope, projectedTime) lives in BuddyCore, where
// `swift test` holds it to the shapes real data produced — rollover,
// flat, recovering, short spread.
//
// Two sources, in order of preference:
//   1. Claude Desktop's own plan-usage samples — a real % against the real
//      limit, so the projection means something. Requires Desktop running.
//   2. Output tokens from local transcripts — always available, but it can
//      only say "you're spending quickly", never "you'll hit 90% at 16:40",
//      because nothing local knows what the limit is.

extension AppDelegate {
    /// Output tokens per hour, from the in-memory ring buffer of
    /// (sampled-at, tokens-today) pairs — the fallback when Claude Desktop
    /// isn't around to write real percentages.
    func recordTokenVelocitySample() {
        let now = Date()
        // 5s refresh would pile up 1,400 entries over the window; a minute
        // apart is plenty to measure an hourly rate.
        if let last = velocitySamples.last, now.timeIntervalSince(last.date) < 60 { return }
        // "Tokens today" resets at midnight, and a session transcript can be
        // deleted — either way a drop means the baseline is gone, not that
        // tokens were un-spent.
        if let last = velocitySamples.last, usage.tokensToday < last.tokens {
            velocitySamples.removeAll()
        }
        velocitySamples.append((now, usage.tokensToday))
        let cutoff = now.addingTimeInterval(-2 * 3600)
        velocitySamples.removeAll { $0.date < cutoff }
    }

    func tokenVelocityPerHour() -> Int? {
        guard let first = velocitySamples.first, let last = velocitySamples.last else { return nil }
        let hours = last.date.timeIntervalSince(first.date) / 3600
        guard hours >= 10.0 / 60.0 else { return nil }  // at least 10 minutes of history
        let delta = last.tokens - first.tokens
        guard delta > 0 else { return nil }
        return Int(Double(delta) / hours)
    }

    /// The "Burn:" line in the menu, plus the projected-limit notifications.
    func updateBurnLine() {
        let stale = planUsageIsStale
        let pct = usage.fiveHourPct

        if !stale, let pct = pct, let slope = BurnRate.fiveHourSlope(from: usage.planSamples) {
            checkProjectionNotifications(pct: pct, slope: slope)
            var text: String
            if slope >= 0.5 {
                text = String(format: "Burn: ▲ %.0f%%/h", slope)
                if let eta = BurnRate.projectedTime(pct: pct, target: 90, slope: slope) {
                    text += " · 90% ≈ \(BurnRate.formatClock(eta))"
                }
            } else if slope <= -0.5 {
                // The rolling window is giving budget back faster than it's
                // being spent.
                text = String(format: "Burn: ▼ %.0f%%/h recovering", -slope)
            } else {
                text = "Burn: — steady"
            }
            setBurnLine(text, color: slope >= 8 ? .systemOrange : .secondaryLabelColor)
            return
        }

        // No usable percentages: say how fast tokens are going out, and be
        // explicit that this can't become a projection.
        if let velocity = tokenVelocityPerHour() {
            setBurnLine("Burn: ~\(formatTokens(velocity)) tok/h" + (stale ? " (plan % stale)" : ""),
                        color: .secondaryLabelColor)
        } else if !velocitySamples.isEmpty {
            // A rate needs ~10 minutes of history. Say so, rather than
            // showing a dash that reads as "broken" after every restart.
            setBurnLine("Burn: measuring…", color: .tertiaryLabelColor)
        } else {
            setBurnLine("Burn: —", color: .tertiaryLabelColor)
        }
    }

    private func setBurnLine(_ text: String, color: NSColor) {
        burnLineItem.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: color,
                         .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
        )
    }

    /// Warns once per 5-hour window that the CURRENT pace lands on 75% (and
    /// again on 90%) within the hour — early enough to change course, which
    /// is the whole point of a projection over a threshold you've already
    /// crossed.
    private func checkProjectionNotifications(pct: Int, slope: Double) {
        // A rollover resets the warnings along with the budget.
        if pct < lastProjectionPct - BurnRate.resetDrop {
            notifiedProjection = 0
        }
        lastProjectionPct = pct

        for target in [75, 90] where target > notifiedProjection {
            guard let eta = BurnRate.projectedTime(pct: pct, target: target, slope: slope),
                  eta.timeIntervalSinceNow <= 3600 else { continue }
            notifiedProjection = target
            sendNotification(
                title: "Claude 5-hour limit heading for \(target)%",
                body: String(format: "At %.0f%%/h you'd hit %d%% around %@ (now %d%%).",
                             slope, target, BurnRate.formatClock(eta), pct))
            // The pet says the short version of the same warning.
            showSpeechBubble("⏳ \(target)% ≈ \(BurnRate.formatClock(eta))")
        }
    }
}
