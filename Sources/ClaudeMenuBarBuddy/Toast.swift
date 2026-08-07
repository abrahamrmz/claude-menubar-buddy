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
        card.setAccessibilityLabel("\(project.isEmpty ? "Claude Code" : project): turn finished in \(formatDuration(elapsed))")
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
}
