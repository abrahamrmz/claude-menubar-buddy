import AppKit
import Defaults
import KeyboardShortcuts

// The first-run welcome, and the setup check it's built around.
//
// AppKit like the rest of the app. SwiftUI does compile fine in this
// bundle-less SPM binary — that was checked, not assumed — but the reason
// SettingsWindow.swift gives for staying AppKit holds here too: a SwiftUI
// island buys nothing and costs a second set of layout rules. It would also
// cost an NSViewRepresentable wrapper to show an animated GIF, and the pet
// tour on the last page is made of animated GIFs.
//
// This is the one window in the app allowed to take focus. Everything else is
// built around never interrupting you; a welcome screen that you can't see
// isn't a welcome screen.

extension Defaults.Keys {
    static let onboardingCompleted = Key<Bool>("onboardingCompleted", default: false)
}

/// Accent-tinted panel behind the one idea worth boxing. A subclass rather
/// than a layer configured once, so the colours re-resolve when the system
/// flips between light and dark — CGColors baked into a layer don't.
final class CalloutView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
    }
}

final class OnboardingWindowController: NSWindowController {
    private let pages: [(title: String, make: () -> NSView)]
    private var index = 0

    private let contentContainer = NSView()
    private let dots = NSStackView()
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)

    init(pages: [(title: String, make: () -> NSView)], startAt: Int = 0) {
        self.pages = pages
        self.index = min(startAt, max(pages.count - 1, 0))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Claude Menu Bar Buddy"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeChrome()
        showPage(index)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func makeChrome() -> NSView {
        let root = NSView()

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(goNext)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"

        dots.orientation = .horizontal
        dots.spacing = 6
        for _ in pages {
            let dot = NSTextField(labelWithString: "●")
            dot.font = .systemFont(ofSize: 9)
            dots.addArrangedSubview(dot)
        }

        let footer = NSStackView(views: [backButton, dots, NSView(), nextButton])
        footer.orientation = .horizontal
        footer.spacing = 12
        footer.alignment = .centerY

        for view in [contentContainer, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            contentContainer.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
        return root
    }

    func showPage(_ page: Int) {
        index = max(0, min(page, pages.count - 1))
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let view = pages[index].make()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor),
        ])
        backButton.isHidden = index == 0
        nextButton.title = index == pages.count - 1 ? "Done" : "Next"
        for (i, dot) in dots.arrangedSubviews.enumerated() {
            (dot as? NSTextField)?.textColor = i == index ? .labelColor : .quaternaryLabelColor
        }
        window?.setAccessibilityLabel("\(pages[index].title) — step \(index + 1) of \(pages.count)")
    }

    /// Rebuild the page in place — the setup check needs this to re-read the
    /// world without losing the user's place in the walkthrough.
    func refreshCurrentPage() { showPage(index) }

    @objc private func goBack() { showPage(index - 1) }

    @objc private func goNext() {
        if index == pages.count - 1 {
            close()
        } else {
            showPage(index + 1)
        }
    }
}

extension AppDelegate {

    // MARK: - Presenting

    /// Shown once, the first time the app runs. Marked complete on *show*,
    /// not on finish: the LaunchAgent starts this app at every login, and a
    /// gate that only closes when someone clicks through to the last page
    /// would steal focus every morning from anyone who closed it early.
    func showOnboardingIfFirstRun() {
        guard !Defaults[.onboardingCompleted] else { return }
        showOnboarding()
    }

    @objc func showOnboarding() {
        presentOnboarding(startAt: 0)
    }

    /// Opens straight on the setup check — what the menu's warning line links
    /// to, since someone chasing a broken hook doesn't want a tour first.
    @objc func showSetupCheck() {
        presentOnboarding(startAt: 1)
    }

