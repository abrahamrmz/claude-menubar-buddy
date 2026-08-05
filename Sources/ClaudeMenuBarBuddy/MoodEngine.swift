import AppKit

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

    // The pet's mood follows the 5-hour limit, not the weekly one — it's
    // the one that actually blocks you mid-session, so it's the one worth
    // dramatizing. The ladder: <50% used = active, 50% = tired, 70% =
    // stressed, 85% = critical, 100% = asleep.
    func petMood(for pct: Int?) -> String {
        guard let pct = pct else { return "idle" }
        if pct >= 100 { return "asleep" }
        if pct >= 85 { return "critical" }
        if pct >= 70 { return "stressed" }
        if pct >= 50 { return "tired" }
        return "idle"
    }

    func petMoodText(_ mood: String) -> String {
        switch mood {
        case "thinking": return "🤔 Thinking it over..."
        case "working": return "⚡ Working — running tools"
        case "tired": return "😅 Getting tired..."
        case "stressed": return "😰 Feeling the pressure (70% of the 5h limit)"
        case "critical": return "🥵 Running on fumes (85% of the 5h limit)"
        case "sleepy": return "😴 Getting sleepy..."
        case "asleep": return "💤 Fast asleep (5h limit reached)"
        case "sad": return "😔 Aw, denied"
        case "excited": return "🤩 A new session said hi!"
        default: return "🐼 Active and happy"
        }
    }

    /// True while any Claude Code turn is actually in flight, going by the
    /// turn_start markers notify-done.sh maintains (written on
    /// UserPromptSubmit, removed on Stop). This is the fix for the pet
    /// flickering back to idle mid-turn: transcript mtime goes quiet during
    /// long tool runs (a 30s build writes nothing), but the marker doesn't.
    /// The 30-minute cap self-heals orphans from sessions killed mid-turn.
    func anyTurnInFlight() -> Bool {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return false }
        let now = Date()
        for url in urls where url.lastPathComponent.hasPrefix("turn_start_") {
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
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else { return false }
        var isNew = false
        for url in urls where url.lastPathComponent.hasPrefix("turn_start_") {
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
            if currentRequestId == nil { flashMood("celebrate", for: 4.0) }
        } else if greetsNewSession && currentRequestId == nil {
            flashMood("excited", for: 3.0)
        } else if flashWorkItem == nil && currentRequestId == nil {
            // Don't stomp an in-progress heart/celebrate flash (it reverts
            // to lastComputedMood by itself) or the pending pose.
            applyMoodGif(mood)
        }
    }

    /// Not every pet has art for every mood — the species come from the
    /// hardware-buddy firmware, which only ever drew a handful of poses, and
    /// even the panda borrows for the newest limit bands. Each mood names
    /// the closest thing it can degrade to, ending at idle, so a missing GIF
    /// never leaves the previous one frozen on screen.
    func moodGifCandidates(_ mood: String) -> [String] {
        switch mood {
        // Until 2.4 gives the pressure bands their own poses, they wear the
        // sleep ladder's — which is at least the right direction.
        case "stressed": return ["stressed", "tired"]
        case "critical": return ["critical", "sleepy", "tired"]
        case "thinking": return ["thinking", "working"]
        case "excited": return ["excited", "celebrate", "heart"]
        case "sad": return ["sad", "tired"]
        default: return [mood]
        }
    }

    func gifName(for species: String, mood: String) -> String {
        for candidate in moodGifCandidates(mood) {
            if Bundle.module.url(forResource: "\(species)_\(candidate)", withExtension: "gif",
                                 subdirectory: "Resources") != nil {
                return "\(species)_\(candidate)"
            }
        }
        return "\(species)_idle"
    }

    func applyMoodGif(_ mood: String) {
        guard mood != displayedMood else { return }
        displayedMood = mood
        let text = petMoodText(mood)
        // The mood strings lead with an emoji, which VoiceOver would announce
        // by name ("panda face, active and happy") — drop it for the label.
        let spoken = String(text.drop(while: { !$0.isLetter }))
        setGif(on: petImageView, named: gifName(for: selectedSpecies, mood: mood))
        petImageView.setAccessibilityLabel(spoken)
        petMoodLineItem.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        // Floating pet is panda-only regardless of the dropdown's species
        // choice (Ray, 2026-07-12: "ทำแค่ panda ก็พอ").
        if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: gifName(for: "buddy", mood: mood))
            floatingImageView.setAccessibilityLabel(spoken)
        }
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
