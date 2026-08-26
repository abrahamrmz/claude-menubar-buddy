import AppKit
import KeyboardShortcuts

// The approval card's assembly and lifecycle: build it for a request,
// position it, arm its buttons while a shortcut's modifiers are held, and
// wire up the pending state. The visual vocabulary (pill buttons, accents,
// text styling) lives in CardLayout.swift; what happens when a button is
// pushed lives in CardDecision.swift (split in Fase 7.2).
extension AppDelegate {
    // Interactive approval card positioned just above the floating pet, so
    // the decision can be made right on the desktop pet without opening the
    // menu bar dropdown. Only exists while there's a real pending request.
    //
    // .nonactivatingPanel is the load-bearing detail: clicking Allow/Deny
    // must NOT activate this app or steal key focus from whatever the user
    // is typing in (single-screen laptop workflow — approve and keep
    // typing in the terminal without a window switch).
    //
    // The card grows with its content (short command = compact pill, long
    // command/diff = taller card) up to a cap, then scrolls — full content
    // is always reachable before deciding, never a truncated teaser.
    func showStatusBubble(for req: PendingRequest, queued: Int) {
        guard floatingPetVisible, let petWindow = floatingWindow else { return }
        let cardWidth: CGFloat = 430
        let pad: CGFloat = 14
        let stripeWidth: CGFloat = 4
        let contentX = pad + stripeWidth
        let blockInset: CGFloat = 8
        let accent = toolAccent(req.tool)
        // Multiple-choice card: the body is the question being asked, and the
        // action rows are its options instead of Allow/Deny. Questions are
        // walked one at a time (see choiceIndex).
        let question = req.choices?.indices.contains(choiceIndex) == true ? req.choices![choiceIndex] : nil
        let bodyFont = question != nil
            ? NSFont.systemFont(ofSize: 13)
            : NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        // The block scrolls, so the display limit is generous and matches the
        // hook's payload cap; whatever still doesn't fit is announced rather
        // than quietly dropped. A question's text is never cut by the hook —
        // `choices` rides along in full — so only the hint carries a cut.
        let body = bodyText(question?.question ?? req.hint, limit: 20000,
                            alreadyCut: question == nil ? (req.hidden ?? 0) : 0)
        let bodyMaxHeight: CGFloat = 200

        let measured = (body as NSString).boundingRect(
            with: NSSize(width: cardWidth - contentX - pad - blockInset * 2 - 14, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont]
        )
        let textHeight = min(bodyMaxHeight, max(18, ceil(measured.height) + 4))
        let blockHeight = textHeight + blockInset * 2
        let headerHeight: CGFloat = 26
        let buttonRowHeight: CGFloat = 32
        // Third, quieter action row, tool-dependent: Bash remembers the
        // base command; edit tools offer auto-approve mode; plans hand off
        // to VS Code where the full options (auto-accept / manual / tell
        // Claude) live.
        // Nothing to promise about text that arrived cut — the hidden tail is
        // exactly where a second command would be sitting.
        let base = (req.tool == "Bash" && (req.hidden ?? 0) == 0)
            ? commandBase(from: req.hint) : nil
        currentCommandBase = base
        // Which project the grant would be scoped to, or nil when the session
        // has no cwd to scope by (ssh/tmux). The grant keys on the full path;
        // this is only what the button calls it.
        let grantScope: String? = {
            guard let cwd = req.cwd, !cwd.isEmpty else { return nil }
            if let project = req.project, !project.isEmpty { return project }
            return (cwd as NSString).lastPathComponent
        }()
        let isEditTool = ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(req.tool)
        let isPlan = req.tool == "ExitPlanMode"
        let hasQuietRow = question == nil && (base != nil || isEditTool || isPlan)
        let alwaysRowHeight: CGFloat = hasQuietRow ? 26 + 8 : 0

        // Option buttons stack vertically and size to their own text: the
        // description is what you actually choose on, so it gets up to two
        // lines rather than a "…" at the point it starts being useful.
        let optionGap: CGFloat = 6
        let optionTextWidth = cardWidth - contentX - pad - 24
        let optionHeights: [CGFloat] = (question?.options ?? []).map { option in
            var height: CGFloat = 8 + 17 + 8   // padding + label line + padding
            if let detail = option.description, !detail.isEmpty {
                let measured = (detail as NSString).boundingRect(
                    with: NSSize(width: optionTextWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    attributes: [.font: NSFont.systemFont(ofSize: 11)])
                height += 2 + min(30, ceil(measured.height))  // two lines, then truncate
            }
            return height
        }
        let actionsHeight: CGFloat = question != nil
            ? optionHeights.reduce(0, +) + CGFloat(max(0, optionHeights.count - 1)) * optionGap
            : buttonRowHeight + alwaysRowHeight
        let cardHeight = pad + actionsHeight + 10 + blockHeight + 10 + headerHeight + pad

        let window: NSWindow
        if let existing = statusBubbleWindow {
            window = existing
            window.setContentSize(NSSize(width: cardWidth, height: cardHeight))
        } else {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: cardWidth, height: cardHeight)),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = false
            panel.becomesKeyOnlyIfNeeded = true
            // Explicit opt-in to screen capture: on Sequoia this panel was
            // absent from ScreenCaptureKit's shareable content (screenshots
            // showed everything but the card), which also breaks capturing
            // it for docs/debugging. Visibility on the physical display was
            // never affected.
            panel.sharingType = .readOnly
            // Delegate so windowDidMove can remember where the user drags
            // the card relative to the pet.
            panel.delegate = self
            window = panel
            statusBubbleWindow = window
        }

