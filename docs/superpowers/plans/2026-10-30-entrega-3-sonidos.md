# Entrega 3: sonidos — plan de implementación

> **Para agentes:** ejecuta este plan tarea por tarea, en orden, marcando cada checkbox (`- [ ]` → `- [x]`) al terminar el paso. El plan, con sus checkboxes marcados, entra en el commit de cada tarea: agrega `docs/superpowers/plans/2026-10-30-entrega-3-sonidos.md` al `git add` que da la tarea. Si tienes las skills `superpowers:subagent-driven-development` o `superpowers:executing-plans`, úsalas. Lee `AGENTS.md` antes de empezar.

**Meta:** que el usuario elija desde el menú de la barra el sonido de cada uno de los cuatro eventos del buddy (o lo silencie), con cinco sonidos propios CC0 además de los 14 de macOS.

**Arquitectura:**
- **`BuddyCore`, la lógica pura con tests:**
  - el catálogo de sonidos;
  - qué toca cada evento según lo guardado;
  - el modelo del submenú;
  - qué sonido se corta antes de otro.
- **La app solo cablea:**
  - un `SoundPlayer` que carga cada `NSSound` una vez y lo reinicia si ya sonaba;
  - cuatro llaves de `Defaults`;
  - el submenú "Sonidos";
  - los cuatro sitios que hoy llaman a `NSSound` directo.

**Stack:** Swift 5.9+ con Swift Testing, AppKit (`NSSound`, `NSMenu`), `Defaults` (ya es dependencia), `CryptoKit` solo en los tests y SwiftPM con solo Command Line Tools.

**Spec:** `docs/superpowers/specs/2026-10-30-sonidos-design.md` (aprobada). Este plan parte de `5e3eba1`, en la rama `sonidos`.

## Restricciones globales

- Todas las de `AGENTS.md`: Swift 5.9+, macOS 13+, solo Command Line Tools, **sin dependencias nuevas**, lógica pura en `Sources/BuddyCore/` con `public`, tests con Swift Testing que solo importan `BuddyCore`, siempre `swift build && swift test`, y el repo es público.
- **`Package.swift` no cambia.** El target de la app ya tiene `resources: [.copy("Resources")]`, que copia `Resources/Sounds/` entera al bundle. Se carga con `Bundle.module.url(forResource:withExtension:subdirectory: "Resources/Sounds")`, igual que las fuentes usan `"Resources/Fonts"`.
- **No toques los archivos de `Sources/ClaudeMenuBarBuddy/Resources/Sounds/`** (los cinco `.wav` y `CREDITS.md`). Los puso Claude en la tarea 0, y el test de la tarea 3 compara sus SHA-256.
- **Textos que ve el usuario** (copia exacta):
  - el submenú: `Sonidos`;
  - los eventos: `Tarjeta nueva`, `Turno terminado`, `Clic a la mascota`, `Atajo bloqueado`;
  - los sonidos propios: `Madera`, `Cuerda`, `Gota`, `Clic`, `Bong`;
  - el encabezado de los de macOS: `macOS`;
  - el silencio: `Sin sonido`;
  - la fila de cada evento: `<evento> — <sonido>` (con raya larga `—` y un espacio a cada lado).
- **Ids que se guardan** (no cambian nunca, o se pierde lo que eligió el usuario):
  - los propios: `woodblock`, `pluck`, `drop`, `click`, `bong`;
  - los de macOS: `macos.<Nombre>`;
  - el silencio: `none`.
- **Llaves de `UserDefaults`:** `cardSound`, `turnDoneSound`, `petClickSound` y `blockedSound`.
- **Valores por defecto:**

  | Evento | Sonido |
  |---|---|
  | Tarjeta nueva | `woodblock` |
  | Turno terminado | `macos.Glass` |
  | Clic a la mascota | `click` |
  | Atajo bloqueado | `bong` |

## Puntos de revisión

Estos casos los pide la spec, pero ningún test de la app los ejercita: la app no tiene tests. Claude los revisa en el diff del bloque 2 y en la prueba en vivo.

1. **Dos tarjetas seguidas suenan las dos.**
   - **El problema:** `NSSound(named:)` reusa una sola instancia, y `play()` no hace nada si esa instancia sigue sonando.
   - **Lo que se espera:** `SoundPlayer` hace `stop()` antes de `play()`. Tarea 4.
2. **El sonido de la tarjeta no suena cada vez que cambia la cola.**
   - **Lo que se espera:** `playSound(.cardArrived)` reemplaza al `Ping` en `setPending` (`ApprovalCard.swift`) y en ningún otro lugar. **Nunca en `showStatusBubble`**, porque `poll()` la llama cada vez que la cola crece o se achica. Tarea 4.
3. **⌘⏎ rechazado en una tarjeta crítica:**
   - suena el bong aunque el woodblock de la tarjeta siga sonando, porque `SoundPlayer` corta antes el de la tarjeta (`eventsToStop`, con test en la tarea 1);
   - no depende del volumen de alertas de macOS, porque ya no se usa `NSSound.beep()`. Tarea 4.
