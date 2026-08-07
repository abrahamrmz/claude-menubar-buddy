import AppKit

// When several sessions ask at once, the card shows one and the rest wait
// behind a +N badge. This is the machinery for reaching past the front of
// that line: picking a specific request, and answering the whole line at once.
extension AppDelegate {
    /// Live requests in the order the card will surface them: oldest first,
    /// except that a request the user picked jumps to the front and stays
    /// there until it's answered.
    func orderedRequests() -> [PendingRequest] {
        var requests = scanRequests()
        guard let pinned = pinnedRequestId else { return requests }
        guard let index = requests.firstIndex(where: { $0.id == pinned }) else {
            // Answered elsewhere, or the hook gave up — stop holding a spot
            // for something that no longer exists.
            pinnedRequestId = nil
            return requests
        }
        if index > 0 { requests.insert(requests.remove(at: index), at: 0) }
        return requests
    }

    /// Bring the request at `index` (0 = the card already on screen) to the
    /// front. Pinning is what makes it stick: poll() re-sorts by age every
    /// second and would otherwise put the oldest back on top.
    func selectQueued(_ index: Int) {
        guard !isDismissing else { return }
        let requests = orderedRequests()
        guard requests.indices.contains(index) else { return }
        let picked = requests[index]
        guard picked.id != currentRequestId else { return }
        pinnedRequestId = picked.id
        switchingCardByHand = true
        poll()
    }

    /// One line per queued request, for the +N popup and the menu bar.
    /// Deliberately short — this is a "which one is that?" list, not a
    /// summary you should be deciding from. Deciding happens on the card.
    func queueLabel(for req: PendingRequest, index: Int) -> String {
        let project = (req.project?.isEmpty == false) ? " — \(req.project!)" : ""
        let firstLine = req.hint.split(separator: "\n").first.map(String.init) ?? ""
        let trimmed = firstLine.count > 46 ? String(firstLine.prefix(45)) + "…" : firstLine
        let shortcut = index < 9 ? "⌘\(index + 1)  " : "     "
        return "\(shortcut)\(req.tool)\(project)\(trimmed.isEmpty ? "" : ": \(trimmed)")"
    }

    /// The +N badge's menu: the whole line, then the batch actions. Pops up
    /// from the non-activating card without taking focus.
    @objc func showQueueMenu(_ sender: NSView) {
        guard let menu = buildQueueMenu() else { return }
        // Verified working straight from the non-activating panel, including
        // from inside the button's mouse-tracking loop — no deferral needed,
        // and the menu doesn't take focus away from whatever you're typing in.
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: sender.bounds.minY - 4),
                   in: sender)
    }

    /// The queue as a menu, used both by the +N badge popup and as a submenu
    /// in the menu bar dropdown — same list, same batch actions, so there's
    /// only one place to get it right.
    func buildQueueMenu() -> NSMenu? {
        let requests = orderedRequests()
        guard requests.count > 1 else { return nil }
        let menu = NSMenu()
        menu.addItem(statusMenuItem("\(requests.count) requests waiting"))
        menu.addItem(NSMenuItem.separator())
        for (index, req) in requests.enumerated() {
            let item = NSMenuItem(title: queueLabel(for: req, index: index),
                                  action: #selector(queueMenuPick(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.state = req.id == currentRequestId ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())

        // Two-step, not a confirmation dialog: an NSAlert would activate the
        // app and take focus, which this card exists to avoid. A submenu asks
        // the same question without any of that — and "allow all" deserves
        // asking, since it approves things you haven't read.
        menu.addItem(confirmItem(title: "Allow all (\(requests.count))…",
                                 confirm: "Yes, allow all \(requests.count)",
                                 hint: "Approves every request above. Open this to confirm.",
                                 action: #selector(allowAllQueued)))
        menu.addItem(confirmItem(title: "Deny all (\(requests.count))…",
                                 confirm: "Yes, deny all \(requests.count)",
                                 hint: "Denies every request above. Open this to confirm.",
                                 action: #selector(denyAllQueued)))
        return menu
    }

    /// Batch actions live one level in. An item with a submenu ignores a
    /// direct click, so the title carries the macOS "needs another step"
    /// ellipsis rather than looking like a button that did nothing.
    private func confirmItem(title: String, confirm: String, hint: String, action: Selector) -> NSMenuItem {
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        top.toolTip = hint
        let sub = NSMenu()
        let go = NSMenuItem(title: confirm, action: action, keyEquivalent: "")
        go.target = self
        sub.addItem(go)
        top.submenu = sub
        return top
    }

    @objc func queueMenuPick(_ sender: NSMenuItem) { selectQueued(sender.tag) }
    @objc func allowAllQueued() { respondToQueue("allow") }
    @objc func denyAllQueued() { respondToQueue("deny") }

    /// Answers every waiting request the same way. The ones behind the card
    /// are written straight to disk; the card itself goes through respond()
    /// so the queue gets a single verdict animation rather than N of them
    /// racing each other.
    func respondToQueue(_ decision: String) {
        guard let currentId = currentRequestId, !isDismissing else { return }
        for req in orderedRequests() where req.id != currentId {
            writeDecision(id: req.id, request: req, decision: decision)
        }
        lastQueuedCount = 0
        pinnedRequestId = nil
        respond(decision)
    }
}
