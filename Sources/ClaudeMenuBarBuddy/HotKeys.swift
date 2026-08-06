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
    // Jump to the terminal/editor hosting the requesting session. ⌘M is
    // Minimize everywhere else, which is exactly why it's only borrowed for
    // the couple of seconds a card is up AND has somewhere to jump to.
    static let jumpToHost = Self("jumpToHost", default: .init(.m, modifiers: [.command]))
    // Picking an option on a multiple-choice card. Live only while such a
    // card is up — ⌘1-4 switches tabs in most apps the rest of the time.
    static let choice1 = Self("choice1", default: .init(.one, modifiers: [.command]))
    static let choice2 = Self("choice2", default: .init(.two, modifiers: [.command]))
    static let choice3 = Self("choice3", default: .init(.three, modifiers: [.command]))
    static let choice4 = Self("choice4", default: .init(.four, modifiers: [.command]))
}

final class ApprovalHotKeys {
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    var onJumpToHost: (() -> Void)?
    /// Index (0-based) of the multiple-choice option the user picked.
    var onChoice: ((Int) -> Void)?

    private static let decisionNames: [KeyboardShortcuts.Name] = [.approvalAllow, .approvalDeny, .approvalQuiet]
    private static let choiceNames: [KeyboardShortcuts.Name] = [.choice1, .choice2, .choice3, .choice4]

    init() {
        KeyboardShortcuts.onKeyDown(for: .approvalAllow) { [weak self] in self?.onAllow?() }
        KeyboardShortcuts.onKeyDown(for: .approvalDeny) { [weak self] in self?.onDeny?() }
        KeyboardShortcuts.onKeyDown(for: .approvalQuiet) { [weak self] in self?.onAlwaysAllow?() }
        KeyboardShortcuts.onKeyDown(for: .jumpToHost) { [weak self] in self?.onJumpToHost?() }
        for (index, name) in Self.choiceNames.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in self?.onChoice?(index) }
        }
        // Registering a handler implicitly enables its shortcut — flip them
        // off until a request is actually pending.
        disable()
    }

    /// - Parameters:
    ///   - jump: whether this request knows which app hosts it. False for
    ///     ssh/tmux sessions, and there ⌘M must keep minimizing windows.
    ///   - choices: how many options the card is offering. Only that many
    ///     ⌘-number keys are borrowed, and only while the card is up.
    func enable(jump: Bool, choices: Int = 0) {
        for name in Self.decisionNames { KeyboardShortcuts.enable(name) }
        if jump {
            KeyboardShortcuts.enable(.jumpToHost)
        } else {
            KeyboardShortcuts.disable(.jumpToHost)
        }
        for (index, name) in Self.choiceNames.enumerated() {
            if index < choices {
                KeyboardShortcuts.enable(name)
            } else {
                KeyboardShortcuts.disable(name)
            }
        }
    }

    func disable() {
        for name in Self.decisionNames { KeyboardShortcuts.disable(name) }
        KeyboardShortcuts.disable(.jumpToHost)
        for name in Self.choiceNames { KeyboardShortcuts.disable(name) }
    }
}