4. **Elegir un sonido en el menú se ve de inmediato:**
   - la palomita y la fila "Tarjeta nueva — …" cambian sin esperar a la siguiente tarjeta. `soundChosen` sigue el patrón de `toggleAutoMode`: `buildIdleMenu()` y luego `setIdle()` si no hay tarjeta. **No el de `petSizeChanged`.**
   - elegir el que ya está marcado lo vuelve a tocar. Tarea 5.
5. **El volumen del buddy no se le cuela a nadie más:** `SoundPlayer` toca una **copia** de `NSSound(named:)`, no la instancia compartida. Además, un archivo que falta deja el evento mudo, sin tronar. Tarea 4.

## Bloques de revisión

Al terminar cada bloque, detente y avisa en el chat. Claude revisa antes de que sigas.

| Bloque | Tareas | Qué queda |
|---|---|---|
| 1 | 1, 2 y 3 | Todo `BuddyCore` y la auditoría de los archivos, con tests |
| 2 | 4, 5 y 6 | La app cableada, el README y la verificación final |

Después del bloque 2, Claude hace la prueba en vivo con el usuario.

## Mapa de archivos

**Ya en el repo (tarea 0, hecha por Claude en `5e3eba1`):** `Sources/ClaudeMenuBarBuddy/Resources/Sounds/`, con `woodblock.wav`, `pluck.wav`, `drop.wav`, `click.wav`, `bong.wav` y `CREDITS.md`.

**Nuevos:**

| Archivo | Responsabilidad |
|---|---|
| `Sources/BuddyCore/Sounds.swift` | Los eventos, el catálogo, qué toca cada evento y qué se corta antes |
| `Sources/BuddyCore/SoundMenu.swift` | El modelo del submenú de cada evento |
| `Sources/ClaudeMenuBarBuddy/SoundPlayer.swift` | Cargar, guardar y tocar cada `NSSound` |
| `Tests/ClaudeMenuBarBuddyTests/SoundCatalogTests.swift` | Tests de `Sounds.swift` |
| `Tests/ClaudeMenuBarBuddyTests/SoundMenuTests.swift` | Tests de `SoundMenu.swift` |
| `Tests/ClaudeMenuBarBuddyTests/SoundFilesAuditTests.swift` | Archivos, catálogo y `CREDITS.md` de acuerdo |

**Modificados** (en `Sources/ClaudeMenuBarBuddy/`, salvo el README):
- `Prefs.swift`: las cuatro llaves y sus accesos;
- `main.swift`: la propiedad `soundPlayer`;
- `ApprovalCard.swift`, `Toast.swift`, `MoodEngine.swift` y `CardDecision.swift`: los cuatro sonidos de hoy;
- `Menus.swift`: el submenú "Sonidos";
- `README.md`.

---

### Tarea 1: el catálogo de sonidos

**Archivos:**
- Crear: `Sources/BuddyCore/Sounds.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/SoundCatalogTests.swift`

**Interfaces:**
- Produce (todo `public`):
```swift
public enum SoundEvent: String, CaseIterable, Sendable {
    case cardArrived, turnDone, petClicked, hotKeyBlocked   // en este orden
    public var title: String          // el nombre en el menú
    public var defaultsKey: String    // la llave de UserDefaults
    public var defaultSoundID: String // el id por defecto
}

public enum SoundSource: Equatable, Sendable {
    case bundled(file: String, ext: String)   // un archivo de Resources/Sounds
    case system(name: String)                 // un sonido de macOS, por su nombre de NSSound
}

public struct SoundOption: Equatable, Sendable {
    public let id: String
    public let title: String
    public let source: SoundSource
    public let gain: Float            // 0...1, se aplica como NSSound.volume
    public init(id: String, title: String, source: SoundSource, gain: Float)
}

public enum SoundChoice: Equatable, Sendable {
    case sound(SoundOption)
    case silent
}

public enum SoundCatalog {
    public static let noneID: String                 // "none"
    public static let bundled: [SoundOption]         // los cinco propios, en orden de menú
    public static let systemNames: [String]          // los 14 de macOS, en orden alfabético
    public static let system: [SoundOption]          // systemNames como opciones
    public static let all: [SoundOption]             // bundled + system
    public static func option(id: String) -> SoundOption?
    public static func resolve(stored: String?, for event: SoundEvent) -> SoundChoice
    public static func eventsToStop(before event: SoundEvent) -> [SoundEvent]
}
```

- [ ] **Paso 1: escribir los tests**

Crea `Tests/ClaudeMenuBarBuddyTests/SoundCatalogTests.swift` con exactamente esto:

