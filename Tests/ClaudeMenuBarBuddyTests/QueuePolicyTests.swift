import Testing
import BuddyCore

// The queue's ordering rule decides what ⌘⏎ answers. These tests pin the
// three promises: oldest first (deterministically, even on timestamp ties),
// a pick jumps to the front and survives, and a dead pin lets go.
@Suite struct QueuePolicyTests {
    struct Req {
        let id: String
        let ts: Double?
    }

    private func ordered(_ items: [Req], pinned: String? = nil) -> (items: [Req], pinned: String?) {
        QueuePolicy.ordered(items, id: { $0.id }, ts: { $0.ts }, pinned: pinned)
    }

    @Test func oldestFirstRegardlessOfScanOrder() {
        let scan = [Req(id: "c", ts: 300), Req(id: "a", ts: 100), Req(id: "b", ts: 200)]
        #expect(ordered(scan).items.map(\.id) == ["a", "b", "c"])
    }

    @Test func missingTimestampSortsAsOldest() {
        // A request without ts (legacy hook) must not jump the line the
        // other way: nil counts as 0, i.e. older than everything real.
        let scan = [Req(id: "real", ts: 1000), Req(id: "legacy", ts: nil)]
        #expect(ordered(scan).items.map(\.id) == ["legacy", "real"])
    }

    @Test func timestampTiesAreDeterministic() {
        // Two requests in the same instant: both scan orders must produce
        // the same front id, or poll() would flicker between two cards.
        let ab = ordered([Req(id: "a", ts: 100), Req(id: "b", ts: 100)]).items.map(\.id)
        let ba = ordered([Req(id: "b", ts: 100), Req(id: "a", ts: 100)]).items.map(\.id)
        #expect(ab == ba)
        #expect(ab == ["a", "b"])
    }

    @Test func pinnedJumpsToFrontAndTheRestKeepAgeOrder() {
        let scan = [Req(id: "a", ts: 100), Req(id: "b", ts: 200), Req(id: "c", ts: 300)]
        let result = ordered(scan, pinned: "c")
        #expect(result.items.map(\.id) == ["c", "a", "b"])
        #expect(result.pinned == "c")
    }

    @Test func pinnedAlreadyAtTheFrontStaysPut() {
        let scan = [Req(id: "a", ts: 100), Req(id: "b", ts: 200)]
        let result = ordered(scan, pinned: "a")
        #expect(result.items.map(\.id) == ["a", "b"])
        #expect(result.pinned == "a")
    }

    @Test func stalePinLetsGo() {
        // Answered elsewhere, or the hook gave up: the pin must come back
        // nil (so the caller stops holding the spot) and the age order must
        // be untouched.
        let scan = [Req(id: "a", ts: 100), Req(id: "b", ts: 200)]
        let result = ordered(scan, pinned: "ghost")
        #expect(result.items.map(\.id) == ["a", "b"])
        #expect(result.pinned == nil)
    }

    @Test func noPinMeansNoPin() {
        let result = ordered([Req(id: "a", ts: 100)], pinned: nil)
        #expect(result.pinned == nil)
    }

    @Test func emptyQueue() {
        let result = ordered([], pinned: "anything")
        #expect(result.items.isEmpty)
        #expect(result.pinned == nil)
    }
}
