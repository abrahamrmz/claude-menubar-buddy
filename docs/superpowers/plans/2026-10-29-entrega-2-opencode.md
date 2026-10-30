# Entrega 2: opencode — plan de implementación

> **Para agentes:** ejecuta este plan tarea por tarea, en orden, marcando cada checkbox (`- [ ]` → `- [x]`) al terminar el paso. Si tienes las skills `superpowers:subagent-driven-development` o `superpowers:executing-plans`, úsalas. Lee `AGENTS.md` antes de empezar.

**Meta:** que las solicitudes de permiso, las preguntas y los turnos terminados de opencode pasen por el buddy, con la misma regla y el mismo modo auto que Claude Code.

**Arquitectura:** un puente dentro de la app se conecta al servicio local de opencode (eventos por SSE, respuestas por HTTP). Reusa el protocolo de archivos que la app ya entiende:
- **Tarjetas:** escribe `request_<id>.json` igual que el hook, y la cola, la tarjeta, el historial y los atajos funcionan como con Claude.
- **Respuestas:** salen por HTTP en lugar de un archivo `response_`.
- **Turno terminado:** escribe `done_<sesión>.json` y el aviso existente lo toma.

Casi toda la lógica nueva es pura y vive en `BuddyCore`, con tests: el lector de SSE, los eventos, la regla aplicada a opencode, el diff, el estado del puente, la API y la revisión de configuración. La app solo agrega la conexión y unos pocos cambios de interfaz.

**Stack:** Swift 5.9+ con Swift Testing, AppKit, `URLSession` (con delegado) y SwiftPM con solo Command Line Tools.

**Spec:** `docs/superpowers/specs/2026-10-21-modo-auto-y-opencode-design.md`, sección 8, con lo que la API verificada dice en 8.1. La entrega 1 ya está en `personal` (`96f1397`); este plan parte de ahí, en la rama `opencode-entrega-2`.

## Restricciones globales

- Todas las de la entrega 1 siguen vigentes (ver `AGENTS.md`): Swift 5.9+, macOS 13+, solo Command Line Tools, sin dependencias nuevas, lógica pura en `Sources/BuddyCore/`, tests con Swift Testing, `shellcheck` limpio, siempre `swift build && swift test`, repo público.
- **opencode verificado:** 2.1.2. Descubrimiento en `~/.local/state/opencode/service.json` → `{id, version, url, pid, password}`. Autenticación `Basic opencode:<password>`.
- **Solo loopback:** el puente solo se conecta si la URL de `service.json` es `http` con host `127.0.0.1`, `localhost` o `::1`. Cualquier otra cosa es "no disponible".
- **La contraseña y el encabezado `Authorization` nunca van a `DebugLog`** ni a ningún otro log o archivo.
- **Endpoints** (copia exacta de lo verificado):
  - `GET /api/event` — SSE con líneas `data: {json}`, latidos `: heartbeat`;
  - `GET /api/session?limit=N&order=desc` — sesiones de todas las carpetas, con `location.directory`, `parentID` y `time.updated`;
  - `GET /api/session/{sid}` — `{data: Session.Info}`;
  - `GET /api/session/{sid}/permission` y `GET /api/session/{sid}/form` — pendientes de esa sesión, `{data: [...]}`;
  - `GET /api/session/{sid}/permission/{rid}` — 200 si sigue pendiente;
  - `POST /api/session/{sid}/permission/{rid}/reply` con `{"decision":"once"|"reject","message":"…"}` → 204;
  - `POST /api/session/{sid}/form/{fid}/reply` con `{"answer":{"q0":"Rojo"}}` → 204.
- **El puente siempre responde `once` o `reject`, nunca `always`:** la lista "siempre permitir" es la del buddy (spec, decisión).
- **`reject` siempre lleva `message`:** sin mensaje, opencode rechaza también las demás solicitudes de esa sesión.
- **Sin límite de tiempo:** las solicitudes de opencode no tienen la ventana de 60 s de Claude; esperan hasta que alguien conteste, aquí o en la terminal de opencode.
- **Textos que ve el usuario** (copia exacta):
  - motivo de rechazo por defecto: `El usuario lo rechazó desde el buddy.`;
  - etiqueta de la tarjeta: `opencode · <proyecto>`;
  - título del aviso de turno: `opencode — <proyecto>`.

## Puntos de revisión

1. **opencode se reinicia o se corta el stream:** el puente se reconecta, recupera lo pendiente y **no duplica tarjetas** (mismo id = misma tarjeta). Test en la tarea 5.
2. **Se contesta en la terminal de opencode antes que en la tarjeta:** la tarjeta se retira sola. Si la respuesta del buddy llega tarde (404), se ignora. Tests en las tareas 5 y 6.
3. **`service.json` falta, está corrupto o apunta fuera de la máquina:** el puente se queda inactivo, sin conectarse a nada. Test en la tarea 6.
4. **Eventos desconocidos, mal formados o con campos faltantes:** se ignoran sin tumbar la app. Test en la tarea 2.
5. **El stream llega cortado en cualquier punto,** incluso a la mitad de una letra con acento, con `\r\n` o con latidos intercalados: cada evento sale entero. Test en la tarea 1.

## Mapa de archivos

**Nuevos, en `Sources/BuddyCore/OpenCode/`:**

| Archivo | Responsabilidad |
|---|---|
| `SSEParser.swift` | Bytes del stream → cuerpos `data` de cada evento |
| `OpenCodeEvent.swift` | Los eventos que usa el puente, decodificados |
| `OpenCodeRule.swift` | Una solicitud de opencode → sujetos de la regla → evaluación |
| `UnifiedDiff.swift` | El diff de opencode → el mini-diff de la tarjeta |
| `OpenCodeBridgeCore.swift` | El estado del puente: eventos → acciones (responder solo, mostrar tarjeta, retirarla, avisar turno) |
| `OpenCodeAPI.swift` | `service.json`, las llamadas HTTP y qué significa cada respuesta de la tarjeta |
| `OpenCodeConfigCheck.swift` | Si la configuración de opencode pregunta por `shell` y `edit` |

**Nuevo en la app:** `Sources/ClaudeMenuBarBuddy/OpenCodeBridge.swift`, la conexión, que ejecuta las acciones.

**Modificados:**
- `Sources/BuddyCore/Rule/RuleTypes.swift` y `Sources/BuddyCore/Rule/CommandRule.swift`: sujeto `.fileRead`.
- `Sources/ClaudeMenuBarBuddy/`:
  - `main.swift`: arranque del puente, barrido y ventana de 60 s;
  - `CardDecision.swift`: `writeDecision` y la ventana en `respond`;
  - `ApprovalCard.swift`: etiqueta;
  - `CardLayout.swift`: íconos;
  - `Toast.swift`: título;
  - `Health.swift`: dos chequeos.
- `README.md`.

**Tests nuevos** (en `Tests/ClaudeMenuBarBuddyTests/`):
- `SSEParserTests.swift`
- `OpenCodeEventTests.swift`
- `OpenCodeRuleTests.swift`
- `UnifiedDiffTests.swift`
- `OpenCodeBridgeCoreTests.swift`
- `OpenCodeAPITests.swift`
- `OpenCodeConfigCheckTests.swift`
- `Support/OpenCodeFixtures.swift`

---

### Tarea 1: lector de SSE

**Archivos:**
- Crear: `Sources/BuddyCore/OpenCode/SSEParser.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/SSEParserTests.swift`

**Interfaces:**
- Produce:
```swift
public struct SSEParser {
    public init()
    /// Feeds bytes as they arrive; returns the `data` payload of every event this chunk completed.
    public mutating func feed(_ chunk: Data) -> [String]
}
```

- [x] **Paso 1: escribir los tests**

```swift
import Foundation
import Testing
import BuddyCore

@Suite struct SSEParserTests {
    private func feed(_ parts: [String]) -> [String] {
        var p = SSEParser()
        return parts.flatMap { p.feed(Data($0.utf8)) }
    }

    @Test func oneEvent() {
        #expect(feed(["data: {\"a\":1}\n\n"]) == ["{\"a\":1}"])
    }

    @Test func twoEventsInOneChunk() {
        #expect(feed(["data: 1\n\ndata: 2\n\n"]) == ["1", "2"])
    }

    @Test func eventSplitAcrossChunks() {
        #expect(feed(["da", "ta: {\"x\":", "true}\n", "\n"]) == ["{\"x\":true}"])
    }

    @Test func splitInsideAMultibyteCharacter() {
        let bytes = Array("data: adiós\n\n".utf8)
        let cut = bytes.firstIndex(of: 0xC3)! + 1          // between the two bytes of "ó"
        var p = SSEParser()
        var out = p.feed(Data(bytes[..<cut]))
        out += p.feed(Data(bytes[cut...]))
        #expect(out == ["adiós"])
    }

    @Test func heartbeatsAndOtherFieldsAreIgnored() {
        #expect(feed([": heartbeat\n\nevent: x\nid: 7\ndata: ok\n\n: heartbeat\n\n"]) == ["ok"])
    }

    @Test func crlfAndNoSpaceAfterColon() {
        #expect(feed(["data:sin-espacio\r\n\r\n"]) == ["sin-espacio"])
    }

    @Test func multiLineDataIsJoinedWithNewline() {
        #expect(feed(["data: a\ndata: b\n\n"]) == ["a\nb"])
    }

    @Test func incompleteEventIsHeldBack() {
        var p = SSEParser()
        #expect(p.feed(Data("data: a\n".utf8)).isEmpty)
        #expect(p.feed(Data("\n".utf8)) == ["a"])
    }
}
```