```swift
import Foundation
import Testing
import BuddyCore

@Suite struct SoundCatalogTests {
    @Test func bundledSoundsInMenuOrder() {
        #expect(SoundCatalog.bundled.map(\.id) == ["woodblock", "pluck", "drop", "click", "bong"])
        #expect(SoundCatalog.bundled.map(\.title) == ["Madera", "Cuerda", "Gota", "Clic", "Bong"])
        #expect(SoundCatalog.bundled.map(\.source) == [
            .bundled(file: "woodblock", ext: "wav"),
            .bundled(file: "pluck", ext: "wav"),
            .bundled(file: "drop", ext: "wav"),
            .bundled(file: "click", ext: "wav"),
            .bundled(file: "bong", ext: "wav"),
        ])
        #expect(SoundCatalog.bundled.map(\.gain) == [1.0, 0.25, 0.28, 0.28, 0.28])
    }

    @Test func systemSoundsAreTheFourteenOfMacOS() {
        #expect(SoundCatalog.system.count == 14)
        #expect(SoundCatalog.system.first == SoundOption(id: "macos.Basso", title: "Basso",
                                                         source: .system(name: "Basso"), gain: 1.0))
        #expect(SoundCatalog.system.last?.id == "macos.Tink")
        #expect(SoundCatalog.system.allSatisfy { $0.gain == 1.0 })
        #expect(SoundCatalog.all == SoundCatalog.bundled + SoundCatalog.system)
    }

    @Test func idsAreUniqueAndNoneIsNotOne() {
        let ids = SoundCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(SoundCatalog.noneID))
        #expect(SoundCatalog.noneID == "none")
    }

    @Test func gainsStayBetweenZeroAndOne() {
        for option in SoundCatalog.all {
            #expect(option.gain > 0 && option.gain <= 1, "\(option.id): \(option.gain)")
        }
    }

    @Test func eventsDefaultsAndKeys() {
        #expect(SoundEvent.allCases == [.cardArrived, .turnDone, .petClicked, .hotKeyBlocked])
        #expect(SoundEvent.allCases.map(\.title)
                == ["Tarjeta nueva", "Turno terminado", "Clic a la mascota", "Atajo bloqueado"])
        #expect(SoundEvent.allCases.map(\.defaultsKey)
                == ["cardSound", "turnDoneSound", "petClickSound", "blockedSound"])
        #expect(SoundEvent.allCases.map(\.defaultSoundID)
                == ["woodblock", "macos.Glass", "click", "bong"])
    }

    @Test func everyDefaultIsInTheCatalog() {
        for event in SoundEvent.allCases {
            #expect(SoundCatalog.option(id: event.defaultSoundID) != nil, "\(event)")
        }
    }

    @Test func optionLookup() {
        #expect(SoundCatalog.option(id: "drop")?.title == "Gota")
        #expect(SoundCatalog.option(id: "macos.Ping")?.source == .system(name: "Ping"))
        #expect(SoundCatalog.option(id: "Ping") == nil)
        #expect(SoundCatalog.option(id: "none") == nil)
    }

    @Test func resolveKnownIDs() {
        let drop = SoundCatalog.option(id: "drop")!
        let ping = SoundCatalog.option(id: "macos.Ping")!
        #expect(SoundCatalog.resolve(stored: "drop", for: .cardArrived) == .sound(drop))
        #expect(SoundCatalog.resolve(stored: "macos.Ping", for: .petClicked) == .sound(ping))
    }

    @Test func resolveNoneIsSilenceForEveryEvent() {
        for event in SoundEvent.allCases {
            #expect(SoundCatalog.resolve(stored: "none", for: event) == .silent)
        }
    }

    @Test func unknownEmptyOrMissingFallsBackToTheDefaultNeverToSilence() {
        let woodblock = SoundCatalog.option(id: "woodblock")!
        let glass = SoundCatalog.option(id: "macos.Glass")!
        for stored in [nil, "", "macos.Nope", "Ping", "NONE", "gota"] as [String?] {
            #expect(SoundCatalog.resolve(stored: stored, for: .cardArrived) == .sound(woodblock),
                    "\(stored ?? "nil")")
            #expect(SoundCatalog.resolve(stored: stored, for: .turnDone) == .sound(glass),
                    "\(stored ?? "nil")")
        }
    }

    @Test func onlyTheBlockedHotKeyCutsTheCardSound() {
        #expect(SoundCatalog.eventsToStop(before: .hotKeyBlocked) == [.cardArrived])
        #expect(SoundCatalog.eventsToStop(before: .cardArrived).isEmpty)
        #expect(SoundCatalog.eventsToStop(before: .turnDone).isEmpty)
        #expect(SoundCatalog.eventsToStop(before: .petClicked).isEmpty)
    }
}
```

