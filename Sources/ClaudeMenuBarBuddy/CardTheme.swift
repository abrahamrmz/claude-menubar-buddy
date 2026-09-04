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
// friends). The card paints its own surface, so it does not follow the
// system appearance any more — a `.labelColor` here would turn white on
// white the moment the user switches to dark mode.
//
// WHICH surface it paints is a setting (Settings ▸ Appearance ▸ Card
// colors). Every color token below is derived from the four a CardPalette
// states, which is what keeps a palette from half-applying — and what makes
// the dark palette cost no new tokens at all: flip the ink and the surface,
// and the whole ramp flips with them.
enum CardTheme {

    // MARK: - Palette

    /// The palette every color token below is derived from.
    ///
    /// A stored property rather than a live read of the setting: `draw(_:)`
    /// asks for `surface` on every redraw, and building one card asks for
    /// some token about thirty times. Set at launch and again when the
    /// setting changes — which also keeps this file free of any opinion
    /// about how the app stores things.
    static private(set) var palette: CardPalette = .masko

    /// Switches palettes by id, falling back when the id names one that no
    /// longer exists — the same self-healing read as `selectedSpecies`, and
    /// for the same reason: retiring a palette must never leave a card with
    /// no colors at all.
    static func usePalette(_ id: String) { palette = CardPalette.resolve(id) }

    // MARK: - Ink

    /// The single ink every non-accent element is drawn from. Dark on a
    /// light palette, light on a dark one.
    static var ink: NSColor { palette.ink }

    /// The opacity ramp. These five stops are the whole grayscale of the
    /// card — a sixth value would be a sixth thing to keep consistent. None
    /// of them assumes which way the ink runs, which is the entire reason a
    /// dark palette needed no tokens of its own.
    static var inkPrimary: NSColor { ink }                          // titles, body
    static var inkMuted: NSColor { ink.withAlphaComponent(0.55) }   // secondary text, Deny
    static var inkHint: NSColor { ink.withAlphaComponent(0.30) }    // header icons, hint bar
    static var inkBorder: NSColor { ink.withAlphaComponent(0.12) }  // Deny outline, dividers
    static var inkWellBorder: NSColor { ink.withAlphaComponent(0.06) }
    static var inkChip: NSColor { ink.withAlphaComponent(0.05) }    // project pill

    // MARK: - Accent

    /// One accent for the whole card. The per-tool rainbow it replaces is
    /// still readable at a glance through the tool's SF Symbol and name —
    /// the color was the redundant half of that signal, and spending it on
    /// "this is the thing to press" buys more than spending it on "this is a
    /// Bash".
    static var accent: NSColor { palette.accent }

    /// The darker shade the primary button's hard shadow is drawn in, so the
    /// press reads as the cap descending onto its own base rather than as a
    /// blur appearing underneath it.
    ///
    /// Derived rather than stated, so no palette can ship a shadow that
    /// isn't its own accent. The factor reproduces Masko's hand-picked
    /// #c94a01 to within a unit per channel — a difference nobody can see,
    /// and one fewer number for a new palette to get wrong.
    static var accentShadow: NSColor { accent.darkened(by: 0.81) }
    static var accentSubtle: NSColor { accent.withAlphaComponent(0.08) }
    static var accentBorder: NSColor { accent.withAlphaComponent(0.25) }

    /// What text and glyphs sitting ON the accent are drawn in: the
    /// palette's light neutral, which on every palette shipped so far is the
    /// white "Allow" already wore.
    ///
    /// Deliberately NOT "whichever of the two contrasts more". Against
    /// Masko's orange that picks the plum ink over white; it measures
    /// better, and it is not the button this card was built around. So the
    /// swap only fires for an accent light enough that the light neutral
    /// would genuinely disappear on it — the case a hand-picked accent could
    /// actually walk into.
    static var onAccent: NSColor {
        accent.relativeLuminance < 0.45 ? palette.lightNeutral : palette.darkNeutral
    }

    // MARK: - Surfaces

    static var surface: NSColor { palette.surface }
    /// The code well: a half-step off the card so the command sits IN
    /// something without needing a heavy border.
    static var well: NSColor { palette.well }

    // MARK: - Diff colors

