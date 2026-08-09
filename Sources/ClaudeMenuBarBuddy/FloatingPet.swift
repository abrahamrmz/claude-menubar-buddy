import AppKit
import Defaults

// window.isMovableByWindowBackground alone doesn't reliably drag when a
// subview (here, an NSImageView filling the whole content area) is what
// actually receives the mouseDown — the hit-tested view can swallow the
// event before the window's own background-drag logic gets a chance, and
// this was inconsistent enough in testing (2026-07-12) to just implement
// dragging explicitly instead of trusting the flag.
final class DraggablePetImageView: PixelArtImageView {
    private var dragStartMouseScreenLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero

    // Without this, the first click on the pet while the app is inactive is
    // swallowed by activation and the drag never starts. The app is inactive
    // almost always once the non-activating approval card is in use (that
    // panel deliberately never activates us), which made the pet undraggable
    // exactly whenever the card was on screen.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseScreenLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartMouseScreenLocation.x
        let dy = current.y - dragStartMouseScreenLocation.y
        window.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + dx, y: dragStartWindowOrigin.y + dy))
    }

}

// Codex-style floating desktop pet: a borderless, always-on-top window that
// shows the selected species' GIF, draggable anywhere on screen, independent
// of the menu bar dropdown. Deliberately minimal — no speech bubble, no
// click-to-chat (Claude Code has no API for that, see revealSession's
// comment) — just ambient presence, which is the part that's actually
// buildable today.
final class FloatingPetWindow: NSWindow {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                    styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }
}

extension AppDelegate {
    /// Three steps instead of a slider, because only some sizes are honest.
    /// The koala's art is a 64px square (see CROP in generate_koala_gifs.py)
    /// and a Retina screen draws 2 backing pixels per point, so 128pt is
    /// exactly 4 screen pixels per source pixel, 192pt is 6 and 256pt is 8.
    /// Sizes in between split a source pixel across screen pixels, and pixel
    /// art shows that immediately as uneven block widths.
    ///
    /// The ladder follows the koala because it's the pet drawn for this app;
    /// the others have their own native sizes (panda 160, firmware pets
    /// 108×80) and can't all be integral at once. Changing CROP means
    /// rechecking these three numbers.
    var floatingPetSide: CGFloat {
        switch floatingPetSize {
        case "small": return 128
        case "large": return 256
        default: return 192
        }
    }

    // Codex-style floating pet — ambient status, no chat bubble (see
    // FloatingPetWindow's comment for why). Position and size persist across
    // launches; position defaults to the bottom-right of the main screen.
    //
    // The window is square and scales proportionally, so it fits both the
    // tall pets (buddy 160×160, koala 64×64) and the wide firmware ones
    // (108×80, which letterbox into transparency rather than stretch).
    func showFloatingPet() {
        if floatingWindow == nil {
            let side = floatingPetSide
            let window = FloatingPetWindow(size: NSSize(width: side, height: side))
            let imageView = DraggablePetImageView(frame: NSRect(x: 0, y: 0, width: side, height: side))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            setGif(on: imageView, named: gifName(for: selectedSpecies, mood: lastComputedMood))
            window.contentView?.addSubview(imageView)
            window.delegate = self
            let saved = Defaults[.floatingPetOrigin]
            if !saved.isEmpty, NSPointFromString(saved) != .zero {
                // Clamped, because a saved origin was recorded under whatever
                // size was current then — and under whatever monitors were
                // attached then. Restoring it verbatim can put a bigger pet
                // (or the same pet on a smaller screen) partly out of reach.
                var origin = NSPointFromString(saved)
                if let screen = NSScreen.main {
                    let visible = screen.visibleFrame
                    origin.x = min(max(origin.x, visible.minX), visible.maxX - side)
                    origin.y = min(max(origin.y, visible.minY), visible.maxY - side)
                }
                window.setFrameOrigin(origin)
            } else if let screen = NSScreen.main {
                let margin: CGFloat = 40
                window.setFrameOrigin(NSPoint(
                    x: screen.visibleFrame.maxX - side - margin,
                    y: screen.visibleFrame.minY + margin
                ))
            }
            floatingWindow = window
            floatingImageView = imageView
        }
        applyAnimationPolicy()
        floatingWindow?.orderFront(nil)
    }

    func hideFloatingPet() {
        floatingWindow?.orderOut(nil)
        hideStatusBubble()
        hideDoneToast()
    }

    /// Resizes in place around the pet's current centre rather than growing
    /// down-right from its origin: the pet is wherever the user parked it,
    /// and the eye tracks its middle, not its corner. Clamped back onto the
    /// screen afterwards, because a large pet parked in a corner would
    /// otherwise grow half of itself off the edge.
    @objc func petSizeChanged(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? String, size != floatingPetSize else { return }
        floatingPetSize = size
        buildIdleMenu()
        guard let window = floatingWindow else { return }
        let side = floatingPetSide
        var frame = NSRect(x: window.frame.midX - side / 2, y: window.frame.midY - side / 2,
                           width: side, height: side)
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - side)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - side)
        }
        window.setFrame(frame, display: true)
        floatingImageView?.frame = NSRect(x: 0, y: 0, width: side, height: side)
        // The window is transparent, so its shadow is derived from the
        // content's alpha — without this it keeps the outline of the old size.
        window.invalidateShadow()
        Defaults[.floatingPetOrigin] = NSStringFromPoint(frame.origin)
        if statusBubbleWindow?.isVisible == true { positionStatusBubble(above: window) }
    }

    @objc func toggleFloatingPet() {
        floatingPetVisible.toggle()
        if floatingPetVisible { showFloatingPet() } else { hideFloatingPet() }
        buildIdleMenu()
        if currentRequestId == nil {
            setIdle()
            updatePetMood()
        }
    }

    /// Default spot for any pet-attached window (approval card, done toast):
    /// centered above the pet's head. Keeps it on screen: with the pet
    /// parked near the top the "above the head" spot is offscreen (the card
    /// silently opened out of view), so flip it below the pet; and a pet
    /// hugging a side edge would push a centered window past it, so clamp
    /// horizontally.
    func originNearPet(for size: NSSize) -> NSPoint {
        guard let pet = floatingWindow else { return .zero }
        let petFrame = pet.frame
        var origin = NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY + 6)
        if let screen = pet.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.y + size.height > visible.maxY {
                origin.y = petFrame.minY - 6 - size.height
            }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        return origin
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? FloatingPetWindow {
            Defaults[.floatingPetOrigin] = NSStringFromPoint(window.frame.origin)
            if statusBubbleWindow?.isVisible == true {
                positionStatusBubble(above: window)
            }
        } else if let panel = notification.object as? NSWindow, panel === statusBubbleWindow,
                  let pet = floatingWindow {
            cardOffset = NSPoint(x: panel.frame.origin.x - pet.frame.origin.x,
                                 y: panel.frame.origin.y - pet.frame.origin.y)
        }
    }

    /// Same in-process render as the card selfie, for the pet window:
    /// `touch ~/.config/claude-menubar-buddy/capture_pet` → pet_selfie.png.
    func capturePetSelfieIfRequested() {
        guard debugFlagIsSet("capture_pet") else { return }
        let flagURL = dirURL.appendingPathComponent("capture_pet")
        guard let content = floatingWindow?.contentView, floatingWindow?.isVisible == true else { return }
        try? FileManager.default.removeItem(at: flagURL)
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dirURL.appendingPathComponent("pet_selfie.png"))
        }
    }
}