- [ ] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter SoundCatalogTests`
Esperado: no compila (no existe `SoundCatalog`).

- [ ] **Paso 3: implementar `Sources/BuddyCore/Sounds.swift`**

Las firmas son las de Interfaces. Los valores, exactos:

- **`SoundEvent`:**

  | Caso | `title` | `defaultsKey` | `defaultSoundID` |
  |---|---|---|---|
  | `cardArrived` | `Tarjeta nueva` | `cardSound` | `woodblock` |
  | `turnDone` | `Turno terminado` | `turnDoneSound` | `macos.Glass` |
  | `petClicked` | `Clic a la mascota` | `petClickSound` | `click` |
  | `hotKeyBlocked` | `Atajo bloqueado` | `blockedSound` | `bong` |

- **`SoundCatalog.bundled`,** en este orden; todos `.bundled(file: <id>, ext: "wav")`:

  | id | title | gain |
  |---|---|---|
  | `woodblock` | `Madera` | 1.0 |
  | `pluck` | `Cuerda` | 0.25 |
  | `drop` | `Gota` | 0.28 |
  | `click` | `Clic` | 0.28 |
  | `bong` | `Bong` | 0.28 |

- **`systemNames`:** `Basso`, `Blow`, `Bottle`, `Frog`, `Funk`, `Glass`, `Hero`, `Morse`, `Ping`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`.
- **`system`:** cada nombre como `SoundOption(id: "macos.<nombre>", title: <nombre>, source: .system(name: <nombre>), gain: 1.0)`.
- **`resolve`:**
  1. `"none"` → `.silent`;
  2. un id del catálogo → `.sound(esa opción)`;
  3. cualquier otra cosa, incluidos `nil` y `""` → `.sound(la opción de event.defaultSoundID)`. **Nunca `.silent`.**
- **`eventsToStop`:** `.hotKeyBlocked` → `[.cardArrived]`; los demás → `[]`.
- **Comentarios de documentación:**
  - en `defaultsKey`, que una llave no se renombra nunca, o lo que eligió el usuario se pierde y vuelve el valor por defecto;
  - en `eventsToStop`, que el atajo bloqueado corta el de la tarjeta porque si no, lo tapa (spec §9).

- [ ] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter SoundCatalogTests`
Esperado: PASA (11 tests).

- [ ] **Paso 5: commit**

```bash
git add Sources/BuddyCore/Sounds.swift Tests/ClaudeMenuBarBuddyTests/SoundCatalogTests.swift
git commit -m "BuddyCore sabe qué sonidos hay y cuál toca cada evento"
```

---

### Tarea 2: el modelo del submenú

**Archivos:**
- Crear: `Sources/BuddyCore/SoundMenu.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/SoundMenuTests.swift`

**Interfaces:**
- Consume: `SoundEvent`, `SoundCatalog` y `SoundChoice` de la tarea 1.
- Produce:
```swift
public enum SoundMenuRow: Equatable, Sendable {
    case option(id: String, title: String, checked: Bool)
    case header(String)
    case separator
}

public enum SoundMenu {
    /// "Tarjeta nueva — Madera"; "… — Sin sonido" for silence.
    public static func rowTitle(for event: SoundEvent, stored: String?) -> String
    /// One event's submenu rows. `systemAvailable` gets a macOS sound's name ("Glass").
    public static func rows(for event: SoundEvent, stored: String?,
                            systemAvailable: (String) -> Bool) -> [SoundMenuRow]
}
```

- [ ] **Paso 1: escribir los tests**

Crea `Tests/ClaudeMenuBarBuddyTests/SoundMenuTests.swift` con exactamente esto:

```swift
import Foundation
import Testing
import BuddyCore

@Suite struct SoundMenuTests {
    private let onlyGlassAndTink: (String) -> Bool = { $0 == "Glass" || $0 == "Tink" }

    @Test func rowTitleNamesTheCurrentSound() {
        #expect(SoundMenu.rowTitle(for: .cardArrived, stored: nil) == "Tarjeta nueva — Madera")
        #expect(SoundMenu.rowTitle(for: .turnDone, stored: nil) == "Turno terminado — Glass")
        #expect(SoundMenu.rowTitle(for: .petClicked, stored: "drop") == "Clic a la mascota — Gota")
        #expect(SoundMenu.rowTitle(for: .hotKeyBlocked, stored: "none") == "Atajo bloqueado — Sin sonido")
        #expect(SoundMenu.rowTitle(for: .hotKeyBlocked, stored: "borrado") == "Atajo bloqueado — Bong")
    }

