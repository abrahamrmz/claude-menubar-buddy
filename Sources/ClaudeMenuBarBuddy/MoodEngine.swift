import AppKit
import BuddyCore

// The pet's mood pipeline: signals (turn markers, transcript activity, plan
// limit %) → a single mood string → GIF swaps on both pets, with flash
// states (heart/celebrate) layered on top.
extension AppDelegate {
    /// Only Claude Desktop writes plan-usage-history.json; with Desktop
    /// closed the numbers freeze at the last sample. Past this age they're
    /// history, not status — the UI grays them out and the pet/notification
    /// logic ignores them entirely.
    var planUsageIsStale: Bool {
        guard let sampled = usage.planUsageDate else { return true }
        return Date().timeIntervalSince(sampled) > 30 * 60
    }

    // The limit ladder (<50% = active … 100% = asleep) lives in
    // MoodPolicy, under test; this wrapper keeps the call sites short.
    func petMood(for pct: Int?) -> String {
        MoodPolicy.petMood(forFiveHourPct: pct)
    }

    func petMoodText(_ mood: String) -> String {
        switch mood {
        case "thinking": return "🤔 Thinking it over..."
        case "working": return "⚡ Working — running tools"
        case "tired": return "😅 Getting tired..."
        case "stressed": return "😰 Feeling the pressure (70% of the 5h limit)"
        case "critical": return "🥵 Running on fumes (85% of the 5h limit)"
        case "asleep": return "💤 Fast asleep (5h limit reached)"
        case "sad": return "😔 Aw, denied"
        case "excited", "greet": return "🤩 A new session said hi!"
        case "meditate": return "🧘 Meditating — compacting context"
        case "yawn": return "🥱 Nothing to do…"
        case "dance": return "🎉 Back in business!"
        // Species-neutral on purpose: this line follows whichever pet is
        // selected, and a koala announcing itself with a panda face was a
        // leftover from when the panda was the only pet.
        default: return "😊 Active and happy"
        }
    }

    /// True while any Claude Code turn is actually in flight, going by the
    /// turn_start markers notify-done.sh maintains (written on
    /// UserPromptSubmit, removed on Stop). This is the fix for the pet
    /// flickering back to idle mid-turn: transcript mtime goes quiet during
    /// long tool runs (a 30s build writes nothing), but the marker doesn't.
    /// The 30-minute cap self-heals orphans from sessions killed mid-turn.
    func anyTurnInFlight() -> Bool {
        let now = Date()
        for url in dirEntries where url.lastPathComponent.hasPrefix("turn_start_") {
            if let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
               now.timeIntervalSince(mtime) < 30 * 60 {
                return true
            }
        }
        return false
    }

