import AppKit

// What happens when the card is answered: the actions its buttons and
// hotkeys fire, the verdict animation, and everything a decision leaves on
// disk. Split out of ApprovalCard.swift (Fase 7.2), which keeps the card's
// assembly and lifecycle; the visual vocabulary lives in CardLayout.swift.
extension AppDelegate {
    /// First token of the command — must match hook.sh's extraction so the
    /// button's promise ("gh won't ask again") is exactly what the fast path
    /// later honors. Returns nil for anything that doesn't look like a plain
    /// command name.
    ///
    /// Also nil the moment the command can chain, substitute, redirect or
    /// expand. hook.sh refuses to fast-path those — an allowlist entry names
    /// one command and can only speak for one command — so offering the
    /// button there would be promising something that never happens, on the
    /// exact shapes where the promise would be most dangerous if it did.
    /// The character set is the same one hook.sh screens on; they have to
    /// agree or the button and the fast path drift apart.
    ///
    /// An env assignment in front is nil for the same reason, and it is the
    /// subtler case: the word stays `ls`, but `PATH=` changes which binary
    /// that word finds and `DYLD_INSERT_LIBRARIES=` loads foreign code into
    /// the right one. hook.sh sends those to a card, so no button here.
    func commandBase(from hint: String) -> String? {
        let shellMetacharacters = CharacterSet(charactersIn: ";&|<>()`$\\\n")
        guard hint.rangeOfCharacter(from: shellMetacharacters) == nil else { return nil }
        guard let token = hint.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { return nil }
        guard token.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) == nil else { return nil }
        let base = String(token)
        guard base.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil else { return nil }
        return base
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
        if let cwd = currentRequest?.cwd, !cwd.isEmpty {
            var forProject = list.projects[cwd] ?? []
            if !forProject.contains(base) { forProject.append(base) }
            list.projects[cwd] = forProject
        } else if !list.global.contains(base) {
            // No cwd — an ssh/tmux session, or a request written by a hook
            // older than the field. There is no project to scope to, so the
            // only grant expressible is the wide one, and the card's own
            // wording says "everywhere" in that case rather than implying a
            // narrowness it can't deliver.
            list.global.append(base)
        }
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

    @objc func chooseOption(_ sender: NSButton) { pickOption(at: sender.tag) }
    @objc func chooseOptionFromMenu(_ sender: NSMenuItem) { pickOption(at: sender.tag) }

    /// Hotkey path (⌘1..⌘4): flash the button first, same as ⌘⏎ does, so the
    /// shortcut feels like pressing the option rather than the card obeying.
    func chooseOptionViaHotKey(_ index: Int) {
        guard currentRequestId != nil, !isDismissing else { return }
        guard let card = statusBubbleWindow?.contentView, statusBubbleWindow?.isVisible == true,
              let button = card.subviews.compactMap({ $0 as? PressablePillButton })
                  .first(where: { $0.tag == index && $0.action == #selector(chooseOption(_:)) }) else {
            pickOption(at: index)
            return
        }
        button.setPressed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            button.setPressed(false)
            self?.pickOption(at: index)
        }
    }

