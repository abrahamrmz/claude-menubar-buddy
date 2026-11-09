# Notas de ejecución

Lo que no se pudo hacer tal como dice el plan, o donde el plan se contradecía. Cada nota dice la tarea, el paso, qué falló y qué se hizo.

---

## Tarea 4: `sed` y `find` no estaban en ningún conjunto, pero sus tests los piden como lectura

**Paso:** el paso 1 (tests) contra el paso 4 (implementación).

**Qué falló:** con los tres archivos que pide la tarea 4 (`RuleTypes.swift`, `CommandCatalog.swift`, `ShellRule.swift`) y sus reglas generales, tres casos de `reads` daban `desconocido`:

- `cd /Users/u/repo && sed -n 1,40p a.swift; tail -5 b.txt | wc -l`
- `find . -name '*.swift'`
- `[[ -f x ]] && cat x`

Los dos primeros porque `sed` y `find` no están en ningún `CommandCatalog`, y el paso 4 dice que sus manejadores llegan en la tarea 5 («hasta esa tarea… caen en las reglas generales», o sea desconocido). Pero el paso 5 pide que `ShellRuleTests` pase, y la spec (§5.1) también los clasifica como lectura.

**Qué se hizo (decisión del usuario):** adelantar a la tarea 4 los manejadores de `sed` y `find` tal como los define la tarea 5, para no dejar ningún commit intermedio donde `sed -i` o `find -delete` se lean como lectura. La tarea 5 añade `git`, `gh`, `ssh`, `awk` y `xargs`, más su batería adversaria. El manejador de `sed` vive en `Sources/BuddyCore/Rule/ShellRule+Commands.swift`, el mismo archivo que la tarea 5 extiende.

**`[[` en el analizador:** el caso `[[ -f x ]] && cat x` fallaba porque la tarea 2 marca `[` sin comillas como glob, y el analizador devolvía `[[` con `expands = true`; la regla, con razón, no aprueba una palabra que expande. En bash `[[` es una palabra reservada, no un glob. Se corrigió en `ShellScript.parse` (un `[` seguido de otro `[`, o pegado a uno, ya no marca `expands`), sin cambios en las interfaces públicas ni en el resto de los casos de la tarea 2.

---

## Tarea 3 (entrega 2): el caso `.fileRead` de `RuleSubject` vive en `CommandRule.swift`, no en `RuleTypes.swift`

**Paso:** el mapa de archivos de la tarea: «Modificar: `Sources/BuddyCore/Rule/RuleTypes.swift` (nuevo caso de `RuleSubject`) y `Sources/BuddyCore/Rule/CommandRule.swift`».

**Qué pasó:** el plan sitúa el caso nuevo de `RuleSubject` en `RuleTypes.swift`, pero el enum `RuleSubject` está definido en `Sources/BuddyCore/Rule/CommandRule.swift`; `RuleTypes.swift` solo contiene `RuleCategory`, `Assessment` y `RuleContext`. En Swift un caso de enum solo se puede agregar donde el enum está declarado, así que `.fileRead(path:)` se agregó en `CommandRule.swift`, junto a los demás casos.

**Qué se hizo:** el caso y su evaluación (`assessFileRead`) quedaron en `CommandRule.swift`; `RuleTypes.swift` no se tocó porque no había nada que cambiar ahí. El comportamiento y las interfaces son exactamente los del bloque de la tarea.

---

## Tarea 8 (entrega 2): dos detalles del texto del plan que no compilan tal cual

**Paso:** paso 1 (implementar `OpenCodeBridge`).

**Qué pasó:**

1. El bloque de interfaces escribe `OpenCodeService.load(from: .defaultFile)`. El parámetro es `from file: URL`, así que `.defaultFile` se busca como miembro de `URL`, y `defaultFile` en realidad es un estático de `OpenCodeService`. Tal cual, no compila.
2. El paso 1 pide «una `URLSession` propia con delegado». En Foundation, `URLSession.delegate` es de solo lectura: solo se fija al construir la sesión con `init(configuration:delegate:delegateQueue:)`. Como `self` todavía no existe antes de `super.init()`, no se puede asignar el delegado después.

**Qué se hizo (sin cambiar el diseño):** `OpenCodeService.load(from: OpenCodeService.defaultFile)`, que es lo que el plan quiere decir; y la sesión del stream se declaró `lazy` con `delegate: self`, en lugar de asignar el delegado tras `init`. Los endpoints, el ciclo de reconexión y la recuperación son los del plan, y el delegado sigue recibiendo solo los eventos del stream porque las demás llamadas van por una `URLSession` aparte.

---

## Tarea 13 (entrega 5): tres comprobaciones de lectura del paso 7 chocan con el propio plan

**Paso:** paso 7 («revisar el diff»).

**Qué pasó:** tres de las comprobaciones del paso 7 no se cumplen tal cual, pero no porque falte nada en el código — el código es exactamente el bloque que da el propio plan — sino porque sus expectativas contradicen instrucciones anteriores del mismo plan:

1. «`git grep -n "SessionGrantStore(" Sources/ClaudeMenuBarBuddy` aparece solo en `Prefs.swift`». Aparece también en `OpenCodeBridge.swift`, que es lo que el bloque 3 manda explícitamente: la línea 4248 del plan dice «`Prefs.sessionGrantStore` llega en la tarea 13; el puente tiene el suyo, sobre la misma carpeta», y la tarea 11 (paso 1) escribe `self.grantStore = SessionGrantStore(configDirectory: configDir)`.
2. «`git grep -n "sweepExpired\|grantEnded" Sources/ClaudeMenuBarBuddy` aparece solo en `SessionGrants.swift` (la tarea 14 sumará `Menus.swift`)». Aparece también en `OpenCodeBridge.swift` (bloque 3, tarea 11): al recibir `sessionEnded` el puente llama a `AutoLog.append(.grantEnded(…, cause: .sessionEnded, …))`.
3. «`git grep -n "decisions.jsonl\|writeDecision\|openCodeBridge" Sources/ClaudeMenuBarBuddy/SessionGrants.swift` no encuentra nada». Encuentra dos coincidencias, ambas en el comentario que el propio plan manda copiar textualmente (líneas 4920–4921: «never in `decisions.jsonl`, which is what you answered»). Ninguna línea de código escribe en ese archivo ni toca el puente.

**Qué se hizo:** nada en el código: se copió el bloque de `SessionGrants.swift` tal cual (verbatim), y el objetivo real de las tres comprobaciones se cumple — el barrido de la app no escribe en `decisions.jsonl`, no pasa por `writeDecision` ni por el puente de opencode, y no crea concesiones. Las expectativas de los greps quedaron desactualizadas respecto al bloque 3 y respecto al propio comentario verbatim del plan. Se deja anotado para que quien revise lo confirme; no se cambió ninguna decisión de diseño.

**Comprobaciones del paso 7 que sí se cumplen:** `openCodeBridge?.sweepCoveredCards()` va antes de `var requests = orderedRequests()`; `\.grant(` no aparece en `Sources/ClaudeMenuBarBuddy`; `sessionCoverableFlag` es `Bool?` y `session` es `String?`; `tickSessionGrants()` queda después de `if isDismissing { return }`.