        // Fresh content view per request — rebuilding is cheaper to reason
        // about than reframing five subviews around a variable-height body.
        let card = DraggableCardView(frame: NSRect(origin: .zero, size: NSSize(width: cardWidth, height: cardHeight)))
        card.material = .hudWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.masksToBounds = true
        card.setAccessibilityLabel("Permission request: \(req.tool)"
            + ((req.project?.isEmpty == false) ? " in \(req.project!)" : ""))
        window.contentView = card

        let stripe = NSView(frame: NSRect(x: 0, y: 0, width: stripeWidth, height: cardHeight))
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = accent.cgColor
        card.addSubview(stripe)

        // Header: [icon chip] Tool                [↗] [+N] [project]
        let headerY = cardHeight - pad - headerHeight
        let chip = NSImageView(frame: NSRect(x: contentX, y: headerY + 1, width: 24, height: 24))
        chip.wantsLayer = true
        chip.layer?.backgroundColor = accent.withAlphaComponent(0.22).cgColor
        chip.layer?.cornerRadius = 6
        if let symbol = NSImage(systemSymbolName: toolSymbol(req.tool), accessibilityDescription: req.tool) {
            chip.image = symbol.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            chip.contentTintColor = accent
        }
        // Decoration — the tool name is right beside it in the title.
        chip.setAccessibilityElement(false)
        card.addSubview(chip)

        var rightEdge = cardWidth - pad
        if let project = req.project, !project.isEmpty {
            let badge = pillLabel(project, textColor: .secondaryLabelColor,
                                  background: NSColor.white.withAlphaComponent(0.10))
            badge.setFrameOrigin(NSPoint(x: rightEdge - badge.frame.width, y: headerY + 4))
            card.addSubview(badge)
            rightEdge -= badge.frame.width + 6
        }
        if queued > 0 {
            // The badge is a button (built with the rest of the queue
            // machinery in Queue.swift): the line behind the card is
            // reachable, not just countable.
            let badge = queueBadgeButton(queued: queued)
            badge.setFrameOrigin(NSPoint(x: rightEdge - badge.frame.width, y: headerY + 4))
            card.addSubview(badge)
            rightEdge -= badge.frame.width + 6
        }

