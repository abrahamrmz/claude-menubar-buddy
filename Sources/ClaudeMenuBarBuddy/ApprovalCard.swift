import AppKit

// Pill button that visibly sinks while pressed — scales down and dims, then
// springs back. setPressed is public so the ⌘⏎ hotkey path can flash the
// same pressed state: the whole point is that the shortcut FEELS like
// pushing the on-screen button, not like the card silently obeying.
final class PressablePillButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        // Blocks in the cell's tracking loop; the action fires inside it.
        super.mouseDown(with: event)
        setPressed(false)
    }

    func setPressed(_ down: Bool) {
        guard let layer = layer else { return }
        // Scale about the center, not AppKit's default bottom-left anchor.
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let f = layer.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: f.midX, y: f.midY)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        layer.setAffineTransform(down ? CGAffineTransform(scaleX: 0.95, y: 0.93) : .identity)
        layer.opacity = down ? 0.7 : 1.0
        CATransaction.commit()
    }
}

// The approval card's background: same manual drag as the pet (grab the
// title row or any empty padding; buttons and the text view keep handling
// their own clicks), so the card can be pulled out of the way of whatever
// it happens to cover.
final class DraggableCardView: NSVisualEffectView {
    private var dragStartMouseScreenLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseScreenLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartMouseScreenLocation.x
        let dy = current.y - dragStartMouseScreenLocation.y
        window.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy))
    }
}

// The approval card: build, style, position, decide, animate.
extension AppDelegate {
    // Per-tool accent so the card reads at a glance what KIND of action is
    // asking — a green Allow on an orange "Edit" card is a different snap
    // judgment than on a teal "Bash" one.
    func toolAccent(_ tool: String) -> NSColor {
        switch tool {
        case "Bash": return .systemTeal
        case "Edit", "MultiEdit": return .systemOrange
        case "Write": return .systemPurple
        case "WebFetch", "WebSearch": return .systemBlue
        case "NotebookEdit": return .systemYellow
        case "ExitPlanMode": return .systemPink
        case "AskUserQuestion": return .systemIndigo
        default: return .systemGray
        }
    }

    func toolSymbol(_ tool: String) -> String {
        switch tool {
        case "Bash": return "terminal.fill"
        case "Edit", "MultiEdit": return "pencil"
        case "Write": return "square.and.pencil"
        case "WebFetch", "WebSearch": return "globe"
        case "NotebookEdit": return "text.book.closed.fill"
        case "ExitPlanMode": return "list.bullet.clipboard.fill"
        case "AskUserQuestion": return "questionmark.bubble.fill"
        default: return "questionmark.circle.fill"
        }
    }

    /// Small capsule label (project badge, "+N" queue badge).
    func pillLabel(_ text: String, textColor: NSColor, background: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = textColor
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = background.cgColor
        let width = ceil(label.intrinsicContentSize.width) + 16
        label.frame = NSRect(x: 0, y: 0, width: width, height: 18)
        label.layer?.cornerRadius = 9
        return label
    }

