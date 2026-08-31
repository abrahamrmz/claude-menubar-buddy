import AppKit
import CoreText

// The card's design tokens, in the vocabulary Masko Code used: a light
// surface, ONE ink at several opacities instead of a palette, ONE accent,
// a rounded display face for anything you act on, and a speech-bubble
// silhouette with a tail that points back at the pet.
//
// The tokens are gathered here rather than spread through the layout code
// because that is what makes them a system: the difference between "the
// muted label is 55% ink" and "the muted label is some gray someone picked"
// is whether the next label added agrees with the ones already there.
//
// Colors are literal sRGB, NOT semantic system colors (.labelColor and
// friends). The card paints its own light surface, so it does not follow
// the system appearance any more — a `.labelColor` here would turn white on
// white the moment the user switches to dark mode.
enum CardTheme {

    // MARK: - Ink

    /// The single ink every non-accent element is drawn from: a deep plum
    /// that reads as "almost black" without the harshness of true black on
    /// a warm white.
    static let ink = NSColor(srgbRed: 35 / 255, green: 17 / 255, blue: 60 / 255, alpha: 1)

    /// The opacity ramp. These five stops are the whole grayscale of the
    /// card — a sixth value would be a sixth thing to keep consistent.
    static let inkPrimary = ink                      // titles, body
    static let inkMuted = ink.withAlphaComponent(0.55)   // secondary text, Deny
    static let inkHint = ink.withAlphaComponent(0.30)    // header icons, hint bar
    static let inkBorder = ink.withAlphaComponent(0.12)  // Deny outline, dividers
    static let inkWellBorder = ink.withAlphaComponent(0.06)
    static let inkChip = ink.withAlphaComponent(0.05)    // project pill

    // MARK: - Accent

    /// One accent for the whole card. The per-tool rainbow it replaces is
    /// still readable at a glance through the tool's SF Symbol and name —
    /// the color was the redundant half of that signal, and spending it on
    /// "this is the thing to press" buys more than spending it on "this is a
    /// Bash".
    static let accent = NSColor(srgbRed: 249 / 255, green: 93 / 255, blue: 2 / 255, alpha: 1)
    /// The darker shade the primary button's hard shadow is drawn in, so the
    /// press reads as the cap descending onto its own base rather than as a
    /// blur appearing underneath it.
    static let accentShadow = NSColor(srgbRed: 201 / 255, green: 74 / 255, blue: 1 / 255, alpha: 1)
    static let accentSubtle = NSColor(srgbRed: 249 / 255, green: 93 / 255, blue: 2 / 255, alpha: 0.08)
    static let accentBorder = NSColor(srgbRed: 249 / 255, green: 93 / 255, blue: 2 / 255, alpha: 0.25)

    // MARK: - Surfaces

    static let surface = NSColor.white
    /// The code well: warm off-white, a half-step down from the card so the
    /// command sits IN something without needing a heavy border.
    static let well = NSColor(srgbRed: 250 / 255, green: 249 / 255, blue: 247 / 255, alpha: 1)

    // MARK: - Diff colors

    // Tuned for the near-white well, not inherited from the system: on
    // #faf9f7, `.systemGreen` is a pastel that fails as "this line is being
    // added" and `.systemRed` glows. These are the darker web-safe pair.
    static let removed = NSColor(srgbRed: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)
    static let added = NSColor(srgbRed: 21 / 255, green: 128 / 255, blue: 61 / 255, alpha: 1)

    // MARK: - Metrics

    /// Wide enough that a mini-diff's lines don't wrap at `codeSize`. Masko's
    /// bubble is 280 because it punts long content to an expanded panel; this
    /// card shows the diff you are approving, and a wrapped diff line is a
    /// diff line you have to reassemble in your head before deciding.
    static let cardWidth: CGFloat = 430
    static let cornerRadius: CGFloat = 14
    static let cornerRadiusSmall: CGFloat = 10
    static let buttonRadius: CGFloat = 8
    /// Outer padding and the gap between stacked sections.
    static let padding: CGFloat = 10
    static let spacing: CGFloat = 6
    static let tailHeight: CGFloat = 9
    static let tailWidth: CGFloat = 16

    // MARK: - Type scale

    // Masko's compact bubble runs at 11/10/8pt — but it is 280pt wide, and
    // ours is 430 because it shows mini-diffs instead of deferring them all
    // to an expanded panel. Lifting those numbers onto a card half again as
    // wide read small, and matching the sizes the card used BEFORE the
    // repaint (14 title / 13 buttons / 12.5 code, all in the system font)
    // still read small — because Fredoka and Rubik carry less optical size
    // per point than SF, which is drawn with a large x-height and loose
    // spacing precisely so it survives at small sizes. A custom face has to
    // be set a point or two larger to land at the same apparent size, so
    // these deliberately sit ABOVE what the system font needed.
    static let titleSize: CGFloat = 15      // tool name, toast project
    static let bodySize: CGFloat = 13.5     // question text
    static let codeSize: CGFloat = 12.5     // the command / diff
    static let buttonSize: CGFloat = 14     // Allow, Deny, option labels
    static let metaSize: CGFloat = 12.5     // project pill, descriptions, quiet row
    static let hintSize: CGFloat = 11       // the shortcut line under the buttons
    static let badgeSize: CGFloat = 11      // the ⌘-held capsules

    // MARK: - Typography

    // Fredoka (rounded, friendly) for anything you read as a label or press
    // as a button; Rubik for prose. Both are variable fonts registered at
    // launch, so a weight is a point on the `wght` axis rather than a
    // separate file.
    private static let weightAxis = 0x77676874  // 'wght'

