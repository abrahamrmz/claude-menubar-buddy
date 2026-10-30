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
