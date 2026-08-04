import AppKit
import Foundation

// Claude Menu Bar Buddy — hardware-free stand-in for the M5Stick Hardware
// Buddy. A PreToolUse hook (~/.config/claude-menubar-buddy/hook.sh) writes
// pending_request.json when Claude Code needs a permission decision; this
// app polls for it, shows Approve/Deny in the menu bar, and writes back
// response_<id>.json for the hook to pick up.

// UNUserNotificationCenter requires a real .app bundle (mainBundle must have
// a valid bundleProxyForCurrentProcess) — this runs as a raw SPM binary from
// .build/debug, which crashes on launch if UserNotifications is touched at
// all. osascript's "display notification" has no such requirement.
func sendNotification(title: String, body: String) {
    let script = "display notification \"\(body.replacingOccurrences(of: "\"", with: "'"))\" with title \"\(title.replacingOccurrences(of: "\"", with: "'"))\""
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script]
    try? task.run()
}

let dirURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/claude-menubar-buddy")
// Written by hook.sh versions before the one-file-per-request queue; still
// honored so an in-flight session running the old hook isn't orphaned.
let legacyRequestURL = dirURL.appendingPathComponent("pending_request.json")

struct PendingRequest: Decodable {
    let id: String
    let tool: String
    let hint: String
    // Optional so request files written by an older hook.sh (no project field)
    // still decode instead of being silently ignored by poll().
    let project: String?
    let ts: Double?
}

// Returns the menu item plus the NSImageView inside it, so callers that need
// to swap the GIF later (e.g. mood changes) don't have to rebuild the item.
// If target/action are given, a transparent NSButton is layered over the
// GIF so clicking the pet (even mid-menu-tracking) fires the action —
// AppKit only reliably delivers clicks to real controls inside a custom
// NSMenuItem view, not to plain NSViews/NSImageViews via gesture recognizers.
func gifMenuItem(named name: String, target: AnyObject? = nil, action: Selector? = nil) -> (NSMenuItem, NSImageView) {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let size = NSSize(width: 220, height: 90)
    let container = NSView(frame: NSRect(origin: .zero, size: size))
    // Square frame, not 128x64 — the GIFs aren't 2:1 (buddy is 128x128,
    // species art varies per pet), so a non-square box forced a squash.
    // scaleProportionallyUpOrDown then letterboxes each pet's real aspect
    // ratio inside this square instead of distorting it.
    let side: CGFloat = 80
    let frame = NSRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    let imageView = NSImageView(frame: frame)
    setGif(on: imageView, named: name)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    container.addSubview(imageView)
    if let target = target, let action = action {
        let button = NSButton(frame: frame)
        button.title = ""
        button.isBordered = false
        button.target = target
        button.action = action
        button.toolTip = "Pet the buddy"
        container.addSubview(button)
    }
    item.view = container
    return (item, imageView)
}

func setGif(on imageView: NSImageView, named name: String) {
    guard let url = Bundle.module.url(forResource: name, withExtension: "gif", subdirectory: "Resources"),
          let image = NSImage(contentsOf: url) else { return }
    // Leave image.size at its native pixel dimensions (each GIF has its own
    // aspect ratio) so .scaleProportionallyUpOrDown on the view fits it
    // without distortion, instead of stretching everything to one fixed box.
    imageView.image = image
    imageView.animates = true
}

func statusMenuItem(_ text: String) -> NSMenuItem {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
        string: text,
        attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
    )
    return item
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
    return "\(n)"
}

func availableSpecies() -> [String] {
    guard let url = Bundle.module.url(forResource: "species", withExtension: "txt", subdirectory: "Resources"),
          let text = try? String(contentsOf: url, encoding: .utf8) else {
        return ["buddy"]
    }
    let names = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    return names.isEmpty ? ["buddy"] : names
}

// window.isMovableByWindowBackground alone doesn't reliably drag when a
// subview (here, an NSImageView filling the whole content area) is what
// actually receives the mouseDown — the hit-tested view can swallow the
// event before the window's own background-drag logic gets a chance, and
// this was inconsistent enough in testing (2026-07-12) to just implement
// dragging explicitly instead of trusting the flag.
final class DraggablePetImageView: NSImageView {
    private var dragStartMouseScreenLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    // Without this, the first click on the pet while the app is inactive is
    // swallowed by activation and the drag never starts. The app is inactive
    // almost always once the non-activating approval card is in use (that
    // panel deliberately never activates us), which made the pet undraggable
    // exactly whenever the card was on screen.
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

// Codex-style floating desktop pet: a borderless, always-on-top window that
// shows just the panda GIF, draggable anywhere on screen, independent of
// the menu bar dropdown. Deliberately minimal — no speech bubble, no
// click-to-chat (Claude Code has no API for that, see revealSession's
// comment) — just ambient presence, which is the part that's actually
// buildable today.
final class FloatingPetWindow: NSWindow {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                    styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var currentRequestId: String?
    // How many requests are waiting behind the one currently shown — used to
    // decide when the bubble's "(+N queued)" suffix needs a refresh without
    // rebuilding the whole pending menu (unsafe while the menu is open).
    var lastQueuedCount = 0
    // Active Claude Code sessions (transcript activity in the last ~15s),
    // shown as a number next to the pet in the menu bar while idle.
    var lastActiveCount = 0
    var usage = UsageSnapshot()
    // Belt-and-suspenders against the same request file being seen twice
    // (e.g. the hook writes it again, or a filesystem event fires twice)
    // right after we've already answered it.
    var respondedIds = Set<String>()

