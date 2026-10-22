import Foundation
import Testing
import BuddyCore

@Suite struct CardSafetyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func nonCriticalHotKeyWorksAtOnce() {
        #expect(CardSafety.hotKeyMayApprove(critical: false, shownAt: t0, now: t0))
        #expect(CardSafety.hotKeyMayApprove(critical: false, shownAt: nil, now: t0))
    }

    @Test func criticalHotKeyWaitsOneAndAHalfSeconds() {
        #expect(!CardSafety.hotKeyMayApprove(critical: true, shownAt: t0, now: t0.addingTimeInterval(0.5)))
        #expect(!CardSafety.hotKeyMayApprove(critical: true, shownAt: t0, now: t0.addingTimeInterval(1.49)))
        #expect(CardSafety.hotKeyMayApprove(critical: true, shownAt: t0, now: t0.addingTimeInterval(1.5)))
        #expect(!CardSafety.hotKeyMayApprove(critical: true, shownAt: nil, now: t0))
    }

    @Test func batchSkipsCritical() {
        let items = [("a", false), ("b", true), ("c", false)]
        #expect(CardSafety.batchAllowable(items, isCritical: { $0.1 }).map(\.0) == ["a", "c"])
    }
}