- [x] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter SSEParserTests`
Esperado: no compila.

- [x] **Paso 3: implementar `SSEParser`**

- Guarda **bytes** pendientes, no texto. Solo convierte a `String` (UTF-8) una línea completa, cuando aparece `\n`; así una letra partida entre dos trozos nunca se rompe.
- Quita un `\r` final de cada línea.
- **Línea vacía:** si hay datos acumulados, emite el evento (las líneas de datos unidas con `\n`) y limpia.
- **Línea que empieza con `:`** (comentario o latido): se ignora.
- **`data:` con o sin un espacio después:** agrega lo que sigue a los datos del evento.
- **Cualquier otro campo** (`event:`, `id:`, `retry:`): se ignora.

- [x] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter SSEParserTests`
Esperado: PASA.

- [x] **Paso 5: commit**

```bash
git add Sources/BuddyCore/OpenCode/SSEParser.swift Tests/ClaudeMenuBarBuddyTests/SSEParserTests.swift
git commit -m "BuddyCore lee el stream de eventos de opencode aunque llegue partido"
```

---

### Tarea 2: los eventos de opencode

**Archivos:**
- Crear: `Sources/BuddyCore/OpenCode/OpenCodeEvent.swift`
- Crear: `Tests/ClaudeMenuBarBuddyTests/Support/OpenCodeFixtures.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/OpenCodeEventTests.swift`

**Interfaces:**
- Produce:
```swift
public struct OpenCodePermissionRequest: Equatable {
    public let id: String                 // "per_…"
    public let sessionID: String
    public let action: String             // "shell", "edit", "read", "webfetch", …
    public let resources: [String]
    public let editedFiles: [String]      // metadata.files[].file, in order
    public let patches: [String]          // metadata.files[].patch, same order
    public let callID: String?            // source.id
    public init(id: String, sessionID: String, action: String, resources: [String],
                editedFiles: [String] = [], patches: [String] = [], callID: String? = nil)
}
public struct OpenCodeFormOption: Equatable {
    public let value: String
    public let label: String
    public let description: String?
    public init(value: String, label: String, description: String? = nil)
}
public struct OpenCodeFormField: Equatable {
    public let key: String
    public let title: String?
    public let description: String?
    public let type: String               // "string", "multiselect", …
    public let options: [OpenCodeFormOption]
    public init(key: String, title: String?, description: String?, type: String, options: [OpenCodeFormOption])
}
public struct OpenCodeForm: Equatable {
    public let id: String                 // "frm_…"
    public let sessionID: String
    public let title: String
    public let kind: String?              // metadata.kind — "question" for the question tool
    public let fields: [OpenCodeFormField]
    public init(id: String, sessionID: String, title: String, kind: String?, fields: [OpenCodeFormField])
}
public enum OpenCodeEvent: Equatable {
    case permissionAsked(OpenCodePermissionRequest, directory: String?)
    case permissionReplied(sessionID: String, requestID: String)
    case toolCalled(sessionID: String, callID: String, input: [String: String])   // only the string-valued inputs
    case formCreated(OpenCodeForm, directory: String?)
    case formClosed(sessionID: String, formID: String)       // form.replied or form.cancelled
    case sessionCreated(sessionID: String, directory: String?)
    case executionStarted(sessionID: String)
    case executionFinished(sessionID: String)                // succeeded, failed or interrupted
    case other(type: String)
    /// nil when the text isn't a JSON object with a string "type"; `.other(type)` for a type the
    /// bridge doesn't use, or for a known type whose required fields are missing.
    public static func decode(_ json: String) -> OpenCodeEvent?
}
```
- Produce para los tests (`Support/OpenCodeFixtures.swift`, saneados de la captura del 2026-10-21; las rutas reales se cambiaron por `/tmp/oc-prueba`):
```swift
enum OpenCodeFixtures {
    static let toolCalledShell = #"{"id":"evt_1","created":1,"type":"session.tool.called","location":{"directory":"/tmp/oc-prueba"},"data":{"sessionID":"ses_1","assistantMessageID":"msg_1","id":"call_1","input":{"command":"ls -la notas.txt 2>&1; echo \"---\"; cat -A notas.txt 2>&1 | tail -20"},"executed":false}}"#
    static let permissionShell = #"{"id":"evt_2","created":2,"type":"permission.asked","location":{"directory":"/tmp/oc-prueba"},"data":{"id":"per_1","sessionID":"ses_1","action":"shell","resources":["ls -la notas.txt 2>&1","echo \"---\"","cat -A notas.txt 2>&1","tail -20"],"save":["ls *","echo *","cat *","tail *"],"source":{"type":"tool","messageID":"msg_1","id":"call_1"}}}"#
    static let toolCalledEdit = #"{"id":"evt_3","created":3,"type":"session.tool.called","location":{"directory":"/tmp/oc-prueba"},"data":{"sessionID":"ses_1","assistantMessageID":"msg_2","id":"call_2","input":{"path":"/tmp/oc-prueba/notas.txt","oldString":"adiós\n","newString":"adiós\nadiós 2\n"},"executed":false}}"#
    static let permissionEdit = #"{"id":"evt_4","created":4,"type":"permission.asked","location":{"directory":"/tmp/oc-prueba"},"data":{"id":"per_2","sessionID":"ses_1","action":"edit","resources":["notas.txt"],"save":["*"],"metadata":{"files":[{"file":"notas.txt","patch":"Index: notas.txt\n===================================================================\n--- notas.txt\n+++ notas.txt\n@@ -1,2 +1,3 @@\n hola\n adiós\n+adiós 2\n","status":"modified","additions":1,"deletions":0}]},"source":{"type":"tool","messageID":"msg_2","id":"call_2"}}}"#
    static let permissionReplied = #"{"id":"evt_5","created":5,"type":"permission.replied","location":{"directory":"/tmp/oc-prueba"},"data":{"sessionID":"ses_1","requestID":"per_1","reply":"once"}}"#
    static let formCreated = #"{"id":"evt_6","created":6,"type":"form.created","location":{"directory":"/tmp/oc-prueba"},"data":{"form":{"id":"frm_1","sessionID":"ses_1","title":"Questions","metadata":{"kind":"question","tool":{"messageID":"msg_3","id":"call_3"}},"fields":[{"key":"q0","title":"Color","description":"¿Qué color prefieres?","type":"string","options":[{"value":"Rojo","label":"Rojo","description":"Elegir el color rojo"},{"value":"Azul","label":"Azul","description":"Elegir el color azul"}],"custom":true}]}}}"#
    static let formReplied = #"{"id":"evt_7","created":7,"type":"form.replied","location":{"directory":"/tmp/oc-prueba"},"data":{"id":"frm_1","sessionID":"ses_1","answer":{"q0":"Rojo"}}}"#
    static let formCancelled = #"{"id":"evt_8","created":8,"type":"form.cancelled","data":{"id":"frm_1","sessionID":"ses_1"}}"#
    static let sessionCreated = #"{"id":"evt_9","created":9,"type":"session.created","location":{"directory":"/tmp/oc-prueba"},"data":{"sessionID":"ses_1","agent":"build","location":{"directory":"/tmp/oc-prueba"}}}"#
    static let executionStarted = #"{"id":"evt_10","created":10,"type":"session.execution.started","data":{"sessionID":"ses_1"}}"#
    static let executionSucceeded = #"{"id":"evt_11","created":11,"type":"session.execution.succeeded","data":{"sessionID":"ses_1"}}"#
    static let executionFailed = #"{"id":"evt_12","created":12,"type":"session.execution.failed","data":{"sessionID":"ses_1","error":"x"}}"#
    static let executionInterrupted = #"{"id":"evt_13","created":13,"type":"session.execution.interrupted","data":{"sessionID":"ses_1","reason":"user"}}"#
    static let textDelta = #"{"id":"evt_14","created":14,"type":"session.text.delta","location":{"directory":"/tmp/oc-prueba"},"data":{"sessionID":"ses_1","delta":"hola"}}"#
}
```

- [x] **Paso 1: escribir los tests**

