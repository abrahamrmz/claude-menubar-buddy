import AppKit
import BuddyCore
import Foundation
import Settings

// Claude Menu Bar Buddy — hardware-free stand-in for the M5Stick Hardware
// Buddy. A PreToolUse hook (~/.config/claude-menubar-buddy/hook.sh) writes
// pending_request.json when Claude Code needs a permission decision; this
// app polls for it, shows Approve/Deny in the menu bar, and writes back
// response_<id>.json for the hook to pick up.
//
// File layout (SPM requires top-level statements to live in main.swift, so
// the bootstrap stays here; everything else is AppDelegate extensions):
//   ApprovalCard.swift — the card's assembly and lifecycle
//   CardLayout.swift   — the card's visual vocabulary (pills, accents, text)
//   CardDecision.swift — what answering the card does (respond/verdict/log)
//   Menus.swift        — the dropdown menu and its in-place refresh
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
    // Title and body go in as ARGUMENTS, never spliced into the script text.
    // Both can carry a project name — which is just a folder name, i.e.
    // whatever happened to be on disk — and swapping quotes for apostrophes
    // was not enough: a name ending in a backslash swallowed the closing
    // quote and the notification died silently.
    let script = """
    on run argv
        display notification (item 1 of argv) with title (item 2 of argv)
    end run
    """
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", script, body, title]
    try? task.run()
}

// CLAUDE_BUDDY_CONFIG_DIR exists for the debug/selfie instance and nothing
// else: pointed at a scratch directory, a test copy of the app sees only the
// requests injected for it — while the real app keeps serving the real queue,
// the user's global hotkeys keep answering REAL cards, and decisions.jsonl
// stops collecting approvals of props. (Learned the direct way: a fake card
// on the shared dir got ⌘⏎'d by the user within two seconds, out of habit.)
// Trust-wise it adds nothing new: whoever can set this app's environment
// already controls the LaunchAgent plist that launches it.
let dirURL = ProcessInfo.processInfo.environment["CLAUDE_BUDDY_CONFIG_DIR"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/claude-menubar-buddy")

/// Debug captures are opt-in per launch: without CLAUDE_BUDDY_DEBUG in the
/// environment, the capture_* flag files do nothing whatsoever.
///
/// They earn their keep — a non-activating panel renders blank through
/// ScreenCaptureKit, so an in-process render is the only faithful screenshot
/// of the card, which is exactly what you want while working on its layout.
/// But they render whatever card is on screen, and that card can be a diff
/// carrying a credential; the PNG lands on disk; and any process running as
/// this user can create the flag that asks for one. A fine trade while
/// debugging your own layout, a bad one to leave standing on a shared machine.
let debugCapturesEnabled: Bool = {
    guard let value = ProcessInfo.processInfo.environment["CLAUDE_BUDDY_DEBUG"] else { return false }
    return !["", "0", "false", "no"].contains(value.lowercased())
}()
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

    // Present only for AskUserQuestion: the questions Claude wants answered,
    // verbatim from the tool call, so the card can offer the same options the
    // native picker would.
    let choices: [ChoiceQuestion]?

    // How many characters of the real command/diff didn't fit in `hint`.
    // Approving what you cannot see is the one thing this card must never
    // make easy, so a non-zero count is spelled out on it. Optional: an older
    // hook.sh doesn't write the field, and absent means "nothing was cut".
    let hidden: Int?

    enum CodingKeys: String, CodingKey {
        case id, tool, hint, project, ts, cwd, choices, hidden
        case hostBundle = "host_bundle"
        case termProgram = "term_program"
    }
}

struct ChoiceQuestion: Decodable {
    let question: String
    let header: String?
    let options: [ChoiceOption]
}

struct ChoiceOption: Decodable {
    let label: String
    // Optional purely defensively — the tool schema requires it, but a card
    // that silently vanishes because one field was missing would be worse
    // than one with a bare label.
    let description: String?
}