    private func presentOnboarding(startAt: Int) {
        Defaults[.onboardingCompleted] = true
        if onboardingWindowController == nil {
            onboardingWindowController = OnboardingWindowController(
                pages: onboardingPages(), startAt: startAt)
        } else {
            onboardingWindowController?.showPage(startAt)
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.showWindow(nil)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func onboardingPages() -> [(title: String, make: () -> NSView)] {
        [
            ("Welcome", { [unowned self] in welcomePage() }),
            ("Setup check", { [unowned self] in setupPage() }),
            ("Shortcuts", { [unowned self] in shortcutsPage() }),
            ("Your pet", { [unowned self] in petPage() }),
        ]
    }

    // MARK: - Pages

    private func welcomePage() -> NSView {
        let (_, imageView) = gifMenuItem(named: "\(selectedSpecies)_idle")
        imageView.animates = true
        return page([
            centered(imageView),
            title("Approvals, without losing your place"),
            body("When Claude Code needs permission to run something, a card appears "
                 + "next to your pet with the command, the project, and the reason."),
            callout("The card never takes focus.",
                    "Whatever you were typing keeps the cursor — you can read the card, "
                    + "ignore it, finish your sentence, and answer whenever you like. "
                    + "This window is the one exception in the whole app."),
            body("If the buddy isn't running, nothing breaks: the hook simply times "
                 + "out and Claude Code's own prompt takes over."),
        ])
    }

    private func setupPage() -> NSView {
        let health = BuddyHealth.inspect()
        let notes = health.checks.filter { !$0.ok }.count
        let recheck = NSButton(title: "Check again", target: self,
                               action: #selector(recheckHealth))
        recheck.bezelStyle = .rounded

        var rows: [NSView] = [
            title(!health.isHealthy ? "Something needs attention"
                  : notes > 0 ? "Approvals are wired up" : "Everything's wired up"),
            body(!health.isHealthy
                 ? "Each failure below is silent otherwise — the hook just never fires, "
                   + "and the buddy sits here looking perfectly healthy."
                 : notes > 0
                 ? "Checked just now, against your actual config. The amber item isn't "
                   + "blocking anything, but it's worth a look."
                 : "Checked just now, against your actual config — not a checklist to "
                   + "read. Come back any time from the menu; this page is how you find "
                   + "out why a card didn't appear."),
        ]
        rows += health.checks.map { checkRow($0) }
        rows.append(leading(recheck))
        rows.append(footnote(
            "Fixing the wiring means editing ~/.claude/settings.json, and the "
            + "buddy never edits Claude Code's config — that's a door it "
            + "shouldn't be able to open on its own. Hand the line above to "
            + "Claude Code, or run it yourself."))
        return page(rows)
    }

    private func shortcutsPage() -> NSView {
        // Read out of KeyboardShortcuts rather than hard-coded, so a remapped
        // shortcut shows what it actually is instead of what it shipped as.
        let bound: [(KeyboardShortcuts.Name, String)] = [
            (.approvalAllow, "Allow the request"),
            (.approvalDeny, "Deny it"),
            (.approvalQuiet, "Deny quietly — no card, no note back to Claude"),
            (.jumpToHost, "Jump to the editor or terminal that's asking"),
        ]
        var rows: [NSView] = [
            title("While a card is on screen"),
            body("These are live only while something is waiting on you. The rest of "
                 + "the time they belong to whatever app you're in, so ⌘↩ still sends "
                 + "your message."),
        ]
        rows += bound.map { name, description in
            shortcutRow(KeyboardShortcuts.getShortcut(for: name)?.description ?? "unassigned",
                        description)
        }
        rows.append(shortcutRow("⌘1…4", "Pick an option when Claude asks a question"))
        rows.append(shortcutRow("⌘1…9", "Switch cards when several are queued"))
        rows.append(footnote(
            "All of them are remappable in Settings › Behavior. When more than "
            + "one request is waiting, the +N badge on the card opens the queue — "
            + "including allow-all and deny-all."))
        return page(rows)
    }

    private func petPage() -> NSView {
        let ladder = NSStackView()
        ladder.orientation = .horizontal
        ladder.spacing = 10
        ladder.alignment = .bottom
        // "50% · slower" earns its keep: for the 18 firmware pets, tired is
        // the idle choreography at a drowsier tempo, so it is genuinely the
        // same picture. Saying so beats presenting two identical stills as if
        // they were different drawings.
        for (mood, label) in [("idle", "under 50%"), ("tired", "50% · slower"),
                              ("stressed", "70%"), ("critical", "85%"),
                              ("asleep", "100%")] {
            ladder.addArrangedSubview(moodSample(mood: mood, label: label))
        }
        return page([
            title("The pet is a gauge"),
            body("It follows your 5-hour limit — the one that actually stops you "
                 + "mid-session — so you can read where you stand without opening "
                 + "anything."),
            centered(ladder),
            body("It also reacts to what's happening: heads-down while tools run, "
                 + "thinking while Claude does, and a little celebration when the "
                 + "limit resets."),
            footnote("There are 19 pets, each animated with the pose choreography from "
                     + "the Claude hardware buddy's firmware. Pick yours in Settings › "
                     + "Appearance, and drag the floating pet anywhere you like — or turn "
                     + "it off from the menu."),
        ])
    }

    @objc private func recheckHealth() {
        onboardingWindowController?.refreshCurrentPage()
    }

    /// `touch ~/.config/claude-menubar-buddy/capture_onboarding` renders every
    /// page side by side to onboarding_selfie.png. Like the settings one, it
    /// deliberately does NOT open the window — this is the only window in the
    /// app that takes focus, so checking its layout shouldn't cost you yours.
    func captureOnboardingSelfieIfRequested() {
        guard debugFlagIsSet("capture_onboarding") else { return }
        try? FileManager.default.removeItem(
            at: dirURL.appendingPathComponent("capture_onboarding"))

        let pageWidth: CGFloat = 524   // the window's 580 less its margins
        var images: [(String, NSImage)] = []
        for page in onboardingPages() {
            let view = page.make()
            view.frame = NSRect(x: 0, y: 0, width: pageWidth, height: 0)
            view.widthAnchor.constraint(equalToConstant: pageWidth).isActive = true
            view.layoutSubtreeIfNeeded()
            let height = view.fittingSize.height
            view.frame = NSRect(x: 0, y: 0, width: pageWidth, height: height)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(rep)
            images.append((page.title, image))
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
            try? png.write(to: dirURL.appendingPathComponent("onboarding_selfie.png"))
        }
    }

    // MARK: - Small view vocabulary

    /// Stacks page content vertically and pins every row to the page width.
    ///
    /// The width constraint is the whole point. A vertical NSStackView sizes
    /// its rows from their intrinsic width, and a plain NSView container
    /// hasn't got one — so a row built from containers rather than labels ends
    /// up ambiguous, and ambiguous rows land on top of each other. Stating the
    /// width once here is what keeps wrapping labels wrapping and boxes boxed.
    private func page(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    /// Left-aligns a view that shouldn't stretch — a button pinned to the
    /// page width would run the whole way across.
    private func leading(_ view: NSView) -> NSView {
        let wrapper = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            wrapper.trailingAnchor.constraint(greaterThanOrEqualTo: view.trailingAnchor),
        ])
        return wrapper
    }

    /// Centres a view in a full-width wrapper. Spacer NSViews in a stack
    /// don't do this — they have no intrinsic size, so the stack has nothing
    /// to divide and everything lands on top of everything else.
    private func centered(_ view: NSView) -> NSView {
        let wrapper = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            wrapper.widthAnchor.constraint(greaterThanOrEqualTo: view.widthAnchor),
        ])
        return wrapper
    }

