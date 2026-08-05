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
    // dramatizing. <50% used = active, 50-79% = tired, 80-99% = sleepy,
    // 100% = asleep.
    func petMood(for pct: Int?) -> String {
        guard let pct = pct else { return "idle" }
        if pct >= 100 { return "asleep" }
        if pct >= 80 { return "sleepy" }
        if pct >= 50 { return "tired" }
        return "idle"
    }

    func petMoodText(_ mood: String) -> String {
        switch mood {
        case "working": return "⚡ Working — session active"
        case "tired": return "😅 Getting tired..."
        case "sleepy": return "😴 Getting sleepy..."
        case "asleep": return "💤 Fast asleep (5h limit reached)"
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

    func updatePetMood() {
        // Stale plan data (Claude Desktop closed) is treated as unknown —
        // a pet asleep over an 11-day-old "100%" would be lying.
        let limitMood = petMood(for: planUsageIsStale ? nil : usage.fiveHourPct)
        // Was tired/sleepy/asleep last time we checked, and just dropped
        // back to healthy — the 5-hour window rolled over. Worth a little
        // fanfare instead of silently snapping back to the idle GIF.
        // (Not when the drop is only the reading going stale, though.)
        let limitJustRefreshed = lastLimitMood != "idle" && limitMood == "idle" && !planUsageIsStale
        lastLimitMood = limitMood

        // Working (turn marker in flight, or a transcript touched in the
        // last ~15s as fallback for sessions without the notify-done hook)
        // beats the intermediate limit moods, but not asleep — a pet at
        // 100% of the 5-hour limit can't be typing.
        let mood: String
        if limitMood == "asleep" {
            mood = "asleep"
        } else if anyTurnInFlight() || !usage.activeSessions.isEmpty {
            mood = "working"
        } else {
            mood = limitMood
        }
        lastComputedMood = mood

        if limitJustRefreshed {
            sendNotification(title: "Claude 5-hour limit refreshed", body: "Buddy is back and ready to go!")
            if currentRequestId == nil { flashMood("celebrate", for: 4.0) }
        } else if flashWorkItem == nil && currentRequestId == nil {
            // Don't stomp an in-progress heart/celebrate flash (it reverts
            // to lastComputedMood by itself) or the pending pose.
            applyMoodGif(mood)
        }
    }

    /// Only the panda has a "working" GIF (the species art comes from the
    /// hardware-buddy firmware, which has no such pose) — fall back to idle
    /// rather than leaving the previous GIF frozen on screen.
    func gifName(for species: String, mood: String) -> String {
        if Bundle.module.url(forResource: "\(species)_\(mood)", withExtension: "gif", subdirectory: "Resources") != nil {
            return "\(species)_\(mood)"
        }
        return "\(species)_idle"
    }

    func applyMoodGif(_ mood: String) {
        guard mood != displayedMood else { return }
        displayedMood = mood
        setGif(on: petImageView, named: gifName(for: selectedSpecies, mood: mood))
        petMoodLineItem.attributedTitle = NSAttributedString(
            string: petMoodText(mood),
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        // Floating pet is panda-only regardless of the dropdown's species
        // choice (Ray, 2026-07-12: "ทำแค่ panda ก็พอ").
        if let floatingImageView = floatingImageView {
            setGif(on: floatingImageView, named: gifName(for: "buddy", mood: mood))
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
