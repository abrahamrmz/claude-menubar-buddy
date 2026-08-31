import AppKit
import KeyboardShortcuts

// The card's visual vocabulary: the two custom views and the small factories
// every card is assembled from, plus how request text is styled. Split out of
// ApprovalCard.swift (Fase 7.2), which keeps the assembly and lifecycle;
// CardDecision.swift holds what happens when a button is pushed. The colors,
// faces and metrics themselves live in CardTheme.swift.

/// How a pill is dressed. Three roles, not three color choices: the card has
/// exactly one thing you are meant to press, one thing you press to refuse,
/// and one quieter standing offer — and each is recognizable by shape and
/// weight before any of them is read.
enum PillStyle {
    /// The action. Filled accent with a hard shadow it visibly descends onto.
    case primary
    /// The refusal. Outline only — declining should not compete for the eye.
    case secondary
    /// The standing grant. Same outline, smaller and in body type, because
    /// it is an offer rather than an answer to the question on screen.
    case quiet
}

// Pill button that visibly sinks while pressed. setPressed is public so the
// ⌘⏎ hotkey path can flash the same pressed state: the whole point is that
// the shortcut FEELS like pushing the on-screen button, not like the card
// silently obeying.
//
// The primary pill sinks the way Masko's does — a hard offset shadow in a
// darker shade of its own fill, so the cap sits on a base and the press
// drives it down onto that base. A blurred shadow would read as the button
// floating; this reads as a key with travel.
final class PressablePillButton: NSButton {
    var style: PillStyle = .secondary
    /// Shown only while the modifier half of a shortcut is held, the way
    /// Masko reveals ⌘1…⌘N. The rest of the time the shortcuts live in the
    /// hint bar under the card, so the buttons stay a clean pair of words.
    private(set) var badge: NSTextField?

    // Whether the button is currently lit up as "armed" — the modifier half
    // of its shortcut is being held, so it lifts slightly and grows a bright
    // rim to say "⏎ lands here". The button's own resting border is saved on
    // arm and restored on release.
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

    /// The lifted "armed" pose, also what a released press springs back to
    /// while the modifier is still held. The primary rises instead of
    /// growing: it already has a shadow saying how high off the base it is,
    /// and scaling it would fight that.
    private var armedTransform: CGAffineTransform {
        guard armed else { return .identity }
        return style == .primary ? CGAffineTransform(translationX: 0, y: 1)
                                 : CGAffineTransform(scaleX: 1.02, y: 1.05)
    }

    /// Press and release are deliberately NOT the same motion. Going down is
    /// your finger doing it — short, and eased so it starts fast and lands
    /// soft. Coming back up is the button's own doing, so it springs: a key
    /// rebounds off its base, it doesn't get lifted at constant speed.
    ///
    /// (Both used to run in a bare CATransaction, which interpolates
    /// LINEARLY — constant velocity, dead stop at each end. That is what made
    /// every press on this card feel like a slide rather than a click.)
    func setPressed(_ down: Bool) {
        guard let layer = layer else { return }
        if style != .primary { CardTheme.centerAnchor(layer) }
        let target = down ? pressedTransform : armedTransform
        let current = layer.affineTransform()

        CATransaction.begin()
        CATransaction.setAnimationDuration(down ? 0.07 : 0.0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1))
        if style == .primary {
            // Down onto its own base: the cap travels the shadow's height,
            // and the shadow shrinks to what is left underneath.
            layer.shadowOffset = CGSize(width: 0, height: down ? -1 : -4)
        } else {
            layer.opacity = down ? 0.7 : 1.0
        }
        layer.setAffineTransform(target)
        CATransaction.commit()