    @Test func rowsBundledThenMacOSThenSilence() {
        let rows = SoundMenu.rows(for: .cardArrived, stored: "drop", systemAvailable: onlyGlassAndTink)
        #expect(rows == [
            .option(id: "woodblock", title: "Madera", checked: false),
            .option(id: "pluck", title: "Cuerda", checked: false),
            .option(id: "drop", title: "Gota", checked: true),
            .option(id: "click", title: "Clic", checked: false),
            .option(id: "bong", title: "Bong", checked: false),
            .separator,
            .header("macOS"),
            .option(id: "macos.Glass", title: "Glass", checked: false),
            .option(id: "macos.Tink", title: "Tink", checked: false),
            .separator,
            .option(id: "none", title: "Sin sonido", checked: false),
        ])
    }

    @Test func allFourteenMacOSSoundsWhenTheMacHasThem() {
        let rows = SoundMenu.rows(for: .turnDone, stored: nil, systemAvailable: { _ in true })
        #expect(rows.count == 5 + 2 + 14 + 2)
        #expect(rows.filter { if case .option(_, _, true) = $0 { return true }; return false }
                == [.option(id: "macos.Glass", title: "Glass", checked: true)])
    }

    @Test func noMacOSSectionWhenNoneAreAvailable() {
        let rows = SoundMenu.rows(for: .petClicked, stored: nil, systemAvailable: { _ in false })
        #expect(rows == [
            .option(id: "woodblock", title: "Madera", checked: false),
            .option(id: "pluck", title: "Cuerda", checked: false),
            .option(id: "drop", title: "Gota", checked: false),
            .option(id: "click", title: "Clic", checked: true),
            .option(id: "bong", title: "Bong", checked: false),
            .separator,
            .option(id: "none", title: "Sin sonido", checked: false),
        ])
    }

    @Test func silenceIsCheckedWhenChosen() {
        let rows = SoundMenu.rows(for: .hotKeyBlocked, stored: "none", systemAvailable: onlyGlassAndTink)
        #expect(rows.last == .option(id: "none", title: "Sin sonido", checked: true))
        #expect(rows.dropLast().allSatisfy { if case .option(_, _, true) = $0 { return false }; return true })
    }

    @Test func unknownStoredValueChecksTheDefault() {
        let rows = SoundMenu.rows(for: .hotKeyBlocked, stored: "retirado", systemAvailable: onlyGlassAndTink)
        #expect(rows.contains(.option(id: "bong", title: "Bong", checked: true)))
        #expect(rows.last == .option(id: "none", title: "Sin sonido", checked: false))
    }
}
```

- [ ] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter SoundMenuTests`
Esperado: no compila (no existe `SoundMenu`).

- [ ] **Paso 3: implementar `Sources/BuddyCore/SoundMenu.swift`**

- **`rowTitle`:** según `SoundCatalog.resolve(stored:for:)`, `"\(event.title) — \(option.title)"` o `"\(event.title) — Sin sonido"`.
- **`rows`, en este orden:**
  1. una `.option` por cada sonido de `SoundCatalog.bundled`;
  2. si al menos uno de `SoundCatalog.system` pasa `systemAvailable(nombre)`: `.separator`, `.header("macOS")` y una `.option` por cada uno que pasa, en el orden del catálogo. Si ninguno pasa, este bloque no aparece;
  3. `.separator` y `.option(id: "none", title: "Sin sonido", …)`.
- **La palomita (`checked`)** va en la fila cuyo id es lo que devuelve `resolve`: el id de la opción, o `"none"` si es `.silent`. Así, un valor guardado desconocido marca el sonido por defecto.

- [ ] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter SoundMenuTests`
Esperado: PASA (6 tests).

- [ ] **Paso 5: commit**

```bash
git add Sources/BuddyCore/SoundMenu.swift Tests/ClaudeMenuBarBuddyTests/SoundMenuTests.swift
git commit -m "BuddyCore arma el submenú de sonidos de cada evento"
```

---

### Tarea 3: la auditoría de los archivos de sonido

El repo es público: cada sonido necesita su fuente y su licencia comprobables. Este test lee la carpeta `Resources/Sounds` del repo vía `#filePath`, como `MoodPolicyTests` hace con los GIFs. Falla si un archivo, el catálogo y `CREDITS.md` dejan de coincidir.

**Archivos:**
- Test: `Tests/ClaudeMenuBarBuddyTests/SoundFilesAuditTests.swift`

**Interfaces:**
- Consume: `SoundCatalog.bundled` y `SoundSource` de la tarea 1, y los archivos de la tarea 0.
- Produce: nada; es solo un test.

- [ ] **Paso 1: escribir el test**

Crea `Tests/ClaudeMenuBarBuddyTests/SoundFilesAuditTests.swift` con exactamente esto:

```swift
import CryptoKit
import Foundation
import Testing
import BuddyCore

// The repo is public, so every sound it ships needs a checkable source and a
// free license. This audit reads the checked-in Resources/Sounds via
// #filePath (like MoodPolicyTests does for the GIFs) and fails the moment a
// file, the catalog and CREDITS.md drift apart.
@Suite struct SoundFilesAuditTests {
    private static let soundsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ClaudeMenuBarBuddyTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/ClaudeMenuBarBuddy/Resources/Sounds")

    private static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "ogg", "oga", "flac"]

    private func catalogFiles() -> Set<String> {
        Set(SoundCatalog.bundled.compactMap { option in
            if case .bundled(let file, let ext) = option.source { return "\(file).\(ext)" }
            return nil
        })
    }

    private func audioFilesOnDisk() throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.soundsDir.path)
        return Set(names.filter { Self.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) })
    }

    /// CREDITS.md: a "## <file>" line opens each file's section; its
    /// "- key: value" lines follow.
    private func credits() throws -> [String: [String: String]] {
        let text = try String(contentsOf: Self.soundsDir.appendingPathComponent("CREDITS.md"), encoding: .utf8)
        var sections: [String: [String: String]] = [:]
        var current: String?
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                let name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                sections[name] = [:]
                current = name
            } else if let name = current, line.hasPrefix("- "), let colon = line.firstIndex(of: ":") {
                let key = line[line.index(line.startIndex, offsetBy: 2)..<colon]
                    .trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                sections[name]?[key] = value
            }
        }
        return sections
    }

    @Test func everyBundledSoundHasItsFile() throws {
        let onDisk = try audioFilesOnDisk()
        for name in catalogFiles() {
            #expect(onDisk.contains(name), "falta \(name) en Resources/Sounds")
        }
    }

    @Test func everyFileOnDiskIsInTheCatalogAndNoneIsOgg() throws {
        let catalog = catalogFiles()
        for name in try audioFilesOnDisk() {
            #expect(catalog.contains(name), "\(name) no está en SoundCatalog.bundled")
            let ext = (name as NSString).pathExtension.lowercased()
            #expect(ext != "ogg" && ext != "oga", "\(name): macOS no reproduce OGG")
        }
    }

    @Test func everyFileHasItsCreditsWithAFreeLicense() throws {
        let credits = try credits()
        let onDisk = try audioFilesOnDisk()
        for name in onDisk {
            let entry = try #require(credits[name], "\(name) no tiene sección en CREDITS.md")
            let license = entry["licencia"] ?? ""
            #expect(license.contains("CC0") || license.lowercased().contains("dominio público"),
                    "\(name): licencia \"\(license)\"")
            #expect((entry["descarga"] ?? "").hasPrefix("https://"), "\(name): sin URL de descarga")
            #expect((entry["sha256 original"] ?? "").count == 64, "\(name): sin sha256 original")
        }
        for name in credits.keys {
            #expect(onDisk.contains(name), "CREDITS.md habla de \(name), que no existe")
        }
    }

    @Test func checksumsMatchCredits() throws {
        let credits = try credits()
        for name in try audioFilesOnDisk() {
            let data = try Data(contentsOf: Self.soundsDir.appendingPathComponent(name))
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(credits[name]?["sha256 en el repo"] == hash,
                    "\(name) no coincide con su sha256 de CREDITS.md")
        }
    }
}
```

- [ ] **Paso 2: verificar que pasa**

Corre: `swift build && swift test --filter SoundFilesAuditTests`
Esperado: PASA (4 tests) **a la primera**. Este test no lleva código nuevo: vigila los archivos que ya puso la tarea 0 y el catálogo de la tarea 1.

Si falla, **no toques los archivos de sonido ni `CREDITS.md`**. Anota el mensaje del fallo en `NOTAS-EJECUCION.md` y detente.

- [ ] **Paso 3: correr todo**

Corre: `swift build && swift test`
Esperado: todo en verde, 246 tests (225 + 11 + 6 + 4).

- [ ] **Paso 4: commit**

```bash
git add Tests/ClaudeMenuBarBuddyTests/SoundFilesAuditTests.swift
git commit -m "Los tests vigilan que cada sonido tenga su archivo, su licencia y su sha256"
```

**Fin del bloque 1.** Detente y avisa en el chat.

---

### Tarea 4: el reproductor y los cuatro sonidos de hoy

**Archivos:**
- Crear: `Sources/ClaudeMenuBarBuddy/SoundPlayer.swift`
- Modificar (en `Sources/ClaudeMenuBarBuddy/`): `Prefs.swift`, `main.swift`, `ApprovalCard.swift`, `Toast.swift`, `MoodEngine.swift` y `CardDecision.swift`

**Interfaces:**
- Consume: `SoundEvent`, `SoundOption`, `SoundSource` y `SoundCatalog` de la tarea 1.
- Produce:
```swift
// SoundPlayer.swift
final class SoundPlayer {
    func play(_ event: SoundEvent, stored: String?)
    func preview(_ option: SoundOption)
    static func systemSoundExists(_ name: String) -> Bool
}
// AppDelegate
let soundPlayer: SoundPlayer                               // main.swift
func storedSoundID(for event: SoundEvent) -> String         // Prefs.swift
func setStoredSoundID(_ id: String, for event: SoundEvent)  // Prefs.swift
func playSound(_ event: SoundEvent)                          // Prefs.swift
```

La app no tiene tests. La verificación es que compile y que todo siga en verde; lo demás lo ve Claude en el diff y en la prueba en vivo (puntos de revisión 1, 2, 3 y 5).

- [ ] **Paso 1: crear `SoundPlayer.swift`**

```swift
import AppKit
import BuddyCore
```

- **Guarda dos diccionarios privados:** `[String: NSSound]` por id de opción (lo cargado) y `[SoundEvent: NSSound]` (lo último que tocó cada evento).
- **`play(_:stored:)`:**
  1. para cada evento de `SoundCatalog.eventsToStop(before: event)`, `stop()` a lo último que tocó ese evento;
  2. si `SoundCatalog.resolve(stored:for:)` es `.silent`, o el sonido no carga, no hace nada más;
  3. si no, lo toca (abajo) y lo guarda como lo último de `event`.