    /// Flat rounded pill button; the keyboard shortcut rides along dimmed
    /// inside the title so it never reads as part of the action name.
    /// `accessibility` spells the action out for VoiceOver, which would
    /// otherwise announce the decorative ✓/✕ and the raw shortcut glyphs.
    func pillButton(title: String, shortcut: String, fill: NSColor, textColor: NSColor,
                    action: Selector, accessibility: String) -> PressablePillButton {
        let button = PressablePillButton(title: "", target: self, action: action)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = fill.cgColor
        button.layer?.cornerRadius = 16
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ])
        text.append(NSAttributedString(string: "  \(shortcut)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: textColor.withAlphaComponent(0.55),
            .paragraphStyle: paragraph,
        ]))
        button.attributedTitle = text
        button.setAccessibilityLabel(accessibility)
        return button
    }

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
            // The badge is a button: the line behind the card is reachable,
            // not just countable.
            let badge = PressablePillButton(title: "", target: self, action: #selector(showQueueMenu(_:)))
            badge.isBordered = false
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemOrange.cgColor
            badge.layer?.cornerRadius = 9
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            badge.attributedTitle = NSAttributedString(string: "+\(queued) ▾", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ])
            let badgeWidth = ceil(badge.attributedTitle.size().width) + 16
            badge.frame = NSRect(x: rightEdge - badgeWidth, y: headerY + 4, width: badgeWidth, height: 18)
            badge.toolTip = "\(queued) more request\(queued == 1 ? "" : "s") waiting — click to pick one, or answer them all"
            badge.setAccessibilityLabel("\(queued) more requests waiting. Show the queue.")
            card.addSubview(badge)
            rightEdge -= badgeWidth + 6
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
                quietButton = pillButton(title: "⚡ Always allow \(base)", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(alwaysAllow),
                                         accessibility: "Allow, and always allow \(base) from now on")
                currentQuietAction = { [weak self] in self?.alwaysAllow() }
            } else if isEditTool {
                quietButton = pillButton(title: "⚡ Auto-approve edits from now on", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(autoApproveEditsFromCard),
                                         accessibility: "Allow, and auto-approve edits from now on")
                currentQuietAction = { [weak self] in self?.autoApproveEditsFromCard() }
            } else {
                quietButton = pillButton(title: "⚡ Yes — and auto-accept edits from here", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(autoApproveEditsFromCard),
                                         accessibility: "Approve the plan and auto-approve its edits from now on")
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

    /// One option of a multiple-choice question: its label, and underneath in
    /// smaller type what picking it actually means. Both come verbatim from
    /// the tool call — a card that paraphrased the options would be putting
    /// words in the user's mouth.
    func optionButton(_ option: ChoiceOption, index: Int, accent: NSColor) -> PressablePillButton {
        let button = PressablePillButton(title: "", target: self, action: #selector(chooseOption(_:)))
        button.tag = index
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        button.layer?.cornerRadius = 10
        button.layer?.borderWidth = 1
        button.layer?.borderColor = accent.withAlphaComponent(0.35).cgColor

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.firstLineHeadIndent = 12
        paragraph.headIndent = 12
        paragraph.tailIndent = -12

        let text = NSMutableAttributedString(string: "\(index + 1). \(option.label)", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        text.append(NSAttributedString(string: "   ⌘\(index + 1)", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]))
        if let detail = option.description, !detail.isEmpty {
            let detailParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
            detailParagraph.lineBreakMode = .byWordWrapping
            text.append(NSAttributedString(string: "\n\(detail)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: detailParagraph,
            ]))
        }
        button.attributedTitle = text
        button.setAccessibilityLabel(option.description.map { "\(option.label). \($0)" } ?? option.label)
        return button
    }

    func hideStatusBubble() {
        statusBubbleWindow?.orderOut(nil)
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

    /// Leads the line that says how much of the request didn't fit. Its own
    /// prefix so attributedHint can color it like the warning it is.
    static let truncationMarker = "⚠︎"

    /// The text to show, plus — when the real thing didn't fit — an
    /// unmissable note of how much is missing. Two separate cuts can land
    /// here: hook.sh's payload cap (`alreadyCut`) and this card's own display
    /// limit. Either one, left unsaid, turns Allow into a signature on a
    /// document whose last page nobody was shown: a 2,100-character command
    /// used to render cut at 2,000, with `; rm -rf ~/importante` past the
    /// fold and approved all the same.
    func bodyText(_ source: String, limit: Int, alreadyCut: Int = 0) -> String {
        let shown = String(source.prefix(limit))
        let hidden = alreadyCut + max(0, source.count - shown.count)
        guard hidden > 0 else { return shown }
        return shown + "\n\n\(AppDelegate.truncationMarker) faltan \(hidden) caracteres que no caben aquí — ábrelo con ↗ antes de aprobar."
    }

    /// Colors the hook's mini-diff like a real diff: lines under "--- quita"
    /// in red, lines under "+++ pone" / "+++ contenido" in green, the marker
    /// lines themselves dimmed, everything else (commands, paths) plain.
    func attributedHint(_ text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var section = 0 // 0 = plain, 1 = removing, 2 = adding
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let color: NSColor
            if line.hasPrefix(AppDelegate.truncationMarker) {
                // Deliberately outside the diff sections — a warning painted
                // diff-green because it landed after "+++ pone" would be the
                // one line on the card that must not blend in.
                color = .systemRed
            } else if line.hasPrefix("--- quita") {
                section = 1
                color = .secondaryLabelColor
            } else if line.hasPrefix("+++ pone") || line.hasPrefix("+++ contenido") {
                section = 2
                color = .secondaryLabelColor
            } else {
                switch section {
                case 1: color = .systemRed
                case 2: color = .systemGreen
                default: color = .labelColor
                }
            }
            let suffix = index < lines.count - 1 ? "\n" : ""
            result.append(NSAttributedString(string: line + suffix,
                                             attributes: [.font: font, .foregroundColor: color]))
        }
        return result
    }

    func setPending(_ req: PendingRequest, queued: Int) {
        applyPendingStatusIcon(for: req, queued: queued)
        currentRequestId = req.id
        currentRequest = req
        lastQueuedCount = queued
        choiceIndex = 0
        collectedAnswers = [:]

        let menu = NSMenu()
        menu.addItem(gifMenuItem(named: "\(selectedSpecies)_pending").0)

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
            setGif(on: floatingImageView, named: "buddy_pending")
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

    /// First token of the command that isn't an env assignment — must match
    /// hook.sh's extraction so the button's promise ("gh won't ask again")
    /// is exactly what the fast path later honors. Returns nil for anything
    /// that doesn't look like a plain command name.
    ///
    /// Also nil the moment the command can chain, substitute, redirect or
    /// expand. hook.sh refuses to fast-path those — an allowlist entry names
    /// one command and can only speak for one command — so offering the
    /// button there would be promising something that never happens, on the
    /// exact shapes where the promise would be most dangerous if it did.
    /// The character set is the same one hook.sh screens on; they have to
    /// agree or the button and the fast path drift apart.
    func commandBase(from hint: String) -> String? {
        let shellMetacharacters = CharacterSet(charactersIn: ";&|<>()`$\\\n")
        guard hint.rangeOfCharacter(from: shellMetacharacters) == nil else { return nil }
        for token in hint.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            if token.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil { continue }
            let base = String(token)
            guard base.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil else { return nil }
            return base
        }
        return nil
    }

    /// Hotkey path: flash the matching button's pressed state first, so
    /// ⌘⏎ visibly pushes the button instead of the card silently obeying.
    /// (Mouse clicks get this for free from PressablePillButton.mouseDown.)
    /// decision is "allow", "deny", or "always" (allow + remember command).
    func decideViaHotKey(_ decision: String) {
        guard currentRequestId != nil, !isDismissing else { return }
        let button: PressablePillButton?
        switch decision {
        case "allow": button = allowButtonRef
        case "always": button = alwaysButtonRef
        default: button = denyButtonRef
        }
        let perform: () -> Void = { [weak self] in
            switch decision {
            case "always":
                // Whatever the quiet row offers for this card (always
                // allow / auto-edits / review in VS Code); plain allow when
                // the card has no quiet row.
                if let quiet = self?.currentQuietAction { quiet() }
                else { self?.respond("allow") }
            case "allow": self?.respond("allow")
            default: self?.respond("deny")
            }
        }
        guard let button = button, statusBubbleWindow?.isVisible == true else {
            perform()
            return
        }
        button.setPressed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            button.setPressed(false)
            perform()
        }
    }

    /// Approve the current request AND remember its base command in the
    /// buddy allowlist, so hook.sh auto-approves it from now on without a
    /// card. Falls back to a plain allow when no base was extractable
    /// (non-Bash card, or an unparseable command).
    @objc func alwaysAllow() {
        guard let base = currentCommandBase else {
            respond("allow")
            return
        }
        var list = readAlwaysAllow()
        if !list.contains(base) { list.append(base) }
        writeAlwaysAllow(list)
        respond("allow")
    }

    /// Approve this edit AND flip on auto-approve-edits mode (hook.sh
    /// fast-paths edit tools from now on; the menu item unchecks it).
    @objc func autoApproveEditsFromCard() {
        try? Data().write(to: autoEditsFlagURL)
        buildIdleMenu()
        respond("allow")
    }

    /// No decision from the buddy — the hook returns immediately and the
    /// native VS Code / terminal prompt takes over with all its options.
    @objc func passToNative() {
        respond("pass")
    }

    @objc func chooseOption(_ sender: NSButton) { pickOption(at: sender.tag) }
    @objc func chooseOptionFromMenu(_ sender: NSMenuItem) { pickOption(at: sender.tag) }

    /// Hotkey path (⌘1..⌘4): flash the button first, same as ⌘⏎ does, so the
    /// shortcut feels like pressing the option rather than the card obeying.
    func chooseOptionViaHotKey(_ index: Int) {
        guard currentRequestId != nil, !isDismissing else { return }
        guard let card = statusBubbleWindow?.contentView, statusBubbleWindow?.isVisible == true,
              let button = card.subviews.compactMap({ $0 as? PressablePillButton })
                  .first(where: { $0.tag == index && $0.action == #selector(chooseOption(_:)) }) else {
            pickOption(at: index)
            return
        }
        button.setPressed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            button.setPressed(false)
            self?.pickOption(at: index)
        }
    }

    /// Records one answer. A call can hold several questions and the tool
    /// takes them as a single map, so the card walks to the next question
    /// instead of answering early — only the last pick actually responds.
    func pickOption(at index: Int) {
        guard !isDismissing, let req = currentRequest,
              let questions = req.choices, questions.indices.contains(choiceIndex) else { return }
        let question = questions[choiceIndex]
        guard question.options.indices.contains(index) else { return }
        collectedAnswers[question.question] = question.options[index].label

        if choiceIndex + 1 < questions.count {
            choiceIndex += 1
            let next = questions[choiceIndex]
            approvalHotKeys.enable(jump: jumpTarget(for: req) != nil, choices: next.options.count)
            showStatusBubble(for: req, queued: lastQueuedCount)
            return
        }
        respond("answer")
    }

    /// Verdict flash + exit: a green ✓ / red ✕ pops over a tinted wash,
    /// then the whole card fades away. The response file was already
    /// written by then — the animation only delays the NEXT card, never
    /// the decision reaching the hook.
    func animateCardDismiss(decision: String, completion: @escaping () -> Void) {
        guard let window = statusBubbleWindow, window.isVisible, let card = window.contentView else {
            completion()
            return
        }
        // Hand-off to the native prompt: no verdict was rendered by the
        // buddy, so no ✓/✕ — just a quick neutral fade.
        if decision == "pass" {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
                window.alphaValue = 1
                completion()
            })
            return
        }
        // Answering a question is an affirmative act, not an approval — but
        // it's certainly not a rejection, so it gets the green ✓.
        let isAllow = decision == "allow" || decision == "answer"
        let color: NSColor = isAllow ? .systemGreen : .systemRed

        let overlay = NSView(frame: card.bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = color.withAlphaComponent(0.20).cgColor
        overlay.alphaValue = 0

        let iconSide: CGFloat = 64
        let icon = NSImageView(frame: NSRect(x: card.bounds.midX - iconSide / 2,
                                             y: card.bounds.midY - iconSide / 2,
                                             width: iconSide, height: iconSide))
        icon.imageScaling = .scaleProportionallyUpOrDown
        if let symbol = NSImage(systemSymbolName: isAllow ? "checkmark.circle.fill" : "xmark.circle.fill",
                                accessibilityDescription: decision) {
            icon.image = symbol.withSymbolConfiguration(.init(pointSize: 48, weight: .bold))
            icon.contentTintColor = color
        }
        // Start small; animating the frame outward reads as a little pop.
        icon.frame = icon.frame.insetBy(dx: 14, dy: 14)
        overlay.addSubview(icon)
        card.addSubview(overlay)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = 1
            icon.animator().frame = icon.frame.insetBy(dx: -14, dy: -14)
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
                window.alphaValue = 1
                completion()
            })
        })
    }

    /// Everything a decision does on disk — the response file the hook is
    /// waiting on, the audit line, and clearing the request. Split out from
    /// respond() because a batch does this N times but animates once.
    func writeDecision(id: String, request: PendingRequest?, decision: String,
                       reason: String? = nil, answers: [String: String]? = nil) {
        let responseURL = dirURL.appendingPathComponent("response_\(id).json")
        var payload: [String: Any] = ["decision": decision]
        if let reason = reason { payload["reason"] = reason }
        if let answers = answers { payload["answers"] = answers }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: responseURL, options: [.atomic])
        }

        // Append to the decision audit trail (shown in the Decision History
        // submenu). Hint is capped — the log records what was decided, not
        // full file contents.
        if let req = request {
            var entry: [String: Any] = [
                "ts": Date().timeIntervalSince1970,
                "tool": req.tool,
                "project": req.project ?? "",
                "hint": String(req.hint.prefix(200)),
                "decision": decision,
                // Which app was hosting the session — the audit trail should
                // say where a decision came from, not just what it was.
                "host": req.hostBundle ?? "",
            ]
            // For a question, "answer" alone says nothing — the log needs to
            // record what was actually chosen on the user's behalf.
            if let answers = answers { entry["answers"] = answers }
            if let line = try? JSONSerialization.data(withJSONObject: entry) {
                let logURL = dirURL.appendingPathComponent("decisions.jsonl")
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(line)
                    handle.write(Data([0x0A]))
                    try? handle.close()
                } else {
                    try? (String(decoding: line, as: UTF8.self) + "\n")
                        .write(to: logURL, atomically: true, encoding: .utf8)
                }
            }
        }
        // Remove the request file ourselves right away — don't wait for
        // hook.sh's own poll loop to notice and delete it. Otherwise our
        // poll() can see the still-there (already-answered) request on its
        // next tick, treat it as new (currentRequestId was just reset to
        // nil by setIdle()), and re-trigger setPending() — including a
        // second, spurious Ping sound.
        try? FileManager.default.removeItem(at: dirURL.appendingPathComponent("request_\(id).json"))
        try? FileManager.default.removeItem(at: legacyRequestURL)
        respondedIds.insert(id)
    }

    /// `decision` is allow / deny / pass / answer. `reason` rides along to the
    /// hook as the permissionDecisionReason, so a card that offers a specific
    /// choice ("keep planning") can say which one was taken instead of a
    /// generic "denied".
    func respond(_ decision: String, reason: String? = nil) {
        guard let id = currentRequestId, !isDismissing else { return }
        writeDecision(id: id, request: currentRequest, decision: decision, reason: reason,
                      answers: decision == "answer" ? collectedAnswers : nil)
        // Verdict animation first — the decision is already on disk, so the
        // hook isn't waiting on this. setIdle + surfacing the next queued
        // request happen when the card finishes leaving, so back-to-back
        // approvals read as distinct cards instead of content swapping.
        isDismissing = true
        animateCardDismiss(decision: decision) { [weak self] in
            guard let self = self else { return }
            self.isDismissing = false
            self.setIdle()
            // A denial deserves a beat of visible disappointment — but only
            // after setIdle has put the real mood back, since it would
            // otherwise overwrite the flash immediately.
            if decision == "deny" { self.flashMood("sad", for: 3.0) }
            self.poll()
        }
    }

    @objc func allow() { respond("allow") }

    @objc func deny() {
        // On a plan card the deny button doesn't say "no", it says "keep
        // planning" — so the hook should pass that on rather than a bare
        // rejection Claude has to guess the meaning of.
        guard currentRequest?.tool == "ExitPlanMode" else {
            respond("deny")
            return
        }
        respond("deny", reason: "Not yet — keep planning. The user wants the plan refined before any of it is implemented.")
    }

    /// Debug/docs helper: `touch ~/.config/claude-menubar-buddy/capture_card`
    /// while a card is showing and the app renders it to card_selfie.png in
    /// the same directory. Exists because the non-activating panel renders
    /// blank through ScreenCaptureKit (screencapture gets only the blur
    /// material), so an in-process render is the only faithful screenshot.
    func captureCardSelfieIfRequested() {
        let flagURL = dirURL.appendingPathComponent("capture_card")
        guard FileManager.default.fileExists(atPath: flagURL.path) else { return }
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
