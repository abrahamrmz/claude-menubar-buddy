import AppKit
import BuddyCore
import Defaults

// Occasional speech bubble at the floating pet: one short line of context
// ("meditating", "heading for 90% ≈ 16:40") in a small HUD pill above the
// pet's head. Same visual language as the toast, but smaller and rarer —
// the bubble is seasoning, and the cooldowns below are what keep it from
// becoming a chat log.
extension AppDelegate {
    // Which transitions are worth narrating — and which stay silent — is
    // policy, so it lives in MoodPolicy with the words themselves.
    func bubbleText(for mood: String) -> String? {
        MoodPolicy.bubbleLine(mood)
    }

    /// Shows a bubble unless something outranks it. The suppressions are the
    /// design: no bubble over an approval card (the card is the spotlight),
    /// none while the finish toast is up (two pieces of chrome saying
    /// different things), none for a hidden pet, and never the same line
    /// twice in five minutes nor any two lines within 20 seconds.
    func showSpeechBubble(_ text: String, seconds: Double = 4.0) {
        guard speechBubbles,
              floatingPetVisible, let pet = floatingWindow, pet.isVisible,
              !animationsPaused,
              currentRequestId == nil,
              toastWindow?.isVisible != true else { return }
        let now = Date()
        if text == lastSpeechBubbleText, now.timeIntervalSince(lastSpeechBubbleAt) < 300 { return }
        if now.timeIntervalSince(lastSpeechBubbleAt) < 20 { return }
        lastSpeechBubbleText = text
        lastSpeechBubbleAt = now

        speechBubbleDismissWork?.cancel()

        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        // Measured by the field itself, not by NSString.size — the field is
        // what draws, so the field is what gets to say how wide it is. (The
        // gap was first noticed with the since-retired emoji prefixes, but
        // the principle outlives them.)
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.sizeToFit()
        // +6: sizeToFit is knife-edge and subpixel rounding in the actual
        // draw needs a hair more before the ellipsis backs off.
        let textWidth = ceil(label.frame.width) + 6
        let height: CGFloat = 26
        // The cap only exists so a pathological string can't build a banner
        // across the screen.
        let width = min(textWidth + 24, 340)

        let window: NSPanel
        if let existing = speechBubbleWindow {
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
            speechBubbleWindow = panel
            window = panel
        }

        let pill = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        pill.material = .hudWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = height / 2
        pill.layer?.masksToBounds = true
        pill.setAccessibilityLabel(text)
        window.contentView = pill

        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.frame = NSRect(x: 12, y: (height - label.frame.height) / 2,
                             width: width - 24, height: label.frame.height)
        pill.addSubview(label)

        let wasVisible = window.isVisible
        window.setFrameOrigin(originNearPet(for: NSSize(width: width, height: height)))
        if wasVisible {
            window.orderFront(nil)
        } else {
            let target = window.frame
            window.setFrame(target.offsetBy(dx: 0, dy: -6), display: false)
            window.alphaValue = 0
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                window.animator().setFrame(target, display: true)
            }
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let bubble = self.speechBubbleWindow, bubble.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                bubble.animator().alphaValue = 0
            }, completionHandler: {
                bubble.orderOut(nil)
                bubble.alphaValue = 1
            })
        }
        speechBubbleDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hideSpeechBubble() {
        speechBubbleDismissWork?.cancel()
        speechBubbleWindow?.orderOut(nil)
        speechBubbleWindow?.alphaValue = 1
    }

    /// Sibling of capture_pet: `touch ~/.config/claude-menubar-buddy/
    /// capture_bubble` → bubble_selfie.png (only under CLAUDE_BUDDY_DEBUG).
    func captureBubbleSelfieIfRequested() {
        guard debugFlagIsSet("capture_bubble") else { return }
        let flagURL = dirURL.appendingPathComponent("capture_bubble")
        guard let content = speechBubbleWindow?.contentView,
              speechBubbleWindow?.isVisible == true else { return }
        try? FileManager.default.removeItem(at: flagURL)
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dirURL.appendingPathComponent("bubble_selfie.png"))
        }
    }
}