```swift
import Testing
import BuddyCore

@Suite struct OpenCodeEventTests {
    @Test func permissionShell() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.permissionShell) == .permissionAsked(
            OpenCodePermissionRequest(id: "per_1", sessionID: "ses_1", action: "shell",
                                      resources: ["ls -la notas.txt 2>&1", "echo \"---\"", "cat -A notas.txt 2>&1", "tail -20"],
                                      callID: "call_1"),
            directory: "/tmp/oc-prueba"))
    }

    @Test func permissionEditCarriesItsPatch() {
        guard case let .permissionAsked(req, dir)? = OpenCodeEvent.decode(OpenCodeFixtures.permissionEdit) else {
            Issue.record("not decoded"); return
        }
        #expect(dir == "/tmp/oc-prueba")
        #expect(req.action == "edit")
        #expect(req.editedFiles == ["notas.txt"])
        #expect(req.patches.count == 1)
        #expect(req.patches[0].contains("+adiós 2"))
        #expect(req.callID == "call_2")
    }

    @Test func toolCalledKeepsStringInputs() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.toolCalledEdit) == .toolCalled(
            sessionID: "ses_1", callID: "call_2",
            input: ["path": "/tmp/oc-prueba/notas.txt", "oldString": "adiós\n", "newString": "adiós\nadiós 2\n"]))
    }

    @Test func formCreated() {
        guard case let .formCreated(form, dir)? = OpenCodeEvent.decode(OpenCodeFixtures.formCreated) else {
            Issue.record("not decoded"); return
        }
        #expect(dir == "/tmp/oc-prueba")
        #expect(form == OpenCodeForm(id: "frm_1", sessionID: "ses_1", title: "Questions", kind: "question", fields: [
            OpenCodeFormField(key: "q0", title: "Color", description: "¿Qué color prefieres?", type: "string", options: [
                OpenCodeFormOption(value: "Rojo", label: "Rojo", description: "Elegir el color rojo"),
                OpenCodeFormOption(value: "Azul", label: "Azul", description: "Elegir el color azul"),
            ]),
        ]))
    }

    @Test func closingAndLifecycleEvents() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.permissionReplied) == .permissionReplied(sessionID: "ses_1", requestID: "per_1"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.formReplied) == .formClosed(sessionID: "ses_1", formID: "frm_1"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.formCancelled) == .formClosed(sessionID: "ses_1", formID: "frm_1"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.sessionCreated) == .sessionCreated(sessionID: "ses_1", directory: "/tmp/oc-prueba"))
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.executionStarted) == .executionStarted(sessionID: "ses_1"))
        for f in [OpenCodeFixtures.executionSucceeded, OpenCodeFixtures.executionFailed, OpenCodeFixtures.executionInterrupted] {
            #expect(OpenCodeEvent.decode(f) == .executionFinished(sessionID: "ses_1"))
        }
    }

    @Test func unknownAndBrokenInput() {
        #expect(OpenCodeEvent.decode(OpenCodeFixtures.textDelta) == .other(type: "session.text.delta"))
        #expect(OpenCodeEvent.decode(#"{"type":"permission.asked","data":{"sessionID":"s"}}"#) == .other(type: "permission.asked"))
        #expect(OpenCodeEvent.decode(#"{"type":"form.created","data":{}}"#) == .other(type: "form.created"))
        #expect(OpenCodeEvent.decode("no es json") == nil)
        #expect(OpenCodeEvent.decode(#"{"data":{}}"#) == nil)
        #expect(OpenCodeEvent.decode(#"[1,2]"#) == nil)
    }
}
```

- [x] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter OpenCodeEventTests`
Esperado: no compila.

- [x] **Paso 3: implementar `OpenCodeEvent.decode`**

- Usa `JSONSerialization` (los campos son abiertos y varían entre versiones; `Codable` estricto rompería con cualquier campo nuevo).
- `directory` sale de `location.directory` del envoltorio.
- **Campos obligatorios** (si falta alguno, `.other(type)`):
  - `permission.asked`: `data.id`, `data.sessionID`, `data.action`;
  - `permission.replied`: `sessionID`, `requestID`;
  - `session.tool.called`: `sessionID`, `id`;
  - `form.created`: `form.id`, `form.sessionID`;
  - `form.replied`/`form.cancelled`: `id`, `sessionID`;
  - `session.execution.*` y `session.created`: `sessionID`.
- `resources` faltante = `[]`. En `toolCalled`, `input` guarda solo los valores de tipo `String`.
- Los campos de formulario sin `key` o sin `type` se descartan; las opciones sin `value` o sin `label` también.

- [x] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter OpenCodeEventTests`
Esperado: PASA.

- [x] **Paso 5: commit**

```bash
git add Sources/BuddyCore/OpenCode/OpenCodeEvent.swift Tests/ClaudeMenuBarBuddyTests/Support/OpenCodeFixtures.swift Tests/ClaudeMenuBarBuddyTests/OpenCodeEventTests.swift
git commit -m "BuddyCore entiende los eventos de opencode que necesita el puente e ignora el resto"
```

---

### Tarea 3: la regla aplicada a opencode

**Archivos:**
- Modificar: `Sources/BuddyCore/Rule/RuleTypes.swift` (nuevo caso de `RuleSubject`) y `Sources/BuddyCore/Rule/CommandRule.swift`
- Crear: `Sources/BuddyCore/OpenCode/OpenCodeRule.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/OpenCodeRuleTests.swift`

**Interfaces:**
- Consume: `RuleSubject`, `CommandRule.assess`, `RuleContext`, `Assessment` (entrega 1); `OpenCodePermissionRequest` (tarea 2).
- Produce:
```swift
// in RuleSubject:
case fileRead(path: String)
// CommandRule.assess(.fileRead(path:)):
//   empty, relative or containing ".." → Assessment(.desconocido, "no se puede saber qué lee: P")
//   isSensitive → Assessment(.sensible, "toca un archivo sensible: R")
//   otherwise   → Assessment(.lectura, "solo lee")

public enum OpenCodeRule {
    /// The rule subjects one permission request stands for (one per file in a multi-file edit).
    public static func subjects(for request: OpenCodePermissionRequest, toolInput: [String: String]?,
                                directory: String) -> [RuleSubject]
    /// The worst assessment over those subjects (highest severity, first wins on ties) and the
    /// subject it came from. An empty list is Assessment(.desconocido, "la regla no reconoce: ACTION").
    public static func assess(_ request: OpenCodePermissionRequest, toolInput: [String: String]?,
                              directory: String, context: RuleContext) -> (subject: RuleSubject, assessment: Assessment)
}
```

- [x] **Paso 1: escribir los tests**

```swift
import Testing
import BuddyCore

@Suite struct OpenCodeRuleTests {
    private let dir = "/Users/u/repo"
    private func req(_ action: String, _ resources: [String], files: [String] = [], callID: String? = nil) -> OpenCodePermissionRequest {
        OpenCodePermissionRequest(id: "per_x", sessionID: "ses_x", action: action, resources: resources,
                                  editedFiles: files, patches: [], callID: callID)
    }

    @Test func shellPrefersTheFullCommand() {
        let s = OpenCodeRule.subjects(for: req("shell", ["ls -la", "rm x"]), toolInput: ["command": "ls -la && rm x"], directory: dir)
        #expect(s == [.shell(command: "ls -la && rm x")])
    }

    @Test func shellFallsBackToTheResources() {
        #expect(OpenCodeRule.subjects(for: req("shell", ["ls -la", "rm x"]), toolInput: nil, directory: dir)
                == [.shell(command: "ls -la; rm x")])
    }

    @Test func editResolvesRelativeFilesAgainstTheSession() {
        #expect(OpenCodeRule.subjects(for: req("edit", ["notas.txt"], files: ["notas.txt"]), toolInput: nil, directory: dir)
                == [.fileEdit(path: "/Users/u/repo/notas.txt")])
        #expect(OpenCodeRule.subjects(for: req("edit", ["a"]), toolInput: ["path": "/Users/u/repo/a.swift"], directory: dir)
                == [.fileEdit(path: "/Users/u/repo/a.swift")])
    }

    @Test func otherActions() {
        #expect(OpenCodeRule.subjects(for: req("read", [".env"]), toolInput: nil, directory: dir) == [.fileRead(path: "/Users/u/repo/.env")])
        #expect(OpenCodeRule.subjects(for: req("webfetch", ["https://x"]), toolInput: nil, directory: dir) == [.web(tool: "webfetch")])
        #expect(OpenCodeRule.subjects(for: req("skill", ["x"]), toolInput: nil, directory: dir) == [.other(tool: "skill")])
    }

    @Test func worstFileWins() {
        let r = OpenCodeRule.assess(req("edit", [], files: ["src/a.swift", ".git/config", "b.md"]), toolInput: nil,
                                    directory: dir, context: ruleContext)
        #expect(r.assessment.category == .rutaProtegida)
        #expect(r.subject == .fileEdit(path: "/Users/u/repo/.git/config"))
    }

    @Test func assessments() {
        let a = { (r: OpenCodePermissionRequest, input: [String: String]?) in
            OpenCodeRule.assess(r, toolInput: input, directory: self.dir, context: ruleContext).assessment.category
        }
        #expect(a(req("shell", ["git status"]), nil) == .lectura)
        #expect(a(req("shell", ["x"]), ["command": "python3 x.py"]) == .ejecuta)
        #expect(a(req("edit", ["src/a.swift"]), nil) == .edicion)
        #expect(a(req("read", [".env"]), nil) == .sensible)
        #expect(a(req("read", ["src/a.swift"]), nil) == .lectura)
        #expect(a(req("websearch", ["q"]), nil) == .sale)
        #expect(a(req("external_directory", ["/etc/*"]), nil) == .desconocido)
    }

    @Test func fileReadInCommandRule() {
        #expect(CommandRule.assess(.fileRead(path: "notes.txt"), context: ruleContext)
                == Assessment(.desconocido, "no se puede saber qué lee: notes.txt"))
        #expect(CommandRule.assess(.fileRead(path: "/Users/u/.aws/credentials"), context: ruleContext).category == .sensible)
        #expect(CommandRule.assess(.fileRead(path: "/Users/u/repo/a.swift"), context: ruleContext) == Assessment(.lectura, "solo lee"))
    }
}
```