        // Hand-off: answer this one in VS Code / the terminal instead. The
        // hook returns no decision immediately, so the native prompt (with
        // all its options) appears right away rather than after the 55s
        // timeout.
        let passButton = NSButton(frame: NSRect(x: rightEdge - 22, y: headerY + 2, width: 22, height: 22))
        passButton.isBordered = false
        passButton.target = self
        passButton.action = #selector(passToNative)
        if let symbol = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "decide in VS Code") {
            passButton.image = symbol.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            passButton.contentTintColor = .secondaryLabelColor
        }
        passButton.toolTip = "Decide in VS Code / terminal instead (full native options)"
        passButton.setAccessibilityLabel("Decide in VS Code or terminal instead")
        card.addSubview(passButton)
        rightEdge -= 28

        // Jump to the window that's asking — read the diff/plan in context
        // WITHOUT answering here (the card stays up and pending). Absent
        // when the hook couldn't tell who hosts the session.
        if let target = jumpTarget(for: req) {
            let jumpButton = NSButton(frame: NSRect(x: rightEdge - 22, y: headerY + 2, width: 22, height: 22))
            jumpButton.isBordered = false
            jumpButton.target = self
            jumpButton.action = #selector(jumpToHost)
            if let symbol = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                    accessibilityDescription: "show the asking window") {
                jumpButton.image = symbol.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
                jumpButton.contentTintColor = .secondaryLabelColor
            }
            jumpButton.toolTip = "Show this session in \(target.name)  ⌘M"
            jumpButton.setAccessibilityLabel("Show this session in \(target.name)")
            card.addSubview(jumpButton)
            rightEdge -= 28
        }

        // For a question, the tool name means nothing to the reader — its own
        // header does ("Prioridad", "Approach"), plus which of several
        // questions this is.
        var title = req.tool
        if let question = question {
            title = question.header ?? "Question"
            if let all = req.choices, all.count > 1 {
                title += "  ·  \(choiceIndex + 1) of \(all.count)"
            }
        }
        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.boldSystemFont(ofSize: 14)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: contentX + 32, y: headerY + 4,
                                  width: rightEdge - contentX - 32, height: 18)
        card.addSubview(titleField)

        // Body: the full command / mini-diff inside a code-block well.
        let block = NSView(frame: NSRect(x: contentX, y: pad + actionsHeight + 10,
                                         width: cardWidth - contentX - pad, height: blockHeight))
        block.wantsLayer = true
        block.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        block.layer?.cornerRadius = 8
        card.addSubview(block)

        let scroll = NSScrollView(frame: NSRect(x: blockInset, y: blockInset,
                                                width: block.frame.width - blockInset * 2, height: textHeight))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.textStorage?.setAttributedString(attributedHint(body, font: bodyFont))
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel(question != nil ? "The question being asked"
                                       : (req.tool == "ExitPlanMode" ? "Proposed plan" : "Request details"))
        scroll.documentView = textView
        block.addSubview(scroll)

        // Multiple choice: the options replace Allow/Deny entirely. Answering
        // isn't approving — there's no "no" to give here, so offering one
        // would only be a way to get the question asked again. The ↗ in the
        // header is still the way out to the native picker (free-text
        // "Other", for one).
        if let question = question {
            var y = pad + actionsHeight
            for (index, option) in question.options.enumerated() {
                let height = optionHeights[index]
                y -= height
                let button = optionButton(option, index: index, accent: accent)
                button.frame = NSRect(x: contentX, y: y, width: cardWidth - contentX - pad, height: height)
                card.addSubview(button)
                if index == 0 { allowButtonRef = button }
                y -= optionGap
            }
            currentQuietAction = nil
            finishStatusBubble(window: window, petWindow: petWindow)
            return
        }

        let buttonWidth: CGFloat = (cardWidth - contentX - pad - 8) / 2
        // A plan's three native options map onto the three the card already
        // has, so plans get the real choices instead of a hand-off: ⌘⏎ is the
        // careful yes, ⌥⌘⏎ the one that also flips auto-edits on, ⇧⌘⏎ "keep
        // planning" (a deny that says why).
        let allowButton = pillButton(title: isPlan ? "✓ Yes — approve each edit" : "✓ Allow", shortcut: "⌘⏎",
                                     fill: .systemGreen, textColor: .white, action: #selector(allow),
                                     accessibility: isPlan ? "Approve the plan, approving each edit as it comes"
                                                           : "Allow \(req.tool)")
        allowButton.frame = NSRect(x: contentX, y: pad, width: buttonWidth, height: buttonRowHeight)
        card.addSubview(allowButton)
        allowButtonRef = allowButton

        let denyButton = pillButton(title: isPlan ? "✕ No — keep planning" : "✕ Deny", shortcut: "⇧⌘⏎",
                                    fill: NSColor.white.withAlphaComponent(0.10),
                                    textColor: .systemRed, action: #selector(deny),
                                    accessibility: isPlan ? "Don't implement yet — keep planning"
                                                          : "Deny \(req.tool)")
        denyButton.frame = NSRect(x: contentX + buttonWidth + 8, y: pad, width: buttonWidth, height: buttonRowHeight)
        card.addSubview(denyButton)
        denyButtonRef = denyButton

        // Quieter full-width row above the pills, per tool kind.
        if hasQuietRow {
            let quietButton: PressablePillButton
            if let base = base {
                // Scoped to the asking project by default. A standing grant
                // is worth as much as it is narrow, and the project you are
                // in is the one you just decided about — "everywhere" is a
                // different, wider decision, so it lives in Settings ▸ Safety
                // where it costs a deliberate trip and a confirmation.
                let where_ = grantScope.map { "in \($0)" } ?? "everywhere"
                quietButton = pillButton(title: "Always allow \(base) \(where_)", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(alwaysAllow),
                                         accessibility: "Allow, and always allow \(base) \(where_) from now on",
                                         symbol: "bolt.fill")
                currentQuietAction = { [weak self] in self?.alwaysAllow() }
            } else if isEditTool {
                quietButton = pillButton(title: "Auto-approve edits from now on", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(autoApproveEditsFromCard),
                                         accessibility: "Allow, and auto-approve edits from now on",
                                         symbol: "bolt.fill")
                currentQuietAction = { [weak self] in self?.autoApproveEditsFromCard() }
            } else {
                quietButton = pillButton(title: "Yes — and auto-accept edits from here", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(autoApproveEditsFromCard),
                                         accessibility: "Approve the plan and auto-approve its edits from now on",
                                         symbol: "bolt.fill")
                currentQuietAction = { [weak self] in self?.autoApproveEditsFromCard() }
            }
            quietButton.layer?.cornerRadius = 13
            quietButton.frame = NSRect(x: contentX, y: pad + buttonRowHeight + 8,
                                       width: cardWidth - contentX - pad, height: 26)
            card.addSubview(quietButton)
            alwaysButtonRef = quietButton
        } else {
            currentQuietAction = nil
        }

        finishStatusBubble(window: window, petWindow: petWindow)
    }

    /// Position and reveal — shared by both card shapes, since the choice
    /// branch returns before the Allow/Deny rows are built.
    func finishStatusBubble(window: NSWindow, petWindow: NSWindow) {
        let wasVisible = window.isVisible
        startModifierWatch()
        positionStatusBubble(above: petWindow)
        if wasVisible {
            window.orderFront(nil)
        } else {
            // Entrance: fade in while rising the last few points. Exit stays
            // instant — approve should feel like the card got out of the way.
            let target = window.frame
            window.setFrame(target.offsetBy(dx: 0, dy: -8), display: false)
            window.alphaValue = 0
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                window.animator().setFrame(target, display: true)
            }
        }
    }

    func hideStatusBubble() {
        stopModifierWatch()
        statusBubbleWindow?.orderOut(nil)
    }

    // MARK: - Armed buttons (modifier held, key not yet)

    // Holding the modifier half of a shortcut lights up the button it would
    // push: ⌘ down and Allow lifts with a bright rim before ⏎ ever lands,
    // add ⇧ and the glow hops to Deny, ⌥ and it's the quiet row. On a
    // multiple-choice card ⌘ arms the options (they share it). Matching goes
    // through the user's actual recorded shortcuts, not the defaults, so a
    // remapped Allow arms on whatever modifiers it was remapped to.

    /// The modifier keys being physically held right now, filtered down to
    /// the four a shortcut can be recorded with (caps lock and fn are not
    /// intent).
    private static let armableModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    func startModifierWatch() {
        guard modifierWatchTimer == nil else { return }
        // 20Hz is imperceptible CPU for the seconds a card is up, and fast
        // enough that the glow reads as instant. .common so it keeps ticking
        // while a menu is being tracked.
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateArmedButtons()
        }
        RunLoop.main.add(t, forMode: .common)
        modifierWatchTimer = t
        updateArmedButtons()
    }

    func stopModifierWatch() {
        modifierWatchTimer?.invalidate()
        modifierWatchTimer = nil
        armButtons(matching: [])
    }

    func updateArmedButtons() {
        guard statusBubbleWindow?.isVisible == true, !isDismissing else {
            armButtons(matching: [])
            return
        }
        armButtons(matching: NSEvent.modifierFlags.intersection(Self.armableModifiers))
    }

    private func armButtons(matching held: NSEvent.ModifierFlags) {
        func armed(_ name: KeyboardShortcuts.Name) -> Bool {
            guard !held.isEmpty, let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return false }
            return shortcut.modifiers.intersection(Self.armableModifiers) == held
        }
        // A choice card parks option 0 in allowButtonRef (so the ⌘⏎ flash
        // path has something to flash) — arm the options by their own
        // shortcuts and leave the decision names out of it.
        let optionButtons = (statusBubbleWindow?.contentView?.subviews ?? [])
            .compactMap { $0 as? PressablePillButton }
            .filter { $0.action == #selector(chooseOption(_:)) }
        if !optionButtons.isEmpty {
            for button in optionButtons {
                let name = ApprovalHotKeys.choiceNames.indices.contains(button.tag)
                    ? ApprovalHotKeys.choiceNames[button.tag] : nil
                button.setArmed(name.map(armed) ?? false)
            }
            return
        }
        allowButtonRef?.setArmed(armed(.approvalAllow))
        denyButtonRef?.setArmed(armed(.approvalDeny))
        alwaysButtonRef?.setArmed(armed(.approvalQuiet))
    }

    func positionStatusBubble(above petWindow: NSWindow) {
        guard let bubble = statusBubbleWindow else { return }
        if let offset = cardOffset {
            let petFrame = petWindow.frame
            bubble.setFrameOrigin(NSPoint(x: petFrame.origin.x + offset.x,
                                          y: petFrame.origin.y + offset.y))
            return
        }
        bubble.setFrameOrigin(originNearPet(for: bubble.frame.size))
    }

    func setPending(_ req: PendingRequest, queued: Int) {
        applyPendingStatusIcon(for: req, queued: queued)
        currentRequestId = req.id
        currentRequest = req
        lastQueuedCount = queued
        choiceIndex = 0
        collectedAnswers = [:]

        let menu = NSMenu()

        // "tool — project" when the hook told us which session is asking;
        // several concurrent sessions otherwise look identical up here.
        let toolTitle = (req.project?.isEmpty == false) ? "\(req.tool) — \(req.project!)" : req.tool
        let toolItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        toolItem.attributedTitle = NSAttributedString(
            string: toolTitle,
            attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.boldSystemFont(ofSize: 13)]
        )
        menu.addItem(toolItem)

        // Full content in the dropdown too — wrapping, monospaced, capped in
        // height. Same "no truncated teaser" rule as the floating card.
        let hintFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let hintText = bodyText(req.hint, limit: 1200, alreadyCut: req.hidden ?? 0)
        let hintWidth: CGFloat = 400
        let hintMeasured = (hintText as NSString).boundingRect(
            with: NSSize(width: hintWidth - 28, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: hintFont]
        )
        let hintHeight = min(180, ceil(hintMeasured.height) + 8)
        let hintContainer = NSView(frame: NSRect(x: 0, y: 0, width: hintWidth, height: hintHeight))
        let hintField = NSTextField(wrappingLabelWithString: "")
        hintField.attributedStringValue = attributedHint(hintText, font: hintFont)
        hintField.frame = NSRect(x: 14, y: 4, width: hintWidth - 28, height: hintHeight - 8)
        hintContainer.addSubview(hintField)
        let hintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        hintItem.view = hintContainer
        menu.addItem(hintItem)
        if queued > 0, let queueMenu = buildQueueMenu() {
            let top = NSMenuItem(title: "\(queued) more request\(queued == 1 ? "" : "s") waiting",
                                 action: nil, keyEquivalent: "")
            top.submenu = queueMenu
            menu.addItem(top)
        }
        menu.addItem(NSMenuItem.separator())
        if let question = req.choices?.first {
            // A question has no allow/deny — the dropdown gets the same
            // options the card shows.
            for (index, option) in question.options.enumerated() {
                let item = NSMenuItem(title: option.label, action: #selector(chooseOptionFromMenu(_:)),
                                      keyEquivalent: "\(index + 1)")
                item.tag = index
                item.target = self
                item.toolTip = option.description
                menu.addItem(item)
            }
        } else {
            menu.addItem(withTitle: "Allow", action: #selector(allow), keyEquivalent: "a")
            menu.addItem(withTitle: "Deny", action: #selector(deny), keyEquivalent: "d")
        }
        if let target = jumpTarget(for: req) {
            menu.addItem(withTitle: "Show in \(target.name)", action: #selector(jumpToHost), keyEquivalent: "m")
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        statusItem.menu = menu

        hideDoneToast()
        showStatusBubble(for: req, queued: queued)
        // Wide-eyed attention pose on the floating pet too, matching the
        // dropdown's pending GIF; setIdle reverts both to the real mood.
        if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: gifName(for: selectedSpecies, mood: "pending"))
            applyAnimationPolicy()
        }
        approvalHotKeys.enable(jump: jumpTarget(for: req) != nil,
                               choices: req.choices?.first?.options.count ?? 0,
                               queue: queued > 0 ? min(9, queued + 1) : 0)
        // No sound when the user is the one flipping through the queue —
        // they know the card changed, they asked for it.
        if switchingCardByHand {
            switchingCardByHand = false
        } else {
            NSSound(named: "Ping")?.play()
        }
    }

    /// Debug/docs helper: `touch ~/.config/claude-menubar-buddy/capture_card`
    /// while a card is showing and the app renders it to card_selfie.png in
    /// the same directory. Exists because the non-activating panel renders
    /// blank through ScreenCaptureKit (screencapture gets only the blur
    /// material), so an in-process render is the only faithful screenshot.
    func captureCardSelfieIfRequested() {
        guard debugFlagIsSet("capture_card") else { return }
        let flagURL = dirURL.appendingPathComponent("capture_card")
        // Whichever pet-attached window is up: done toast or approval card.
        let visibleContent = (toastWindow?.isVisible == true ? toastWindow?.contentView : nil)
            ?? (statusBubbleWindow?.isVisible == true ? statusBubbleWindow?.contentView : nil)
        guard let card = visibleContent else { return }
        try? FileManager.default.removeItem(at: flagURL)
        guard let rep = card.bitmapImageRepForCachingDisplay(in: card.bounds) else { return }
        card.cacheDisplay(in: card.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dirURL.appendingPathComponent("card_selfie.png"))
        }
    }
}