- **`preview(_:)`:** carga y toca la opción, sin tocar lo último de ningún evento.
- **Tocar:** `stop()`, luego `volume = option.gain` y luego `play()`. Con un comentario: `play()` sobre un sonido que sigue sonando no hace nada, y por eso la segunda tarjeta seguida llegaba muda.
- **Cargar:** la primera vez que se pide un id, y luego se guarda.
  - `.bundled(file, ext)` → `Bundle.module.url(forResource: file, withExtension: ext, subdirectory: "Resources/Sounds")` y `NSSound(contentsOf: url, byReference: true)`.
  - `.system(name)` → `NSSound(named: name)?.copy() as? NSSound`. Con un comentario: `NSSound(named:)` le da a todos la misma instancia compartida, y el volumen del buddy se le colaría.
  - Si no carga (`nil`), no se guarda y no truena.
- **`systemSoundExists(_:)`:** `FileManager.default.fileExists(atPath: "/System/Library/Sounds/\(name).aiff")`. Con un comentario: se revisa en disco para que armar el menú no cargue los 14.
- **Comentario de la clase:** cada `NSSound` se carga la primera vez que suena y se guarda, así que en reposo no cuesta nada.

- [ ] **Paso 2: las llaves y los accesos en `Prefs.swift`**

En `extension Defaults.Keys`, después de `cardPalette`:

```swift
    // The sound chosen for each SoundEvent, by SoundCatalog id ("none" is
    // silence). Resolved on read (SoundCatalog.resolve), so an id left
    // behind by a retired sound plays the default instead of nothing.
    static let cardSound = Key<String>(SoundEvent.cardArrived.defaultsKey, default: SoundEvent.cardArrived.defaultSoundID)
    static let turnDoneSound = Key<String>(SoundEvent.turnDone.defaultsKey, default: SoundEvent.turnDone.defaultSoundID)
    static let petClickSound = Key<String>(SoundEvent.petClicked.defaultsKey, default: SoundEvent.petClicked.defaultSoundID)
    static let blockedSound = Key<String>(SoundEvent.hotKeyBlocked.defaultsKey, default: SoundEvent.hotKeyBlocked.defaultSoundID)
```

En `extension AppDelegate`, después de `var cardPalette`:
- `storedSoundID(for:)` y `setStoredSoundID(_:for:)` leen y escriben `Defaults[soundKey(for: event)]`.
- `private func soundKey(for event: SoundEvent) -> Defaults.Key<String>` es un `switch` que devuelve `.cardSound`, `.turnDoneSound`, `.petClickSound` o `.blockedSound`.
- `playSound(_:)` llama a `soundPlayer.play(event, stored: storedSoundID(for: event))`. Lleva el comentario `/// Plays the event's sound. The one way the app makes a sound.`

- [ ] **Paso 3: la propiedad en `main.swift`**

En `AppDelegate`, justo después de `var switchingCardByHand = false`:

```swift
    // Every sound the buddy makes goes through here (SoundPlayer.swift).
    let soundPlayer = SoundPlayer()
```

- [ ] **Paso 4: los cuatro sonidos de hoy**

Cambia cada línea, en el mismo lugar donde está, y nada más:

| Archivo | Hoy | Queda |
|---|---|---|
| `ApprovalCard.swift`, en `setPending`, dentro del `else` de `if switchingCardByHand` | `NSSound(named: "Ping")?.play()` | `playSound(.cardArrived)` |
| `Toast.swift`, en `processDoneMarkers` | `NSSound(named: "Glass")?.play()` | `playSound(.turnDone)` |
| `MoodEngine.swift`, en `petClicked` | `NSSound(named: "Tink")?.play()` | `playSound(.petClicked)` |
| `CardDecision.swift`, en `decideViaHotKey` | `NSSound.beep()` | `playSound(.hotKeyBlocked)` |

En `CardDecision.swift`, el comentario `///` que está justo encima de `func shakeCard()` menciona el beep en dos lugares. La primera frase está partida entre dos líneas del comentario:
- «The beep alone was easy to miss — with alert sounds off» queda «The sound alone was easy to miss — with it silenced»;
- «where the beep has to carry it» queda «where the sound has to carry it».

- [ ] **Paso 5: verificar**

Corre: `swift build && swift test`
Esperado: compila sin errores y todo en verde (246 tests).

Corre: `grep -rn "NSSound" Sources/ClaudeMenuBarBuddy | grep -v SoundPlayer.swift`
Esperado: no imprime nada. Solo `SoundPlayer.swift` usa `NSSound`.

- [ ] **Paso 6: commit**

```bash
git add Sources/ClaudeMenuBarBuddy/SoundPlayer.swift Sources/ClaudeMenuBarBuddy/Prefs.swift Sources/ClaudeMenuBarBuddy/main.swift Sources/ClaudeMenuBarBuddy/ApprovalCard.swift Sources/ClaudeMenuBarBuddy/Toast.swift Sources/ClaudeMenuBarBuddy/MoodEngine.swift Sources/ClaudeMenuBarBuddy/CardDecision.swift
git commit -m "Los cuatro sonidos salen del catálogo, y el atajo bloqueado ya no depende de las alertas de macOS"
```

---

### Tarea 5: el submenú "Sonidos"

**Archivos:**
- Modificar: `Sources/ClaudeMenuBarBuddy/Menus.swift`