    // Tuned for the well, not inherited from the system: on #faf9f7,
    // `.systemGreen` is a pastel that fails as "this line is being added"
    // and `.systemRed` glows. The dark pair is the same judgement in the
    // other direction — those deep shades turn to mud on a dark well, so a
    // dark palette gets the lighter ones that survive there.
    static var removed: NSColor { palette.isDark ? hex(0xf871_71) : hex(0xdc26_26) }
    static var added: NSColor { palette.isDark ? hex(0x4ade_80) : hex(0x1580_3d) }

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

// MARK: - Palettes

/// The four colors a palette states. Everything else on the card is derived
/// from them.
///
/// Four and not thirty because the derivation is what keeps a palette
/// coherent: the ink ramp, the accent's shadow and washes, the text that
/// lands on the accent and the diff pair all fall out of these. A palette
/// can be an ugly choice, but it cannot be internally inconsistent.
struct CardPalette {
    let id: String
    /// Shown in the settings popup, and the key that popup maps back to `id`.
    let name: String
    /// The single ink. Dark on a light palette, light on a dark one.
    let ink: NSColor
    /// The one color that means "this is the thing to press". Keep it below
    /// ~0.45 relative luminance: `CardTheme.onAccent` puts the palette's
    /// light neutral on top of it, and a pale accent would swallow that.
    let accent: NSColor
    let surface: NSColor
    /// The code well. A half-step DOWN from the surface on a light palette
    /// and UP on a dark one — which is why it is stated rather than derived.
    /// "Slightly different from the surface" has a sign, and the sign flips.
    let well: NSColor

    /// Asked of the ink and the surface rather than of an absolute
    /// threshold. What the diff pair and `onAccent` actually need to know is
    /// which of the two neutrals is the lighter one, and that stays
    /// answerable for a palette that is neither clearly light nor clearly
    /// dark.
    var isDark: Bool { surface.relativeLuminance < ink.relativeLuminance }
    var lightNeutral: NSColor { isDark ? ink : surface }
    var darkNeutral: NSColor { isDark ? surface : ink }
}

extension CardPalette {
    /// Masko Code's own, read out of its source: plum ink, that orange, a
    /// warm off-white well.
    static let masko = CardPalette(
        id: "masko", name: "Masko",
        ink: hex(0x2311_3c), accent: hex(0xf95d_02),
        surface: hex(0xffff_ff), well: hex(0xfaf9_f7))

    /// Claude Code's clay over a warm near-black and an ivory well.
    static let claude = CardPalette(
        id: "claude", name: "Claude",
        ink: hex(0x1f1d_1a), accent: hex(0xd977_57),
        surface: hex(0xffff_ff), well: hex(0xf5f2_ea))

    /// The cold one: teal on deep navy, over a well tinted the same way.
    static let ocean = CardPalette(
        id: "ocean", name: "Ocean",
        ink: hex(0x0f2a_3d), accent: hex(0x0d94_88),
        surface: hex(0xffff_ff), well: hex(0xf1f7_f8))

    /// The same orange over a plum night. The accent is deliberately
    /// unchanged from Masko: `onAccent` picks the light neutral for any
    /// accent this dark, so the button behaves identically on both, and the
    /// palette's whole difference is the surface rather than a second
    /// opinion about what "press me" looks like.
    static let midnight = CardPalette(
        id: "midnight", name: "Midnight",
        ink: hex(0xf4f0_fb), accent: hex(0xf95d_02),
        surface: hex(0x1c1a_24), well: hex(0x2622_32))

    /// Popup order. Masko leads because it is the default.
    static let all: [CardPalette] = [.masko, .claude, .ocean, .midnight]

    static func resolve(_ id: String) -> CardPalette {
        all.first { $0.id == id } ?? .masko
    }

    static func named(_ displayName: String) -> CardPalette? {
        all.first { $0.name == displayName }
    }
}

/// sRGB from the hex everyone actually reads a palette in.
private func hex(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1)
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

// MARK: - Color math

private extension NSColor {
    /// The same color with sRGB components you can actually ask for.
    /// `NSColor.white` and friends live in a gray space where
    /// `.redComponent` raises instead of answering.
    var srgb: NSColor { usingColorSpace(.sRGB) ?? self }

    /// WCAG relative luminance — "is this light or dark", asked the way that
    /// accounts for green carrying most of the perceived brightness. A plain
    /// average of the channels calls #0d9488 and a mid gray equally dark,
    /// and they are not.
    var relativeLuminance: CGFloat {
        let color = srgb
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }

    /// Toward black by a flat factor per channel. Algebraically identical to
    /// scaling HSB brightness with the saturation held, but it stays in sRGB
    /// instead of round-tripping through the calibrated space NSColor's hue
    /// initializer builds in.
    func darkened(by factor: CGFloat) -> NSColor {
        let color = srgb
        return NSColor(srgbRed: color.redComponent * factor,
                       green: color.greenComponent * factor,
                       blue: color.blueComponent * factor,
                       alpha: color.alphaComponent)
    }
}
