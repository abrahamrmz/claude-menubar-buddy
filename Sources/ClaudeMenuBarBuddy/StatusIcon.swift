import AppKit

// What the menu bar actually shows. One function owns the whole icon so the
// three places that used to poke `statusItem.button?.title` can't drift.
//
// The default is a drawn template image rather than the 🐼 emoji: a template
// follows the menu bar's own appearance (light wallpaper, dark wallpaper,
// "Reduce transparency", the highlight while the menu is open) instead of
// being a fixed-color glyph sitting in it. The emoji is still one click away
// for anyone who wants the color back.
extension AppDelegate {
    var usesTemplateIcon: Bool { iconStyle == "template" }

    /// Panda as a silhouette: filled ears + head with the eye patches punched
    /// OUT of the mask. That inversion is what keeps it recognizable in
    /// monochrome — a solid blob would just read as a circle.
    func pandaIcon(pending: Bool, autoEdits: Bool) -> NSImage {
        let side: CGFloat = 18
        // Auto-approve-edits is a standing grant to watch for, so it earns
        // its own glyph beside the panda rather than a subtlety inside it.
        let pencilWidth: CGFloat = autoEdits ? 11 : 0
        let image = NSImage(size: NSSize(width: side + pencilWidth, height: side))
        image.lockFocus()

        let body = NSBezierPath()
        body.appendOval(in: NSRect(x: 1.0, y: 10.0, width: 6.2, height: 6.2))    // left ear
        body.appendOval(in: NSRect(x: 10.8, y: 10.0, width: 6.2, height: 6.2))   // right ear
        body.appendOval(in: NSRect(x: 0.6, y: 1.6, width: 16.8, height: 13.2))   // head
        NSColor.black.setFill()
        body.fill()

        // Wide eyes when a request is waiting — the same "!" the pending GIF
        // pulls, so the menu bar and the pet are telling one story.
        NSGraphicsContext.current?.compositingOperation = .clear
        let eyeW: CGFloat = pending ? 4.6 : 3.8
        let eyeH: CGFloat = pending ? 6.0 : 4.4
        let eyeY: CGFloat = pending ? 5.0 : 5.6
        let eyes = NSBezierPath()
        eyes.appendOval(in: NSRect(x: 3.8, y: eyeY, width: eyeW, height: eyeH))
        eyes.appendOval(in: NSRect(x: side - 3.8 - eyeW, y: eyeY, width: eyeW, height: eyeH))
        eyes.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        if autoEdits,
           let pencil = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(pointSize: 11, weight: .bold)) {
            pencil.draw(in: NSRect(x: side + 0.5, y: 3.5, width: 10, height: 11))
        }

        image.unlockFocus()
        // Alpha-only: AppKit tints it for the current appearance and inverts
        // it while the menu is open.
        image.isTemplate = true
        return image
    }

    /// The single entry point for the menu bar's state.
    /// - count: sessions when idle, queued requests when pending — either way
    ///   a number worth showing next to the icon.
    func applyStatusIcon(pending: Bool, count: Int, autoEdits: Bool, accessibility: String) {
        guard let button = statusItem.button else { return }
        button.setAccessibilityLabel(accessibility)
        button.toolTip = accessibility

        guard usesTemplateIcon else {
            button.image = nil
            button.imagePosition = .noImage
            button.contentTintColor = nil
            let badge = pending ? "❗" : (autoEdits ? "✏️" : "")
            button.title = "🐼\(badge)" + (count > 0 ? "\(count)" : "")
            return
        }

        button.image = pandaIcon(pending: pending, autoEdits: autoEdits)
        button.title = count > 0 ? " \(count)" : ""
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
        // Color carries urgency, the wide eyes carry it again for anyone who
        // can't use the color — a template image takes the tint wholesale.
        button.contentTintColor = pending ? .systemOrange : nil
    }

    /// Pending flavor of applyStatusIcon — the count is the queue behind the
    /// card, and the label names what's actually asking.
    func applyPendingStatusIcon(for req: PendingRequest, queued: Int) {
        let project = (req.project?.isEmpty == false) ? " in \(req.project!)" : ""
        let waiting = queued > 0 ? ", \(queued) more waiting" : ""
        applyStatusIcon(pending: true, count: queued > 0 ? queued + 1 : 0, autoEdits: false,
                        accessibility: "Claude Menu Bar Buddy — \(req.tool) permission request\(project)\(waiting)")
    }

    /// Debug/docs helper, same idea as capture_card/capture_pet: `touch
    /// ~/.config/claude-menubar-buddy/capture_icon` and the app writes every
    /// icon variant to icon_selfie.png, drawn light-on-dark the way the menu
    /// bar tints a template. Beats squinting at 18 points of menu bar.
    func captureIconSelfieIfRequested() {
        let flagURL = dirURL.appendingPathComponent("capture_icon")
        guard FileManager.default.fileExists(atPath: flagURL.path) else { return }
        try? FileManager.default.removeItem(at: flagURL)

        let variants: [(String, NSImage)] = [
            ("idle", pandaIcon(pending: false, autoEdits: false)),
            ("pending", pandaIcon(pending: true, autoEdits: false)),
            ("auto-edits", pandaIcon(pending: false, autoEdits: true)),
        ]
        let scale: CGFloat = 6
        let gap: CGFloat = 12
        let width = variants.reduce(0) { $0 + $1.1.size.width * scale + gap } + gap
        let height = 18 * scale + gap * 2
        let sheet = NSImage(size: NSSize(width: width, height: height))
        sheet.lockFocus()
        NSColor(white: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        var x = gap
        for (_, icon) in variants {
            let box = NSRect(x: 0, y: 0, width: icon.size.width * scale, height: 18 * scale)
            // Tint on its own transparent canvas: .sourceAtop paints wherever
            // the DESTINATION has alpha, so doing this straight onto the
            // already-opaque sheet would just fill a rectangle.
            let tinted = NSImage(size: box.size)
            tinted.lockFocus()
            icon.draw(in: box)
            NSColor(white: 0.95, alpha: 1).set()
            box.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: box.offsetBy(dx: x, dy: gap))
            x += box.width + gap
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dirURL.appendingPathComponent("icon_selfie.png"))
        }
    }

}