- [x] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter OpenCodeRuleTests`
Esperado: no compila.

- [x] **Paso 3: implementar**

- **`.fileRead` en `CommandRule.assess`,** como dice el bloque de interfaces. Agrega el caso nuevo también en el `switch` de `HookRuleCLI.hint(for:)`, que devuelve la ruta; si no, no compila.
- **Mapeo de `OpenCodeRule.subjects`** (la acción, sin distinguir mayúsculas):
  - `shell` → `[.shell(command: toolInput["command"] ?? resources.joined(separator: "; "))]`;
  - `edit` → una `.fileEdit` por ruta. Las rutas son `editedFiles` si no está vacío; si no, `[toolInput["path"]]` si existe; si no, `resources`. Las relativas se unen a `directory`;
  - `read` → `.fileRead` por cada recurso, con las relativas unidas a `directory`;
  - `webfetch` o `websearch` → `[.web(tool: action)]`;
  - `question` → `[.question(tool: "question")]`;
  - cualquier otra → `[.other(tool: action)]`.
- **Peor evaluación:** por `RuleCategory.severity`; en empate gana la primera.

- [x] **Paso 4: verificar que pasa todo**

Corre: `swift build && swift test`
Esperado: todo en verde.

- [x] **Paso 5: commit**

```bash
git add Sources/BuddyCore/Rule/RuleTypes.swift Sources/BuddyCore/Rule/CommandRule.swift Sources/BuddyCore/OpenCode/OpenCodeRule.swift Tests/ClaudeMenuBarBuddyTests/OpenCodeRuleTests.swift
git commit -m "La regla evalúa las solicitudes de opencode con la misma vara que las de Claude"
```

---

### Tarea 4: el diff de opencode en la tarjeta

**Archivos:**
- Crear: `Sources/BuddyCore/OpenCode/UnifiedDiff.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/UnifiedDiffTests.swift`

**Interfaces:**
- Produce:
```swift
public enum UnifiedDiff {
    /// opencode's unified patches → the card's mini-diff ("--- quita" / "+++ pone" sections, as hook.sh writes them).
    public static func buddyHint(files: [String], patches: [String]) -> String
}
```

- [x] **Paso 1: escribir los tests**

```swift
import Testing
import BuddyCore

@Suite struct UnifiedDiffTests {
    @Test func additionOnly() {
        let patch = "Index: notas.txt\n===================================================================\n--- notas.txt\n+++ notas.txt\n@@ -1,2 +1,3 @@\n hola\n adiós\n+adiós 2\n"
        #expect(UnifiedDiff.buddyHint(files: ["notas.txt"], patches: [patch]) == "notas.txt\n+++ pone\nadiós 2")
    }

    @Test func replacement() {
        let patch = "--- a.swift\n+++ a.swift\n@@ -1,2 +1,2 @@\n-let x = 1\n+let x = 2\n keep\n"
        #expect(UnifiedDiff.buddyHint(files: ["a.swift"], patches: [patch]) == "a.swift\n--- quita\nlet x = 1\n+++ pone\nlet x = 2")
    }

    @Test func twoHunksAndTwoFiles() {
        let p1 = "@@ -1 +1 @@\n-a\n+b\n@@ -9 +9 @@\n-c\n"
        let p2 = "@@ -0,0 +1 @@\n+nuevo\n"
        #expect(UnifiedDiff.buddyHint(files: ["f1", "f2"], patches: [p1, p2])
                == "f1\n--- quita\na\n+++ pone\nb\n--- quita\nc\nf2\n+++ pone\nnuevo")
    }

    @Test func noPatchIsJustTheFiles() {
        #expect(UnifiedDiff.buddyHint(files: ["a", "b"], patches: []) == "a\nb")
    }
}
```

- [x] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter UnifiedDiffTests`
Esperado: no compila.

- [x] **Paso 3: implementar `UnifiedDiff.buddyHint`**

- Por cada archivo, en orden, emite su ruta.
- Si tiene parche, cada línea `@@` abre un bloque. Del bloque se juntan las líneas que empiezan con `-` (pero no `---`), sin el `-`, como "quita", y las que empiezan con `+` (pero no `+++`), sin el `+`, como "pone". El contexto y los encabezados (`Index:`, `====`, `---`, `+++`) se ignoran.
- Cada bloque emite `--- quita` más lo quitado (si hay) y `+++ pone` más lo puesto (si hay).
- Todo se une con `\n`, sin `\n` final.

- [x] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter UnifiedDiffTests`
Esperado: PASA.

- [x] **Paso 5: commit**

```bash
git add Sources/BuddyCore/OpenCode/UnifiedDiff.swift Tests/ClaudeMenuBarBuddyTests/UnifiedDiffTests.swift
git commit -m "El diff de una edición de opencode se ve en la tarjeta como el de Claude"
```

---

### Tarea 4b: dos huecos de la revisión del bloque 1

La revisión encontró dos casos que el plan dejó mal especificados. No son errores de la ejecución.

1. **El diff se come líneas.** El paso 3 de la tarea 4 descarta toda línea que empieza con `---` o `+++` como si fuera encabezado, aunque esté dentro de un bloque. Por eso una línea quitada `-- borra la tabla` (un comentario de SQL), que en el parche es `--- borra la tabla`, desaparece de la tarjeta. Pasa lo mismo con una línea puesta `++ x` o con un `---` de Markdown. Cada parche de opencode (`metadata.files[].patch`) es de **un solo archivo**, así que los encabezados `Index:`, `====`, `---` y `+++` solo aparecen **antes del primer `@@`**. Después de él, toda línea con `-` o `+` es contenido.
2. **Las rutas con `~` se resuelven mal.** `OpenCodeRule` une `~/.aws/credentials` a la carpeta de la sesión y produce `/repo/~/.aws/credentials`, que la regla evalúa como lectura normal y deja pasar. El buddy no sabe si opencode expande `~`. Una ruta que empieza con `~` se deja **tal cual**, y la regla la trata como desconocida: muestra tarjeta.

**Archivos:**
- Modificar: `Sources/BuddyCore/OpenCode/UnifiedDiff.swift`, `Sources/BuddyCore/OpenCode/OpenCodeRule.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/UnifiedDiffTests.swift`, `Tests/ClaudeMenuBarBuddyTests/OpenCodeRuleTests.swift`

**Interfaces:** sin cambios.

- [x] **Paso 1: escribir los tests**

En `UnifiedDiffTests`:

```swift
    @Test func contentThatLooksLikeAHeaderIsKept() {
        let patch = "Index: a.sql\n===================================================================\n--- a.sql\n+++ a.sql\n@@ -1,3 +1,3 @@\n select 1;\n--- borra la tabla\n+-- nada\n+++ suma\n drop table x;\n"
        #expect(UnifiedDiff.buddyHint(files: ["a.sql"], patches: [patch])
                == "a.sql\n--- quita\n-- borra la tabla\n+++ pone\n-- nada\n++ suma")
    }

    @Test func markdownRuleIsKept() {
        let patch = "--- README.md\n+++ README.md\n@@ -1,2 +1,2 @@\n----\n+===\n texto\n"
        #expect(UnifiedDiff.buddyHint(files: ["README.md"], patches: [patch]) == "README.md\n--- quita\n---\n+++ pone\n===")
    }
```

En `OpenCodeRuleTests`:

```swift
    @Test func tildePathsAreLeftAsTheyCome() {
        #expect(OpenCodeRule.subjects(for: req("read", ["~/.aws/credentials"]), toolInput: nil, directory: dir)
                == [.fileRead(path: "~/.aws/credentials")])
        #expect(OpenCodeRule.subjects(for: req("edit", [], files: ["~/notas.txt"]), toolInput: nil, directory: dir)
                == [.fileEdit(path: "~/notas.txt")])
        #expect(OpenCodeRule.assess(req("read", ["~/.aws/credentials"]), toolInput: nil, directory: dir,
                                    context: ruleContext).assessment.category == .desconocido)
    }