**Interfaces:**
- Consume:
  - de la tarea 2: `SoundMenu.rows(for:stored:systemAvailable:)`, `SoundMenu.rowTitle(for:stored:)` y `SoundMenuRow`;
  - de la tarea 1: `SoundCatalog.option(id:)` y `SoundEvent(rawValue:)`;
  - de la tarea 4: `storedSoundID(for:)`, `setStoredSoundID(_:for:)`, `soundPlayer.preview(_:)` y `SoundPlayer.systemSoundExists`.
- Produce (en `extension AppDelegate`):
```swift
func soundsMenuItem() -> NSMenuItem
@objc func soundChosen(_ sender: NSMenuItem)
```

- [ ] **Paso 1: implementar `soundsMenuItem()`**

Va en `Menus.swift`, justo antes de `toggleAutoMode`.

- Un `NSMenuItem` titulado `Sonidos`, sin acción, con un submenú. Ese submenú lleva una fila por cada `SoundEvent.allCases`, en orden.
- **Cada fila de evento:** título `SoundMenu.rowTitle(for: event, stored: storedSoundID(for: event))`, sin acción, con su propio submenú armado con `SoundMenu.rows(for: event, stored: storedSoundID(for: event), systemAvailable: SoundPlayer.systemSoundExists)`:

  | Fila del modelo | Elemento del menú |
  |---|---|
  | `.separator` | `NSMenuItem.separator()` |
  | `.header(text)` | `NSMenuItem(title: text, action: nil, keyEquivalent: "")`, con `isEnabled = false` |
  | `.option(id, title, checked)` | `NSMenuItem(title: title, action: #selector(soundChosen(_:)), keyEquivalent: "")`, con `target = self`, `representedObject = [event.rawValue, id]` (un `[String]`) y `state = checked ? .on : .off` |

- Comentario de la función: el orden, la palomita y los títulos salen de `SoundMenu` (`BuddyCore`).

- [ ] **Paso 2: implementar `soundChosen(_:)`**

1. Saca `[String]` de `sender.representedObject`, con dos elementos, y `SoundEvent(rawValue:)` del primero. Si algo falla, `return`.
2. `setStoredSoundID(id, for: event)`.
3. Si `SoundCatalog.option(id: id)` existe, `soundPlayer.preview(option)`. Con `"none"` no suena nada. **Sin `return` temprano cuando el id es el mismo que ya estaba:** elegirlo otra vez es para volver a oírlo.
4. `buildIdleMenu()` y luego `if currentRequestId == nil { setIdle(); updatePetMood() }`, igual que `toggleAutoMode`. Con un comentario: solo `setIdle()` le pasa el menú nuevo a `statusItem.menu`, así que la palomita se vería tarde con el patrón de `petSizeChanged`.

- [ ] **Paso 3: ponerlo en el menú**

En `buildIdleMenu()`, justo antes de la línea `let autoModeItem = NSMenuItem(title: "Modo auto", …`:

```swift
        menu.addItem(soundsMenuItem())
```

- [ ] **Paso 4: verificar**

Corre: `swift build && swift test`
Esperado: compila sin errores y todo en verde (246 tests).

- [ ] **Paso 5: commit**

```bash
git add Sources/ClaudeMenuBarBuddy/Menus.swift
git commit -m "El menú de la barra deja elegir o silenciar el sonido de cada evento"
```

---

### Tarea 6: README y verificación final

**Archivos:**
- Modificar: `README.md`

- [ ] **Paso 1: el README**

- **En el árbol de archivos,** después de la línea de `Resources/Fonts/`, agrega con la misma alineación:
  `  Resources/Sounds/           # CC0 sounds + CREDITS.md (source, license, sha256)`
- **En la misma lista,** `# hook fixtures, burn-rate shapes, art audit` queda `# hook fixtures, burn-rate shapes, art and sound audits`.
- **En "## License",** después del párrafo de las fuentes (el que empieza con "The card is set in"), agrega este párrafo, separado por una línea en blanco (texto exacto):

```markdown
The sounds in `Resources/Sounds/` are CC0: four from Kenney's [Interface Sounds](https://kenney.nl/assets/interface-sounds) and a woodblock from Versilian Studios' [VCSL](https://github.com/sgossner/VCSL), louder than the original. `CREDITS.md` beside them gives each file's download URL, license and SHA-256, and `SoundFilesAuditTests` keeps it honest. The other sounds in the Sonidos menu are the ones macOS ships; they are played from the system, not bundled.
```

- [ ] **Paso 2: verificación final**

Corre: `swift build && swift test`
Esperado: todo en verde, 246 tests.

Corre: `shellcheck hook.sh notify-done.sh`
Esperado: sin avisos. Esta entrega no los toca, pero se revisa igual.

Corre: `git status --short`
Esperado: solo `README.md` y el plan modificados.

- [ ] **Paso 3: commit**

```bash
git add README.md
git commit -m "El README da los créditos de los sonidos"
```

**Fin del bloque 2.** Detente y avisa en el chat con un resumen: qué hiciste en cada tarea, la cuenta de tests y cualquier nota que hayas escrito en `NOTAS-EJECUCION.md`.
