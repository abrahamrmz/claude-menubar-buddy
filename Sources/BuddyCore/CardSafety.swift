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

    public static func batchAllowable<T>(_ items: [T], isCritical: (T) -> Bool) -> [T] {
        items.filter { !isCritical($0) }
    }
}