```

- [x] **Paso 2: verificar que fallan**

Corre: `swift build && swift test --filter "UnifiedDiffTests|OpenCodeRuleTests"`
Esperado: fallan `contentThatLooksLikeAHeaderIsKept`, `markdownRuleIsKept` y `tildePathsAreLeftAsTheyCome`; los demás pasan.

- [x] **Paso 3: corregir**

- **`UnifiedDiff`:** antes del primer `@@` de un parche se ignora todo. Después del primer `@@` ya no se descarta ninguna línea por empezar con `---` o `+++`: la que empieza con `-` es "quita" y la que empieza con `+` es "pone", siempre sin su primer carácter. Lo demás (contexto, `\ No newline at end of file`, líneas vacías) se sigue ignorando. Corrige también el comentario del código que habla de los encabezados.
- **`OpenCodeRule`:** en el helper que vuelve absolutas las rutas, una ruta que empieza con `~` se devuelve sin tocar, igual que una absoluta.

- [x] **Paso 4: verificar que pasa todo**

Corre: `swift build && swift test`
Esperado: todo en verde (199 + 3).

- [x] **Paso 5: commit**

```bash
git add Sources/BuddyCore/OpenCode/UnifiedDiff.swift Sources/BuddyCore/OpenCode/OpenCodeRule.swift Tests/ClaudeMenuBarBuddyTests/UnifiedDiffTests.swift Tests/ClaudeMenuBarBuddyTests/OpenCodeRuleTests.swift
git commit -m "La tarjeta ya no pierde líneas del diff que parecen encabezados y las rutas con ~ piden tarjeta"
```

---

### Tarea 5: el estado del puente

**Archivos:**
- Crear: `Sources/BuddyCore/OpenCode/OpenCodeBridgeCore.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/OpenCodeBridgeCoreTests.swift`

**Interfaces:**
- Consume: `OpenCodeEvent` (tarea 2), `OpenCodeRule` (tarea 3), `UnifiedDiff` (tarea 4), `AutoModePolicy`, `AlwaysAllow`, `PathPolicy`, `AutoLogEntry` (entrega 1).
- Produce:
```swift
public struct OpenCodeChoice: Equatable {
    public let fieldKey: String
    public let question: String            // field.description ?? field.title ?? field.key
    public let header: String?             // field.title
    public let options: [OpenCodeFormOption]
}
public struct OpenCodeCardRequest: Equatable {
    public enum Kind: Equatable { case permission, form }
    public let id: String                  // the opencode permission or form id — also the buddy request id
    public let sessionID: String
    public let kind: Kind
    public let tool: String                // the action ("shell", "edit", …) or "question"
    public let hint: String
    public let hidden: Int
    public let project: String             // last path component of cwd
    public let cwd: String
    public let category: String
    public let critical: Bool
    public let reason: String
    public let choices: [OpenCodeChoice]?  // forms only
    /// The request_<id>.json body: the keys hook.sh writes (id, tool, hint, project, cwd, choices, hidden, ts,
    /// category, critical, reason) plus "agent": "opencode". `choices` uses the hook's shape:
    /// [{"question":…, "header":…, "options":[{"label":…, "description":…}]}], or null.
    public func requestFileJSON(now: Date) -> Data
}
public enum OpenCodeAction: Equatable {
    case autoReply(sessionID: String, requestID: String, log: AutoLogEntry)   // reply "once" now
    case showCard(OpenCodeCardRequest)                                       // after the pending check
    case withdrawCard(id: String)                                            // answered elsewhere
    case turnFinished(sessionID: String, elapsed: Int)
}
public struct OpenCodeBridgeCore {
    public struct Settings {
        public var autoMode: Bool
        public var allowList: AlwaysAllow
        public var paths: PathPolicy
        public init(autoMode: Bool, allowList: AlwaysAllow, paths: PathPolicy)
    }
    public init()
    public mutating func handle(_ event: OpenCodeEvent, settings: Settings, now: Date) -> [OpenCodeAction]
    public func pending(id: String) -> OpenCodeCardRequest?
    public mutating func forget(id: String)        // after answering, or when the pending check says it's gone
}
```

- [ ] **Paso 1: escribir los tests**

```swift
import Foundation
import Testing
import BuddyCore

@Suite struct OpenCodeBridgeCoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func settings(auto: Bool, allow: AlwaysAllow = AlwaysAllow()) -> OpenCodeBridgeCore.Settings {
        OpenCodeBridgeCore.Settings(autoMode: auto, allowList: allow, paths: ruleContext.paths)
    }
    private func run(_ fixtures: [String], auto: Bool, core: inout OpenCodeBridgeCore) -> [OpenCodeAction] {
        fixtures.flatMap { core.handle(OpenCodeEvent.decode($0)!, settings: settings(auto: auto), now: t0) }
    }

    @Test func autoModePassesAReadAndLogsIt() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.toolCalledShell, OpenCodeFixtures.permissionShell], auto: true, core: &core)
        guard case let .autoReply(sid, rid, log)? = out.first, out.count == 1 else { Issue.record("\(out)"); return }
        #expect(sid == "ses_1")
        #expect(rid == "per_1")
        #expect(log.agent == "opencode")
        #expect(log.tool == "shell")
        #expect(log.category == "lectura")
        #expect(log.project == "oc-prueba")
        #expect(log.hint.hasPrefix("ls -la notas.txt"))
    }

    @Test func autoModeOffShowsACardWithTheFullCommand() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.toolCalledShell, OpenCodeFixtures.permissionShell], auto: false, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.id == "per_1")
        #expect(card.kind == .permission)
        #expect(card.tool == "shell")
        #expect(card.hint == #"ls -la notas.txt 2>&1; echo "---"; cat -A notas.txt 2>&1 | tail -20"#)
        #expect(card.project == "oc-prueba")
        #expect(card.cwd == "/tmp/oc-prueba")
        #expect(card.critical == false)
        #expect(core.pending(id: "per_1") == card)
    }

    @Test func criticalAlwaysShowsACard() {
        var core = OpenCodeBridgeCore()
        let tool = #"{"type":"session.tool.called","data":{"sessionID":"ses_1","id":"call_9","input":{"command":"python3 x.py"}}}"#
        let perm = #"{"type":"permission.asked","location":{"directory":"/tmp/oc-prueba"},"data":{"id":"per_9","sessionID":"ses_1","action":"shell","resources":["python3 x.py"],"source":{"type":"tool","id":"call_9"}}}"#
        let out = run([tool, perm], auto: true, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.critical)
        #expect(card.category == "ejecuta")
        #expect(card.reason == "ejecuta código: python3")
    }

    @Test func editCardShowsTheDiff() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.toolCalledEdit, OpenCodeFixtures.permissionEdit], auto: false, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.tool == "edit")
        #expect(card.hint == "notas.txt\n+++ pone\nadiós 2")
    }

    @Test func sameRequestTwiceIsOneCard() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.permissionShell, OpenCodeFixtures.permissionShell], auto: false, core: &core)
        #expect(out.count == 1)
    }

    @Test func answeredInTheTerminalWithdrawsTheCard() {
        var core = OpenCodeBridgeCore()
        _ = run([OpenCodeFixtures.permissionShell], auto: false, core: &core)
        #expect(run([OpenCodeFixtures.permissionReplied], auto: false, core: &core) == [.withdrawCard(id: "per_1")])
        #expect(core.pending(id: "per_1") == nil)
        #expect(run([OpenCodeFixtures.permissionReplied], auto: false, core: &core).isEmpty)
    }

    @Test func forgottenRequestsDoNotComeBack() {
        var core = OpenCodeBridgeCore()
        _ = run([OpenCodeFixtures.permissionShell], auto: false, core: &core)
        core.forget(id: "per_1")
        #expect(run([OpenCodeFixtures.permissionShell], auto: false, core: &core).isEmpty)
    }

    @Test func questionFormBecomesAChoiceCard() {
        var core = OpenCodeBridgeCore()
        let out = run([OpenCodeFixtures.formCreated], auto: true, core: &core)
        guard case let .showCard(card)? = out.first else { Issue.record("\(out)"); return }
        #expect(card.kind == .form)
        #expect(card.tool == "question")
        #expect(card.category == "pregunta")
        #expect(card.choices == [OpenCodeChoice(fieldKey: "q0", question: "¿Qué color prefieres?", header: "Color", options: [
            OpenCodeFormOption(value: "Rojo", label: "Rojo", description: "Elegir el color rojo"),
            OpenCodeFormOption(value: "Azul", label: "Azul", description: "Elegir el color azul"),
        ])])
        #expect(run([OpenCodeFixtures.formReplied], auto: true, core: &core) == [.withdrawCard(id: "frm_1")])
    }

    @Test func formsTheCardCannotAnswerStayInTheTerminal() {
        var core = OpenCodeBridgeCore()
        let multi = #"{"type":"form.created","data":{"form":{"id":"frm_2","sessionID":"ses_1","title":"Q","metadata":{"kind":"question"},"fields":[{"key":"q0","type":"multiselect","options":[{"value":"a","label":"a"}]}]}}}"#
        let free = #"{"type":"form.created","data":{"form":{"id":"frm_3","sessionID":"ses_1","title":"Q","metadata":{"kind":"question"},"fields":[{"key":"q0","type":"string"}]}}}"#
        let notQuestion = #"{"type":"form.created","data":{"form":{"id":"frm_4","sessionID":"ses_1","title":"Login","metadata":{"kind":"auth"},"fields":[{"key":"u","type":"string","options":[{"value":"a","label":"a"}]}]}}}"#
        #expect(run([multi, free, notQuestion], auto: false, core: &core).isEmpty)
    }

    @Test func turnFinishedMeasuresTheTurn() {
        var core = OpenCodeBridgeCore()
        _ = core.handle(.executionStarted(sessionID: "ses_1"), settings: settings(auto: false), now: t0)
        let out = core.handle(.executionFinished(sessionID: "ses_1"), settings: settings(auto: false), now: t0.addingTimeInterval(42))
        #expect(out == [.turnFinished(sessionID: "ses_1", elapsed: 42)])
        #expect(core.handle(.executionFinished(sessionID: "ses_1"), settings: settings(auto: false), now: t0).isEmpty)
    }

    @Test func requestFileHasTheHookShape() throws {
        var core = OpenCodeBridgeCore()
        guard case let .showCard(card)? = run([OpenCodeFixtures.formCreated], auto: false, core: &core).first else {
            Issue.record("no card"); return
        }
        let obj = try JSONSerialization.jsonObject(with: card.requestFileJSON(now: t0)) as! [String: Any]
        #expect(obj["id"] as? String == "frm_1")
        #expect(obj["agent"] as? String == "opencode")
        #expect(obj["tool"] as? String == "question")
        #expect(obj["cwd"] as? String == "/tmp/oc-prueba")
        #expect(obj["project"] as? String == "oc-prueba")
        #expect(obj["ts"] as? Double == 1_000)
        #expect(obj["critical"] as? Bool == false)
        let choices = obj["choices"] as? [[String: Any]]
        #expect(choices?.first?["question"] as? String == "¿Qué color prefieres?")
        #expect((choices?.first?["options"] as? [[String: Any]])?.map { $0["label"] as? String } == ["Rojo", "Azul"])
    }
}
```

- [ ] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter OpenCodeBridgeCoreTests`
Esperado: no compila.