    // Built once and reused — menuWillOpen updates these items' text in
    // place rather than swapping statusItem.menu out from under an
    // already-opening menu (which is unsafe / can glitch mid-open).
    var idleMenu: NSMenu!
    var statusLineItem: NSMenuItem!
    var tokensLineItem: NSMenuItem!
    var activityLineItem: NSMenuItem!
    var fiveHourLineItem: NSMenuItem!
    var weeklyLineItem: NSMenuItem!
    var sessionsSubmenuTop: NSMenuItem!
    var historySubmenuTop: NSMenuItem!
    var alwaysSubmenuTop: NSMenuItem!
    var petImageView: NSImageView!
    var petMoodLineItem: NSMenuItem!
    // Tracks the last mood actually computed from usage, separate from
    // whatever GIF is on screen right now — a "heart" or "celebrate" flash
    // temporarily overrides the displayed GIF without losing track of what
    // to revert to.
    var lastComputedMood = "idle"
    // Limit-derived mood only (idle/tired/sleepy/asleep), ignoring "working" —
    // the celebrate-on-refresh detection must not misfire on a plain
    // working→idle transition when a turn ends.
    var lastLimitMood = "idle"
    // What applyMoodGif last put on screen. Reloading the same GIF restarts
    // its animation loop, which at the 5s refresh cadence would make the pet
    // visibly stutter — so same-mood applies are skipped.
    var displayedMood: String?
    var flashWorkItem: DispatchWorkItem?

    // Codex-style floating desktop pet — panda only (Ray, 2026-07-12).
    var floatingWindow: FloatingPetWindow?
    var floatingImageView: NSImageView?
    var floatingPetVisible: Bool {
        get { UserDefaults.standard.object(forKey: "floatingPetVisible") == nil ? true : UserDefaults.standard.bool(forKey: "floatingPetVisible") }
        set { UserDefaults.standard.set(newValue, forKey: "floatingPetVisible") }
    }
    // How many 1s poll() ticks between background usage/mood refreshes for
    // the floating pet — it has no "menu opened" moment to piggyback on
    // like the dropdown does, so it needs its own cheap periodic check.
    // 5s (down from 30s) so the working↔idle animation reacts within a few
    // seconds of a turn starting/ending; affordable because UsageReader
    // caches per-file token counts and only reads appended transcript bytes.
    var floatingRefreshTickCounter = 0
    let floatingRefreshEveryTicks = 5

    // Approval card above the floating pet (xisland-inspired): title row
    // with project+tool, monospaced scrollable body with the FULL command /
    // mini-diff, Allow/Deny buttons. Content is rebuilt per request; only
    // the panel window itself is reused.
    var statusBubbleWindow: NSWindow?
    var currentRequest: PendingRequest?

    // ⌘⏎ / ⇧⌘⏎, live only while a request is pending (see HotKeys.swift).
    let approvalHotKeys = ApprovalHotKeys()
    // The current card's buttons, kept so the hotkey path can flash the
    // matching button's pressed state before dismissing.
    weak var allowButtonRef: PressablePillButton?
    weak var denyButtonRef: PressablePillButton?
    weak var alwaysButtonRef: PressablePillButton?
    // Base command (e.g. "gh") of the Bash request currently on screen, when
    // one could be extracted — enables the "Always allow" button/hotkey.
    var currentCommandBase: String?
    // What the card's quiet third row does for the CURRENT request (always
    // allow / auto-edits / review in VS Code) — ⌥⌘⏎ triggers it too.
    var currentQuietAction: (() -> Void)?
    // True while the verdict/exit animation runs — poll() must not surface
    // the next queued request (or rebuild the card) mid-animation, and a
    // second ⌘⏎ mash must not double-respond.
    var isDismissing = false

    // Turn-finished toast: same visual language as the approval card,
    // compact, no buttons, auto-dismissing. Fed by done_<session>.json
    // files that notify-done.sh writes on Stop.
    var toastWindow: NSPanel?
    var toastDismissWorkItem: DispatchWorkItem?
    // Turns shorter than this don't get a toast — you were watching anyway.
    // (The macOS banner threshold lives in notify-done.sh; this one is
    // deliberately lower because a toast at the pet is much less intrusive.)
    let toastMinSeconds = 15

    // Thresholds match ClaudeBar's scheme (see the community-project survey):
    // <50% used = healthy, 50-80% = warning, >80% = critical. Persist the
    // highest threshold already notified-for per limit so we don't re-fire
    // the same notification every time the menu happens to be opened.
    var notifiedFiveHour: Int {
        get { UserDefaults.standard.integer(forKey: "notifiedFiveHour") }
        set { UserDefaults.standard.set(newValue, forKey: "notifiedFiveHour") }
    }
    var notifiedWeekly: Int {
        get { UserDefaults.standard.integer(forKey: "notifiedWeekly") }
        set { UserDefaults.standard.set(newValue, forKey: "notifiedWeekly") }
    }