        if !down {
            layer.add(CardTheme.spring("transform",
                                       from: NSValue(caTransform3D: CATransform3DMakeAffineTransform(current)),
                                       to: NSValue(caTransform3D: CATransform3DMakeAffineTransform(target)),
                                       damping: 17, stiffness: 420),
                      forKey: "press.release")
        }
    }

    /// How far the button sinks. The primary translates (its shadow already
    /// says how high off the base it sits, and scaling would fight that);
    /// the outlined ones, which have no base, shrink instead.
    private var pressedTransform: CGAffineTransform {
        style == .primary ? CGAffineTransform(translationX: 0, y: -3)
                          : CGAffineTransform(scaleX: 0.98, y: 0.96)
    }

    func setArmed(_ on: Bool) {
        guard on != armed, let layer = layer else { return }
        armed = on
        if on {
            restingBorderWidth = layer.borderWidth
            restingBorderColor = layer.borderColor
        }
        if style != .primary { CardTheme.centerAnchor(layer) }
        let current = layer.affineTransform()

        // The rim fades; the lift springs. Arming is the card answering a
        // held modifier, so it should settle rather than arrive and stop.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.borderWidth = on ? 1.5 : restingBorderWidth
        layer.borderColor = on ? CardTheme.accent.cgColor : restingBorderColor
        layer.setAffineTransform(armedTransform)
        CATransaction.commit()

        layer.add(CardTheme.spring("transform",
                                   from: NSValue(caTransform3D: CATransform3DMakeAffineTransform(current)),
                                   to: NSValue(caTransform3D: CATransform3DMakeAffineTransform(armedTransform)),
                                   damping: 20, stiffness: 360),
                  forKey: "arm")
    }

    /// Gives the button the capsule it shows while a modifier is held.
    func attachBadge(_ text: String) {
        let badge = NSTextField(labelWithString: text)
        badge.font = CardTheme.heading(CardTheme.badgeSize, weight: 700)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = (style == .primary ? CardTheme.ink.withAlphaComponent(0.45)
                                                          : CardTheme.ink.withAlphaComponent(0.55)).cgColor
        badge.sizeToFit()
        let width = ceil(badge.frame.width) + 11
        let height: CGFloat = 18
        badge.frame = NSRect(x: 0, y: 0, width: width, height: height)
        badge.layer?.cornerRadius = height / 2
        badge.isHidden = true
        badge.setAccessibilityElement(false)
        addSubview(badge)
        self.badge = badge
    }

    /// A two-line option: its label, and underneath what picking it means.
    /// These are real text fields rather than one attributed title, because
    /// NSButtonCell will not soft-wrap a title no matter what its paragraph
    /// style or `wraps` say — it honors explicit newlines and clips anything
    /// longer than a line, silently and mid-sentence. That is exactly what a
    /// description must never do: it is what you are choosing on.
    private(set) var stackedTitle: NSTextField?
    private(set) var stackedDetail: NSTextField?

    func attachStackedText(title: NSAttributedString, detail: NSAttributedString?) {
        let titleField = NSTextField(labelWithAttributedString: title)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setAccessibilityElement(false)
        addSubview(titleField)
        stackedTitle = titleField

        if let detail = detail {
            let detailField = NSTextField(wrappingLabelWithString: "")
            detailField.attributedStringValue = detail
            detailField.isSelectable = false
            // Ellipsizes the last line it has room for instead of stopping on
            // a clean word with nothing to say it was cut.
            detailField.lineBreakMode = .byTruncatingTail
            detailField.maximumNumberOfLines = 3
            detailField.setAccessibilityElement(false)
            addSubview(detailField)
            stackedDetail = detailField
        }
    }

    /// Turns "this far down from the top" into a frame origin. NSButton is a
    /// FLIPPED view, so laying its subviews out with the bottom-left
    /// arithmetic the rest of the card uses puts the label under the
    /// description instead of over it. Going through here means the math
    /// reads the same either way and survives the day AppKit disagrees.
    private func fromTop(_ distance: CGFloat, height: CGFloat) -> CGFloat {
        isFlipped ? distance : bounds.height - distance - height
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 12
        // The badge rides the top-right corner on a stacked option (it pairs
        // with the number in the label) and the vertical centre on a plain
        // pill, where there is only one line for it to sit beside.
        if let badge = badge {
            let y = stackedTitle == nil ? (bounds.height - badge.frame.height) / 2
                                        : fromTop(7, height: badge.frame.height)
            badge.setFrameOrigin(NSPoint(x: bounds.maxX - badge.frame.width - 8, y: y))
        }
        guard let titleField = stackedTitle else { return }

        let badgeRoom = badge.map { $0.frame.width + 14 } ?? 0
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = NSRect(x: inset, y: fromTop(7, height: titleHeight),
                                  width: max(0, bounds.width - inset * 2 - badgeRoom),
                                  height: titleHeight)

        guard let detailField = stackedDetail else { return }
        let detailTop = 7 + titleHeight + 3
        let detailHeight = max(0, bounds.height - detailTop - 8)
        detailField.frame = NSRect(x: inset, y: fromTop(detailTop, height: detailHeight),
                                   width: max(0, bounds.width - inset * 2), height: detailHeight)
    }

    /// Pops the badge in and out with the same spring the rest of the card
    /// moves on, so a held ⌘ feels like the card answering rather than a
    /// label blinking on.
    func setBadgeVisible(_ visible: Bool) {
        guard let badge = badge, badge.isHidden == visible else { return }
        badge.isHidden = !visible
        guard visible, let layer = badge.layer else { return }
        CardTheme.centerAnchor(layer)
        layer.add(CardTheme.spring("transform.scale", from: 0.62, to: 1,
                                   damping: 17, stiffness: 340), forKey: "badge.pop")
    }
}

