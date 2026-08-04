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
    var petImageView: NSImageView!
    var petMoodLineItem: NSMenuItem!
    // Tracks the last mood actually computed from usage, separate from
    // whatever GIF is on screen right now — a "heart" or "celebrate" flash
    // temporarily overrides the displayed GIF without losing track of what
    // to revert to.
    var lastComputedMood = "idle"
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
    var floatingRefreshTickCounter = 0
    let floatingRefreshEveryTicks = 30

    // Approval card above the floating pet (xisland-inspired): title row
    // with project+tool, monospaced scrollable body with the FULL command /
    // mini-diff, Allow/Deny buttons. Content is rebuilt per request; only
    // the panel window itself is reused.
    var statusBubbleWindow: NSWindow?
    var currentRequest: PendingRequest?

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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(buildSpeciesSubmenuItem())
        let floatingItem = NSMenuItem(title: "Floating Pet", action: #selector(toggleFloatingPet), keyEquivalent: "")
        floatingItem.target = self
        floatingItem.state = floatingPetVisible ? .on : .off
        menu.addItem(floatingItem)
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        idleMenu = menu
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
        let cardWidth: CGFloat = 360
        let pad: CGFloat = 10
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let body = String(req.hint.prefix(2000))
        let bodyMaxHeight: CGFloat = 150

        let measured = (body as NSString).boundingRect(
            with: NSSize(width: cardWidth - pad * 2 - 14, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: bodyFont]
        )
        let bodyHeight = min(bodyMaxHeight, max(16, ceil(measured.height) + 4))
        let titleHeight: CGFloat = 16
        let buttonRowHeight: CGFloat = 24
        let cardHeight = pad + buttonRowHeight + 6 + bodyHeight + 6 + titleHeight + pad

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
            window = panel
            statusBubbleWindow = window
        }

        // Fresh content view per request — rebuilding is cheaper to reason
        // about than reframing five subviews around a variable-height body.
        let card = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: cardWidth, height: cardHeight)))
        card.material = .hudWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        window.contentView = card

        var title = req.tool
        if let project = req.project, !project.isEmpty { title = "\(project) — \(title)" }
        if queued > 0 { title += "   (+\(queued) queued)" }
        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.boldSystemFont(ofSize: 12)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: pad, y: cardHeight - pad - titleHeight, width: cardWidth - pad * 2, height: titleHeight)
        card.addSubview(titleField)

        let scroll = NSScrollView(frame: NSRect(x: pad, y: pad + buttonRowHeight + 6, width: cardWidth - pad * 2, height: bodyHeight))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.string = body
        textView.font = bodyFont
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        card.addSubview(scroll)

        let buttonWidth: CGFloat = (cardWidth - pad * 2 - 8) / 2
        let allowButton = NSButton(title: "✓ Allow", target: self, action: #selector(allow))
        allowButton.bezelStyle = .rounded
        allowButton.controlSize = .small
        allowButton.frame = NSRect(x: pad, y: pad, width: buttonWidth, height: buttonRowHeight)
        card.addSubview(allowButton)

        let denyButton = NSButton(title: "✕ Deny", target: self, action: #selector(deny))
        denyButton.bezelStyle = .rounded
        denyButton.controlSize = .small
        denyButton.frame = NSRect(x: pad + buttonWidth + 8, y: pad, width: buttonWidth, height: buttonRowHeight)
        card.addSubview(denyButton)

        positionStatusBubble(above: petWindow)
        window.orderFront(nil)
    }

    func hideStatusBubble() {
        statusBubbleWindow?.orderOut(nil)
    }

    func positionStatusBubble(above petWindow: NSWindow) {
        guard let bubble = statusBubbleWindow else { return }
        let petFrame = petWindow.frame
        let bubbleSize = bubble.frame.size
        bubble.setFrameOrigin(NSPoint(
            x: petFrame.midX - bubbleSize.width / 2,
            y: petFrame.maxY + 6
        ))
    }

    @objc func toggleFloatingPet() {
        floatingPetVisible.toggle()
        if floatingPetVisible { showFloatingPet() } else { hideFloatingPet() }
        buildIdleMenu()
        if currentRequestId == nil {
            setIdle()
            updatePetMood(usage.fiveHourPct)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? FloatingPetWindow else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: "floatingPetOrigin")
        if statusBubbleWindow?.isVisible == true {
            positionStatusBubble(above: window)
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
        updatePetMood(usage.fiveHourPct)
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
        if let fh = usage.fiveHourPct {
            fiveHourLineItem.attributedTitle = NSAttributedString(
                string: "5-hour limit: \(bar(fh)) \(fh)%",
                attributes: [.foregroundColor: thresholdColor(fh), .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
            )
            checkThreshold(pct: fh, label: "5-hour limit", lastNotified: notifiedFiveHour) { self.notifiedFiveHour = $0 }
            updatePetMood(fh)
        }
        if let sd = usage.weeklyPct {
            weeklyLineItem.attributedTitle = NSAttributedString(
                string: "Weekly limit: \(bar(sd)) \(sd)%",
                attributes: [.foregroundColor: thresholdColor(sd), .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
            )
            checkThreshold(pct: sd, label: "Weekly limit", lastNotified: notifiedWeekly) { self.notifiedWeekly = $0 }
        }
        updateSessionsSubmenu()
    }

    func bar(_ pct: Int, width: Int = 10) -> String {
        let filled = min(width, max(0, pct * width / 100))
        return String(repeating: "▓", count: filled) + String(repeating: "░", count: width - filled)
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
        case "tired": return "😅 Getting tired..."
        case "sleepy": return "😴 Getting sleepy..."
        case "asleep": return "💤 Fast asleep (5h limit reached)"
        default: return "🐼 Active and happy"
        }
    }

    func updatePetMood(_ fiveHourPct: Int?) {
        let mood = petMood(for: fiveHourPct)
        // Was tired/sleepy/asleep last time we checked, and just dropped
        // back to healthy — the 5-hour window rolled over. Worth a little
        // fanfare instead of silently snapping back to the idle GIF.
        if lastComputedMood != "idle" && mood == "idle" {
            sendNotification(title: "Claude 5-hour limit refreshed", body: "Buddy is back and ready to go!")
            flashMood("celebrate", for: 4.0)
        }
        lastComputedMood = mood
        applyMoodGif(mood)
    }

    func applyMoodGif(_ mood: String) {
        setGif(on: petImageView, named: "\(selectedSpecies)_\(mood)")
        petMoodLineItem.attributedTitle = NSAttributedString(
            string: petMoodText(mood),
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        // Floating pet is panda-only regardless of the dropdown's species
        // choice (Ray, 2026-07-12: "ทำแค่ panda ก็พอ").
        if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: "buddy_\(mood)")
        }
    }

    // Shows a mood GIF ("heart" on click, "celebrate" on limit reset) for a
    // few seconds, then reverts to whatever the current real mood is.
    func flashMood(_ mood: String, for seconds: Double) {
        flashWorkItem?.cancel()
        applyMoodGif(mood)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
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

    func setIdle() {
        statusItem.button?.title = "🐼"
        currentRequestId = nil
        currentRequest = nil
        statusItem.menu = idleMenu
        hideStatusBubble()
        // Floating pet back to its real mood (it was showing the pending GIF).
        if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: "buddy_\(lastComputedMood)")
        }
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
        let hintFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let hintText = String(req.hint.prefix(1200))
        let hintWidth: CGFloat = 340
        let hintMeasured = (hintText as NSString).boundingRect(
            with: NSSize(width: hintWidth - 28, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: hintFont]
        )
        let hintHeight = min(160, ceil(hintMeasured.height) + 8)
        let hintContainer = NSView(frame: NSRect(x: 0, y: 0, width: hintWidth, height: hintHeight))
        let hintField = NSTextField(wrappingLabelWithString: hintText)
        hintField.font = hintFont
        hintField.textColor = .labelColor
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

        showStatusBubble(for: req, queued: queued)
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

    func poll() {
        // Background usage/mood refresh, throttled — the floating pet has
        // no "menu opened" moment to piggyback on like the dropdown does,
        // so it needs its own periodic check. Full jsonl scan isn't free,
        // hence every ~30s rather than every 1s tick.
        if floatingPetVisible {
            floatingRefreshTickCounter += 1
            if floatingRefreshTickCounter >= floatingRefreshEveryTicks {
                floatingRefreshTickCounter = 0
                usage = UsageReader.snapshot()
                if let fh = usage.fiveHourPct { updatePetMood(fh) }
            }
        }

        let requests = scanRequests()
        guard let first = requests.first else {
            if currentRequestId != nil { setIdle() }
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

    func respond(_ decision: String) {
        guard let id = currentRequestId else { return }
        let responseURL = dirURL.appendingPathComponent("response_\(id).json")
        let payload = "{\"decision\":\"\(decision)\"}"
        try? payload.write(to: responseURL, atomically: true, encoding: .utf8)
        // Remove the request file ourselves right away — don't wait for
        // hook.sh's own poll loop to notice and delete it. Otherwise our
        // poll() can see the still-there (already-answered) request on its
        // next tick, treat it as new (currentRequestId was just reset to
        // nil by setIdle()), and re-trigger setPending() — including a
        // second, spurious Ping sound.
        try? FileManager.default.removeItem(at: dirURL.appendingPathComponent("request_\(id).json"))
        try? FileManager.default.removeItem(at: legacyRequestURL)
        respondedIds.insert(id)
        setIdle()
        // Surface the next queued request immediately instead of waiting up
        // to a full 1s timer tick — back-to-back approvals should feel snappy.
        poll()
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