- [ ] **Paso 3: implementar `OpenCodeBridgeCore`**

- **Estado interno:**
  - el caché `callID → input` de `toolCalled`, con un máximo de 200 entradas (descarta la más vieja);
  - `sessionID → directory` de `sessionCreated` y de cada evento que traiga carpeta;
  - `sessionID → inicio` de `executionStarted`;
  - `pending: [String: OpenCodeCardRequest]`;
  - `handled: Set<String>`, los ids ya decididos o mostrados.
- **`permissionAsked`:**
  - si el id ya está en `handled`, nada;
  - `dir = directory ?? carpeta guardada de la sesión ?? ""`;
  - evalúa con `OpenCodeRule.assess(…, toolInput: caché[callID], directory: dir, context: RuleContext(cwd: dir, paths: settings.paths))`;
  - decide con `AutoModePolicy.decide(subject:, assessment:, autoMode:, allowList:, cwd: dir, planMode: false)`.
  - **Si pasa:** `.autoReply` con `AutoLogEntry(ts: now, agent: "opencode", project: último componente de dir, cwd: dir, tool: action, hint: primeros 200 caracteres del hint, category: rawValue)`.
  - **Si no:** `.showCard`, con el hint así:

    | Acción | Hint |
    |---|---|
    | `shell` | El comando de la evaluación (completo o unido) |
    | `edit` | `UnifiedDiff.buddyHint(files: editedFiles, patches: patches)`; sin `editedFiles`, la ruta |
    | Cualquier otra | La acción, salto de línea, y los recursos unidos con `\n` |

    El hint se corta a 20 000 caracteres y `hidden` cuenta lo que no cupo, como en `hook.sh`.
  - En los dos casos el id entra a `handled`.
- **`formCreated`:**
  - **Solo si** `kind == "question"` y **todos** los campos son `type == "string"` con al menos una opción.
  - Crea una tarjeta `kind: .form`, `tool: "question"`, `category: "pregunta"`, `critical: false` y `reason: "pregunta del agente"`; el hint son las preguntas unidas con `\n\n`.
  - Si no cumple, nada: la terminal de opencode la contesta.
- **`permissionReplied` / `formClosed`:** si el id está en `pending`, lo quita y da `.withdrawCard`; si no, nada.
- **`executionFinished`:** si hay inicio, da `.turnFinished` con los segundos enteros y borra el inicio.
- **`forget(id:)`:** quita de `pending` y deja el id en `handled`.

- [ ] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter OpenCodeBridgeCoreTests`
Esperado: PASA.

- [ ] **Paso 5: commit**

```bash
git add Sources/BuddyCore/OpenCode/OpenCodeBridgeCore.swift Tests/ClaudeMenuBarBuddyTests/OpenCodeBridgeCoreTests.swift
git commit -m "El puente decide qué de opencode pasa solo, qué va a tarjeta y cuándo retirarla"
```

---

### Tarea 6: la API de opencode

**Archivos:**
- Crear: `Sources/BuddyCore/OpenCode/OpenCodeAPI.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/OpenCodeAPITests.swift`

**Interfaces:**
- Consume: `OpenCodeCardRequest`, `OpenCodeChoice` (tarea 5).
- Produce:
```swift
public struct OpenCodeService: Equatable {
    public let baseURL: URL
    public let password: String
    public static var defaultFile: URL { get }       // ~/.local/state/opencode/service.json
    /// nil when the file is missing or unreadable, or the URL isn't http on 127.0.0.1, localhost or ::1.
    public static func load(from file: URL) -> OpenCodeService?
    public var authorization: String { get }          // "Basic " + base64("opencode:" + password)
}
public enum OpenCodeCall: Equatable {
    case events
    case sessions(limit: Int)
    case session(id: String)
    case pendingPermissions(sessionID: String)
    case pendingForms(sessionID: String)
    case permissionStillPending(sessionID: String, requestID: String)
    case replyPermission(sessionID: String, requestID: String, decision: String, message: String?)
    case replyForm(sessionID: String, formID: String, answer: [String: String])
    public func urlRequest(service: OpenCodeService) -> URLRequest
}
public enum OpenCodeAnswer {
    /// What a card decision means for opencode. nil = no call: the opencode terminal keeps its own prompt.
    public static func call(for card: OpenCodeCardRequest, decision: String, reason: String?,
                            answers: [String: String]?) -> OpenCodeCall?
}
```

- [ ] **Paso 1: escribir los tests**

```swift
import Foundation
import Testing
import BuddyCore

@Suite struct OpenCodeAPITests {
    private func file(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    private let service = OpenCodeService.load(from: try! {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID().uuidString).json")
        try #"{"id":"x","version":"2.1.2","url":"http://127.0.0.1:49374","pid":1,"password":"secreto"}"#
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }())!

    @Test func loadsALoopbackService() {
        #expect(service.baseURL.absoluteString == "http://127.0.0.1:49374")
        #expect(service.authorization == "Basic " + Data("opencode:secreto".utf8).base64EncodedString())
    }

    @Test(arguments: [
        #"{"url":"http://10.0.0.5:49374","password":"p"}"#, #"{"url":"https://127.0.0.1:1","password":"p"}"#,
        #"{"url":"http://evil.com","password":"p"}"#, #"{"password":"p"}"#, #"{"url":"http://127.0.0.1:1"}"#, "no json",
    ])
    func refusesAnythingElse(text: String) throws {
        #expect(OpenCodeService.load(from: try file(text)) == nil)
    }

    @Test func missingFile() {
        #expect(OpenCodeService.load(from: URL(fileURLWithPath: "/nonexistent/service.json")) == nil)
    }

    @Test func requestShapes() throws {
        let get = OpenCodeCall.permissionStillPending(sessionID: "ses_1", requestID: "per_1").urlRequest(service: service)
        #expect(get.httpMethod == "GET")
        #expect(get.url?.absoluteString == "http://127.0.0.1:49374/api/session/ses_1/permission/per_1")
        #expect(get.value(forHTTPHeaderField: "Authorization") == service.authorization)
        #expect(OpenCodeCall.events.urlRequest(service: service).url?.path == "/api/event")
        #expect(OpenCodeCall.sessions(limit: 20).urlRequest(service: service).url?.absoluteString
                == "http://127.0.0.1:49374/api/session?limit=20&order=desc")
        #expect(OpenCodeCall.pendingForms(sessionID: "s").urlRequest(service: service).url?.path == "/api/session/s/form")

        let reply = OpenCodeCall.replyPermission(sessionID: "s", requestID: "r", decision: "reject", message: "no")
            .urlRequest(service: service)
        #expect(reply.httpMethod == "POST")
        #expect(reply.url?.path == "/api/session/s/permission/r/reply")
        #expect(reply.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: reply.httpBody!) as! [String: Any]
        #expect(body["decision"] as? String == "reject")
        #expect(body["message"] as? String == "no")

