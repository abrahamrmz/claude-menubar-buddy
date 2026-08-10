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
    // Bringing a queued request to the front. Same ⌘-number keys the choice
    // card uses, which is fine because the two are never live at once: a
    // choice card takes them for its options, and the queue is reachable from
    // the +N badge instead. Deliberately absent from the Settings recorders —
    // nine remappable names would swamp that list to no purpose.
    static let queue1 = Self("queue1", default: .init(.one, modifiers: [.command]))
    static let queue2 = Self("queue2", default: .init(.two, modifiers: [.command]))
    static let queue3 = Self("queue3", default: .init(.three, modifiers: [.command]))
    static let queue4 = Self("queue4", default: .init(.four, modifiers: [.command]))
    static let queue5 = Self("queue5", default: .init(.five, modifiers: [.command]))
    static let queue6 = Self("queue6", default: .init(.six, modifiers: [.command]))
    static let queue7 = Self("queue7", default: .init(.seven, modifiers: [.command]))
    static let queue8 = Self("queue8", default: .init(.eight, modifiers: [.command]))
    static let queue9 = Self("queue9", default: .init(.nine, modifiers: [.command]))
}

final class ApprovalHotKeys {
    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    var onJumpToHost: (() -> Void)?
    /// Index (0-based) of the multiple-choice option the user picked.
    var onChoice: ((Int) -> Void)?
    /// Index (0-based) into the queue, where 0 is the card already on screen.
    var onQueuePick: ((Int) -> Void)?

    private static let decisionNames: [KeyboardShortcuts.Name] = [.approvalAllow, .approvalDeny, .approvalQuiet]
    // Internal (not private) so the card can look up a choice button's
    // shortcut when deciding which buttons to light up as "armed".
    static let choiceNames: [KeyboardShortcuts.Name] = [.choice1, .choice2, .choice3, .choice4]
    private static let queueNames: [KeyboardShortcuts.Name] = [
        .queue1, .queue2, .queue3, .queue4, .queue5, .queue6, .queue7, .queue8, .queue9,
    ]

    init() {
        KeyboardShortcuts.onKeyDown(for: .approvalAllow) { [weak self] in self?.onAllow?() }
        KeyboardShortcuts.onKeyDown(for: .approvalDeny) { [weak self] in self?.onDeny?() }
        KeyboardShortcuts.onKeyDown(for: .approvalQuiet) { [weak self] in self?.onAlwaysAllow?() }
        KeyboardShortcuts.onKeyDown(for: .jumpToHost) { [weak self] in self?.onJumpToHost?() }
        for (index, name) in Self.choiceNames.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in self?.onChoice?(index) }
        }
        for (index, name) in Self.queueNames.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in self?.onQueuePick?(index) }
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
    ///   - queue: how many requests are selectable by number (the card on
    ///     screen plus the ones behind it). Must be 0 whenever `choices` is
    ///     non-zero — they share the ⌘-number keys, and the choice card wins
    ///     because picking an option is the whole point of it being up.
    func enable(jump: Bool, choices: Int = 0, queue: Int = 0) {
        for name in Self.decisionNames { KeyboardShortcuts.enable(name) }
        if jump {
            KeyboardShortcuts.enable(.jumpToHost)
        } else {
            KeyboardShortcuts.disable(.jumpToHost)
        }
        let queueCount = choices > 0 ? 0 : queue
        for (index, name) in Self.choiceNames.enumerated() {
            setEnabled(name, index < choices)
        }
        for (index, name) in Self.queueNames.enumerated() {
            setEnabled(name, index < queueCount)
        }
    }

    func disable() {
        for name in Self.decisionNames { KeyboardShortcuts.disable(name) }
        KeyboardShortcuts.disable(.jumpToHost)
        for name in Self.choiceNames { KeyboardShortcuts.disable(name) }
        for name in Self.queueNames { KeyboardShortcuts.disable(name) }
    }

    private func setEnabled(_ name: KeyboardShortcuts.Name, _ enabled: Bool) {
        if enabled {
            KeyboardShortcuts.enable(name)
        } else {
            KeyboardShortcuts.disable(name)
        }
    }
}