// The silhouette every pet-attached window wears: a speech bubble whose tail
// points back at the pet, so what it says reads as the pet saying it rather
// than as a panel parked nearby. Shared by all three — the approval card, the
// turn-finished toast and the pet's one-line mood bubble — because they are
// the same pet talking, and three hand-rolled outlines would drift.
//
// The bubble is DRAWN, not a layer mask. Two reasons: the selfie path
// (`captureCardSelfieIfRequested`) goes through `cacheDisplay`, which renders
// the view hierarchy and would miss both a layer background and a mask — the
// one way we have to check these windows visually would come back blank —
// and a drawn shape leaves the rest of the window truly transparent, which is
// what lets the window shadow hug the bubble and its tail.
class BubbleBackgroundView: NSView {
    /// Which edge the tail leaves from, and where along it. Set by `aimTail`
    /// once the window and the pet both have frames.
    var tail: TailSide = .bottom { didSet { needsDisplay = true; resizeContent() } }
    var tailPercent: CGFloat = 0.5 { didSet { needsDisplay = true } }
    /// The card keeps the theme's 14pt corner; the mood bubble sets this to
    /// half its height and becomes a capsule with a tail.
    var cornerRadius: CGFloat = CardTheme.cornerRadius { didSet { needsDisplay = true } }

    /// Everything the window shows lives in here, in its own coordinates, so
    /// the layout math never has to know whether a tail is stealing 8pt off
    /// the bottom or the top.
    let content = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(content)
        resizeContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The rounded part, without the tail strip.
    var bodyRect: NSRect {
        switch tail {
        case .bottom:
            return NSRect(x: 0, y: CardTheme.tailHeight,
                          width: bounds.width, height: bounds.height - CardTheme.tailHeight)
        case .top:
            return NSRect(x: 0, y: 0,
                          width: bounds.width, height: bounds.height - CardTheme.tailHeight)
        case .none:
            return bounds
        }
    }

    private func resizeContent() { content.frame = bodyRect }

    override func layout() {
        super.layout()
        resizeContent()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.addPath(CardTheme.bubblePath(in: bounds, tail: tail, percent: tailPercent,
                                         radius: cornerRadius))
        ctx.setFillColor(CardTheme.surface.cgColor)
        ctx.fillPath()
    }
}