    var selectedSpecies: String {
        get { UserDefaults.standard.string(forKey: "selectedSpecies") ?? "buddy" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedSpecies") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        approvalHotKeys.onAllow = { [weak self] in self?.decideViaHotKey("allow") }
        approvalHotKeys.onDeny = { [weak self] in self?.decideViaHotKey("deny") }
        approvalHotKeys.onAlwaysAllow = { [weak self] in self?.decideViaHotKey("always") }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildIdleMenu()
        setIdle()
        if floatingPetVisible { showFloatingPet() }

        // .common (not just .default) so this keeps firing while an NSMenu
        // dropdown is open — AppKit switches the run loop to .eventTracking
        // mode during that time, and a plain scheduledTimer would go silent
        // until the menu closes, delaying pending-request detection.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }

    func buildIdleMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let (petItem, imageView) = gifMenuItem(named: "\(selectedSpecies)_idle", target: self, action: #selector(petClicked))
        petImageView = imageView
        menu.addItem(petItem)
        petMoodLineItem = statusMenuItem("🐼 Active and happy")
        menu.addItem(petMoodLineItem)
        menu.addItem(withTitle: "No pending requests", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        statusLineItem = statusMenuItem("○ Idle")
        tokensLineItem = statusMenuItem("Tokens today: —")
        activityLineItem = statusMenuItem("Last activity: —")
        fiveHourLineItem = statusMenuItem("5-hour limit: —")
        weeklyLineItem = statusMenuItem("Weekly limit: —")
        menu.addItem(statusLineItem)
        menu.addItem(tokensLineItem)
        menu.addItem(activityLineItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(fiveHourLineItem)
        menu.addItem(weeklyLineItem)
        menu.addItem(NSMenuItem.separator())
        sessionsSubmenuTop = NSMenuItem(title: "Active Sessions", action: nil, keyEquivalent: "")
        sessionsSubmenuTop.submenu = NSMenu()
        menu.addItem(sessionsSubmenuTop)
        historySubmenuTop = NSMenuItem(title: "Decision History", action: nil, keyEquivalent: "")
        historySubmenuTop.submenu = NSMenu()
        menu.addItem(historySubmenuTop)
        alwaysSubmenuTop = NSMenuItem(title: "Auto-allowed Commands", action: nil, keyEquivalent: "")
        alwaysSubmenuTop.submenu = NSMenu()
        menu.addItem(alwaysSubmenuTop)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildSpeciesSubmenuItem())
        let floatingItem = NSMenuItem(title: "Floating Pet", action: #selector(toggleFloatingPet), keyEquivalent: "")
        floatingItem.target = self
        floatingItem.state = floatingPetVisible ? .on : .off
        menu.addItem(floatingItem)
        let autoEditsItem = NSMenuItem(title: "Auto-approve Edits", action: #selector(toggleAutoEdits), keyEquivalent: "")
        autoEditsItem.target = self
        autoEditsItem.state = autoEditsEnabled ? .on : .off
        autoEditsItem.toolTip = "While on, Edit/Write/NotebookEdit are approved instantly with no card. Uncheck to go back to ask-before-each-edit."
        menu.addItem(autoEditsItem)
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        idleMenu = menu
        // petImageView was just recreated with the idle GIF — invalidate the
        // same-mood skip so the next applyMoodGif really loads its GIF.
        displayedMood = nil
    }

    // Codex-style floating pet — panda only, ambient status, no chat bubble
    // (see FloatingPetWindow's comment for why). Position persists across
    // launches; defaults to the bottom-right of the main screen.
    func showFloatingPet() {
        if floatingWindow == nil {
            let side: CGFloat = 120
            let window = FloatingPetWindow(size: NSSize(width: side, height: side))
            let imageView = DraggablePetImageView(frame: NSRect(x: 0, y: 0, width: side, height: side))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            setGif(on: imageView, named: "buddy_\(lastComputedMood)")
            window.contentView?.addSubview(imageView)
            window.delegate = self
            if let saved = UserDefaults.standard.string(forKey: "floatingPetOrigin"),
               NSPointFromString(saved) != .zero {
                window.setFrameOrigin(NSPointFromString(saved))
            } else if let screen = NSScreen.main {
                let margin: CGFloat = 40
                window.setFrameOrigin(NSPoint(
                    x: screen.visibleFrame.maxX - side - margin,
                    y: screen.visibleFrame.minY + margin
                ))
            }
            floatingWindow = window
            floatingImageView = imageView
        }
        floatingWindow?.orderFront(nil)
    }

    func hideFloatingPet() {
        floatingWindow?.orderOut(nil)
        hideStatusBubble()
        hideDoneToast()
    }

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
    func pillButton(title: String, shortcut: String, fill: NSColor, textColor: NSColor, action: Selector) -> PressablePillButton {
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
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let body = String(req.hint.prefix(2000))
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
        let base = req.tool == "Bash" ? commandBase(from: req.hint) : nil
        currentCommandBase = base
        let isEditTool = ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(req.tool)
        let isPlan = req.tool == "ExitPlanMode"
        let hasQuietRow = base != nil || isEditTool || isPlan
        let alwaysRowHeight: CGFloat = hasQuietRow ? 26 + 8 : 0
        let cardHeight = pad + buttonRowHeight + alwaysRowHeight + 10 + blockHeight + 10 + headerHeight + pad

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
        window.contentView = card

        let stripe = NSView(frame: NSRect(x: 0, y: 0, width: stripeWidth, height: cardHeight))
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = accent.cgColor
        card.addSubview(stripe)

        // Header: [icon chip] Tool                     [+N] [project]
        let headerY = cardHeight - pad - headerHeight
        let chip = NSImageView(frame: NSRect(x: contentX, y: headerY + 1, width: 24, height: 24))
        chip.wantsLayer = true
        chip.layer?.backgroundColor = accent.withAlphaComponent(0.22).cgColor
        chip.layer?.cornerRadius = 6
        if let symbol = NSImage(systemSymbolName: toolSymbol(req.tool), accessibilityDescription: req.tool) {
            chip.image = symbol.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            chip.contentTintColor = accent
        }
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
            let badge = pillLabel("+\(queued)", textColor: .black,
                                  background: NSColor.systemOrange)
            badge.toolTip = "\(queued) more request\(queued == 1 ? "" : "s") waiting"
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
        card.addSubview(passButton)
        rightEdge -= 28

        let titleField = NSTextField(labelWithString: req.tool)
        titleField.font = NSFont.boldSystemFont(ofSize: 14)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: contentX + 32, y: headerY + 4,
                                  width: rightEdge - contentX - 32, height: 18)
        card.addSubview(titleField)

        // Body: the full command / mini-diff inside a code-block well.
        let block = NSView(frame: NSRect(x: contentX, y: pad + buttonRowHeight + alwaysRowHeight + 10,
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
        scroll.documentView = textView
        block.addSubview(scroll)

        let buttonWidth: CGFloat = (cardWidth - contentX - pad - 8) / 2
        let allowButton = pillButton(title: "✓ Allow", shortcut: "⌘⏎",
                                     fill: .systemGreen, textColor: .white, action: #selector(allow))
        allowButton.frame = NSRect(x: contentX, y: pad, width: buttonWidth, height: buttonRowHeight)
        card.addSubview(allowButton)
        allowButtonRef = allowButton

        let denyButton = pillButton(title: "✕ Deny", shortcut: "⇧⌘⏎",
                                    fill: NSColor.white.withAlphaComponent(0.10),
                                    textColor: .systemRed, action: #selector(deny))
        denyButton.frame = NSRect(x: contentX + buttonWidth + 8, y: pad, width: buttonWidth, height: buttonRowHeight)
        card.addSubview(denyButton)
        denyButtonRef = denyButton

        // Quieter full-width row above the pills, per tool kind.
        if hasQuietRow {
            let quietButton: PressablePillButton
            if let base = base {
                quietButton = pillButton(title: "⚡ Always allow \(base)", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(alwaysAllow))
                currentQuietAction = { [weak self] in self?.alwaysAllow() }
            } else if isEditTool {
                quietButton = pillButton(title: "⚡ Auto-approve edits from now on", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(autoApproveEditsFromCard))
                currentQuietAction = { [weak self] in self?.autoApproveEditsFromCard() }
            } else {
                quietButton = pillButton(title: "↗ Review in VS Code — auto-accept, manual, tell Claude…", shortcut: "⌥⌘⏎",
                                         fill: NSColor.white.withAlphaComponent(0.07),
                                         textColor: accent, action: #selector(passToNative))
                currentQuietAction = { [weak self] in self?.passToNative() }
            }
            quietButton.layer?.cornerRadius = 13
            quietButton.frame = NSRect(x: contentX, y: pad + buttonRowHeight + 8,
                                       width: cardWidth - contentX - pad, height: 26)
            card.addSubview(quietButton)
            alwaysButtonRef = quietButton
        } else {
            currentQuietAction = nil
        }

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

    func hideStatusBubble() {
        statusBubbleWindow?.orderOut(nil)
    }

    /// Default spot for any pet-attached window (approval card, done toast):
    /// centered above the pet's head. Keeps it on screen: with the pet
    /// parked near the top the "above the head" spot is offscreen (the card
    /// silently opened out of view), so flip it below the pet; and a pet
    /// hugging a side edge would push a centered window past it, so clamp
    /// horizontally.
    func originNearPet(for size: NSSize) -> NSPoint {
        guard let pet = floatingWindow else { return .zero }
        let petFrame = pet.frame
        var origin = NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY + 6)
        if let screen = pet.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.y + size.height > visible.maxY {
                origin.y = petFrame.minY - 6 - size.height
            }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        return origin
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

    @objc func toggleFloatingPet() {
        floatingPetVisible.toggle()
        if floatingPetVisible { showFloatingPet() } else { hideFloatingPet() }
        buildIdleMenu()
        if currentRequestId == nil {
            setIdle()
            updatePetMood()
        }
    }

    // Where the user last left the card, as an origin offset from the pet's
    // origin. Nil until the card is first positioned; once the user drags
    // the card somewhere, it stays glued to the pet at THAT offset instead
    // of snapping back above its head on the next request.
    var cardOffset: NSPoint?

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? FloatingPetWindow {
            UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "floatingPetOrigin")
            if statusBubbleWindow?.isVisible == true {
                positionStatusBubble(above: window)
            }
        } else if let panel = notification.object as? NSWindow, panel === statusBubbleWindow,
                  let pet = floatingWindow {
            cardOffset = NSPoint(x: panel.frame.origin.x - pet.frame.origin.x,
                                 y: panel.frame.origin.y - pet.frame.origin.y)
        }
    }

    func buildSpeciesSubmenuItem() -> NSMenuItem {
        let top = NSMenuItem(title: "Choose Buddy", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for species in availableSpecies() {
            let item = NSMenuItem(title: species.capitalized, action: #selector(chooseSpecies(_:)), keyEquivalent: "")
            item.representedObject = species
            item.target = self
            item.state = (species == selectedSpecies) ? .on : .off
            sub.addItem(item)
        }
        top.submenu = sub
        return top
    }

    @objc func chooseSpecies(_ sender: NSMenuItem) {
        guard let species = sender.representedObject as? String else { return }
        selectedSpecies = species
        buildIdleMenu()
        setIdle()
        updatePetMood()
    }

    // Fires right before the dropdown is shown to the user — usage/status
    // is computed fresh at that moment instead of on a background timer.
    // Updates item text in place; never reassigns statusItem.menu here.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === idleMenu else { return }
        usage = UsageReader.snapshot()
        updateUsageLabels()
    }

    func updateUsageLabels() {
        let count = usage.activeSessions.count
        lastActiveCount = count
        updateIdleTitle()
        let statusText = count > 0
            ? "● Active — \(count) session\(count == 1 ? "" : "s")"
            : "○ Idle"
        statusLineItem.attributedTitle = NSAttributedString(
            string: statusText,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        tokensLineItem.attributedTitle = NSAttributedString(
            string: "Tokens today: \(formatTokens(usage.tokensToday))",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        if let last = usage.lastActivity {
            let mins = max(0, Int(Date().timeIntervalSince(last) / 60))
            activityLineItem.attributedTitle = NSAttributedString(
                string: "Last activity: \(mins)m ago",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
            )
        }
        let stale = planUsageIsStale
        if let fh = usage.fiveHourPct {
            updateLimitLine(fiveHourLineItem, label: "5-hour limit", pct: fh, stale: stale)
            if !stale {
                checkThreshold(pct: fh, label: "5-hour limit", lastNotified: notifiedFiveHour) { self.notifiedFiveHour = $0 }
            }
        }
        if let sd = usage.weeklyPct {
            updateLimitLine(weeklyLineItem, label: "Weekly limit", pct: sd, stale: stale)
            if !stale {
                checkThreshold(pct: sd, label: "Weekly limit", lastNotified: notifiedWeekly) { self.notifiedWeekly = $0 }
            }
        }
        updatePetMood()
        updateSessionsSubmenu()
        updateHistorySubmenu()
        updateAlwaysSubmenu()
    }

    /// One item per always-allowed base command; clicking removes it, so the
    /// card comes back for that command from then on.
    func updateAlwaysSubmenu() {
        guard let submenu = alwaysSubmenuTop.submenu else { return }
        submenu.removeAllItems()
        let list = readAlwaysAllow()
        if list.isEmpty {
            alwaysSubmenuTop.title = "Auto-allowed Commands"
            submenu.addItem(withTitle: "None yet — ⚡ on a Bash card adds one", action: nil, keyEquivalent: "")
            return
        }
        alwaysSubmenuTop.title = "Auto-allowed Commands (\(list.count))"
        for base in list {
            let item = NSMenuItem(title: "⚡ \(base) — click to remove",
                                  action: #selector(removeAlwaysAllow(_:)), keyEquivalent: "")
            item.representedObject = base
            item.target = self
            submenu.addItem(item)
        }
    }

    @objc func removeAlwaysAllow(_ sender: NSMenuItem) {
        guard let base = sender.representedObject as? String else { return }
        writeAlwaysAllow(readAlwaysAllow().filter { $0 != base })
    }

    /// Last 10 decisions, newest first, from decisions.jsonl (appended by
    /// respond()). Only the tail of the file is read — the log grows forever
    /// by design (it's the user's audit trail) but the menu never pays for
    /// its full length.
    func updateHistorySubmenu() {
        guard let submenu = historySubmenuTop.submenu else { return }
        submenu.removeAllItems()
        let logURL = dirURL.appendingPathComponent("decisions.jsonl")
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        var added = 0
        if let data = try? Data(contentsOf: logURL), !data.isEmpty {
            let tail = data.count > 32_768 ? Data(data.suffix(32_768)) : data
            let lines = String(decoding: tail, as: UTF8.self)
                .split(separator: "\n").suffix(10).reversed()
            for line in lines {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let decision = obj["decision"] as? String,
                      let tool = obj["tool"] as? String else { continue }
                let icon = decision == "allow" ? "✓" : decision == "pass" ? "→" : "✕"
                var title = "\(icon) \(tool)"
                if let project = obj["project"] as? String, !project.isEmpty { title += " — \(project)" }
                if let ts = obj["ts"] as? Double {
                    title += "   \(timeFormatter.string(from: Date(timeIntervalSince1970: ts)))"
                }
                submenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
                added += 1
            }
        }
        if added == 0 {
            submenu.addItem(withTitle: "No decisions yet", action: nil, keyEquivalent: "")
        }
        submenu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open Full Log…", action: #selector(openDecisionLog), keyEquivalent: "")
        openItem.target = self
        submenu.addItem(openItem)
    }

    @objc func openDecisionLog() {
        NSWorkspace.shared.open(dirURL.appendingPathComponent("decisions.jsonl"))
    }

    func bar(_ pct: Int, width: Int = 10) -> String {
        let filled = min(width, max(0, pct * width / 100))
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
    }

    /// Only Claude Desktop writes plan-usage-history.json; with Desktop
    /// closed the numbers freeze at the last sample. Past this age they're
    /// history, not status — the UI grays them out and the pet/notification
    /// logic ignores them entirely.
    var planUsageIsStale: Bool {
        guard let sampled = usage.planUsageDate else { return true }
        return Date().timeIntervalSince(sampled) > 30 * 60
    }

    func formatAge(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds >= 86_400 { return "\(seconds / 86_400)d" }
        if seconds >= 3_600 { return "\(seconds / 3_600)h" }
        return "\(max(1, seconds / 60))m"
    }

    /// Fresh reading: colored by threshold, as always. Stale reading: gray,
    /// tagged with its age, and clickable to launch Claude Desktop (the only
    /// thing that can produce a fresh sample).
    func updateLimitLine(_ item: NSMenuItem, label: String, pct: Int, stale: Bool) {
        var text = "\(label): \(bar(pct)) \(pct)%"
        if stale, let sampled = usage.planUsageDate {
            text += "  · \(formatAge(sampled)) ago"
        }
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: stale ? NSColor.tertiaryLabelColor : thresholdColor(pct),
                         .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
        )
        if stale {
            item.action = #selector(openClaudeDesktop(_:))
            item.target = self
            item.toolTip = "Last sampled by Claude Desktop \(usage.planUsageDate.map(formatAge) ?? "?") ago — click to open Claude Desktop and refresh"
        } else {
            item.action = nil
            item.target = nil
            item.toolTip = nil
        }
    }

    @objc func openClaudeDesktop(_ sender: NSMenuItem) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // <50% used = healthy, 50-80% = warning, >80% = critical.
    func thresholdColor(_ pct: Int) -> NSColor {
        if pct >= 80 { return .systemRed }
        if pct >= 50 { return .systemOrange }
        return .systemGreen
    }

    func thresholdLevel(_ pct: Int) -> Int {
        if pct >= 80 { return 80 }
        if pct >= 50 { return 50 }
        return 0
    }

    // Fires a system notification the first time a limit crosses into a new,
    // higher threshold band. `lastNotified` guards against re-firing every
    // time the menu is opened while still in the same band.
    func checkThreshold(pct: Int, label: String, lastNotified: Int, setNotified: @escaping (Int) -> Void) {
        let level = thresholdLevel(pct)
        guard level > lastNotified else { return }
        setNotified(level)
        guard level > 0 else { return }
        let title = level >= 80 ? "Claude \(label) critical" : "Claude \(label) warning"
        sendNotification(title: title, body: "\(label) usage is at \(pct)%.")
    }

    // Rebuilds the "Active Sessions" submenu in place — one item per session
    // showing its project path + minutes since last activity, clicking it
    // brings Claude Desktop to the front (not session-specific — Claude
    // Code has no API to resume/focus one particular session, see
    // revealSession's comment).
    func updateSessionsSubmenu() {
        guard let submenu = sessionsSubmenuTop.submenu else { return }
        submenu.removeAllItems()
        if usage.activeSessions.isEmpty {
            submenu.addItem(withTitle: "No active sessions", action: nil, keyEquivalent: "")
            sessionsSubmenuTop.title = "Active Sessions"
            return
        }
        sessionsSubmenuTop.title = "Active Sessions (\(usage.activeSessions.count))"
        for session in usage.activeSessions.sorted(by: { $0.lastActivity > $1.lastActivity }) {
            let mins = max(0, Int(Date().timeIntervalSince(session.lastActivity) / 60))
            let item = NSMenuItem(
                title: "\(session.projectPath) — \(mins)m ago",
                action: #selector(revealSession(_:)),
                keyEquivalent: ""
            )
            item.target = self
            submenu.addItem(item)
        }
    }

    // The pet's mood follows the 5-hour limit, not the weekly one — it's
    // the one that actually blocks you mid-session, so it's the one worth
    // dramatizing. <50% used = active, 50-79% = tired, 80-99% = sleepy,
    // 100% = asleep.
    func petMood(for pct: Int?) -> String {
        guard let pct = pct else { return "idle" }
        if pct >= 100 { return "asleep" }
        if pct >= 80 { return "sleepy" }
        if pct >= 50 { return "tired" }
        return "idle"
    }

    func petMoodText(_ mood: String) -> String {
        switch mood {
        case "working": return "⚡ Working — session active"
        case "tired": return "😅 Getting tired..."
        case "sleepy": return "😴 Getting sleepy..."
        case "asleep": return "💤 Fast asleep (5h limit reached)"
        default: return "🐼 Active and happy"
        }
    }

    /// True while any Claude Code turn is actually in flight, going by the
    /// turn_start markers notify-done.sh maintains (written on
    /// UserPromptSubmit, removed on Stop). This is the fix for the pet
    /// flickering back to idle mid-turn: transcript mtime goes quiet during
    /// long tool runs (a 30s build writes nothing), but the marker doesn't.
    /// The 30-minute cap self-heals orphans from sessions killed mid-turn.
    func anyTurnInFlight() -> Bool {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return false }
        let now = Date()
        for url in urls where url.lastPathComponent.hasPrefix("turn_start_") {
            if let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               now.timeIntervalSince(mtime) < 30 * 60 {
                return true
            }
        }
        return false
    }

    func updatePetMood() {
        // Stale plan data (Claude Desktop closed) is treated as unknown —
        // a pet asleep over an 11-day-old "100%" would be lying.
        let limitMood = petMood(for: planUsageIsStale ? nil : usage.fiveHourPct)
        // Was tired/sleepy/asleep last time we checked, and just dropped
        // back to healthy — the 5-hour window rolled over. Worth a little
        // fanfare instead of silently snapping back to the idle GIF.
        // (Not when the drop is only the reading going stale, though.)
        let limitJustRefreshed = lastLimitMood != "idle" && limitMood == "idle" && !planUsageIsStale
        lastLimitMood = limitMood

        // Working (turn marker in flight, or a transcript touched in the
        // last ~15s as fallback for sessions without the notify-done hook)
        // beats the intermediate limit moods, but not asleep — a pet at
        // 100% of the 5-hour limit can't be typing.
        let mood: String
        if limitMood == "asleep" {
            mood = "asleep"
        } else if anyTurnInFlight() || !usage.activeSessions.isEmpty {
            mood = "working"
        } else {
            mood = limitMood
        }
        lastComputedMood = mood

        if limitJustRefreshed {
            sendNotification(title: "Claude 5-hour limit refreshed", body: "Buddy is back and ready to go!")
            if currentRequestId == nil { flashMood("celebrate", for: 4.0) }
        } else if flashWorkItem == nil && currentRequestId == nil {
            // Don't stomp an in-progress heart/celebrate flash (it reverts
            // to lastComputedMood by itself) or the pending pose.
            applyMoodGif(mood)
        }
    }

    /// Only the panda has a "working" GIF (the species art comes from the
    /// hardware-buddy firmware, which has no such pose) — fall back to idle
    /// rather than leaving the previous GIF frozen on screen.
    func gifName(for species: String, mood: String) -> String {
        if Bundle.module.url(forResource: "\(species)_\(mood)", withExtension: "gif", subdirectory: "Resources") != nil {
            return "\(species)_\(mood)"
        }
        return "\(species)_idle"
    }

    func applyMoodGif(_ mood: String) {
        guard mood != displayedMood else { return }
        displayedMood = mood
        setGif(on: petImageView, named: gifName(for: selectedSpecies, mood: mood))
        petMoodLineItem.attributedTitle = NSAttributedString(
            string: petMoodText(mood),
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        // Floating pet is panda-only regardless of the dropdown's species
        // choice (Ray, 2026-07-12: "ทำแค่ panda ก็พอ").
        if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: gifName(for: "buddy", mood: mood))
        }
    }

    // Shows a mood GIF ("heart" on click, "celebrate" on limit reset) for a
    // few seconds, then reverts to whatever the current real mood is.
    func flashMood(_ mood: String, for seconds: Double) {
        flashWorkItem?.cancel()
        applyMoodGif(mood)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Nil first: it doubles as the "flash in progress" flag that
            // keeps updatePetMood from stomping the flash early.
            self.flashWorkItem = nil
            self.applyMoodGif(self.lastComputedMood)
        }
        flashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @objc func petClicked() {
        NSSound(named: "Tink")?.play()
        flashMood("heart", for: 2.0)
    }

    // Claude Code has no public API to resume/focus a specific existing
    // session — its claude-cli:// deep link only starts a NEW session in a
    // directory (see code.claude.com/docs/en/deep-links), and Claude
    // Desktop exposes no AppleScript/scripting interface at all. Best
    // available: bring Claude Desktop to the front generically. Not
    // session-specific, but closer to "go look at your sessions" than
    // opening Finder was.
    @objc func revealSession(_ sender: NSMenuItem) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Menu bar title while no request is pending: pet plus the number of
    /// sessions currently active (hidden when zero) — same at-a-glance
    /// signal Masko showed. ✏️ marks auto-approve-edits mode: a standing
    /// grant of power should never be invisible.
    func updateIdleTitle() {
        guard currentRequestId == nil else { return }
        let editsBadge = autoEditsEnabled ? "✏️" : ""
        statusItem.button?.title = "🐼\(editsBadge)" + (lastActiveCount > 0 ? "\(lastActiveCount)" : "")
    }

    @objc func toggleAutoEdits() {
        if autoEditsEnabled {
            try? FileManager.default.removeItem(at: autoEditsFlagURL)
        } else {
            try? Data().write(to: autoEditsFlagURL)
        }
        buildIdleMenu()
        if currentRequestId == nil {
            setIdle()
            updatePetMood()
        }
    }

    func setIdle() {
        currentRequestId = nil
        currentRequest = nil
        currentCommandBase = nil
        currentQuietAction = nil
        approvalHotKeys.disable()
        updateIdleTitle()
        statusItem.menu = idleMenu
        hideStatusBubble()
        // Both pets back to the real mood (they were showing the pending
        // pose); displayedMood is cleared because setPending bypassed
        // applyMoodGif when it swapped the GIFs.
        displayedMood = nil
        applyMoodGif(lastComputedMood)
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
            if line.hasPrefix("--- quita") {
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
        statusItem.button?.title = queued > 0 ? "🐼❗\(queued + 1)" : "🐼❗"
        currentRequestId = req.id
        currentRequest = req
        lastQueuedCount = queued

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
        let hintText = String(req.hint.prefix(1200))
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
        if queued > 0 {
            menu.addItem(statusMenuItem("\(queued) more request\(queued == 1 ? "" : "s") waiting…"))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Allow", action: #selector(allow), keyEquivalent: "a")
        menu.addItem(withTitle: "Deny", action: #selector(deny), keyEquivalent: "d")
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
        approvalHotKeys.enable()
        NSSound(named: "Ping")?.play()
    }

    /// All live request files, oldest first. Expired ones (hook gave up at
    /// ~55s; anything older is an orphan from a killed hook) are deleted on
    /// sight so they can't wedge the queue.
    func scanRequests() -> [PendingRequest] {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        var requests: [PendingRequest] = []

        var urls = (try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("request_") && $0.pathExtension == "json" } ?? []
        if fm.fileExists(atPath: legacyRequestURL.path) { urls.append(legacyRequestURL) }

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let req = try? JSONDecoder().decode(PendingRequest.self, from: data) else { continue }
            if let ts = req.ts, now - ts > 75 {
                try? fm.removeItem(at: url)
                continue
            }
            if respondedIds.contains(req.id) { continue }
            requests.append(req)
        }
        return requests.sorted { ($0.ts ?? 0) < ($1.ts ?? 0) }
    }

    func formatDuration(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    // MARK: - Always-allow list (mirrors hook.sh's fast path)

    // Buddy-managed allowlist of Bash base commands, stored beside the
    // request files. hook.sh consults it BEFORE writing a request, so
    // always-allowed commands are approved instantly with no card at all.
    // Deliberately separate from ~/.claude/settings.json — the buddy never
    // edits Claude Code's own config.
    var alwaysAllowURL: URL { dirURL.appendingPathComponent("always_allow.json") }

    // Flag file for auto-approve-edits mode; hook.sh fast-paths Edit/Write/
    // NotebookEdit while it exists. A file (not UserDefaults) so the hook
    // can read it without talking to the app.
    var autoEditsFlagURL: URL { dirURL.appendingPathComponent("auto_approve_edits") }
    var autoEditsEnabled: Bool { FileManager.default.fileExists(atPath: autoEditsFlagURL.path) }

    func readAlwaysAllow() -> [String] {
        guard let data = try? Data(contentsOf: alwaysAllowURL),
              let list = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return list
    }

    func writeAlwaysAllow(_ list: [String]) {
        if let data = try? JSONSerialization.data(withJSONObject: list.sorted(), options: [.prettyPrinted]) {
            try? data.write(to: alwaysAllowURL, options: [.atomic])
        }
    }

    /// First token of the command that isn't an env assignment — must match
    /// hook.sh's extraction so the button's promise ("gh won't ask again")
    /// is exactly what the fast path later honors. Returns nil for anything
    /// that doesn't look like a plain command name.
    func commandBase(from hint: String) -> String? {
        guard let firstLine = hint.split(separator: "\n").first else { return nil }
        for token in firstLine.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            if token.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil { continue }
            let base = String(token)
            guard base.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil else { return nil }
            return base
        }
        return nil
    }

    /// Picks up done_<session>.json markers written by notify-done.sh on
    /// Stop and turns them into a toast at the pet (or a banner when an
    /// approval card has the spotlight). Markers are consumed on sight.
    func processDoneMarkers() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else { return }
        let now = Date().timeIntervalSince1970
        var latest: (project: String, elapsed: Int)? = nil
        for url in urls where url.lastPathComponent.hasPrefix("done_") && url.pathExtension == "json" {
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let elapsed = obj["elapsed"] as? Int else { continue }
            // Stale marker (written while the app wasn't running): a toast
            // about something long finished would only confuse.
            if let ts = obj["ts"] as? Double, now - ts > 60 { continue }
            guard elapsed >= toastMinSeconds else { continue }
            let project = obj["project"] as? String ?? ""
            if latest == nil || elapsed > latest!.elapsed { latest = (project, elapsed) }
        }
        guard let done = latest else { return }
        if currentRequestId != nil {
            // An approval card is up — that keeps the spotlight, the finish
            // notice degrades to a banner.
            sendNotification(title: "Claude Code — \(done.project)",
                             body: "Finished in \(formatDuration(done.elapsed))")
        } else {
            showDoneToast(project: done.project, elapsed: done.elapsed)
            flashMood("celebrate", for: 4.0)
            NSSound(named: "Glass")?.play()
        }
    }

    func showDoneToast(project: String, elapsed: Int) {
        guard floatingPetVisible, floatingWindow != nil else {
            sendNotification(title: "Claude Code — \(project)",
                             body: "Finished in \(formatDuration(elapsed))")
            return
        }
        toastDismissWorkItem?.cancel()

        let width: CGFloat = 300
        let height: CGFloat = 64
        let pad: CGFloat = 12
        let stripeWidth: CGFloat = 4

        let window: NSPanel
        if let existing = toastWindow {
            window = existing
            window.setContentSize(NSSize(width: width, height: height))
        } else {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: height)),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = true
            panel.sharingType = .readOnly
            toastWindow = panel
            window = panel
        }

        let card = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        card.material = .hudWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        window.contentView = card

        let stripe = NSView(frame: NSRect(x: 0, y: 0, width: stripeWidth, height: height))
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = NSColor.systemGreen.cgColor
        card.addSubview(stripe)

        let chip = NSImageView(frame: NSRect(x: pad + stripeWidth, y: (height - 28) / 2, width: 28, height: 28))
        chip.wantsLayer = true
        chip.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.22).cgColor
        chip.layer?.cornerRadius = 7
        if let symbol = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: "done") {
            chip.image = symbol.withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
            chip.contentTintColor = .systemGreen
        }
        card.addSubview(chip)

        let textX = pad + stripeWidth + 36
        let titleField = NSTextField(labelWithString: project.isEmpty ? "Claude Code" : project)
        titleField.font = NSFont.boldSystemFont(ofSize: 13)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: textX, y: height / 2 + 1, width: width - textX - pad, height: 17)
        card.addSubview(titleField)

        let subtitleField = NSTextField(labelWithString: "Turn finished in \(formatDuration(elapsed))")
        subtitleField.font = NSFont.systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.frame = NSRect(x: textX, y: height / 2 - 16, width: width - textX - pad, height: 15)
        card.addSubview(subtitleField)

        let wasVisible = window.isVisible
        window.setFrameOrigin(originNearPet(for: NSSize(width: width, height: height)))
        if wasVisible {
            window.orderFront(nil)
        } else {
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

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let toast = self.toastWindow, toast.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                toast.animator().alphaValue = 0
            }, completionHandler: {
                toast.orderOut(nil)
                toast.alphaValue = 1
            })
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: work)
    }

    func hideDoneToast() {
        toastDismissWorkItem?.cancel()
        toastWindow?.orderOut(nil)
        toastWindow?.alphaValue = 1
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

    /// Same in-process render as the card selfie, for the pet window:
    /// `touch ~/.config/claude-menubar-buddy/capture_pet` → pet_selfie.png.
    func capturePetSelfieIfRequested() {
        let flagURL = dirURL.appendingPathComponent("capture_pet")
        guard FileManager.default.fileExists(atPath: flagURL.path) else { return }
        guard let content = floatingWindow?.contentView, floatingWindow?.isVisible == true else { return }
        try? FileManager.default.removeItem(at: flagURL)
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dirURL.appendingPathComponent("pet_selfie.png"))
        }
    }

    func poll() {
        captureCardSelfieIfRequested()
        capturePetSelfieIfRequested()
        // Mid-verdict-animation: don't touch the card or surface the next
        // request; respond()'s completion re-runs poll() the moment the
        // exit finishes.
        if isDismissing { return }

        processDoneMarkers()
        // Background usage/mood/session-count refresh, throttled to every
        // ~5s — cheap thanks to UsageReader's per-file token cache (stat
        // per file, read appended bytes only). Runs regardless of the
        // floating pet: the menu bar session badge and the working/idle
        // animation need it too.
        floatingRefreshTickCounter += 1
        if floatingRefreshTickCounter >= floatingRefreshEveryTicks {
            floatingRefreshTickCounter = 0
            usage = UsageReader.snapshot()
            lastActiveCount = usage.activeSessions.count
            updateIdleTitle()
            updatePetMood()
        }

        let requests = scanRequests()
        guard let first = requests.first else {
            if currentRequestId != nil {
                // Resolved WITHOUT an app decision — hook timeout, answered
                // in the terminal, or the session was cancelled. Neutral
                // fade, deliberately distinct from the ✓/✕ verdict flash:
                // the buddy did not approve anything here.
                if let window = statusBubbleWindow, window.isVisible {
                    isDismissing = true
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration = 0.25
                        window.animator().alphaValue = 0
                    }, completionHandler: { [weak self] in
                        window.orderOut(nil)
                        window.alphaValue = 1
                        self?.isDismissing = false
                        self?.setIdle()
                    })
                } else {
                    setIdle()
                }
            }
            return
        }
        if first.id != currentRequestId {
            setPending(first, queued: requests.count - 1)
        } else if requests.count - 1 != lastQueuedCount {
            // Same request on screen but the line behind it changed length.
            // Only refresh the card and icon badge — rebuilding the pending
            // menu here could glitch it mid-open.
            lastQueuedCount = requests.count - 1
            statusItem.button?.title = lastQueuedCount > 0 ? "🐼❗\(lastQueuedCount + 1)" : "🐼❗"
            showStatusBubble(for: first, queued: lastQueuedCount)
        }
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
        let isAllow = decision == "allow"
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

    func respond(_ decision: String) {
        guard let id = currentRequestId, !isDismissing else { return }
        let responseURL = dirURL.appendingPathComponent("response_\(id).json")
        let payload = "{\"decision\":\"\(decision)\"}"
        try? payload.write(to: responseURL, atomically: true, encoding: .utf8)

        // Append to the decision audit trail (shown in the Decision History
        // submenu). Hint is capped — the log records what was decided, not
        // full file contents.
        if let req = currentRequest {
            let entry: [String: Any] = [
                "ts": Date().timeIntervalSince1970,
                "tool": req.tool,
                "project": req.project ?? "",
                "hint": String(req.hint.prefix(200)),
                "decision": decision,
            ]
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
        // Verdict animation first — the decision is already on disk, so the
        // hook isn't waiting on this. setIdle + surfacing the next queued
        // request happen when the card finishes leaving, so back-to-back
        // approvals read as distinct cards instead of content swapping.
        isDismissing = true
        animateCardDismiss(decision: decision) { [weak self] in
            guard let self = self else { return }
            self.isDismissing = false
            self.setIdle()
            self.poll()
        }
    }

    @objc func allow() { respond("allow") }
    @objc func deny() { respond("deny") }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