        let form = OpenCodeCall.replyForm(sessionID: "s", formID: "f", answer: ["q0": "Rojo"]).urlRequest(service: service)
        #expect(form.url?.path == "/api/session/s/form/f/reply")
        let fbody = try JSONSerialization.jsonObject(with: form.httpBody!) as! [String: Any]
        #expect(fbody["answer"] as? [String: String] == ["q0": "Rojo"])
    }

    private func card(_ kind: OpenCodeCardRequest.Kind) -> OpenCodeCardRequest {
        var core = OpenCodeBridgeCore()
        let fixture = kind == .form ? OpenCodeFixtures.formCreated : OpenCodeFixtures.permissionShell
        let out = core.handle(OpenCodeEvent.decode(fixture)!,
                              settings: .init(autoMode: false, allowList: AlwaysAllow(), paths: ruleContext.paths),
                              now: Date())
        guard case let .showCard(c)? = out.first else { fatalError("fixture produced no card") }
        return c
    }

    @Test func answerMapping() {
        let p = card(.permission)
        #expect(OpenCodeAnswer.call(for: p, decision: "allow", reason: nil, answers: nil)
                == .replyPermission(sessionID: "ses_1", requestID: "per_1", decision: "once", message: nil))
        #expect(OpenCodeAnswer.call(for: p, decision: "deny", reason: nil, answers: nil)
                == .replyPermission(sessionID: "ses_1", requestID: "per_1", decision: "reject",
                                    message: "El usuario lo rechazó desde el buddy."))
        #expect(OpenCodeAnswer.call(for: p, decision: "deny", reason: "mejor no", answers: nil)
                == .replyPermission(sessionID: "ses_1", requestID: "per_1", decision: "reject", message: "mejor no"))
        #expect(OpenCodeAnswer.call(for: p, decision: "pass", reason: nil, answers: nil) == nil)

        let f = card(.form)
        #expect(OpenCodeAnswer.call(for: f, decision: "answer", reason: nil, answers: ["¿Qué color prefieres?": "Azul"])
                == .replyForm(sessionID: "ses_1", formID: "frm_1", answer: ["q0": "Azul"]))
        #expect(OpenCodeAnswer.call(for: f, decision: "pass", reason: nil, answers: nil) == nil)
        #expect(OpenCodeAnswer.call(for: f, decision: "deny", reason: nil, answers: nil) == nil)
    }
}
```

- [ ] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter OpenCodeAPITests`
Esperado: no compila.

- [ ] **Paso 3: implementar**

- **`OpenCodeService.load`:**
  - JSON con `url` y `password` (cadenas no vacías);
  - `URL(string:)` con `scheme == "http"` y `host` en `["127.0.0.1", "localhost", "::1"]`;
  - cualquier otra cosa da nil;
  - `defaultFile` es `~/.local/state/opencode/service.json` (con `FileManager.default.homeDirectoryForCurrentUser`).
- **`urlRequest`:**
  - rutas y métodos exactos de las restricciones globales;
  - encabezado `Authorization` en todas;
  - en los POST, `Content-Type: application/json` y cuerpo con `JSONSerialization`, con `message` solo si no es nil;
  - para `events`, `Accept: text/event-stream`.
- **`OpenCodeAnswer.call`:**

  | Tarjeta | Decisión | Llamada |
  |---|---|---|
  | Permiso | `allow` | `once` |
  | Permiso | `deny` | `reject` con `reason ?? "El usuario lo rechazó desde el buddy."` |
  | Permiso | `pass` o cualquier otra | nil |
  | Formulario | `answer` | Por cada `choice`, la etiqueta en `answers[choice.question]` se traduce al `value` de la opción con esa etiqueta, y queda `answer[choice.fieldKey] = value`. Si no queda ninguna respuesta, nil |
  | Formulario | Cualquier otra | nil |

- [ ] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter OpenCodeAPITests`
Esperado: PASA.

- [ ] **Paso 5: commit**

```bash
git add Sources/BuddyCore/OpenCode/OpenCodeAPI.swift Tests/ClaudeMenuBarBuddyTests/OpenCodeAPITests.swift
git commit -m "BuddyCore habla con el servicio local de opencode y solo con el de esta máquina"
```

---

### Tarea 7: ¿opencode está configurado para preguntar?

**Archivos:**
- Crear: `Sources/BuddyCore/OpenCode/OpenCodeConfigCheck.swift`
- Test: `Tests/ClaudeMenuBarBuddyTests/OpenCodeConfigCheckTests.swift`

**Interfaces:**
- Produce:
```swift
public enum OpenCodeConfigCheck {
    /// The effect opencode ends up with for `action` on resource "*": the last rule whose action is that action
    /// (or "*") and whose resource is exactly "*". nil when no such rule exists — opencode then allows.
    public static func effect(of action: String, inConfig text: String) -> String?
    /// True when both "shell" and "edit" end at "ask".
    public static func asksForShellAndEdit(configText: String) -> Bool
}
```

- [ ] **Paso 1: escribir los tests**

```swift
import Testing
import BuddyCore

@Suite struct OpenCodeConfigCheckTests {
    private let recommended = """
    {
      "$schema": "https://opencode.ai/config.json",
      // the buddy decides
      "permissions": [
        { "action": "shell", "resource": "*", "effect": "ask" },
        { "action": "edit",  "resource": "*", "effect": "ask" },
        { "action": "shell", "resource": "git status *", "effect": "allow" }, /* specific rules don't count */
      ],
    }
    """

    @Test func recommendedConfigAsks() {
        #expect(OpenCodeConfigCheck.effect(of: "shell", inConfig: recommended) == "ask")
        #expect(OpenCodeConfigCheck.asksForShellAndEdit(configText: recommended))
    }

    @Test func noPermissionsMeansNothingAsks() {
        #expect(OpenCodeConfigCheck.effect(of: "shell", inConfig: #"{"provider":{}}"#) == nil)
        #expect(!OpenCodeConfigCheck.asksForShellAndEdit(configText: #"{"provider":{}}"#))
    }

    @Test func lastMatchWins() {
        let text = #"{"permissions":[{"action":"shell","resource":"*","effect":"ask"},{"action":"*","resource":"*","effect":"allow"},{"action":"edit","resource":"*","effect":"ask"}]}"#
        #expect(OpenCodeConfigCheck.effect(of: "shell", inConfig: text) == "allow")
        #expect(OpenCodeConfigCheck.effect(of: "edit", inConfig: text) == "ask")
        #expect(!OpenCodeConfigCheck.asksForShellAndEdit(configText: text))
    }

    @Test func commentsInsideStringsAreText() {
        let text = #"{"permissions":[{"action":"shell","resource":"*","effect":"ask","note":"http://x // no"},{"action":"edit","resource":"*","effect":"ask"}]}"#
        #expect(OpenCodeConfigCheck.asksForShellAndEdit(configText: text))
    }

    @Test func garbageIsNotAsking() {
        #expect(!OpenCodeConfigCheck.asksForShellAndEdit(configText: "{ roto"))
    }
}
```

- [ ] **Paso 2: verificar que falla**

Corre: `swift build && swift test --filter OpenCodeConfigCheckTests`
Esperado: no compila.

- [ ] **Paso 3: implementar**

- Primero convierte JSONC a JSON con un recorrido por caracteres que sepa cuándo está dentro de una cadena (respetando `\"`):
  - quita los comentarios `//…` hasta el fin de línea y `/*…*/`, solo **fuera** de cadenas;
  - quita las comas finales, es decir, una `,` seguida solo de espacios y luego `}` o `]`.
- Luego `JSONSerialization`, el arreglo `permissions` y el último que coincida.

- [ ] **Paso 4: verificar que pasa**

Corre: `swift build && swift test --filter OpenCodeConfigCheckTests`
Esperado: PASA.

- [ ] **Paso 5: commit**

```bash
git add Sources/BuddyCore/OpenCode/OpenCodeConfigCheck.swift Tests/ClaudeMenuBarBuddyTests/OpenCodeConfigCheckTests.swift
git commit -m "BuddyCore sabe si la configuración de opencode le deja algo al buddy"
```

---

### Tarea 8: la conexión con opencode en la app

**Archivos:**
- Crear: `Sources/ClaudeMenuBarBuddy/OpenCodeBridge.swift`
- Modificar: `Sources/ClaudeMenuBarBuddy/main.swift` y `Sources/ClaudeMenuBarBuddy/CardDecision.swift`

**Interfaces:**
- Consume: todo lo de las tareas 1–7, más `AutoLog` y `DebugLog`.
- Produce:
```swift
final class OpenCodeBridge {
    enum State: Equatable { case idle, connecting, connected, unavailable(String) }
    private(set) var state: State
    init(configDir: URL)
    func start()                                   // connects; reconnects with backoff 1, 2, 4, 8, 16, 30, 30… s
    func stop()
    /// The card's decision for an opencode request (agent "opencode"). Called by writeDecision.
    func answer(id: String, decision: String, reason: String?, answers: [String: String]?)
}
// AppDelegate (main.swift):
var openCodeBridge: OpenCodeBridge?
```

La app no tiene tests de UI ni de red. La verificación es que compile, que todo siga en verde y la prueba en vivo que Claude hace con el usuario al final.

- [ ] **Paso 1: implementar `OpenCodeBridge`**

- **Todo en el hilo principal,** salvo la lectura de red: los callbacks de `URLSession` se despachan a `DispatchQueue.main`.
- **Conectar:**
  1. `state = .connecting`.
  2. `OpenCodeService.load(from: .defaultFile)`. Si es nil: `state = .unavailable("opencode no está corriendo")` y reintento en 30 s.
  3. Si no, abre `GET /api/event` con una `URLSession` propia con delegado (`URLSessionDataDelegate`), `timeoutIntervalForRequest = 120` y `timeoutIntervalForResource = 7 * 24 * 3600`.
  4. Cada `didReceive data` pasa por un `SSEParser`, luego por `OpenCodeEvent.decode` (los nil se ignoran) y luego por `handle(event)`.
  5. Al recibir la respuesta 200: `state = .connected`, el retraso de reintento vuelve a 1 s, y se hace la **recuperación**.
  6. Al terminar con error o al cerrarse el stream: `state = .connecting` y reintento con espera creciente (1, 2, 4, 8, 16, 30 s y luego 30 s).
