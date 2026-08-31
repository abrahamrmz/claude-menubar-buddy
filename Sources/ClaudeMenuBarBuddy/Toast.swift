import AppKit

// Turn-finished toast: same visual language as the approval card, compact,
// no buttons, auto-dismissing. Fed by done_<session>.json files that
// notify-done.sh writes on Stop.
extension AppDelegate {
    func formatDuration(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }

    /// Picks up done_<session>.json markers written by notify-done.sh on
    /// Stop and turns them into a toast at the pet (or a banner when an
    /// approval card has the spotlight). Markers are consumed on sight.
    func processDoneMarkers() {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        var latest: (project: String, elapsed: Int)? = nil
        for url in dirEntries where url.lastPathComponent.hasPrefix("done_") && url.pathExtension == "json" {
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

        let width: CGFloat = 260
        let height: CGFloat = 58
        let pad = CardTheme.padding
        // The tail rides on top of the toast's own height, same as the card's.
        let windowSize = NSSize(width: width, height: height + CardTheme.tailHeight)

        let window: NSPanel
        if let existing = toastWindow {
            window = existing
            window.setContentSize(windowSize)
        } else {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: windowSize),
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

        let bubble = BubbleBackgroundView(frame: NSRect(origin: .zero, size: windowSize))
        bubble.setAccessibilityLabel("\(project.isEmpty ? "Claude Code" : project): turn finished in \(formatDuration(elapsed))")
        window.contentView = bubble
        let card = bubble.content

        // The green stays. Everything the card paints in the accent is
        // something to press; this is a report that a turn ENDED WELL, and
        // painting that the same orange as "Allow" would be the accent saying
        // two different things. Same reasoning as the verdict's ✓.
        //
        // The stripe down the left edge is gone though, for the same reason
        // the card's went: on a bubble it reads as a panel's tab.
        let icon = NSImageView(frame: NSRect(x: pad, y: (height - 20) / 2, width: 20, height: 20))
        if let symbol = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: "done") {
            icon.image = symbol.withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
            icon.contentTintColor = CardTheme.added
        }
        icon.setAccessibilityElement(false)
        card.addSubview(icon)

        let textX = pad + 28
        let titleField = NSTextField(labelWithString: project.isEmpty ? "Claude Code" : project)
        titleField.font = CardTheme.heading(CardTheme.titleSize, weight: 700)
        titleField.textColor = CardTheme.inkPrimary
        titleField.lineBreakMode = .byTruncatingTail
        titleField.frame = NSRect(x: textX, y: height / 2, width: width - textX - pad, height: 18)
        card.addSubview(titleField)

        let subtitleField = NSTextField(labelWithString: "Turn finished in \(formatDuration(elapsed))")
        subtitleField.font = CardTheme.body(CardTheme.metaSize)
        subtitleField.textColor = CardTheme.inkMuted
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.frame = NSRect(x: textX, y: height / 2 - 18, width: width - textX - pad, height: 17)
        card.addSubview(subtitleField)

        let wasVisible = window.isVisible
        window.setFrameOrigin(originNearPet(for: windowSize))
        if let pet = floatingWindow { aimTail(of: window, at: pet) }
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
}
