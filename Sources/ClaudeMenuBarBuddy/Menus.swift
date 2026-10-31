import AppKit
import BuddyCore

// The menu bar dropdown and its upkeep: the idle menu, the in-place refresh
// that runs when it opens, the usage/limit/burn lines, the Sessions and
// History submenus, and the idle title. Moved out of main.swift (Fase 7.2),
// which keeps bootstrap, the AppDelegate core state, and the poll loop.

func statusMenuItem(_ text: String) -> NSMenuItem {
    let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
        string: text,
        attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
    )
    return item
}

extension AppDelegate {
    func buildIdleMenu() {
        let menu = NSMenu()
        menu.delegate = self
        // No pet up here. A GIF you can only see by opening a menu is a pet
        // nobody watches, and the one on the desktop is visible without a
        // click and answers to being petted. The mood line stays: that is
        // status text, which is what a menu is for.
        petMoodLineItem = statusMenuItem(petMoodText("idle"))
        menu.addItem(petMoodLineItem)
        menu.addItem(withTitle: "No pending requests", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        statusLineItem = statusMenuItem("○ Idle")
        tokensLineItem = statusMenuItem("Tokens today: —")
        activityLineItem = statusMenuItem("Last activity: —")
        fiveHourLineItem = statusMenuItem("5-hour limit: —")
        weeklyLineItem = statusMenuItem("Weekly limit: —")
        burnLineItem = statusMenuItem("Burn: —")
        menu.addItem(statusLineItem)
        menu.addItem(tokensLineItem)
        menu.addItem(activityLineItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(fiveHourLineItem)
        menu.addItem(weeklyLineItem)
        menu.addItem(burnLineItem)
        menu.addItem(NSMenuItem.separator())
        sessionsSubmenuTop = NSMenuItem(title: "Active Sessions", action: nil, keyEquivalent: "")
        sessionsSubmenuTop.submenu = NSMenu()
        menu.addItem(sessionsSubmenuTop)
        historySubmenuTop = NSMenuItem(title: "Decision History", action: nil, keyEquivalent: "")
        historySubmenuTop.submenu = NSMenu()
        menu.addItem(historySubmenuTop)
        menu.addItem(NSMenuItem.separator())
        // The two standing grants stay one click away — they change what the
        // buddy will do without asking, so burying them behind a Settings
        // window would be the wrong kind of tidy. Everything else that used
        // to live here (species, icon style, the always-allow list) moved
        // there in Fase 2.1.
        let floatingItem = NSMenuItem(title: "Floating Pet", action: #selector(toggleFloatingPet), keyEquivalent: "")
        floatingItem.target = self
        floatingItem.state = floatingPetVisible ? .on : .off
        menu.addItem(floatingItem)
        // A submenu, and only while the pet is on screen: sizing something
        // that isn't shown is a dead control, and the row costs nothing when
        // it isn't there. An item with a submenu can't also carry an action,
        // so this can't just hang off the toggle above.
        if floatingPetVisible {
            let sizeItem = NSMenuItem(title: "Pet Size", action: nil, keyEquivalent: "")
            let sizes = NSMenu()
            for (title, value) in [("Small", "small"), ("Medium", "medium"), ("Large", "large")] {
                let item = NSMenuItem(title: title, action: #selector(petSizeChanged(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = value
                item.state = floatingPetSize == value ? .on : .off
                sizes.addItem(item)
            }
            sizeItem.submenu = sizes
            menu.addItem(sizeItem)
        }
        menu.addItem(soundsMenuItem())
        let autoModeItem = NSMenuItem(title: "Modo auto", action: #selector(toggleAutoMode), keyEquivalent: "")
        autoModeItem.target = self
        autoModeItem.state = autoModeEnabled ? .on : .off
        autoModeItem.toolTip = "Lo rutinario pasa sin tarjeta; lo crítico siempre te pregunta. El ícono lleva un rayo mientras está prendido."
        menu.addItem(autoModeItem)
        menu.addItem(NSMenuItem.separator())
        // Always in the menu, hidden unless menuWillOpen finds a real problem.
        setupWarningItem = NSMenuItem(title: "⚠︎ Setup needs attention…",
                                      action: #selector(showSetupCheck), keyEquivalent: "")
        setupWarningItem.target = self
        setupWarningItem.isHidden = true
        menu.addItem(setupWarningItem)
        let welcomeItem = NSMenuItem(title: "Welcome & Setup Check…",
                                     action: #selector(showOnboarding), keyEquivalent: "")
        welcomeItem.target = self
        menu.addItem(welcomeItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        idleMenu = menu
        // petMoodLineItem was just recreated carrying its placeholder text —
        // invalidate the same-mood skip so the next applyMoodGif really
        // rewrites it.
        displayedMood = nil
    }

    // Fires right before the dropdown is shown to the user — usage/status
    // is computed fresh at that moment instead of on a background timer.
    // Updates item text in place; never reassigns statusItem.menu here.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === idleMenu else { return }
        usage = UsageReader.snapshot()
        updateUsageLabels()
        setupWarningItem?.isHidden = cachedHealth().isHealthy
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
        updateBurnLine()
        updatePetMood()
        updateSessionsSubmenu()
        updateHistorySubmenu()
        // The always-allow list lives in Settings ▸ Safety now; refresh it
        // there if that window happens to be open.
        alwaysAllowTable?.reload()
    }

    /// Last 10 decisions, newest first, from decisions.jsonl (appended by
    /// respond()). Only the tail of the file is read — the log grows forever
    /// by design (it's the user's audit trail) but the menu never pays for
    /// its full length.
    func updateHistorySubmenu() {
        guard let submenu = historySubmenuTop.submenu else { return }
        submenu.removeAllItems()
        // Summary first: the ten most recent lines say what just happened,
        // but "am I approving more than usual, and where?" is the question
        // an audit trail is actually kept for.
        let summaryLines = decisionSummaryLines()
        for line in summaryLines {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.attributedTitle = NSAttributedString(
                string: line,
                attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                             .font: NSFont.systemFont(ofSize: 11)]
            )
            submenu.addItem(item)
        }
        if !summaryLines.isEmpty { submenu.addItem(NSMenuItem.separator()) }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        // Both logs, newest first: half the story is what you answered and
        // the other half is what the rule let through without asking.
        let lines = DecisionHistory.latest(
            historyLines(from: "decisions.jsonl", isAuto: false),
            historyLines(from: "auto_decisions.jsonl", isAuto: true),
            limit: 10)
        for line in lines {
            let icon = line.isAuto ? "⚡︎"
                : line.decision == "allow" ? "✓" : line.decision == "pass" ? "→" : "✕"
            var title = "\(icon) \(line.tool)"
            if !line.project.isEmpty { title += " — \(line.project)" }
            title += "   \(timeFormatter.string(from: Date(timeIntervalSince1970: line.ts)))"
            submenu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        }
        if lines.isEmpty {
            submenu.addItem(withTitle: "No decisions yet", action: nil, keyEquivalent: "")
        }
        submenu.addItem(NSMenuItem.separator())
        let openItem = NSMenuItem(title: "Open Full Log…", action: #selector(openDecisionLog), keyEquivalent: "")
        openItem.target = self
        submenu.addItem(openItem)
    }

    /// The tail of one decision log, parsed. The tail rather than the whole
    /// file: these logs grow for months, and the menu only shows ten.
    func historyLines(from fileName: String, isAuto: Bool) -> [HistoryLine] {
        let url = dirURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let tail = data.count > 32_768 ? Data(data.suffix(32_768)) : data
        // The cut can land mid-line; a broken first line is skipped by parse.
        return DecisionHistory.parse(jsonLines: String(decoding: tail, as: UTF8.self), isAuto: isAuto)
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
    /// signal Masko showed. The bolt glyph marks auto mode: a standing grant
    /// of power should never be invisible.
    func updateIdleTitle() {
        guard currentRequestId == nil else { return }
        var label = lastActiveCount > 0
            ? "Claude Menu Bar Buddy — \(lastActiveCount) active session\(lastActiveCount == 1 ? "" : "s")"
            : "Claude Menu Bar Buddy — no pending requests"
        if autoModeEnabled { label += ", modo auto activo" }
        applyStatusIcon(pending: false, count: lastActiveCount,
                        autoMode: autoModeEnabled, accessibility: label)
    }

    /// The "Sonidos" submenu: one row per event, each with its own submenu.
    /// The order, the checkmark and the titles all come from SoundMenu
    /// (BuddyCore); this only paints them.
    func soundsMenuItem() -> NSMenuItem {
        let soundsItem = NSMenuItem(title: "Sonidos", action: nil, keyEquivalent: "")
        let soundsMenu = NSMenu()
        for event in SoundEvent.allCases {
            let stored = storedSoundID(for: event)
            let eventItem = NSMenuItem(title: SoundMenu.rowTitle(for: event, stored: stored),
                                       action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for row in SoundMenu.rows(for: event, stored: stored,
                                      systemAvailable: SoundPlayer.systemSoundExists) {
                switch row {
                case .separator:
                    submenu.addItem(NSMenuItem.separator())
                case .header(let text):
                    let header = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    submenu.addItem(header)
                case .option(let id, let title, let checked):
                    let item = NSMenuItem(title: title, action: #selector(soundChosen(_:)),
                                          keyEquivalent: "")
                    item.target = self
                    item.representedObject = [event.rawValue, id]
                    item.state = checked ? .on : .off
                    submenu.addItem(item)
                }
            }
            eventItem.submenu = submenu
            soundsMenu.addItem(eventItem)
        }
        soundsItem.submenu = soundsMenu
        return soundsItem
    }

    /// Stores the chosen sound for the event and previews it. Choosing the
    /// one already checked still plays it, so it can be heard again.
    @objc func soundChosen(_ sender: NSMenuItem) {
        guard let parts = sender.representedObject as? [String], parts.count == 2,
              let event = SoundEvent(rawValue: parts[0]) else { return }
        let id = parts[1]
        setStoredSoundID(id, for: event)
        if let option = SoundCatalog.option(id: id) {
            soundPlayer.preview(option)
        }
        // Only setIdle() hands the new menu to statusItem.menu, so following
        // petSizeChanged's pattern alone would show the checkmark late.
        buildIdleMenu()
        if currentRequestId == nil {
            setIdle()
            updatePetMood()
        }
    }

    @objc func toggleAutoMode() {
        if autoModeEnabled {
            try? FileManager.default.removeItem(at: autoModeFlagURL)
        } else {
            try? Data().write(to: autoModeFlagURL)
        }
        buildIdleMenu()
        if currentRequestId == nil {
            setIdle()
            updatePetMood()
        }
    }
}
