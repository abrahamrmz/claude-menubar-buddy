import Foundation

/// The guards that keep a card from being approved by muscle memory.
///
/// A critical request (code execution, a protected path, something that leaves
/// the machine) is worth reading: the keyboard shortcut has to wait until the
/// card has actually been on screen, and a batch approval never sweeps it
/// along.
public enum CardSafety {
    /// How long a critical card must be visible before its hotkey can approve.
    public static let criticalHotKeyDelay: TimeInterval = 1.5

    public static func hotKeyMayApprove(critical: Bool, shownAt: Date?, now: Date) -> Bool {
        guard critical else { return true }
        // No timestamp means "can't tell when it appeared" — the safe answer
        // is no, not "it has probably been a while".
        guard let shownAt else { return false }
        return now.timeIntervalSince(shownAt) >= criticalHotKeyDelay
    }

    /// How long the card's session-grant button ignores a click. The widest
    /// grant in the app comes from a deliberate click, never a reflex; unlike
    /// the hotkey it does not care whether the request is critical (spec 9.1).
    public static let sessionGrantDelay: TimeInterval = 1.5

    public static func sessionGrantMayFire(shownAt: Date?, now: Date) -> Bool {
        // nil means "can't tell when it appeared": safe answer is no. A clock
        // that went back gives a negative interval and is refused too.
        guard let shownAt else { return false }
        return now.timeIntervalSince(shownAt) >= sessionGrantDelay
    }

    public static func batchAllowable<T>(_ items: [T], isCritical: (T) -> Bool) -> [T] {
        items.filter { !isCritical($0) }
    }
}