/// The approval card's background: the shared bubble plus the same manual
/// drag as the pet (grab the title row or any empty padding; buttons and the
/// text view keep handling their own clicks), so the card can be pulled out
/// of the way of whatever it covers. The toast and the mood bubble don't get
/// this — they leave on their own and ignore the mouse entirely.
final class DraggableCardView: BubbleBackgroundView {
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
    // The per-tool accent is gone: one card, one accent. Which KIND of action
    // is asking is still legible at a glance — the tool's own symbol and its
    // name sit side by side in the header — and the color it used to spend
    // on that now goes to the only place a single accent belongs, which is
    // the thing you are about to press.
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
        label.font = CardTheme.body(CardTheme.metaSize, weight: 500)
        label.textColor = textColor
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = background.cgColor
        let width = ceil(label.intrinsicContentSize.width) + 16
        label.frame = NSRect(x: 0, y: 0, width: width, height: 20)
        label.layer?.cornerRadius = 10
        return label
    }

    // MARK: - Springs

    /// The card's spring vocabulary: physically-settled motion instead of an
    /// ease curve that decelerates and just stops. Runs in the render server
    /// like every Core Animation — the app is not woken per frame, so the
    /// idle-CPU story is untouched. Model values are never changed here; the
    /// animation plays over the layer's real state and lifts off.
    func cardSpring(_ keyPath: String, from: Any, to: Any,
                    damping: CGFloat = 24, stiffness: CGFloat = 380,
                    velocity: CGFloat = 0) -> CASpringAnimation {
        CardTheme.spring(keyPath, from: from, to: to,
                         damping: damping, stiffness: stiffness, velocity: velocity)
    }

    /// AppKit layers anchor at the bottom-left corner, so a transform.scale
    /// without this reads as a stretch hinged on the corner instead of a pop
    /// from the middle.
    func centerAnchor(of layer: CALayer) { CardTheme.centerAnchor(layer) }

    // MARK: - Buttons

    /// A pill in one of the three card roles. The keyboard shortcut is NOT
    /// baked into the title any more: it rides in a capsule that appears
    /// only while its modifier is held, and otherwise lives in the hint bar
    /// under the buttons. A label that permanently reads "Allow  ⌘⏎" spends
    /// a third of the button on something you either already know or are not
    /// currently doing.
    ///
    /// `accessibility` spells the action out for VoiceOver, which would
    /// otherwise announce the raw shortcut glyphs. `symbol` puts an SF Symbol
    /// ahead of the title in the title's own color.
    func pillButton(title: String, shortcut: String, style: PillStyle,
                    action: Selector, accessibility: String,
                    symbol: String? = nil) -> PressablePillButton {
        let button = PressablePillButton(title: "", target: self, action: action)
        button.style = style
        button.isBordered = false
        button.wantsLayer = true
        guard let layer = button.layer else { return button }
        layer.cornerRadius = CardTheme.buttonRadius

        let textColor: NSColor
        let font: NSFont
        switch style {
        case .primary:
            layer.backgroundColor = CardTheme.accent.cgColor
            textColor = .white
            font = CardTheme.heading(CardTheme.buttonSize, weight: 600)
            // Hard, unblurred, in a darker shade of the fill: a base for the
            // cap to land on rather than a glow under a floating thing.
            layer.shadowColor = CardTheme.accentShadow.cgColor
            layer.shadowOpacity = 1
            layer.shadowRadius = 0
            layer.shadowOffset = CGSize(width: 0, height: -4)
            layer.masksToBounds = false
        case .secondary:
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderWidth = 1
            layer.borderColor = CardTheme.inkBorder.cgColor
            textColor = CardTheme.ink.withAlphaComponent(0.50)
            font = CardTheme.heading(CardTheme.buttonSize, weight: 600)
        case .quiet:
            layer.backgroundColor = NSColor.clear.cgColor
            layer.borderWidth = 1
            layer.borderColor = CardTheme.inkBorder.cgColor
            textColor = CardTheme.ink.withAlphaComponent(0.50)
            font = CardTheme.body(CardTheme.metaSize, weight: 500)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString()
        if let symbol = symbol,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
               .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
                   .applying(.init(paletteColors: [textColor]))) {
            let attachment = NSTextAttachment()
            attachment.image = image
            // Nudged below the baseline so the glyph sits optically centered
            // against the title instead of riding its cap height.
            attachment.bounds = NSRect(x: 0, y: -1, width: image.size.width, height: image.size.height)
            // The paragraph style must reach the attachment too: layout takes
            // the alignment from the paragraph's first character, which this
            // now is.
            let lead = NSMutableAttributedString(attachment: attachment)
            lead.append(NSAttributedString(string: " "))
            lead.addAttributes([.paragraphStyle: paragraph],
                               range: NSRange(location: 0, length: lead.length))
            text.append(lead)
        }
        text.append(NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]))
        button.attributedTitle = text
        button.setAccessibilityLabel(accessibility)
        if !shortcut.isEmpty { button.attachBadge(shortcut) }
        return button
    }

    /// One option of a multiple-choice question: its label, and underneath in
    /// smaller type what picking it actually means. Both come verbatim from
    /// the tool call — a card that paraphrased the options would be putting
    /// words in the user's mouth.
    func optionButton(_ option: ChoiceOption, index: Int) -> PressablePillButton {
        let button = PressablePillButton(title: "", target: self, action: #selector(chooseOption(_:)))
        button.style = .secondary
        button.tag = index
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = CardTheme.accentSubtle.cgColor
        button.layer?.cornerRadius = CardTheme.buttonRadius
        button.layer?.borderWidth = 1
        button.layer?.borderColor = CardTheme.accentBorder.cgColor

        let title = NSAttributedString(string: "\(index + 1). \(option.label)", attributes: [
            .font: CardTheme.heading(CardTheme.buttonSize, weight: 600),
            .foregroundColor: CardTheme.inkPrimary,
        ])
        let detail = option.description.flatMap { text -> NSAttributedString? in
            guard !text.isEmpty else { return nil }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            return NSAttributedString(string: text, attributes: [
                .font: CardTheme.body(CardTheme.metaSize),
                .foregroundColor: CardTheme.inkMuted,
                .paragraphStyle: paragraph,
            ])
        }
        button.attachStackedText(title: title, detail: detail)
        button.setAccessibilityLabel(option.description.map { "\(option.label). \($0)" } ?? option.label)
        button.attachBadge("⌘\(index + 1)")
        return button
    }

    /// The persistent line under the buttons. Masko keeps one because the
    /// shortcuts left the button faces: without it a first-time user would
    /// have no way to learn ⌘⏎ exists. It reads at 8pt and 35% ink on
    /// purpose — present for whoever looks, invisible to whoever doesn't.
    func shortcutHintBar(width: CGFloat, jump: Bool, quiet: Bool, choices: Int) -> NSTextField {
        // A cleared shortcut drops out of the line rather than showing a
        // default it no longer answers to.
        func part(_ name: KeyboardShortcuts.Name, _ verb: String) -> String? {
            ApprovalHotKeys.label(for: name).map { "\($0) \(verb)" }
        }
        var parts: [String] = []
        if choices > 0 {
            let first = ApprovalHotKeys.choiceNames.first.flatMap(ApprovalHotKeys.label(for:))
            let last = ApprovalHotKeys.choiceNames.indices.contains(min(choices, 4) - 1)
                ? ApprovalHotKeys.label(for: ApprovalHotKeys.choiceNames[min(choices, 4) - 1]) : nil
            if let first = first, let last = last, choices > 1 {
                parts.append("\(first)–\(last) pick")
            } else if let first = first {
                parts.append("\(first) pick")
            }
        } else {
            parts.append(contentsOf: [part(.approvalAllow, "allow"), part(.approvalDeny, "deny")].compactMap { $0 })
            if quiet, let always = part(.approvalQuiet, "always") { parts.append(always) }
        }
        if jump, let jumpPart = part(.jumpToHost, "jump") { parts.append(jumpPart) }
        let label = NSTextField(labelWithString: parts.joined(separator: " · "))
        label.font = CardTheme.heading(CardTheme.hintSize, weight: 500)
        label.textColor = CardTheme.ink.withAlphaComponent(0.35)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 0, y: 0, width: width, height: 15)
        // The buttons already carry these as accessibility labels; repeating
        // the glyph soup to VoiceOver would be noise.
        label.setAccessibilityElement(false)
        return label
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
    ///
    /// `onLight` picks the palette. The card draws its own near-white well,
    /// where the system greens and reds are a pastel and a glow; the menu bar
    /// dropdown draws on whatever the system appearance says, where only the
    /// semantic colors survive a switch to dark mode. Same text, two
    /// surfaces, and the caller is the only one who knows which.
    func attributedHint(_ text: String, font: NSFont, onLight: Bool = false) -> NSAttributedString {
        let plain = onLight ? CardTheme.inkPrimary : NSColor.labelColor
        let dim = onLight ? CardTheme.inkMuted : NSColor.secondaryLabelColor
        let minus = onLight ? CardTheme.removed : NSColor.systemRed
        let plus = onLight ? CardTheme.added : NSColor.systemGreen

        let result = NSMutableAttributedString()
        var section = 0 // 0 = plain, 1 = removing, 2 = adding
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let color: NSColor
            if line.hasPrefix(AppDelegate.truncationMarker) {
                // Deliberately outside the diff sections — a warning painted
                // diff-green because it landed after "+++ pone" would be the
                // one line on the card that must not blend in.
                color = minus
            } else if line.hasPrefix("--- quita") {
                section = 1
                color = dim
            } else if line.hasPrefix("+++ pone") || line.hasPrefix("+++ contenido") {
                section = 2
                color = dim
            } else {
                switch section {
                case 1: color = minus
                case 2: color = plus
                default: color = plain
                }
            }
            let suffix = index < lines.count - 1 ? "\n" : ""
            result.append(NSAttributedString(string: line + suffix,
                                             attributes: [.font: font, .foregroundColor: color]))
        }
        return result
    }
}