    /// Records one answer. A call can hold several questions and the tool
    /// takes them as a single map, so the card walks to the next question
    /// instead of answering early — only the last pick actually responds.
    func pickOption(at index: Int) {
        guard !isDismissing, let req = currentRequest,
              let questions = req.choices, questions.indices.contains(choiceIndex) else { return }
        let question = questions[choiceIndex]
        guard question.options.indices.contains(index) else { return }
        collectedAnswers[question.question] = question.options[index].label

        if choiceIndex + 1 < questions.count {
            choiceIndex += 1
            let next = questions[choiceIndex]
            approvalHotKeys.enable(jump: jumpTarget(for: req) != nil, choices: next.options.count)
            showStatusBubble(for: req, queued: lastQueuedCount)
            return
        }
        respond("answer")
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
        // Answering a question is an affirmative act, not an approval — but
        // it's certainly not a rejection, so it gets the green ✓.
        let isAllow = decision == "allow" || decision == "answer"
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
                // Take the verdict wash back off. Nothing depended on this
                // before — showStatusBubble builds a fresh content view for
                // every request, so the overlay went out with the old one —
                // but that is an invariant nothing enforces, and the failure
                // mode if it ever breaks is a pending card that looks like it
                // was already approved. Cheaper to not leave it lying there.
                overlay.removeFromSuperview()
                completion()
            })
        })
    }

    /// Everything a decision does on disk — the response file the hook is
    /// waiting on, the audit line, and clearing the request. Split out from
    /// respond() because a batch does this N times but animates once.
    func writeDecision(id: String, request: PendingRequest?, decision: String,
                       reason: String? = nil, answers: [String: String]? = nil) {
        let responseURL = dirURL.appendingPathComponent("response_\(id).json")
        DebugLog.note("decision \(decision) written for \(id)\(request.map { " (\($0.tool))" } ?? "")")
        var payload: [String: Any] = ["decision": decision]
        if let reason = reason { payload["reason"] = reason }
        if let answers = answers { payload["answers"] = answers }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: responseURL, options: [.atomic])
        }

        // Append to the decision audit trail (shown in the Decision History
        // submenu). Hint is capped — the log records what was decided, not
        // full file contents.
        if let req = request {
            var entry: [String: Any] = [
                "ts": Date().timeIntervalSince1970,
                "tool": req.tool,
                "project": req.project ?? "",
                "hint": String(req.hint.prefix(200)),
                "decision": decision,
                // Which app was hosting the session — the audit trail should
                // say where a decision came from, not just what it was.
                "host": req.hostBundle ?? "",
            ]
            // For a question, "answer" alone says nothing — the log needs to
            // record what was actually chosen on the user's behalf.
            if let answers = answers { entry["answers"] = answers }
            // Into the in-memory week as well as onto disk, so the summary in
            // the menu is current without the log being re-read.
            noteDecision(DecisionRecord(ts: entry["ts"] as? Double ?? Date().timeIntervalSince1970,
                                        tool: req.tool, project: req.project ?? "", decision: decision))
            if let line = try? JSONSerialization.data(withJSONObject: entry) {
                let logURL = dirURL.appendingPathComponent("decisions.jsonl")
                // One rotation deep at ~1 MB (years of decisions): the menu
                // only ever shows the last 10, so past a point the file is
                // an archive nobody reads growing without bound. The .1 file
                // keeps the previous megabyte greppable; older than that is
                // genuinely gone, which is the accepted trade.
                if let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size]
                       as? Int, size > 1_000_000 {
                    let rotatedURL = dirURL.appendingPathComponent("decisions.1.jsonl")
                    try? FileManager.default.removeItem(at: rotatedURL)
                    try? FileManager.default.moveItem(at: logURL, to: rotatedURL)
                }
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
    }

    /// `decision` is allow / deny / pass / answer. `reason` rides along to the
    /// hook as the permissionDecisionReason, so a card that offers a specific
    /// choice ("keep planning") can say which one was taken instead of a
    /// generic "denied".
    func respond(_ decision: String, reason: String? = nil) {
        guard let id = currentRequestId, !isDismissing else { return }
        // Nobody is listening past the hook's window: the native prompt owns
        // the question now, and a response written here would be an orphan
        // file plus a decisions.jsonl line claiming Claude was told something
        // it never received. scanRequests already sweeps these once a second;
        // this covers the sub-second race where the click lands first.
        // Retiring goes through poll(), which fades the card neutrally (no
        // ✓/✕ — the buddy decided nothing) or surfaces the next in line.
        if let ts = currentRequest?.ts,
           Date().timeIntervalSince1970 - ts > AppDelegate.hookAnswerWindow {
            DebugLog.note("refused \(decision) for \(id): past the \(Int(AppDelegate.hookAnswerWindow))s answer window — nobody is listening, no log entry written")
            try? FileManager.default.removeItem(at: dirURL.appendingPathComponent("request_\(id).json"))
            respondedIds.insert(id)
            poll()
            return
        }
        writeDecision(id: id, request: currentRequest, decision: decision, reason: reason,
                      answers: decision == "answer" ? collectedAnswers : nil)
        // Verdict animation first — the decision is already on disk, so the
        // hook isn't waiting on this. setIdle + surfacing the next queued
        // request happen when the card finishes leaving, so back-to-back
        // approvals read as distinct cards instead of content swapping.
        isDismissing = true
        animateCardDismiss(decision: decision) { [weak self] in
            guard let self = self else { return }
            self.isDismissing = false
            self.setIdle()
            // A denial deserves a beat of visible disappointment — but only
            // after setIdle has put the real mood back, since it would
            // otherwise overwrite the flash immediately.
            if decision == "deny" { self.flashMood("sad", for: 3.0) }
            self.poll()
        }
    }

    @objc func allow() { respond("allow") }

    @objc func deny() {
        // On a plan card the deny button doesn't say "no", it says "keep
        // planning" — so the hook should pass that on rather than a bare
        // rejection Claude has to guess the meaning of.
        guard currentRequest?.tool == "ExitPlanMode" else {
            respond("deny")
            return
        }
        respond("deny", reason: "Not yet — keep planning. The user wants the plan refined before any of it is implemented.")
    }
}
