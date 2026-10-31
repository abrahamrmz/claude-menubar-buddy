import Foundation

/// One row of an event's sound submenu, ready for the app to paint. Pure, so
/// the menu's order and checkmark are tested without AppKit.
public enum SoundMenuRow: Equatable, Sendable {
    case option(id: String, title: String, checked: Bool)
    case header(String)
    case separator
}

/// Builds an event's sound submenu from the catalog and what is stored.
public enum SoundMenu {
    /// The event's menu row: "Tarjeta nueva — Madera"; "… — Sin sonido" for
    /// silence.
    public static func rowTitle(for event: SoundEvent, stored: String?) -> String {
        switch SoundCatalog.resolve(stored: stored, for: event) {
        case .sound(let option):
            return "\(event.title) — \(option.title)"
        case .silent:
            return "\(event.title) — Sin sonido"
        }
    }

    /// One event's submenu rows, in order: the bundled sounds, then the macOS
    /// section (only when at least one of them is available), then "Sin
    /// sonido". The checkmark lands on whatever `resolve` picked, so an
    /// unknown stored value marks the event's default sound.
    public static func rows(for event: SoundEvent, stored: String?,
                            systemAvailable: (String) -> Bool) -> [SoundMenuRow] {
        let chosenID: String
        switch SoundCatalog.resolve(stored: stored, for: event) {
        case .sound(let option): chosenID = option.id
        case .silent: chosenID = SoundCatalog.noneID
        }

        var rows: [SoundMenuRow] = SoundCatalog.bundled.map {
            .option(id: $0.id, title: $0.title, checked: $0.id == chosenID)
        }

        let availableSystem = SoundCatalog.system.filter {
            if case .system(let name) = $0.source { return systemAvailable(name) }
            return false
        }
        if !availableSystem.isEmpty {
            rows.append(.separator)
            rows.append(.header("macOS"))
            rows.append(contentsOf: availableSystem.map {
                .option(id: $0.id, title: $0.title, checked: $0.id == chosenID)
            })
        }

        rows.append(.separator)
        rows.append(.option(id: SoundCatalog.noneID, title: "Sin sonido",
                            checked: chosenID == SoundCatalog.noneID))
        return rows
    }
}