- **Recuperación:** `GET sessions(limit: 20)`. Para cada sesión con `time.updated` (milisegundos) de las últimas 24 h:
  - `GET pendingPermissions(id)`: cada elemento se convierte en `.permissionAsked`, con `directory = location.directory` de la sesión;
  - `GET pendingForms(id)`: cada uno en `.formCreated`.

  Reusa `OpenCodeEvent.decode` armando el envoltorio `{"type":…, "location":…, "data":…}`. Un id ya conocido no se duplica: lo cuida el núcleo.
- **`handle(event)`:** arma `Settings` en cada evento:
  - `autoMode` = existe `configDir/auto_mode`;
  - `allowList` = `AlwaysAllow.read(from: configDir/always_allow.json)`;
  - `paths` = `PathPolicy.fromEnvironment(env, probe: LiveFileProbe())`, donde `env` es el entorno del proceso con `PATH` ampliado con `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin` y `~/bin`. launchd arranca la app con un PATH mínimo, y sin esto las rutas del PATH no quedarían protegidas.

  Luego ejecuta las acciones del núcleo:

  | Acción | Qué hace |
  |---|---|
  | `.autoReply` | POST `replyPermission(…, "once", nil)` y `AutoLog.append(log, in: configDir)` |
  | `.showCard` de permiso | A los 0.3 s, `GET permissionStillPending`. Con 200, escribe `configDir/request_<id>.json` (`requestFileJSON(now: Date())`, escritura atómica). Con otro código, `core.forget(id:)`. Es por el bug #47545 de opencode |
  | `.showCard` de formulario | Escribe el archivo de una vez |
  | `.withdrawCard` | Borra `request_<id>.json` |
  | `.turnFinished` | `GET session(id)`. Si `parentID` no es null, nada (es un subagente). Si no, escribe `configDir/done_<sid>.json` con `{"project": último componente de location.directory, "elapsed": N, "ts": ahora, "agent": "opencode"}` |

- **`answer(…)`:**
  1. `guard let card = core.pending(id:)`;
  2. si `OpenCodeAnswer.call(…)` no es nil, hace el POST; un 404 se ignora porque alguien ya contestó;
  3. borra `request_<id>.json`;
  4. `core.forget(id:)`.
- **Errores:** nunca tumban la app; van a `DebugLog.note` con el tipo de llamada y el código HTTP. **Nunca** la contraseña ni el encabezado `Authorization`.

- [ ] **Paso 2: conectar la app**

- **`main.swift` → `applicationDidFinishLaunching`,** después de `sweepStaleArtifacts()`:
  - borra los `request_*.json` de una corrida anterior cuyo JSON tenga `"agent": "opencode"`; el puente los vuelve a traer al reconectar;
  - `openCodeBridge = OpenCodeBridge(configDir: dirURL)` y `openCodeBridge?.start()`.
- **`main.swift` → `scanRequests()`:** la ventana de `hookAnswerWindow` (el `if let ts = req.ts, now - ts > Self.hookAnswerWindow`) aplica solo cuando `req.agent != "opencode"`.
- **`CardDecision.swift` → `respond(_:reason:)`:** la misma condición en el rechazo por ventana.
- **`CardDecision.swift` → `writeDecision(…)`:**
  - si `request?.agent == "opencode"`, llama a `openCodeBridge?.answer(id: id, decision: decision, reason: reason, answers: answers)` **en lugar de** escribir `response_<id>.json`;
  - el registro en `decisions.jsonl` y `noteDecision` siguen igual;
  - `respondToQueue` y `allowAllNonCriticalQueued` ya pasan por `writeDecision`, así que no cambian.

- [ ] **Paso 3: verificar**

Corre: `swift build && swift test`
Esperado: compila sin errores y todo en verde.

- [ ] **Paso 4: commit**

```bash
git add Sources/ClaudeMenuBarBuddy/OpenCodeBridge.swift Sources/ClaudeMenuBarBuddy/main.swift Sources/ClaudeMenuBarBuddy/CardDecision.swift
git commit -m "El buddy se conecta a opencode: sus permisos y preguntas llegan a la misma tarjeta"
```

---

### Tarea 9: tarjeta, aviso, chequeo de salud y README

**Archivos:**
- Modificar (en `Sources/ClaudeMenuBarBuddy/`): `ApprovalCard.swift`, `CardLayout.swift`, `Toast.swift`, `Health.swift` y `OpenCodeBridge.swift`
- Modificar: `README.md`

- [ ] **Paso 1: implementar**

- **`ApprovalCard.swift`:** en el encabezado, cuando `req.agent == "opencode"`, la etiqueta de proyecto muestra `opencode · <proyecto>` (y `opencode` solo si no hay proyecto). El botón de "ir a la sesión" ya no aparece solo, porque estas solicitudes no traen `host_bundle` ni `term_program`; no hay que tocarlo.
- **`CardLayout.swift` → `toolSymbol`:** agrega:

  | Herramienta | Símbolo |
  |---|---|
  | `shell` | `terminal.fill` |
  | `edit` | `pencil` |
  | `read` | `doc.text` |
  | `webfetch`, `websearch` | `globe` |
  | `question` | `questionmark.bubble.fill` |

- **`Toast.swift`:** `processDoneMarkers` lee también `agent`. El título del aviso y de la notificación es `opencode — <proyecto>` cuando `agent == "opencode"`; si no, queda como hoy (`Claude Code — <proyecto>`). Guarda el agente junto con `project` y `elapsed` en `latest`, y pásalo a `showDoneToast`.
- **`Health.swift`:** dos chequeos opcionales (`optional: true`) al final de `inspect`.
  - **`openCodeConnectionCheck()`, "opencode connection":**
    - el estado se lee de `static var openCodeState: String?`, que se declara en `BuddyHealth` (en `Health.swift`). `OpenCodeBridge` lo actualiza en cada cambio de `state` con un `didSet`: `"connected"`, `"connecting"` o `"unavailable: <motivo>"`;
    - `connected` → ok;
    - `unavailable(…)` → ok con el detalle "opencode no está corriendo" (no es una falla del buddy);
    - `connecting` → no ok, con el remedio "opencode está corriendo pero el buddy no logra conectarse; revisa ~/.local/state/opencode/service.json".
  - **`openCodeConfigCheck()`, "opencode asks before shell and edit":**
    - lee el primero que exista de `~/.config/opencode/opencode.jsonc` y `~/.config/opencode/opencode.json`;
    - sin archivo → ok con "Skipped — no global opencode config";
    - `asksForShellAndEdit` → ok;
    - si no, no ok, con este remedio (texto exacto):
      `Add to ~/.config/opencode/opencode.json: "permissions": [{ "action": "shell", "resource": "*", "effect": "ask" }, { "action": "edit", "resource": "*", "effect": "ask" }]`.
- **`README.md`:** una sección "opencode" después de la de Auto mode, que diga:
  - el buddy se conecta solo al servicio local de opencode (v2, `opencode serve --service`) y le muestra sus permisos y preguntas en la misma tarjeta, con la misma regla y el mismo modo auto;
  - qué agregar a la configuración global de opencode (el bloque de `permissions` de arriba);
  - si el buddy no está abierto, opencode pregunta en su propia terminal;
  - las solicitudes de opencode no tienen límite de tiempo.

- [ ] **Paso 2: verificar**

Corre: `swift build && swift test`
Esperado: todo en verde.

- [ ] **Paso 3: commit**

```bash
git add Sources/ClaudeMenuBarBuddy/ApprovalCard.swift Sources/ClaudeMenuBarBuddy/CardLayout.swift Sources/ClaudeMenuBarBuddy/Toast.swift Sources/ClaudeMenuBarBuddy/Health.swift Sources/ClaudeMenuBarBuddy/OpenCodeBridge.swift README.md
git commit -m "La tarjeta y el aviso dicen cuándo es opencode, y el chequeo de salud revisa la conexión y su configuración"
```

---

### Tarea 10: verificación final

- [ ] **Paso 1: todo en verde desde cero**

Corre: `swift build && swift test 2>&1 | tail -5 && shellcheck hook.sh notify-done.sh`
Esperado: `Test run with N tests passed` con N mayor que 174, ningún fallo, y `shellcheck` sin salida.

- [ ] **Paso 2: nada pendiente**

Corre: `git status --short && git log --oneline origin/personal..HEAD`
Esperado: `git status` vacío y un commit por tarea (1–9), más el del plan.

- [ ] **Paso 3: avisar y detenerse**

Escribe en el chat:
- que la entrega 2 está lista;
- cuántos tests pasan;
- lo anotado en `docs/superpowers/plans/NOTAS-EJECUCION.md`, si hay algo.

**No** instales nada, no corras la app y no hagas push. La prueba en vivo contra opencode la hace Claude con el usuario: hace falta cambiar la configuración de opencode y reiniciar el buddy.