/// Every pet is pixel art, and Cocoa's default interpolation blurs it the
/// moment the view is bigger than the source.
///
/// Only when magnifying, and only when *both* axes fit: dropping interpolation
/// while shrinking throws pixels away instead of averaging them, which is the
/// one case where smoothing is the better answer.
class PixelArtImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        if let image = image, image.size.width <= bounds.width, image.size.height <= bounds.height {
            NSGraphicsContext.current?.imageInterpolation = .none
        }
        super.draw(dirtyRect)
    }
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

    // One listing of the config directory per poll tick, shared by everyone
    // who reads it: pending requests, done markers, turn_start markers and the
    // debug capture flags. Between them they were scanning the same directory
    // three times over and stat'ing four more files every single second, for a
    // folder that rarely holds a dozen entries.
    var dirEntries: [URL] = []

    func refreshDirEntries() {
        dirEntries = (try? FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }

    /// Whether a debug capture flag is present, going by the tick's listing
    /// instead of its own stat. Deliberately NOT how autoEditsEnabled is
    /// read: that one gets checked immediately after the flag file is
    /// written, where a listing up to a second old would report the state the
    /// user just changed away from.
    ///
    /// The CLAUDE_BUDDY_DEBUG check lives in here rather than only at the call
    /// site, so a capture added later can't quietly arrive ungated — the gate
    /// belongs to the mechanism, not to whoever remembers to ask for it.
    func debugFlagIsSet(_ name: String) -> Bool {
        guard debugCapturesEnabled else { return false }
        return dirEntries.contains { $0.lastPathComponent == name }
    }

    // Built once and reused — menuWillOpen updates these items' text in
    // place rather than swapping statusItem.menu out from under an
    // already-opening menu (which is unsafe / can glitch mid-open).
    var idleMenu: NSMenu!
    var statusLineItem: NSMenuItem!
    var tokensLineItem: NSMenuItem!
    var activityLineItem: NSMenuItem!
    var fiveHourLineItem: NSMenuItem!
    var weeklyLineItem: NSMenuItem!
    var burnLineItem: NSMenuItem!
    // Settings window (see SettingsWindow.swift). Built lazily and kept, so
    // reopening it returns to the tab you were on.
    var settingsWindowController: SettingsWindowController?
    var onboardingWindowController: OnboardingWindowController?
    // Shown in the menu only when the setup check finds something broken —
    // the buddy looks identical whether the hook is wired or not, so without
    // this the failure mode is "it just never does anything".
    var setupWarningItem: NSMenuItem!
    var lastHealth: BuddyHealth?
    var lastHealthAt = Date.distantPast
    weak var toastThresholdReadout: NSTextField?
    var alwaysAllowTable: AlwaysAllowTable?
    // A week of decisions, for the Decision History summary. The window's
    // logic lives in BuddyCore; see DecisionStats.swift for why it's held
    // in memory and not re-read from the log.
    var decisions = DecisionWindow()
    // Consecutive mood refreshes spent doing nothing, counted by considerYawn.
    var idleSinceYawn = 0
    // (sampled-at, tokens-today) for the fallback burn rate, pruned to 2h.
    // In memory on purpose: it measures the pace of the session you're in,
    // and a rate stitched across a restart would be measuring a gap.
    var velocitySamples: [(date: Date, tokens: Int)] = []
    // Highest projected-limit warning already sent this 5-hour window, and
    // the reading it was judged against (a big drop = the window rolled and
    // the warnings are due again). Not persisted, for the same reason.
    var notifiedProjection = 0
    var lastProjectionPct = 0
    var sessionsSubmenuTop: NSMenuItem!
    var historySubmenuTop: NSMenuItem!
    var petMoodLineItem: NSMenuItem!
    // Tracks the last mood actually computed from usage, separate from
    // whatever GIF is on screen right now — a "heart" or "celebrate" flash
    // temporarily overrides the displayed GIF without losing track of what
    // to revert to.
    var lastComputedMood = "idle"
    // Limit-derived mood only (idle/tired/stressed/critical/asleep), ignoring "working" —
    // the celebrate-on-refresh detection must not misfire on a plain
    // working→idle transition when a turn ends.
    var lastLimitMood = "idle"
    // What applyMoodGif last put on screen. Reloading the same GIF restarts
    // its animation loop, which at the 5s refresh cadence would make the pet
    // visibly stutter — so same-mood applies are skipped.
    var displayedMood: String?
    var flashWorkItem: DispatchWorkItem?

    // A pet nobody can see doesn't need to be redrawing. NSImageView.animates
    // keeps a GIF looping whether or not its view is on screen, and the two
    // biggest offenders are precisely the ones nobody is looking at: the
    // dropdown's pet loops all day behind a closed menu, and both pets loop
    // against a locked or sleeping display. Locked and asleep are separate
    // flags because waking the display doesn't unlock the screen.
    var screenLocked = false
    var displayAsleep = false
    var animationsPaused: Bool { screenLocked || displayAsleep }
    // Session ids already greeted with the "excited" pose, and whether the
    // set has had its first (seed) pass — see noticeNewSessions().
    var seenTurnSessions: Set<String> = []
    var seededTurnSessions = false

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
    // Ticks only while a card is on screen: samples the hardware modifier
    // state so the button whose shortcut is half-held (⌘ down, ⏎ not yet)
    // lights up "armed". Polled because the panel is non-activating (no
    // local flagsChanged events reach us) and a global monitor would drag
    // in the Accessibility permission this app deliberately does without.
    var modifierWatchTimer: Timer?
    // One-shot, rescheduled with fresh jitter after each squash; nil whenever
    // fidgets are stopped. See Fidgets.swift.
    var fidgetSquashTimer: Timer?
    // True while the verdict/exit animation runs — poll() must not surface
    // the next queued request (or rebuild the card) mid-animation, and a
    // second ⌘⏎ mash must not double-respond.
    var isDismissing = false
    // Multiple-choice cards (AskUserQuestion): which question of the call is
    // on screen, and the labels picked so far. A call can carry up to four
    // questions, so the card walks them one at a time and answers all at once
    // at the end — the tool takes a single answers map.
    var choiceIndex = 0
    var collectedAnswers: [String: String] = [:]
    // A request the user reached past the front of the line for. poll()
    // re-sorts by age every second, so without this the oldest would take the
    // card straight back (see Queue.swift).
    var pinnedRequestId: String?
    // Set when the card change is the user's own doing — they don't need to
    // be pinged about a card they just asked for.
    var switchingCardByHand = false

    // Turn-finished toast (see Toast.swift).
    var toastWindow: NSPanel?
    var toastDismissWorkItem: DispatchWorkItem?
    // The pet's speech bubble (SpeechBubble.swift). The two "last" fields
    // are its rate limiter — the bubble should feel like an aside, not a
    // ticker, so repeats and rapid-fire are dropped at the source.
    var speechBubbleWindow: NSPanel?
    var speechBubbleDismissWork: DispatchWorkItem?
    var lastSpeechBubbleText: String?
    var lastSpeechBubbleAt = Date.distantPast
    // Toast minimum duration now lives in Defaults (Settings ▸ Behavior);
    // see Prefs.swift.

    /// One sweep at launch for the debris the live protocol can't clean up
    /// itself: response files whose hook died before consuming them,
    /// turn-start markers from sessions killed mid-turn while the app wasn't
    /// running, and debug selfies. A day of age is the line — everything the
    /// protocol actually uses lives for seconds (responses) or is capped at
    /// 30 minutes (turn markers), so anything older is guaranteed garbage.
    func sweepStaleArtifacts() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return }
        let now = Date()
        for url in entries {
            let name = url.lastPathComponent
            let sweepable = name.hasPrefix("response_") || name.hasPrefix("turn_start_")
                || name.hasSuffix("_selfie.png")
            guard sweepable,
                  let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                      .contentModificationDate,
                  now.timeIntervalSince(mtime) > 24 * 60 * 60 else { continue }
            try? fm.removeItem(at: url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Owner-only. This directory carries the command, diff or file content
        // of every pending request, plus the decision log and its one rotated
        // predecessor. The hook creates it with the shell's umask — 0755 on a
        // stock Mac — which on a shared or managed machine lets any other local
        // account read what Claude Code has been asked to do. Gating the debug
        // screenshots while leaving that readable would be half a fix.
        // Two calls: the first for a fresh install, the second because
        // createDirectory won't touch the mode of a directory that already
        // exists (the hook usually gets there first).
        try? FileManager.default.createDirectory(
            at: dirURL, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: dirURL.path)
        sweepStaleArtifacts()
        loadDecisionWindow()

        approvalHotKeys.onAllow = { [weak self] in self?.decideViaHotKey("allow") }
        approvalHotKeys.onDeny = { [weak self] in self?.decideViaHotKey("deny") }
        approvalHotKeys.onAlwaysAllow = { [weak self] in self?.decideViaHotKey("always") }
        approvalHotKeys.onJumpToHost = { [weak self] in self?.jumpToHost() }
        approvalHotKeys.onChoice = { [weak self] index in self?.chooseOptionViaHotKey(index) }
        approvalHotKeys.onQueuePick = { [weak self] index in self?.selectQueued(index) }

        // variableLength, not squareLength: the icon grows a count and (in
        // auto-edits mode) a pencil beside the panda.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildIdleMenu()
        setIdle()
        if floatingPetVisible { showFloatingPet() }

        // Nothing to look at, nothing to animate. Both pets stop redrawing
        // while the screen is locked or the display is asleep, and pick up
        // again on the way back.
        let workspace = NSWorkspace.shared.notificationCenter
        _ = workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
            self?.displayAsleep = true
            self?.applyAnimationPolicy()
        }
        _ = workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
            self?.displayAsleep = false
            self?.applyAnimationPolicy()
        }
        let distributed = DistributedNotificationCenter.default()
        _ = distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
                                    object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            self?.applyAnimationPolicy()
        }
        _ = distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                    object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.applyAnimationPolicy()
        }

        // .common (not just .default) so this keeps firing while an NSMenu
        // dropdown is open — AppKit switches the run loop to .eventTracking
        // mode during that time, and a plain scheduledTimer would go silent
        // until the menu closes, delaying pending-request detection.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(t, forMode: .common)
        timer = t

        // Off the main thread: `claude --version` spawns a Node process and
        // costs the better part of a second cold, and the setup check that
        // wants the answer runs when the menu opens.
        DispatchQueue.global(qos: .utility).async { BuddyHealth.refreshClaudeVersion() }

        // Last, so the menu bar icon and the pet are already up behind it —
        // the welcome points at both.
        showOnboardingIfFirstRun()
    }

    /// The setup check re-reads settings.json and hashes hook.sh, which is
    /// cheap but not free, and the answer changes about once a month. Cache it
    /// for a minute so opening the menu repeatedly doesn't repeat the work.
    func cachedHealth() -> BuddyHealth {
        if let health = lastHealth, Date().timeIntervalSince(lastHealthAt) < 60 {
            return health
        }
        let health = BuddyHealth.inspect()
        lastHealth = health
        lastHealthAt = Date()
        return health
    }

    /// Re-applies the animation policy to the floating pet. Has to run after
    /// every GIF swap, because setGif turns animation back on each time it
    /// loads one.
    func applyAnimationPolicy() {
        let floatingWanted = !animationsPaused
        if floatingImageView?.animates != floatingWanted {
            floatingImageView?.animates = floatingWanted
        }
        // Fidgets pause under the same rules as GIF frames, plus their own
        // (occlusion, the Calm pet switch) — one choke point for both.
        applyFidgetPolicy()
    }

    func setIdle() {
        currentRequestId = nil
        currentRequest = nil
        currentCommandBase = nil
        currentQuietAction = nil
        choiceIndex = 0
        collectedAnswers = [:]
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

    /// How long after a request's `ts` its hook is still listening for a
    /// response. hook.sh polls for 55s after writing the request (110 × 0.5s)
    /// and then hands the decision to the native prompt; the margin covers
    /// per-iteration overhead. Past this, an answer from the buddy reaches
    /// nobody — the card must retire rather than collect it (see respond()).
    static let hookAnswerWindow: TimeInterval = 60

    /// All live request files, oldest first. Expired ones are deleted on
    /// sight so they can't wedge the queue. Normally the hook removes its own
    /// file when it gives up, and the card follows within a tick — this cut
    /// is for the orphans (a hook killed with SIGKILL, a terminal window torn
    /// down), which used to keep a card on screen asking a question whose
    /// answerer was already gone.
    func scanRequests() -> [PendingRequest] {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        var requests: [PendingRequest] = []

        var urls = dirEntries.filter {
            $0.lastPathComponent.hasPrefix("request_") && $0.pathExtension == "json"
        }
        if dirEntries.contains(where: { $0.lastPathComponent == legacyRequestURL.lastPathComponent }) {
            urls.append(legacyRequestURL)
        }

        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let req = try? JSONDecoder().decode(PendingRequest.self, from: data) else { continue }
            if let ts = req.ts, now - ts > Self.hookAnswerWindow {
                DebugLog.note("swept expired request \(req.id) (\(req.tool)) — \(Int(now - ts))s old, window is \(Int(Self.hookAnswerWindow))s")
                try? fm.removeItem(at: url)
                continue
            }
            if respondedIds.contains(req.id) { continue }
            requests.append(req)
        }
        // Unordered on purpose: ordering (age + pin) is QueuePolicy's job,
        // and every consumer goes through orderedRequests().
        return requests
    }

    func poll() {
        refreshDirEntries()
        // Mid-verdict-animation: don't touch the card or surface the next
        // request; respond()'s completion re-runs poll() the moment the exit
        // finishes.
        //
        // The capture helpers moved below this line rather than above it. A
        // screenshot taken mid-verdict catches the card still wearing the ✓
        // wash of the decision that is on its way out — which, on a card whose
        // content has already been rebuilt for the NEXT request, reads as a
        // pending request that was somehow approved before anyone saw it.
        if isDismissing { return }

        if debugCapturesEnabled {
            captureCardSelfieIfRequested()
            capturePetSelfieIfRequested()
            captureBubbleSelfieIfRequested()
            captureIconSelfieIfRequested()
            captureSettingsSelfieIfRequested()
            captureOnboardingSelfieIfRequested()
            captureDecisionStatsIfRequested()
        }

        processDoneMarkers()
        processCompactMarkers()
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
            // Keeps the token-velocity history filling (and the projected
            // limit warnings firing) whether or not the menu is ever opened.
            recordTokenVelocitySample()
            updateBurnLine()
            updatePetMood()
        }

        let requests = orderedRequests()
        guard let first = requests.first else {
            if currentRequestId != nil {
                // Resolved WITHOUT an app decision — hook timeout, answered
                // in the terminal, or the session was cancelled. Neutral
                // fade, deliberately distinct from the ✓/✕ verdict flash:
                // the buddy did not approve anything here.
                DebugLog.note("request \(currentRequestId ?? "?") resolved outside the app (timeout, terminal, or cancelled) — card retired neutrally")
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
            DebugLog.note("card up: \(first.id) (\(first.tool)\(first.project.map { ", \($0)" } ?? "")) — \(requests.count - 1) queued behind")
            setPending(first, queued: requests.count - 1)
        } else if requests.count - 1 != lastQueuedCount {
            // Same request on screen but the line behind it changed length.
            // Only refresh the card and icon badge — rebuilding the pending
            // menu here could glitch it mid-open.
            lastQueuedCount = requests.count - 1
            applyPendingStatusIcon(for: first, queued: lastQueuedCount)
            // The line got longer or shorter, so how many ⌘-numbers are worth
            // borrowing changed with it.
            approvalHotKeys.enable(jump: jumpTarget(for: first) != nil,
                                   choices: first.choices?.first?.options.count ?? 0,
                                   queue: lastQueuedCount > 0 ? min(9, requests.count) : 0)
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
