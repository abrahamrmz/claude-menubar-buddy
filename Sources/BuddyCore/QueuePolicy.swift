import Foundation

/// The ordering rule for the request queue: which request is at the front —
/// i.e. what ⌘⏎ answers — and in what order the rest wait. Pure so the tests
/// can exercise it without a config directory or a running app.
public enum QueuePolicy {
    /// Oldest first, ties broken by id. The tiebreak is not cosmetic:
    /// poll() swaps the on-screen card whenever the front id changes, and
    /// Swift's sort is not stable — two requests landing with the same
    /// timestamp could otherwise trade places between scans and flicker
    /// the card back and forth.
    ///
    /// A pinned id jumps to the front and stays there until answered; a pin
    /// that matches nothing (answered elsewhere, or the hook gave up) comes
    /// back as nil so the caller stops holding a spot for something that no
    /// longer exists.
    public static func ordered<T>(_ items: [T],
                                  id: (T) -> String,
                                  ts: (T) -> Double?,
                                  pinned: String?) -> (items: [T], pinned: String?) {
        var sorted = items.sorted {
            let a = ts($0) ?? 0
            let b = ts($1) ?? 0
            return a != b ? a < b : id($0) < id($1)
        }
        guard let pin = pinned,
              let index = sorted.firstIndex(where: { id($0) == pin }) else {
            return (sorted, nil)
        }
        if index > 0 { sorted.insert(sorted.remove(at: index), at: 0) }
        return (sorted, pin)
    }
}