    private func title(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 19, weight: .semibold)
        return field
    }

    private func body(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        field.textColor = .labelColor
        field.preferredMaxLayoutWidth = 500
        return field
    }

    private func footnote(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 500
        return field
    }

    /// The one idea worth putting in a box.
    private func callout(_ heading: String, _ text: String) -> NSView {
        let head = NSTextField(labelWithString: heading)
        head.font = .systemFont(ofSize: 13, weight: .semibold)
        let inner = NSStackView(views: [head, body(text)])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 4
        inner.translatesAutoresizingMaskIntoConstraints = false

        let box = CalloutView()
        box.wantsLayer = true
        box.addSubview(inner)
        let pad: CGFloat = 12
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: pad),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: pad),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -pad),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -pad),
        ])
        return box
    }

    private func checkRow(_ check: BuddyHealth.Check) -> NSView {
        let symbolName = check.ok ? "checkmark.circle.fill"
            : (check.optional ? "exclamationmark.circle.fill" : "xmark.circle.fill")
        let symbol = NSImageView(image: NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: check.ok ? "passed" : "failed") ?? NSImage())
        symbol.contentTintColor = check.ok ? .systemGreen
            : (check.optional ? .systemOrange : .systemRed)
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        let heading = NSTextField(labelWithString: check.title)
        heading.font = .systemFont(ofSize: 13, weight: .medium)

        let text = NSStackView(views: [heading, footnote(check.detail)])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        if !check.ok, let remedy = check.remedy {
            // Selectable so the fix can be copied straight out of the window.
            let field = NSTextField(wrappingLabelWithString: remedy)
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textColor = .labelColor
            field.isSelectable = true
            field.preferredMaxLayoutWidth = 460
            text.addArrangedSubview(field)
        }

        let row = NSStackView(views: [symbol, text])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.setAccessibilityLabel(
            "\(check.title): \(check.ok ? "passed" : "needs attention"). \(check.detail)")
        return row
    }

    private func shortcutRow(_ key: String, _ description: String) -> NSView {
        let keyField = NSTextField(labelWithString: key)
        keyField.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        keyField.alignment = .right
        keyField.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let row = NSStackView(views: [keyField, body(description)])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        row.setAccessibilityLabel("\(key): \(description)")
        return row
    }

    private func moodSample(mood: String, label: String) -> NSView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        setGif(on: imageView, named: gifName(for: selectedSpecies, mood: mood))
        imageView.animates = true
        imageView.widthAnchor.constraint(equalToConstant: 76).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 62).isActive = true

        let caption = NSTextField(labelWithString: label)
        caption.font = .systemFont(ofSize: 10)
        caption.textColor = .secondaryLabelColor
        caption.alignment = .center

        let column = NSStackView(views: [imageView, caption])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 4
        column.setAccessibilityLabel("\(petMoodText(mood)), at \(label) of the limit")
        return column
    }
}
