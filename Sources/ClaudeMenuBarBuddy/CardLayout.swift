import AppKit

// The card's visual vocabulary: the two custom views and the small factories
// every card is assembled from, plus how request text is styled. Split out of
// ApprovalCard.swift (Fase 7.2), which keeps the assembly and lifecycle;
// CardDecision.swift holds what happens when a button is pushed.

// Pill button that visibly sinks while pressed — scales down and dims, then
// springs back. setPressed is public so the ⌘⏎ hotkey path can flash the
// same pressed state: the whole point is that the shortcut FEELS like
// pushing the on-screen button, not like the card silently obeying.
final class PressablePillButton: NSButton {
    // Whether the button is currently lit up as "armed" — the modifier half
    // of its shortcut is being held, so it lifts slightly and grows a bright
    // rim to say "⏎ lands here". The button's own resting border (choice
    // options carry an accent one) is saved on arm and restored on release.
    private var armed = false
    private var restingBorderWidth: CGFloat = 0
    private var restingBorderColor: CGColor?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        setPressed(true)
        // Blocks in the cell's tracking loop; the action fires inside it.
        super.mouseDown(with: event)
        setPressed(false)
    }

    /// Scale about the center, not AppKit's default bottom-left anchor.
    private func centerAnchor(_ layer: CALayer) {
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let f = layer.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: f.midX, y: f.midY)
        }
    }

    /// The lifted "armed" pose, also what a released press springs back to
    /// while the modifier is still held.
    private var armedTransform: CGAffineTransform {
        armed ? CGAffineTransform(scaleX: 1.02, y: 1.05) : .identity
    }

    func setPressed(_ down: Bool) {
        guard let layer = layer else { return }
        centerAnchor(layer)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        layer.setAffineTransform(down ? CGAffineTransform(scaleX: 0.95, y: 0.93) : armedTransform)
        layer.opacity = down ? 0.7 : 1.0
        CATransaction.commit()
    }

    func setArmed(_ on: Bool) {
        guard on != armed, let layer = layer else { return }
        armed = on
        if on {
            restingBorderWidth = layer.borderWidth
            restingBorderColor = layer.borderColor
        }
        centerAnchor(layer)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        layer.borderWidth = on ? 1.5 : restingBorderWidth
        layer.borderColor = on ? NSColor.white.withAlphaComponent(0.9).cgColor : restingBorderColor
        layer.setAffineTransform(armedTransform)
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
}
