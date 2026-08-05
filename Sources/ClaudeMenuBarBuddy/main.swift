import AppKit
import Foundation

// Claude Menu Bar Buddy — hardware-free stand-in for the M5Stick Hardware
// Buddy. A PreToolUse hook (~/.config/claude-menubar-buddy/hook.sh) writes
// pending_request.json when Claude Code needs a permission decision; this
// app polls for it, shows Approve/Deny in the menu bar, and writes back
// response_<id>.json for the hook to pick up.
//
// File layout (SPM requires top-level statements to live in main.swift, so
// the bootstrap stays here; everything else is AppDelegate extensions):
//   ApprovalCard.swift — the floating approval card + decisions
//   FloatingPet.swift  — desktop pet window + positioning near it
//   MoodEngine.swift   — signals → mood → GIF swaps
//   Toast.swift        — turn-finished toast
//   Prefs.swift        — Defaults keys + flag files shared with hook.sh
//   HotKeys.swift      — global approval shortcuts
//   UsageStats.swift   — transcript/token/plan-limit reading

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
    // Where the asking session lives and which app hosts it — everything
    // JumpToHost.swift needs to raise that exact window. Also optional: an
    // older hook.sh doesn't write them, and ssh/tmux sessions have no host
    // app at all.
    let cwd: String?
    let hostBundle: String?
    let termProgram: String?

    enum CodingKeys: String, CodingKey {
        case id, tool, hint, project, ts, cwd
        case hostBundle = "host_bundle"
        case termProgram = "term_program"
    }
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
    // Where the user last left the card, as an origin offset from the pet's
    // origin. Nil until the card is first positioned; once the user drags
    // the card somewhere, it stays glued to the pet at THAT offset instead
    // of snapping back above its head on the next request.
    var cardOffset: NSPoint?

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

    // Turn-finished toast (see Toast.swift).
    var toastWindow: NSPanel?
    var toastDismissWorkItem: DispatchWorkItem?
    // Turns shorter than this don't get a toast — you were watching anyway.
    // (The macOS banner threshold lives in notify-done.sh; this one is
    // deliberately lower because a toast at the pet is much less intrusive.)
    let toastMinSeconds = 15

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        approvalHotKeys.onAllow = { [weak self] in self?.decideViaHotKey("allow") }
        approvalHotKeys.onDeny = { [weak self] in self?.decideViaHotKey("deny") }
        approvalHotKeys.onAlwaysAllow = { [weak self] in self?.decideViaHotKey("always") }
        approvalHotKeys.onJumpToHost = { [weak self] in self?.jumpToHost() }

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

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