    /// Session ids that have submitted at least one prompt while the app has
    /// been running. Seeded at launch so sessions that were already going
    /// before the buddy started don't all get greeted at once; after that, a
    /// previously unseen id means someone just opened a new session — worth
    /// a little "hi!". Returns true when this call found a newcomer.
    func noticeNewSessions() -> Bool {
        var isNew = false
        for url in dirEntries where url.lastPathComponent.hasPrefix("turn_start_") {
            let id = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "turn_start_", with: "")
            if seenTurnSessions.insert(id).inserted, seededTurnSessions { isNew = true }
        }
        // Everything present on the first pass is pre-existing, not news.
        seededTurnSessions = true
        return isNew
    }

    func updatePetMood() {
        // Stale plan data (Claude Desktop closed) is treated as unknown —
        // a pet asleep over an 11-day-old "100%" would be lying.
        let limitMood = petMood(for: planUsageIsStale ? nil : usage.fiveHourPct)
        // Was tired/stressed/critical/asleep last time we checked, and just
        // dropped back to healthy — the 5-hour window rolled over. Worth a
        // little fanfare instead of silently snapping back to the idle GIF.
        // (Not when the drop is only the reading going stale, though.)
        let limitJustRefreshed = lastLimitMood != "idle" && limitMood == "idle" && !planUsageIsStale
        lastLimitMood = limitMood
        // Runs every tick so the seen-set stays current even while another
        // mood is on screen.
        let greetsNewSession = noticeNewSessions()

        // A turn is in flight (marker file, or a transcript touched in the
        // last ~15s as fallback for sessions without the notify-done hook).
        // Both a running tool and a thinking model leave the transcript
        // quiet, so the tail of the newest one decides which pose it is.
        let turnInFlight = anyTurnInFlight() || !usage.activeSessions.isEmpty
        let activeMood: String
        if turnInFlight, let url = usage.newestTranscript,
           UsageReader.turnActivity(in: url, size: usage.newestTranscriptSize) == .model {
            activeMood = "thinking"
        } else {
            activeMood = "working"
        }

        // Priority: being out of budget outranks being busy (a pet at 100%
        // of the 5-hour limit can't be typing, and at 85% the warning is
        // more useful than the animation), but the milder limit moods lose
        // to actual work in progress.
        let mood: String
        if limitMood == "asleep" || limitMood == "critical" {
            mood = limitMood
        } else if turnInFlight {
            mood = activeMood
        } else {
            mood = limitMood
        }
        lastComputedMood = mood

        if limitJustRefreshed {
            sendNotification(title: "Claude 5-hour limit refreshed", body: "Buddy is back and ready to go!")
            // Two poses for the same good news, picked at random. The limit
            // rolling over is the rarest happy event the buddy has, and a
            // celebration that is pixel-identical every time stops reading as
            // one. Pets without dance art fall through to celebrate anyway.
            if currentRequestId == nil {
                flashMood(Bool.random() ? "dance" : "celebrate", for: 4.0)
            }
        } else if greetsNewSession && currentRequestId == nil {
            // A wave, not a face: the koala greets with its paw up, and pets
            // without the art degrade to the star-eyed excited it replaced.
            flashMood("greet", for: 3.0)
        } else if flashWorkItem == nil && currentRequestId == nil {
            // Don't stomp an in-progress heart/celebrate flash (it reverts
            // to lastComputedMood by itself) or the pending pose.
            applyMoodGif(mood)
            considerYawn()
        }
    }

    /// A yawn every so often while the pet has genuinely nothing to do.
    ///
    /// Deliberately the rarest thing on screen: the point is that idle time
    /// *has* texture, which a yawn every minute would destroy — it would read
    /// as a pet that is bored of you rather than one that has been waiting a
    /// while. So it needs an unbroken stretch of idle first, and then only
    /// fires on about one check in six, giving a typical gap of several
    /// minutes with no fixed period to notice.
    ///
    /// Every suppression here is one the speech bubble and the fidgets already
    /// honour: no yawning over a card, at a hidden pet, or while animations
    /// are paused for a locked screen — a pose nobody can see still costs the
    /// GIF swap, and would be waiting on screen at unlock.
    func considerYawn() {
        guard lastComputedMood == "idle", displayedMood == "idle",
              floatingPetVisible, floatingWindow?.isVisible == true,
              !animationsPaused, currentRequestId == nil,
              flashWorkItem == nil else {
            idleSinceYawn = 0
            return
        }
        idleSinceYawn += 1
        // The mood refresh runs every 5s, so 60 ticks is five unbroken
        // minutes of nothing before the first roll — a pet that just finished
        // a turn doesn't yawn at you — and a 1-in-12 chance per refresh after
        // that puts the average gap around six minutes. Worth writing down
        // because the first draft (24 ticks, 1-in-6) worked out to one every
        // two and a half minutes, which is a fidget, not a sign of life.
        guard idleSinceYawn >= 60, Int.random(in: 0..<12) == 0 else { return }
        idleSinceYawn = 0
        flashMood("yawn", for: 3.0)
    }

    // The degradation chains (thinking→working, meditate→thinking→idle, …)
    // live in MoodPolicy, where the tests audit every species × mood against
    // the shipped art; the app's only contribution is which bundle to ask.
    func gifName(for species: String, mood: String) -> String {
        MoodPolicy.gifName(species: species, mood: mood, available: bundleHasGif)
    }

    /// Whether the bundle ships this GIF — the `available` closure MoodPolicy
    /// resolves against (Prefs.selectedSpecies uses it too).
    func bundleHasGif(_ name: String) -> Bool {
        Bundle.module.url(forResource: name, withExtension: "gif",
                          subdirectory: "Resources") != nil
    }

    func applyMoodGif(_ mood: String) {
        guard mood != displayedMood else { return }
        displayedMood = mood
        let text = petMoodText(mood)
        // The mood strings lead with an emoji, which VoiceOver would announce
        // by name ("panda face, active and happy") — drop it for the label.
        let spoken = String(text.drop(while: { !$0.isLetter }))
        petMoodLineItem.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        // The desktop pet is the only one that wears the art now — the menu
        // keeps the mood as a line of text and nothing else.
        if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: gifName(for: selectedSpecies, mood: mood))
            floatingImageView.setAccessibilityLabel(spoken)
        }
        // A transition worth narrating gets a one-line speech bubble at the
        // pet; showSpeechBubble applies its own suppressions and cooldowns,
        // so this fires on every change and stays rare on screen.
        if let line = bubbleText(for: mood) { showSpeechBubble(line) }
        applyAnimationPolicy()
    }

    /// Picks up compact_<session>.json markers written by notify-done.sh on
    /// PreCompact and sends the pet into a meditation while Claude Code
    /// squeezes its context down. Fixed-length pose: there is no "compact
    /// finished" event to hang the end on, and ~25s covers a typical
    /// compaction without the pet looking stuck. Markers are consumed on
    /// sight, same as the done_ ones.
    func processCompactMarkers() {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        var compacting = false
        for url in dirEntries where url.lastPathComponent.hasPrefix("compact_") && url.pathExtension == "json" {
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            // Stale marker (written while the app wasn't running): the
            // compaction it announced is long over.
            if let ts = obj["ts"] as? Double, now - ts > 60 { continue }
            compacting = true
        }
        // An approval card keeps the spotlight — the pet stays in its
        // wide-eyed pending pose instead of serenely closing its eyes right
        // next to a question it is asking you.
        guard compacting, currentRequestId == nil else { return }
        flashMood("meditate", for: 25.0)
    }

    // Shows a mood GIF ("heart" on click, "celebrate" on limit reset) for a
    // few seconds, then reverts to whatever the current real mood is.
    func flashMood(_ mood: String, for seconds: Double) {
        flashWorkItem?.cancel()
        applyMoodGif(mood)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Nil first: it doubles as the "flash in progress" flag that
            // keeps updatePetMood from stomping the flash early.
            self.flashWorkItem = nil
            self.applyMoodGif(self.lastComputedMood)
        }
        flashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @objc func petClicked() {
        NSSound(named: "Tink")?.play()
        flashMood("heart", for: 2.0)
    }
}
