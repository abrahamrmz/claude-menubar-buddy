import Foundation
import Testing
import BuddyCore

// The shapes real plan-usage data produced during Fase 1.5, held for good
// this time: the throwaway harness that first verified them is exactly what
// Fase 7.1 exists to stop doing. Every test pins `now` so nothing here
// depends on when it runs.
//
// Swift Testing rather than XCTest: this project builds with bare Command
// Line Tools on purpose, which ship Testing.framework but no macOS XCTest.
struct BurnRateTests {
    // A fixed anchor; samples are placed relative to it.
    private let now = Date(timeIntervalSince1970: 1_755_600_000)

    /// minutesAgo: 30 means "a sample taken half an hour before `now`".
    private func sample(minutesAgo: Double, pct: Int) -> PlanSample {
        PlanSample(date: now.addingTimeInterval(-minutesAgo * 60), fiveHour: pct, weekly: 0)
    }

    private func slope(_ samples: [PlanSample]) -> Double? {
        BurnRate.fiveHourSlope(from: samples, now: now)
    }

    // MARK: - The rollover, the bug the math exists to avoid

    /// The real 4-aug data: 78% → 3% in nine minutes is the window rolling
    /// over, not usage falling. A fit across it reports a wildly negative
    /// slope; the cut must discard everything before the drop.
    @Test func rolloverIsCutBeforeFitting() throws {
        let climbAfterReset = [
            sample(minutesAgo: 30, pct: 3),
            sample(minutesAgo: 20, pct: 9),
            sample(minutesAgo: 10, pct: 15),
            sample(minutesAgo: 0, pct: 21),
        ]
        let withRolloverInView = [
            sample(minutesAgo: 50, pct: 70),
            sample(minutesAgo: 40, pct: 78),
        ] + climbAfterReset

        let clean = try #require(slope(climbAfterReset))
        let cut = try #require(slope(withRolloverInView))
        // Identical, not merely close: only possible if the pre-reset
        // samples were discarded entirely rather than down-weighted.
        #expect(clean == cut)
        // 6 points per 10 minutes = 36 %/h.
        #expect(abs(clean - 36) < 0.01)
    }

    /// A drop of exactly `resetDrop` (10) is NOT a reset — the threshold is
    /// strictly greater. Real percentages jitter; only a cliff counts.
    @Test func smallDropIsNotARollover() throws {
        let jittery = [
            sample(minutesAgo: 30, pct: 40),
            sample(minutesAgo: 20, pct: 30),  // -10: jitter, keeps fitting
            sample(minutesAgo: 10, pct: 45),
            sample(minutesAgo: 0, pct: 50),
        ]
        // The fit sees all four samples; with only the post-drop three the
        // slope would be 60 %/h, with all four it is much lower.
        let fitted = try #require(slope(jittery))
        #expect(fitted < 45)
    }

    /// Two resets in view: the cut is at the LAST one.
    @Test func cutHappensAtTheLastRollover() throws {
        let twoResets = [
            sample(minutesAgo: 55, pct: 80),
            sample(minutesAgo: 50, pct: 2),   // reset 1
            sample(minutesAgo: 40, pct: 40),
            sample(minutesAgo: 30, pct: 1),   // reset 2
            sample(minutesAgo: 20, pct: 5),
            sample(minutesAgo: 10, pct: 9),
            sample(minutesAgo: 0, pct: 13),
        ]
        // Post-reset-2 climb: 4 points per 10 minutes = 24 %/h.
        let fitted = try #require(slope(twoResets))
        #expect(abs(fitted - 24) < 0.01)
    }

    // MARK: - Ordinary shapes

    @Test func steadyClimb() throws {
        // 1 point per 5 minutes = 12 %/h, on a perfectly linear climb.
        let climb = stride(from: 0, through: 30, by: 5).map {
            sample(minutesAgo: 30 - Double($0), pct: 40 + $0 / 5)
        }
        let fitted = try #require(slope(climb))
        #expect(abs(fitted - 12) < 0.01)
    }

    @Test func flatIsZero() throws {
        let flat = [
            sample(minutesAgo: 30, pct: 42),
            sample(minutesAgo: 15, pct: 42),
            sample(minutesAgo: 0, pct: 42),
        ]
        let fitted = try #require(slope(flat))
        #expect(abs(fitted) < 0.01)
    }

    /// The rolling window giving budget back gradually (no cliff) is a real
    /// negative slope, not a rollover — "▼ recovering" in the menu.
    @Test func gentleRecoveryIsNegative() throws {
        let recovering = [
            sample(minutesAgo: 30, pct: 60),
            sample(minutesAgo: 20, pct: 57),
            sample(minutesAgo: 10, pct: 54),
            sample(minutesAgo: 0, pct: 51),
        ]
        let fitted = try #require(slope(recovering))
        #expect(abs(fitted - (-18)) < 0.01)
    }

    // MARK: - When the honest answer is "can't say"

    @Test func tooFewSamplesIsNil() {
        #expect(slope([
            sample(minutesAgo: 20, pct: 10),
            sample(minutesAgo: 0, pct: 20),
        ]) == nil)
    }

    /// Three samples but only 5 minutes of spread — too short to mean
    /// anything (the 10-minute floor).
    @Test func shortSpreadIsNil() {
        #expect(slope([
            sample(minutesAgo: 5, pct: 10),
            sample(minutesAgo: 2.5, pct: 12),
            sample(minutesAgo: 0, pct: 14),
        ]) == nil)
    }

    /// Samples older than the window are excluded BEFORE counting: plenty of
    /// history, none of it recent, is still "can't say".
    @Test func staleSamplesOutsideWindowAreNil() {
        let old = stride(from: 0, to: 10, by: 1).map {
            sample(minutesAgo: 120 + Double($0) * 10, pct: 10 + $0)
        }
        #expect(slope(old) == nil)
    }

    /// A rollover as the second-to-last sample leaves fewer than 3 points
    /// after the cut — nil, not a fit through the cliff.
    @Test func rolloverTooRecentToFitIsNil() {
        #expect(slope([
            sample(minutesAgo: 40, pct: 70),
            sample(minutesAgo: 30, pct: 78),
            sample(minutesAgo: 10, pct: 3),
            sample(minutesAgo: 0, pct: 6),
        ]) == nil)
    }

    // MARK: - projectedTime's caps

    @Test func projectionArithmetic() throws {
        // 60% now, +10 %/h → 90% in three hours.
        let eta = try #require(BurnRate.projectedTime(pct: 60, target: 90, slope: 10, now: now))
        #expect(abs(eta.timeIntervalSince(now) - 3 * 3600) < 1)
    }

    @Test func flatOrFallingNeverProjects() {
        #expect(BurnRate.projectedTime(pct: 60, target: 90, slope: 0.5, now: now) == nil)
        #expect(BurnRate.projectedTime(pct: 60, target: 90, slope: -3, now: now) == nil)
    }

    /// Beyond 5 hours the 5-hour window will have rolled — projecting there
    /// is fiction, so it must be nil rather than a confident wrong clock.
    @Test func farFutureProjectionIsNil() {
        #expect(BurnRate.projectedTime(pct: 10, target: 90, slope: 1, now: now) == nil)
    }

    @Test func alreadyAtTargetIsNil() {
        #expect(BurnRate.projectedTime(pct: 90, target: 90, slope: 10, now: now) == nil)
        #expect(BurnRate.projectedTime(pct: 95, target: 90, slope: 10, now: now) == nil)
    }
}
