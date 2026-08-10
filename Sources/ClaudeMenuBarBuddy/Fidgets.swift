import AppKit
import Defaults

// Ambient motion for the floating pet: a slow bob, an occasional squash, and
// a small reaction to the cursor. Everything here is Core Animation on the
// pet's layer — the GPU interpolates the frames, no timer ticks per frame —
// or event-driven (tracking areas). The only recurring CPU cost is one timer
// firing every 30–90 seconds, and only while the pet is actually visible.
extension AppDelegate {
    private static let bobKey = "fidget.bob"
    private static let squashKey = "fidget.squash"

    var calmPet: Bool {
        get { Defaults[.calmPet] }
        set { Defaults[.calmPet] = newValue }
    }

    /// The one decision point: fidgets run only while someone could see them.
    /// Called from applyAnimationPolicy, which already runs on every GIF
    /// swap, screen lock/unlock, and display sleep/wake — so the pause rules
    /// for GIF frames and for fidgets can never drift apart. Occlusion (a
    /// fullscreen app covering the pet) comes in via its own delegate call.
    func applyFidgetPolicy() {
        let wanted = !calmPet
            && floatingWindow?.isVisible == true
            && floatingWindow?.occlusionState.contains(.visible) == true
            && !animationsPaused
        if wanted { startFidgets() } else { stopFidgets() }
    }

    private func startFidgets() {
        guard let imageView = floatingImageView else { return }
        imageView.wantsLayer = true
        guard let layer = imageView.layer else { return }
        // AppKit's default anchor is the bottom-left corner, which would turn
        // every scale into a lean. Same fix as the card's buttons: anchor at
        // the center and put position where the frame already is.
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let f = layer.frame
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: f.midX, y: f.midY)
        }
        if layer.animation(forKey: Self.bobKey) == nil {
            let bob = CABasicAnimation(keyPath: "transform.translation.y")
            bob.fromValue = -2
            bob.toValue = 2
            bob.duration = 3.5
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(bob, forKey: Self.bobKey)
        }
        if fidgetSquashTimer == nil { scheduleSquash() }
    }

    private func stopFidgets() {
        fidgetSquashTimer?.invalidate()
        fidgetSquashTimer = nil
        guard let layer = floatingImageView?.layer else { return }
        layer.removeAnimation(forKey: Self.bobKey)
        layer.removeAnimation(forKey: Self.squashKey)
        layer.setAffineTransform(.identity)
    }

    /// The jitter is the point: a squash on a fixed period reads as a
    /// metronome within a couple of repeats, and the pet stops looking alive
    /// and starts looking mechanical. One-shot timers rescheduled with a
    /// fresh random delay each time.
    private func scheduleSquash() {
        fidgetSquashTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 30...90),
                                                 repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.fidgetSquashTimer = nil
            if let layer = self.floatingImageView?.layer {
                let squash = CABasicAnimation(keyPath: "transform.scale.y")
                squash.toValue = 0.94
                squash.duration = 0.1
                squash.autoreverses = true
                squash.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(squash, forKey: Self.squashKey)
            }
            self.scheduleSquash()
        }
    }

    /// Cursor over the pet: a lean-in, and once in a while a heart — but
    /// never while a card is up (the pending pose is holding the spotlight)
    /// and never interrupting a flash already playing.
    func petHoverChanged(_ inside: Bool) {
        guard !calmPet, let layer = floatingImageView?.layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        layer.setAffineTransform(inside ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity)
        CATransaction.commit()
        if inside, Int.random(in: 0..<6) == 0,
           flashWorkItem == nil, currentRequestId == nil {
            flashMood("heart", for: 1.5)
        }
    }

    /// A fullscreen video or a covering window means nobody can see the pet;
    /// macOS tells us exactly that, for free, through the occlusion state.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard notification.object as? FloatingPetWindow != nil else { return }
        applyFidgetPolicy()
    }
}
