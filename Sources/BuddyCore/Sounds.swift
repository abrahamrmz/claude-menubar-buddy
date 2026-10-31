import Foundation

/// The four moments the buddy can make a sound, with the name it shows in the
/// menu, the key its choice is stored under and the sound it falls back to.
/// Pure, so the tests can exercise the catalog without AppKit or a bundle.
public enum SoundEvent: String, CaseIterable, Sendable {
    case cardArrived, turnDone, petClicked, hotKeyBlocked

    /// The name shown in the menu.
    public var title: String {
        switch self {
        case .cardArrived: return "Tarjeta nueva"
        case .turnDone: return "Turno terminado"
        case .petClicked: return "Clic a la mascota"
        case .hotKeyBlocked: return "Atajo bloqueado"
        }
    }

    /// The UserDefaults key. A key is never renamed: doing so loses what the
    /// user chose and silently brings back the default sound.
    public var defaultsKey: String {
        switch self {
        case .cardArrived: return "cardSound"
        case .turnDone: return "turnDoneSound"
        case .petClicked: return "petClickSound"
        case .hotKeyBlocked: return "blockedSound"
        }
    }

    /// The sound used when nothing valid is stored for this event.
    public var defaultSoundID: String {
        switch self {
        case .cardArrived: return "woodblock"
        case .turnDone: return "macos.Glass"
        case .petClicked: return "click"
        case .hotKeyBlocked: return "bong"
        }
    }
}

/// Where a sound comes from: a file bundled in `Resources/Sounds`, or one of
/// the sounds macOS ships.
public enum SoundSource: Equatable, Sendable {
    case bundled(file: String, ext: String)
    case system(name: String)
}

/// One choice in the catalog: an id that is stored, the name shown in the
/// menu, where the sound comes from and the gain applied when it plays.
public struct SoundOption: Equatable, Sendable {
    public let id: String
    public let title: String
    public let source: SoundSource
    public let gain: Float

    public init(id: String, title: String, source: SoundSource, gain: Float) {
        self.id = id
        self.title = title
        self.source = source
        self.gain = gain
    }
}

/// What an event plays: a sound, or silence.
public enum SoundChoice: Equatable, Sendable {
    case sound(SoundOption)
    case silent
}

/// Every sound the buddy can play: the five bundled CC0 sounds first, then
/// the fourteen macOS ones. The ids are stored in UserDefaults, so they are
/// never changed.
public enum SoundCatalog {
    /// The id stored for "no sound". Not a catalog option.
    public static let noneID = "none"

    /// The bundled sounds, in menu order.
    public static let bundled: [SoundOption] = [
        SoundOption(id: "woodblock", title: "Madera",
                    source: .bundled(file: "woodblock", ext: "wav"), gain: 1.0),
        SoundOption(id: "pluck", title: "Cuerda",
                    source: .bundled(file: "pluck", ext: "wav"), gain: 0.25),
        SoundOption(id: "drop", title: "Gota",
                    source: .bundled(file: "drop", ext: "wav"), gain: 0.28),
        SoundOption(id: "click", title: "Clic",
                    source: .bundled(file: "click", ext: "wav"), gain: 0.28),
        SoundOption(id: "bong", title: "Bong",
                    source: .bundled(file: "bong", ext: "wav"), gain: 0.28),
    ]

    /// The macOS sounds, in alphabetical order. These ship with every Mac and
    /// are played from the system, not copied into the repo.
    public static let systemNames: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    /// `systemNames` as catalog options.
    public static let system: [SoundOption] = systemNames.map {
        SoundOption(id: "macos.\($0)", title: $0, source: .system(name: $0), gain: 1.0)
    }

    /// The bundled sounds followed by the macOS ones.
    public static let all: [SoundOption] = bundled + system

    public static func option(id: String) -> SoundOption? {
        all.first { $0.id == id }
    }

    /// Resolves what an event plays from its stored value: `"none"` is
    /// silence, a known id is that sound, and anything else — unknown, empty
    /// or missing — is the event's default. Never silence, so a retired sound
    /// leaves the event audible instead of mute.
    public static func resolve(stored: String?, for event: SoundEvent) -> SoundChoice {
        if stored == noneID { return .silent }
        if let stored, let option = option(id: stored) { return .sound(option) }
        guard let fallback = option(id: event.defaultSoundID) else { return .silent }
        return .sound(fallback)
    }

    /// Which sounds are stopped before another plays. The blocked hotkey
    /// stops the card sound: otherwise the card's sound is still playing and
    /// buries the "not yet" (spec §9). Nothing else stops anything.
    public static func eventsToStop(before event: SoundEvent) -> [SoundEvent] {
        event == .hotKeyBlocked ? [.cardArrived] : []
    }
}
