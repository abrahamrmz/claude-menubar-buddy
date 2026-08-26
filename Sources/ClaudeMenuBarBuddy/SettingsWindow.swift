import AppKit
import KeyboardShortcuts
import Settings

// The settings window, and the form vocabulary its panes are built from.
//
// AppKit, not SwiftUI: sindresorhus/Settings takes plain NSViewControllers,
// KeyboardShortcuts ships an NSSearchField recorder, and the rest of this app
// is programmatic AppKit — a SwiftUI island here would buy nothing and cost a
// second set of layout rules.

/// A pane whose contents are described by a builder closure, so each tab is a
/// short function instead of a class.
final class BuddySettingsPane: NSViewController, SettingsPane {
    let paneIdentifier: Settings.PaneIdentifier
    let paneTitle: String
    let toolbarItemIcon: NSImage

    private let build: (SettingsForm) -> Void

    init(identifier: String, title: String, symbol: String, build: @escaping (SettingsForm) -> Void) {
        self.paneIdentifier = Settings.PaneIdentifier(identifier)
        self.paneTitle = title
        self.toolbarItemIcon = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            ?? NSImage(size: NSSize(width: 1, height: 1))
        self.build = build
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let form = SettingsForm()
        build(form)
        view = form.makeView()
    }
}

/// Label-and-control rows in a grid, plus section headers and footnotes.
/// Exists so the panes read as a list of settings rather than as layout code.
final class SettingsForm {
    private let grid = NSGridView(numberOfColumns: 2, rows: 0)
    private var rowCount = 0

    init() {
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
    }

    /// A labelled row: "Allow:  [recorder]".
    func row(_ label: String, _ control: NSView) {
        let field = NSTextField(labelWithString: label.isEmpty ? "" : "\(label):")
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        grid.addRow(with: [field, control])
        grid.row(at: rowCount).yPlacement = .center
        rowCount += 1
    }

    /// A full-width row with nothing in the label column — checkboxes and
    /// buttons carry their own text.
    func wideRow(_ control: NSView) {
        grid.addRow(with: [NSGridCell.emptyContentView, control])
        rowCount += 1
    }

    func header(_ text: String) {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11, weight: .semibold)
        field.textColor = .secondaryLabelColor
        if rowCount > 0 {
            grid.addRow(with: [NSGridCell.emptyContentView, NSGridCell.emptyContentView])
            grid.row(at: rowCount).height = 8
            rowCount += 1
        }
        grid.addRow(with: [NSGridCell.emptyContentView, field])
        rowCount += 1
    }

    /// Small print under the control it explains.
    func note(_ text: String) {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 320
        grid.addRow(with: [NSGridCell.emptyContentView, field])
        rowCount += 1
    }

    func makeView() -> NSView {
        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        let pad: CGFloat = 20
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: pad),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: pad),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -pad),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -pad),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 480),
        ])
        return container
    }
}