    /// Registers the bundled faces. Called once at startup; safe to call
    /// again (CoreText reports an already-registered URL as a failure, which
    /// is exactly as harmless as it sounds). Returns nothing on purpose:
    /// every accessor below already falls back to a system face, so a failed
    /// registration costs the card its personality and nothing else.
    static func registerFonts() {
        for name in ["Fredoka", "Rubik"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf",
                                              subdirectory: "Resources/Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private static func variable(_ family: String, size: CGFloat, weight: CGFloat,
                                 fallback: NSFont) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: family,
            NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): [weightAxis: weight],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }

    /// Headings, buttons, anything with a voice. Falls back to the system's
    /// own rounded design, which is the closest thing macOS ships to
    /// Fredoka — a plain system fallback would lose the roundness that IS
    /// the character here.
    static func heading(_ size: CGFloat, weight: CGFloat = 600) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight >= 700 ? .bold : .semibold)
        let rounded = system.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: size) } ?? system
        return variable("Fredoka", size: size, weight: weight, fallback: rounded)
    }

    /// Body copy and metadata.
    static func body(_ size: CGFloat, weight: CGFloat = 400) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: weight >= 500 ? .medium : .regular)
        return variable("Rubik", size: size, weight: weight, fallback: fallback)
    }

    /// The command / diff itself stays monospaced — SF Mono, since neither
    /// Fredoka nor Rubik has a fixed-width companion and a proportional font
    /// would misalign the one content on the card where columns carry
    /// meaning.
    static func code(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Motion

    /// The card's spring vocabulary: physically-settled motion instead of an
    /// ease curve that decelerates and just stops. Runs in the render server
    /// like every Core Animation — the app is not woken per frame, so the
    /// idle-CPU story is untouched. Model values are never changed here; the
    /// animation plays over the layer's real state and lifts off.
    static func spring(_ keyPath: String, from: Any, to: Any,
                       damping: CGFloat = 24, stiffness: CGFloat = 380,
                       velocity: CGFloat = 0) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.fromValue = from
        spring.toValue = to
        spring.mass = 1
        spring.damping = damping
        spring.stiffness = stiffness
        spring.initialVelocity = velocity
        spring.duration = spring.settlingDuration
        return spring
    }

    /// AppKit layers anchor at the bottom-left corner, so a transform.scale
    /// without this reads as a stretch hinged on the corner instead of a pop
    /// from the middle. Re-anchoring moves `position` too, or the layer
    /// would jump by half its size.
    static func centerAnchor(_ layer: CALayer) {
        guard layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) else { return }
        let frame = layer.frame
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
    }
}

// MARK: - Speech bubble shape

/// Which edge the tail sticks out of. The card sits above the pet by
/// default, so the tail normally points down; `originNearPet` flips the card
/// below the pet when there's no room above, and the tail flips with it.
enum TailSide {
    case top, bottom, none
}

extension CardTheme {
    /// Rounded rect with a triangular tail, in the content view's own
    /// (bottom-left origin) coordinates. `percent` is where along the edge
    /// the tail's point sits, 0–1, and is clamped so the triangle can never
    /// climb into a corner arc and tear the outline.
    ///
    /// `rect` is the FULL view including the tail strip; the rounded body is
    /// inset from it by `tailHeight` on whichever side the tail is on.
    ///
    /// `radius` is a parameter because the same silhouette serves the card
    /// (14pt corners) and the pet's one-line speech pill, where the corner is
    /// half the height and the shape is a capsule with a tail.
    static func bubblePath(in rect: CGRect, tail: TailSide, percent: CGFloat,
                           radius: CGFloat = cornerRadius) -> CGPath {
        let path = CGMutablePath()

        let body: CGRect
        switch tail {
        case .bottom: body = CGRect(x: 0, y: tailHeight, width: rect.width, height: rect.height - tailHeight)
        case .top: body = CGRect(x: 0, y: 0, width: rect.width, height: rect.height - tailHeight)
        case .none: body = rect
        }

        guard tail != .none else {
            path.addRoundedRect(in: body, cornerWidth: radius, cornerHeight: radius)
            return path
        }

        // Keep the whole triangle clear of both corner arcs.
        let half = tailWidth / 2
        let center = min(max(rect.width * percent, radius + half), rect.width - radius - half)

        // One walk counter-clockwise from just above the bottom-left corner,
        // detouring into the tail on whichever edge carries it.
        // addArc(tangent:) draws each corner from the two edges that meet
        // there, so the joins stay exact without any angle arithmetic.
        path.move(to: CGPoint(x: body.minX, y: body.minY + radius))

        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                    tangent2End: CGPoint(x: body.minX + radius, y: body.minY), radius: radius)
        if tail == .bottom {
            path.addLine(to: CGPoint(x: center - half, y: body.minY))
            path.addLine(to: CGPoint(x: center, y: rect.minY))   // the point
            path.addLine(to: CGPoint(x: center + half, y: body.minY))
        }
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))

        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                    tangent2End: CGPoint(x: body.maxX, y: body.minY + radius), radius: radius)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))

        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                    tangent2End: CGPoint(x: body.maxX - radius, y: body.maxY), radius: radius)
        if tail == .top {
            path.addLine(to: CGPoint(x: center + half, y: body.maxY))
            path.addLine(to: CGPoint(x: center, y: rect.maxY))   // the point
            path.addLine(to: CGPoint(x: center - half, y: body.maxY))
        }
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))

        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX, y: body.maxY - radius), radius: radius)
        path.closeSubpath()
        return path
    }
}
