import KeyboardShortcuts

// Global approval shortcuts, remappable by the user (recorder UI arrives
// with the Settings window in Fase 2.1; remapping already works because
// handlers key off names, not key codes — KeyboardShortcuts persists
// per-name user overrides in UserDefaults).
//
// Defaults: ⌘⏎ = Allow, ⇧⌘⏎ = Deny, ⌥⌘⏎ = the card's quiet-row action.
//
// Same load-bearing contract as the old raw-Carbon implementation this
// replaces: the shortcuts are ENABLED only while a request is pending, so
// the rest of the time ⌘⏎ still reaches Slack/Mail/whatever app is
// frontmost. No Accessibility permission needed (KeyboardShortcuts uses
// Carbon RegisterEventHotKey under the hood, same trade-off as before).
extension KeyboardShortcuts.Name {
    static let approvalAllow = Self("approvalAllow", default: .init(.return, modifiers: [.command]))
    static let approvalDeny = Self("approvalDeny", default: .init(.return, modifiers: [.command, .shift]))
    static let approvalQuiet = Self("approvalQuiet", default: .init(.return, modifiers: [.command, .option]))
    // Fase 1.2: jump to the terminal/editor hosting the requesting session.
    static let jumpToHost = Self("jumpToHost", default: .init(.m, modifiers: [.command]))
}

final class ApprovalHotKeys {
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?

    init() {
        KeyboardShortcuts.onKeyDown(for: .approvalAllow) { [weak self] in self?.onAllow?() }
        KeyboardShortcuts.onKeyDown(for: .approvalDeny) { [weak self] in self?.onDeny?() }
        KeyboardShortcuts.onKeyDown(for: .approvalQuiet) { [weak self] in self?.onAlwaysAllow?() }
        // Registering a handler implicitly enables its shortcut — flip them
        // off until a request is actually pending.
        disable()
    }

    func enable() {
        for name: KeyboardShortcuts.Name in [.approvalAllow, .approvalDeny, .approvalQuiet] {
            KeyboardShortcuts.enable(name)
        }
    }

    func disable() {
        for name: KeyboardShortcuts.Name in [.approvalAllow, .approvalDeny, .approvalQuiet] {
            KeyboardShortcuts.disable(name)
        }
    }
}