extension AppDelegate {
    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                panes: [behaviorPane(), appearancePane(), safetyPane()],
                style: .toolbarItems,
                animated: true
            )
            // Without an .app bundle there's no CFBundleName for the package
            // to build a title from — it would fall back to the executable
            // name.
            settingsWindowController?.window?.title = "Claude Menu Bar Buddy Settings"
        }
        settingsWindowController?.show()
    }

    /// Debug/docs helper (sibling of capture_card/capture_pet): `touch
    /// ~/.config/claude-menubar-buddy/capture_settings` and each pane is
    /// built and rendered to settings_selfie.png. Deliberately does NOT open
    /// the window — this way the layout can be checked without stealing focus
    /// from whatever you're doing.
    func captureSettingsSelfieIfRequested() {
        guard debugFlagIsSet("capture_settings") else { return }
        let flagURL = dirURL.appendingPathComponent("capture_settings")
        try? FileManager.default.removeItem(at: flagURL)

        let panes = [behaviorPane(), appearancePane(), safetyPane()]
        var images: [(String, NSImage)] = []
        for pane in panes {
            let view = pane.view
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            images.append((pane.paneTitle, image))
        }
        guard !images.isEmpty else { return }

        let gap: CGFloat = 16
        let width = images.reduce(0) { $0 + $1.1.size.width + gap } + gap
        let height = (images.map { $0.1.size.height }.max() ?? 0) + gap * 2 + 18
        let sheet = NSImage(size: NSSize(width: width, height: height))
        sheet.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        var x = gap
        for (title, image) in images {
            image.draw(at: NSPoint(x: x, y: height - gap - image.size.height), from: .zero,
                       operation: .sourceOver, fraction: 1)
            (title as NSString).draw(
                at: NSPoint(x: x, y: 6),
                withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12),
                                 .foregroundColor: NSColor.labelColor])
            x += image.size.width + gap
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dirURL.appendingPathComponent("settings_selfie.png"))
        }
    }

    // MARK: - Behavior

    private func behaviorPane() -> BuddySettingsPane {
        BuddySettingsPane(identifier: "behavior", title: "Behavior", symbol: "keyboard") { form in
            form.header("SHORTCUTS — live only while a request is on screen")
            form.row("Allow", KeyboardShortcuts.RecorderCocoa(for: .approvalAllow))
            form.row("Deny", KeyboardShortcuts.RecorderCocoa(for: .approvalDeny))
            form.row("Card's third action", KeyboardShortcuts.RecorderCocoa(for: .approvalQuiet))
            form.row("Show asking session", KeyboardShortcuts.RecorderCocoa(for: .jumpToHost))
            form.note("These are registered only while a request is pending, so the same keys keep working everywhere else the rest of the time.")

            form.header("NOTIFICATIONS")
            let stepper = NSStepper()
            stepper.minValue = 0
            stepper.maxValue = 300
            stepper.increment = 5
            stepper.integerValue = self.toastMinSeconds
            stepper.target = self
            stepper.action = #selector(self.toastThresholdChanged(_:))
            let readout = NSTextField(labelWithString: "\(self.toastMinSeconds)s")
            readout.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            self.toastThresholdReadout = readout
            let row = NSStackView(views: [readout, stepper])
            row.spacing = 6
            form.row("Toast turns longer than", row)
            form.note("Shorter turns finish silently — you were watching anyway.")

            let projected = NSButton(checkboxWithTitle: "Warn when the pace is heading for a limit",
                                     target: self, action: #selector(self.projectedWarningsChanged(_:)))
            projected.state = self.projectedWarnings ? .on : .off
            form.wideRow(projected)
            form.note("Needs Claude Desktop running — it's the only thing that writes live plan percentages.")

            form.header("STARTUP")
            let login = NSButton(checkboxWithTitle: "Start at login",
                                 target: self, action: #selector(self.startAtLoginChanged(_:)))
            login.state = self.startsAtLogin ? .on : .off
            form.wideRow(login)
            form.note("Writes the LaunchAgent that launchd reads at login. Takes effect next login; it never starts or stops the copy running right now.")
        }
    }

    @objc func toastThresholdChanged(_ sender: NSStepper) {
        toastMinSeconds = sender.integerValue
        toastThresholdReadout?.stringValue = "\(sender.integerValue)s"
    }

    @objc func projectedWarningsChanged(_ sender: NSButton) {
        projectedWarnings = sender.state == .on
    }

    @objc func startAtLoginChanged(_ sender: NSButton) {
        setStartsAtLogin(sender.state == .on)
    }

    // MARK: - Appearance

    private func appearancePane() -> BuddySettingsPane {
        BuddySettingsPane(identifier: "appearance", title: "Appearance", symbol: "paintbrush") { form in
            let species = NSPopUpButton()
            for name in availableSpecies() { species.addItem(withTitle: name.capitalized) }
            species.selectItem(withTitle: self.selectedSpecies.capitalized)
            species.target = self
            species.action = #selector(self.speciesPopupChanged(_:))
            form.row("Buddy", species)

            let floating = NSButton(checkboxWithTitle: "Show the floating desktop pet",
                                    target: self, action: #selector(self.floatingPetCheckboxChanged(_:)))
            floating.state = self.floatingPetVisible ? .on : .off
            form.wideRow(floating)
            form.note("The approval card appears at the pet, so hiding it also sends decisions to the menu bar dropdown instead.")

            let calm = NSButton(checkboxWithTitle: "Calm pet — no idle motion",
                                target: self, action: #selector(self.calmPetCheckboxChanged(_:)))
            calm.state = self.calmPet ? .on : .off
            form.wideRow(calm)
            form.note("Turns off the gentle bob, the occasional stretch and the cursor reaction. The animations themselves stay.")

            let bubbles = NSButton(checkboxWithTitle: "Speech bubbles",
                                   target: self, action: #selector(self.speechBubblesCheckboxChanged(_:)))
            bubbles.state = self.speechBubbles ? .on : .off
            form.wideRow(bubbles)
            form.note("An occasional one-liner at the pet — compacting, limit moods, pace warnings. Never over an approval card, and never chatty.")
        }
    }

    @objc func speciesPopupChanged(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem else { return }
        selectedSpecies = title.lowercased()
        buildIdleMenu()
        // setIdle() answers nothing — it just forgets the live request, which
        // would strand the hook until its own timeout. Guarded the way the
        // two sibling handlers here already guard it; with a card up, swap
        // the pending pose to the new species and leave the request alone
        // (setIdle picks the species up for real once it resolves).
        if currentRequestId == nil {
            setIdle()
            updatePetMood()
        } else if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: gifName(for: selectedSpecies, mood: "pending"))
            applyAnimationPolicy()
        }
    }

    @objc func floatingPetCheckboxChanged(_ sender: NSButton) {
        let wanted = sender.state == .on
        guard wanted != floatingPetVisible else { return }
        toggleFloatingPet()
    }

    @objc func calmPetCheckboxChanged(_ sender: NSButton) {
        calmPet = sender.state == .on
        applyFidgetPolicy()
    }

    @objc func speechBubblesCheckboxChanged(_ sender: NSButton) {
        speechBubbles = sender.state == .on
        if !speechBubbles { hideSpeechBubble() }
    }

    // MARK: - Safety

    private func safetyPane() -> BuddySettingsPane {
        BuddySettingsPane(identifier: "safety", title: "Safety", symbol: "lock.shield") { form in
            let autoEdits = NSButton(checkboxWithTitle: "Auto-approve edits (Edit, Write, NotebookEdit)",
                                     target: self, action: #selector(self.autoEditsCheckboxChanged(_:)))
            autoEdits.state = self.autoEditsEnabled ? .on : .off
            form.wideRow(autoEdits)
            form.note("A standing grant: while on, file edits skip the card entirely. The menu bar icon carries a pencil the whole time so it can't be on without you knowing.")

            form.header("AUTO-ALLOWED COMMANDS")
            let table = AlwaysAllowTable(delegate: self)
            self.alwaysAllowTable = table
            form.wideRow(table.view)
            form.note("Bash commands approved instantly, with no card. The card grants them in the project that asked; “Everywhere” covers all of them. Select one and press Remove to bring its card back.")

            form.header("AUDIT")
            let openLog = NSButton(title: "Reveal decision log…", target: self,
                                   action: #selector(self.revealDecisionLog))
            openLog.bezelStyle = .rounded
            form.wideRow(openLog)
            form.note("Every decision the buddy made, one JSON object per line — what, where, and which app was hosting the session.")
        }
    }

    @objc func autoEditsCheckboxChanged(_ sender: NSButton) {
        guard (sender.state == .on) != autoEditsEnabled else { return }
        toggleAutoEdits()
    }

    @objc func revealDecisionLog() {
        let url = dirURL.appendingPathComponent("decisions.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSWorkspace.shared.activateFileViewerSelecting([dirURL])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// The always-allow list as a real table, so entries can be read and removed
/// without hunting through a submenu.
///
/// Also the only place a grant can be **widened**. The card only ever grants
/// in the project that asked; turning one of those into "everywhere" is a
/// different decision, and making it cost a trip here plus a confirmation is
/// the point, not an oversight.
final class AlwaysAllowTable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSStackView()
    private let table = NSTableView()
    private let removeButton: NSButton
    private let promoteButton: NSButton
    private weak var owner: AppDelegate?

    /// One row. `cwd` nil means the global scope.
    private struct Entry {
        let command: String
        let cwd: String?
        let scopeLabel: String
    }
    private var entries: [Entry] = []

    /// Names for each project path, as short as they can be while still
    /// telling them apart. Basenames normally, but the whole reason grants
    /// key on the full path is that two checkouts can be called `api` — and a
    /// table that drew both as "api" would hide exactly the case this feature
    /// exists for. Those get their parent folder back.
    private static func scopeLabels(for paths: [String]) -> [String: String] {
        var byBasename: [String: [String]] = [:]
        for path in paths { byBasename[(path as NSString).lastPathComponent, default: []].append(path) }
        var labels: [String: String] = [:]
        for (basename, sharing) in byBasename {
            for path in sharing {
                guard sharing.count > 1 else { labels[path] = basename; continue }
                let parent = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
                labels[path] = parent.isEmpty ? path : "\(parent)/\(basename)"
            }
        }
        return labels
    }

    init(delegate: AppDelegate) {
        owner = delegate
        removeButton = NSButton(title: "Remove", target: nil, action: nil)
        promoteButton = NSButton(title: "Allow everywhere…", target: nil, action: nil)
        super.init()

        let command = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        command.title = "Command"
        command.width = 150
        table.addTableColumn(command)
        let scope = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("scope"))
        scope.title = "Where"
        scope.width = 190
        table.addTableColumn(scope)
        table.headerView = NSTableHeaderView()
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 20
        table.style = .inset

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // Taller than the one-column version was: scoping multiplies rows —
        // the same command can now appear once per project.
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 360).isActive = true

        for button in [removeButton, promoteButton] {
            button.bezelStyle = .rounded
            button.target = self
            button.isEnabled = false
        }
        removeButton.action = #selector(removeSelected)
        promoteButton.action = #selector(promoteSelected)

        let buttons = NSStackView(views: [removeButton, promoteButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 6
        view.addArrangedSubview(scroll)
        view.addArrangedSubview(buttons)
        reload()
    }

    func reload() {
        let list = owner?.readAlwaysAllow() ?? AlwaysAllow()
        // Global first: those are the entries that speak for every project,
        // so they're the ones worth seeing without scrolling.
        entries = list.global.sorted().map { Entry(command: $0, cwd: nil, scopeLabel: "Everywhere") }
        let labels = Self.scopeLabels(for: Array(list.projects.keys))
        for cwd in list.projects.keys.sorted(by: {
            (labels[$0] ?? $0).localizedCaseInsensitiveCompare(labels[$1] ?? $1) == .orderedAscending
        }) {
            entries += (list.projects[cwd] ?? []).sorted().map {
                Entry(command: $0, cwd: cwd, scopeLabel: labels[cwd] ?? cwd)
            }
        }
        table.reloadData()
        syncButtons()
    }

    private func syncButtons() {
        let row = table.selectedRow
        removeButton.isEnabled = row >= 0
        // Nothing to widen about an entry that is already everywhere.
        promoteButton.isEnabled = row >= 0 && row < entries.count && entries[row].cwd != nil
    }

    @objc private func removeSelected() {
        let row = table.selectedRow
        guard row >= 0, row < entries.count, let owner = owner else { return }
        let entry = entries[row]
        var list = owner.readAlwaysAllow()
        if let cwd = entry.cwd {
            list.projects[cwd]?.removeAll { $0 == entry.command }
        } else {
            list.global.removeAll { $0 == entry.command }
        }
        owner.writeAlwaysAllow(list)
        reload()
    }

    /// Move a project-scoped grant to the global scope. Confirmed, because it
    /// is the one action here that lets a command through somewhere the user
    /// never approved it — including repos that don't exist yet.
    @objc private func promoteSelected() {
        let row = table.selectedRow
        guard row >= 0, row < entries.count, let cwd = entries[row].cwd, let owner = owner else { return }
        let entry = entries[row]
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Always allow ‘\(entry.command)’ in every project?"
        alert.informativeText = """
            Right now it runs without a card only in \(entry.scopeLabel). \
            Allowing it everywhere covers every project on this Mac, including \
            ones you haven't opened yet.
            """
        alert.addButton(withTitle: "Allow Everywhere")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var list = owner.readAlwaysAllow()
        list.projects[cwd]?.removeAll { $0 == entry.command }
        if !list.global.contains(entry.command) { list.global.append(entry.command) }
        owner.writeAlwaysAllow(list)
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        if tableColumn?.identifier.rawValue == "scope" {
            let field = NSTextField(labelWithString: entry.scopeLabel)
            field.font = .systemFont(ofSize: 12)
            field.textColor = entry.cwd == nil ? .systemOrange : .secondaryLabelColor
            // The full path is what the grant is actually keyed on, and two
            // checkouts can share a basename — so it's a hover away, not lost.
            field.toolTip = entry.cwd
            return field
        }
        let field = NSTextField(labelWithString: entry.command)
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        syncButtons()
    }
}
