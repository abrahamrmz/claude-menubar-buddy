# claude-menubar-buddy — "Siguiente nivel" (roadmap en fases)

## Contexto

El fork ya replicó y superó a Masko en lo esencial (tarjetas estilizadas, hotkeys, always-allow, auto-edits, toast, límites). El usuario quiere llevarlo al siguiente nivel en 3 frentes: **productividad/automatización** (rescatar lo mejor del ecosistema: jump-to-terminal de Masko, aprobación remota, batch approve, burn-rate), **más vida para el pet** (estados nuevos + micro-comportamientos, manteniendo CPU ~0), y **UX/UI más intuitiva** (settings window, hotkeys remapeables, onboarding, ícono profesional).

Decisiones ya tomadas (research + usuario):
- **Animación**: mantener pipeline GIF+NSImageView (CPU casi cero) + Core Animation para transforms. NO SpriteKit/Lottie/Rive (8-25% CPU medido).
- **Dependencias aprobadas**: sindresorhus/KeyboardShortcuts, Defaults, Settings. (LaunchAtLogin-Modern NO sirve: requiere .app bundle; usar el LaunchAgent plist de SKILL.md.)
- **NO migrar a MenuBarExtra/SwiftUI completo**: la tarjeta no-activante (sagrada) debe seguir en AppKit; SwiftUI solo puntual (onboarding vía NSHostingView).
- El usuario eligió TODO el scope, en roadmap por fases.

Restricciones duras: CPU idle ~0 · panel no-activante intocable · build SPM-only (`swift build`, LaunchAgent → `.build/debug`) · hooks siempre aditivos (timeout → prompt nativo).

**Hallazgo del research**: `generate_species_gifs.py` apunta a `~/Downloads/claude-buddy-project/claude-desktop-buddy/` que **ya no existe** — re-clonar antes de la Fase 2.5.

---

## Fase 0 — Prerrequisito (~medio día) ✅ 2026-08-04

Agregar los 3 paquetes a `Package.swift` y partir `main.swift` (~1400 líneas) en archivos por tema:
- Nuevos: `ApprovalCard.swift`, `FloatingPet.swift`, `MoodEngine.swift`, `Toast.swift`, `Prefs.swift` (keys de Defaults espejando las de UserDefaults actuales).
- `main.swift` conserva solo bootstrap (SPM exige top-level statements ahí) + AppDelegate core + poll.

Riesgo: verificar que Defaults persiste en binario sin bundle (UserDefaults ya funciona hoy → debería).
Verificar: `swift build` limpio, relanzar, especie/posición del pet persisten, tarjeta sigue no-activante.

## Fase 1 — Quick wins (~3-4 días)

### 1.1 Hotkeys remapeables (KeyboardShortcuts) ✅ 2026-08-04
Reescribir `HotKeys.swift` con `KeyboardShortcuts.Name` (allow ⌘⏎ / deny ⇧⌘⏎ / quiet ⌥⌘⏎ / jump ⌘M), manteniendo el contrato `enable()/disable()` solo-mientras-pendiente (KeyboardShortcuts.enable/disable por nombre). Sin cambios en call-sites. El recorder UI llega en 2.1.
- Riesgo: inicialización sin bundle ID — si truena, mantener Carbon tras un flag.
- Verificar: ⌘⏎ responde con tarjeta; sin tarjeta, ⌘⏎ llega a otras apps.

### 1.2 Jump-to-terminal (⌘M + botón en header de tarjeta) ✅ 2026-08-05
El hook hereda el entorno del host: capturar en el request JSON `cwd` completo, `host_bundle` (`$__CFBundleIdentifier`: com.microsoft.VSCode, iterm2, Terminal, etc.) y `term_program` (fallback). En la app (`JumpToHost.swift` nuevo): VS Code/Cursor → `/usr/bin/open -b <bundle> <cwd>` (levanta la ventana que ya tiene esa carpeta — targeting multi-ventana sin permisos AX); terminales → `NSRunningApplication.activate()`. Botón oculto si no hay `host_bundle` (ssh/tmux). Solo en acción explícita del usuario (roba foco a propósito).
- Archivos: `hook.sh` (+sync instalado), `PendingRequest`, header de tarjeta, `JumpToHost.swift`.
- Verificar: 2 ventanas de VS Code en repos distintos → ⌘M enfoca la correcta; tarjeta sigue visible/pendiente.
- Implementado: ⌘M se habilita **solo** cuando la request trae host (si no, ⌘M sigue siendo Minimize); nombre de la app vía Launch Services (`urlForApplication`) en vez de tabla hardcodeada, y ese lookup hace de check "¿sigue instalada?"; ítem `Show in <app>` también en el menú de la barra; `decisions.jsonl` ahora guarda `host`.

### 1.3 Estados: thinking + sad/excited ✅ 2026-08-05
En `MoodEngine.swift`, prioridad nueva: `asleep(100%) > critical(85%) > thinking(turn marker) > working(transcript activo) > stressed(70%) > tired(50%) > idle`. `thinking` = turno en vuelo sin bytes nuevos (Claude procesando) vs `working` = herramientas corriendo. Flash `sad` (3s) en el completion del dismiss tras deny; `excited` cuando el refresh de 5s ve un `turn_start_*` con session id no visto (sembrar el set al arrancar para no disparar en launch).
- Poses panda nuevas en `generate_gifs.py`: `buddy_thinking` (mano en barbilla), `buddy_sad`, `buddy_excited`. Especies: fallback a `_idle` ya existe (`gifName(for:mood:)`); stressed/critical reusan tired/sleepy hasta 2.5.
- Verificar: prompt → thinking en ≤5s; `sleep 20` en tool → working; deny → flash sad; sesión nueva → excited una vez.
- Implementado: thinking/working NO se distinguen por "bytes nuevos" (una herramienta larga deja el transcript igual de callado que el modelo pensando) sino leyendo el último registro del transcript más reciente — `assistant` con `tool_use` = herramienta corriendo, `user`/tool_result = el modelo es lo que se espera. Lectura de cola de 64KB cacheada por (path, size), solo cuando hay turno en vuelo. `gifName` pasó de fallback plano a cadena de candidatos (`stressed→tired`, `critical→sleepy→tired`, `excited→celebrate→heart`, `sad→tired`) para que las 18 especies degraden a algo con sentido, no a idle. Fix de paso: `TIRED`/`SLEEPY` tenían filas de 17 celdas (se renderizaban 1 celda más anchas que el resto).
- Verificado en vivo vía selfies del pet + comparación contra los GIFs: working ✓, thinking ✓, excited ✓ (aparece ~3s y revierte solo). `sad` queda cableado — se verá en el próximo deny real.

### 1.4 Ícono template + accesibilidad ✅ 2026-08-05
Sustituir `🐼✏️N` por imagen template generada en código (SF Symbol pawprint o silueta 18x18 programática, `isTemplate = true`) + count como `button.title` (`variableLength`); pending = símbolo con badge naranja; auto-edits = overlay lápiz. Key de Defaults "Icon style: Emoji/Template" para conservar el look actual. `setAccessibilityLabel` en status button, tarjeta, pills, pass button, pet.
- Verificar: dark/light adapta; VoiceOver (⌘F5) lee los controles.
- Implementado: silueta de panda dibujada con NSBezierPath (orejas + cabeza rellenas, ojos *recortados* del mask con `.clear` — la inversión es lo que la hace reconocible en monocromo; un blob sólido sería un círculo). Pending no lleva badge separado: el template completo se tiñe de naranja vía `contentTintColor` **y** el panda abre los ojos (mismo idioma visual que el GIF `_pending`), porque el color solo no es señal para todo mundo. Auto-edits compone un SF Symbol `pencil` al lado en el mismo lienzo. Los 3 call-sites que escribían `statusItem.button?.title` a mano ahora pasan por un solo `applyStatusIcon`. Nuevo flag de debug `capture_icon` → `icon_selfie.png` con las 3 variantes a 6x.
- Default = template (el entregable de la fase); `Menu Bar Icon ▸ Panda emoji` regresa al look anterior.
- Verificado: render real de la app vía `capture_icon` ✓. El menú bar en vivo NO se pudo capturar (TCC bloquea `screencapture` desde este proceso) — confirmación visual queda del lado del usuario. VoiceOver tampoco es automatizable desde aquí.

### 1.5 Burn-rate v1 ✅ 2026-08-05
En `UsageStats.swift`: `readPlanUsage` devuelve samples recientes (no solo `.last`). Con datos frescos: fit lineal de `fh` sobre ≤60 min (≥3 samples, ≥10 min spread) → `"▲ 12%/h · 90% ≈ 16:40"` + notificaciones proyectadas 75/90% (keys `notifiedProj75/90`, patrón `checkThreshold`). Con datos stale: solo velocidad de tokens de transcripts (`velocitySamples` ring buffer en memoria, poda 2h, guarda contra rollover del día) → `"~120K tok/h (plan % stale)"`, sin proyección.
- Archivos: `UsageStats.swift`, `burnLineItem` en menú.
- Verificar: con Desktop abierto muestra slope plausible; sin Desktop degrada a velocidad sin notificar.
- **Lo que el plan no contemplaba: el rollover de la ventana.** En los datos reales del 4-ago `fh` cayó 78 → 3 en 9 minutos. Un fit que cruce ese salto reporta una pendiente absurdamente negativa. `fiveHourSlope` recorta a las muestras posteriores al último reset (caída > 10 puntos entre consecutivas) antes de ajustar. Verificado: el mismo tramo de subida, con y sin el rollover a la vista, da la pendiente **idéntica** (34.8%/h) — solo posible si las muestras previas se descartaron.
- Notificaciones: una sola key en memoria (`notifiedProjection`, no dos en Defaults) que guarda el nivel más alto ya avisado y se resetea sola al detectar rollover. En memoria a propósito: una proyección solo significa algo mientras la app está observando, y un buffer cosido a través de un reinicio mediría un hueco.
- Proyección con dos topes: pendiente ≥ 0.5%/h (abajo de eso no es señal) y ETA ≤ 5h (más allá, la ventana ya habrá rotado — proyectar 14h es ficción).
- Extra: `"Burn: measuring…"` mientras el buffer junta sus 10 min, en vez de un guion que se lee como "roto" tras cada reinicio.
- Verificado: matemática con tests aislados sobre los shapes reales (rollover, plano, recuperando, muestras insuficientes, spread corto, fuera de ventana) ✓. Camino en vivo: los datos del usuario están stale (Desktop cerrado) → cae al fallback de tokens, como debe. El camino con datos frescos necesita Claude Desktop abierto para verse en vivo.

**Fase 1 completa** (1.1 ✅ · 1.2 ✅ · 1.3 ✅ · 1.4 ✅ · 1.5 ✅).

## Fase 2 — Features grandes (~7-10 días)

### 2.1 Settings window + adelgazar menú ✅ 2026-08-05
`sindresorhus/Settings`, 3 tabs: **Behavior** (recorders de hotkeys, umbral de toast, umbrales burn-rate, Start at login vía LaunchAgent plist de SKILL.md con `launchctl bootstrap`), **Appearance** (especie, floating pet, icon style, fidgets on/off), **Safety** (auto-edits, tabla de always-allow con remove, log de decisiones, web approval + QR). El menú conserva: pet+mood, líneas de status/uso/burn, Active Sessions, Decision History, los 2 toggles de seguridad (visibles a un click: Floating Pet, Auto-approve Edits), `Settings…`, `Quit`. Fallback si Settings falla sin bundle: NSWindow + NSTabViewController.
- Verificar: cada toggle migrado hace round-trip (flag files siguen moviendo hook.sh); remap de hotkey aplica a la siguiente tarjeta.
- No hizo falta el fallback: `SettingsPane` es un protocolo sobre `NSViewController` y `KeyboardShortcuts.RecorderCocoa` es un `NSSearchField` — o sea, paneles AppKit puros, cero SwiftUI, consistente con el resto de la app. Los resource bundles del paquete quedan junto al binario en `.build/debug`, así que `Bundle.module` resuelve sin `.app`. Solo se sobrescribe el título de la ventana (sin bundle no hay `CFBundleName` de dónde armarlo).
- **Start at login solo escribe/borra el plist, sin `launchctl`.** `bootout` mataría al proceso que ejecuta ese mismo código (la app *es* ese job), y `bootstrap` sobre una copia lanzada a mano pondría dos pandas en la barra. El archivo es lo que launchd lee en el próximo login, que es exactamente lo que el toggle promete.
- Fuera de alcance por no existir aún: fidgets on/off (Fase 3.1) y web approval + QR (2.3) — un toggle muerto sería peor que su ausencia.
- Adelgazado: se fueron `Choose Buddy`, `Menu Bar Icon` y `Auto-allowed Commands`; entró `Settings…` (⌘,). Los 2 grants permanentes se quedan en el menú a propósito: cambian lo que la app hace *sin preguntar*.
- Verificado: los 3 paneles renderizados desde la app real (nuevo flag `capture_settings` → `settings_selfie.png`, que a propósito NO abre la ventana para no robar foco), leyendo estado real (especie "cat", auto-edits on, la lista de always-allow del usuario, los 4 atajos). Instancia de prueba con la ventana abierta sobrevivió sin crash. La ventana en vivo no es capturable (TCC).
- Gotcha documentado en SKILL.md: el primer `kickstart` justo después de `swift build` se lleva un SIGKILL de code-signing (launchd corrió contra el binario a medio reemplazar). Correrlo de nuevo basta; confirmar siempre con `pgrep`.

### 2.2 Decisiones a/b/c en el card (AskUserQuestion + ExitPlanMode) ✅ 2026-08-05
**Agregado 2026-08-05 a petición del usuario.** Hoy, cuando Claude pregunta con opciones, el buddy solo sabe allow/deny — así que esas decisiones lo mandan de vuelta a VS Code, el mismo dolor que teníamos con los comandos de `gh` antes del always-allow.

**Viabilidad verificada empíricamente** (sonda con hook temporal, `settings.json` restaurado idéntico después):
1. `AskUserQuestion` **sí** dispara `PreToolUse`. Su `tool_input` trae todo lo que el card necesita: `questions[]` con `question`, `header`, `multiSelect` y `options[]` de `{label, description}`.
2. **Hay vía limpia, no hace falta el hack de "deny con razón".** La herramienta tiene un campo propio `answers` ("User answers collected by the permission component") y los hooks `PreToolUse` pueden devolver `updatedInput`. Un hook que responde `permissionDecision: "allow"` + `updatedInput: (tool_input + {answers: {"<pregunta>": "<label elegido>"}})` hace que la herramienta corra **con la respuesta ya puesta**: sin picker nativo, y Claude recibe un tool result normal, no un tool bloqueado. Probado end-to-end: la sonda inyectó la segunda opción y eso fue exactamente lo que volvió.

Trabajo real:
- `settings.json`: agregar el matcher `AskUserQuestion` (aditivo como siempre).
- `hook.sh`: para ese tool, volcar `questions` al request JSON; el response file crece de `{"decision":"allow"}` a `{"decision":"answer","answers":{…}}`; emitir el `updatedInput`. Timeout → `{}` → picker nativo, igual que hoy.
- `PendingRequest` + card: un botón por opción (label arriba, `description` como subtítulo) en vez de Allow/Deny; alto variable; ⌘1..⌘4 para elegir (**coordinar con el ⌘1-9 de 2.3**).
- `ExitPlanMode` de paso: sus tres opciones nativas ya mapean a acciones que el buddy tiene — auto-accept = allow + flag de auto-edits, manual = allow, seguir planeando = deny. Tres botones reales en vez del ↗.

Estimado: **~1 día** para el caso que cubre casi todo (1 pregunta, single-select, 2-4 opciones). Otro día para los bordes: varias preguntas por llamada (la herramienta permite hasta 4), `multiSelect` con checkboxes, y el "Other" de texto libre — ese último probablemente NO va al card y se queda con el ↗ a VS Code, que es donde se escribe cómodo.

Sin verificar todavía: inyectar respuestas para **varias** preguntas en una sola llamada, y qué pasa si se responden solo algunas.

- Verificar: pregunta de 3 opciones → 3 botones; elegir la 2 devuelve esa a Claude sin picker nativo; sin buddy corriendo, el picker aparece normal.

**Implementado 2026-08-05** (salió en un día, no dos — el caso de varias preguntas resultó barato):
- La tarjeta de opciones **no lleva Allow/Deny**. Responder no es aprobar: no hay un "no" que dar, y ofrecerlo solo serviría para que te vuelvan a preguntar. La salida sigue siendo el ↗ del header (que es donde además se escribe el "Other" de texto libre).
- Varias preguntas por llamada: se recorren de una en una (`choiceIndex` + `collectedAnswers`), el título muestra "2 of 3", y **solo la última responde** — la herramienta toma un único mapa de respuestas.
- `multiSelect` no llega a la tarjeta: `hook.sh` devuelve `{}` de inmediato y sale el picker nativo. Checkboxes + confirmar es otra interacción; media respuesta habría sido peor que ninguna.
- El response file creció de `{"decision":"allow"}` a admitir `reason` (que el hook pasa como `permissionDecisionReason`) y `answers`. `respond()` ya arma JSON de verdad en vez de concatenar strings.
- **ExitPlanMode salió casi gratis**: sus tres opciones caen en los tres atajos que ya existían — ⌘⏎ "sí, apruebo cada edit", ⌥⌘⏎ "sí, y auto-accept desde aquí" (el quiet row, que antes mandaba a VS Code), ⇧⌘⏎ "no, sigamos planeando" — este último un deny con razón, para que Claude sepa que refine el plan en vez de adivinar por qué lo rechazaron.
- Atajos ⌘1-⌘4 solo mientras hay tarjeta de opciones (⌘1-9 de la 2.3 tendrá que convivir: mismo espacio de teclas).
- `decisions.jsonl` guarda `answers` — "answer" a secas no diría nada sobre qué se eligió en nombre del usuario.
- Ajustes tras ver la primera captura: chip índigo + `questionmark.bubble.fill` propios (salía el "?" genérico), y alto de cada botón calculado con su descripción medida — se cortaban con "…" justo donde empiezan a servir para decidir.
- **Verificado en vivo, dos rondas**: 1 pregunta / 2 opciones ✓ y 2 preguntas / 3 y 2 opciones ✓ (el usuario confirmó que encadenaron sin volver al picker), con las respuestas correctas en `decisions.jsonl` y capturas de la tarjeta en ambas. Round-trip del hook probado aislado (request con `choices` → response `answer` → `updatedInput` correcto) y el bypass de `multiSelect` → `{}`.
- Sin verificar todavía: la tarjeta de tres vías de `ExitPlanMode` (hace falta entrar en modo plan).

### 2.3 Batch approve + selección de cola
⌘1..9 en **Carbon** dinámico (solo mientras `queued > 0`; no vale la pena 9 nombres remapeables). ⌘k fija `pinnedRequestId` que `poll()` ordena al frente. El badge `+N` se vuelve botón → `NSMenu.popUp` (funciona desde panel no-activante) listando la cola (`"⌘2 Bash — proyX: git push…"`) + `Allow all (N)` / `Deny all (N)`. Allow-all con confirmación de doble-click ("Really allow N?"), escribe N response files + N entradas de log, un solo dismiss.
- Verificar: 3 requests en cola; ⌘2 intercambia tarjeta; Allow all libera los 3 hooks.

### 2.4 Aprobación remota web local + QR
`WebApprovalServer.swift` (~250 líneas) con **Network.framework NWListener** (cero deps). Rutas: `GET /?t=<token>` (HTML self-contained con JS que pollea `GET /pending` cada 2s) y `POST /decide` `{id, decision}` → hop a main queue → mismo `respond()` (anima la tarjeta también y evita double-answer vía respondedIds). Token 128-bit regenerado por enable, puerto asignado por sistema, bind LAN; QR (CoreImage CIQRCodeGenerator) en Settings/menú. **Off por defecto**; listener ni se crea si está apagado (CPU 0). Sin TLS: aceptable por token + LAN + off-by-default + peor caso = aprobar un request visible (documentarlo).
- Riesgo: firewall de macOS puede preguntar por el binario sin firmar (documentar en SKILL.md).
- Verificar: QR desde el cel → request aparece ≤2s; Allow en el cel dismissa la tarjeta con ✓; disable → puerto cerrado.

### 2.5 Liberar poses del firmware + escalera stressed/critical
Re-clonar `anthropics/claude-desktop-buddy`; parametrizar `SRC_DIR` en `generate_species_gifs.py`; descubrir poses: `grep -ho 'static void do[A-Za-z]*' src/buddies/*.cpp | sort -u` (hoy solo se extraen doIdle/doAttention/doBusy/doDizzy/doSleep/doHeart/doCelebrate) y mapear doSad/doThink/etc. a los moods nuevos. Extender `first_array_in_function` para tomar TODOS los arrays de cada función → GIFs de 2-4 frames reales. Escalera: 50 tired · 70 stressed (pose nueva o doBusy acelerado) · 85 critical (doDizzy) · 100 asleep. Panda: dibujar stressed/critical en `generate_gifs.py`.
- Verificar: regeneración sin skips, build, forzar cada mood con plan-usage falso y ciclar especies.

### 2.6 Onboarding first-run
`Onboarding.swift`: SwiftUI en NSHostingView dentro de NSWindow normal (puede activar la app, ok). 3-4 páginas: qué es → check de instalación del hook (verifica settings.json + hook.sh, botón "copy snippet", NUNCA auto-edita config de Claude) → hotkeys → tour del pet. Gate: `Defaults[.onboardingCompleted]`.
- Verificar: borrar la key → aparece una vez; check del hook refleja realidad.

## Fase 3 — Pulido (~3-4 días)

### 3.1 Fidgets ambientales (solo Core Animation)
En `floatingImageView.layer`: bob = CABasicAnimation `transform.translation.y` ±2pt/3.5s autoreverse infinito (GPU, gratis); varianza = Timer de baja frecuencia (jitter 30-90s) que dispara squash de 0.2s (`scale.y` 0.94) para romper el metrónomo; cursor = NSTrackingArea (event-driven, cero polling) → scale-up + heart ocasional. **Pausado obligatorio**: remover animaciones en `hideFloatingPet()` y `windowDidChangeOcclusionState` (!visible); re-agregar al mostrar. Kill-switch "Calm pet" en Appearance.
- Riesgo: layer-backing puede afectar el render del GIF — probar `animates` con layer.
- Verificar: Activity Monitor: CPU idle igual que hoy con pet visible; 0.0% oculto/tapado.

### 3.2 Pulido final
Accesibilidad de la página web (botones reales, aria-live), campo `"via":"web"` en decisions.jsonl, copy de Settings, README + SKILL.md (campos nuevos del hook, nota de firewall, start-at-login por LaunchAgent), muestreo de CPU con `/usr/bin/time -l`.

---

## Grafo de dependencias

```
Fase 0 ✅ ─► 1.1 ✅ ─► 2.1 ✅ ─► 2.6
        ├─► 1.3 ✅ ─► 2.5 ─► 3.1
        ├─► 1.4 ✅ ─► 3.2
        ├─► 1.5 ✅ ─► 2.1 (config umbrales) ✅
        └─► 1.2 ✅ (campos hook) ─► 2.2, 2.4 (JSON más rico)
2.2 depende de 1.2 (el request JSON crece otra vez) · comparte espacio de atajos con 2.3
2.3 solo depende de 1.1 · 2.4 independiente salvo QR-en-Settings
2.5 bloqueado por re-clone del firmware
```
Camino crítico: 0 → 1.1 → 2.1 → 2.6 (los tres primeros ya cerrados). Restante: **~9-12 días** (2.3/2.4/2.5 paralelizables).

**Renumeración 2026-08-05**: entró 2.2 (decisiones a/b/c) a petición del usuario y todo lo que seguía corrió un lugar (batch approve 2.2→2.3, web+QR 2.3→2.4, firmware 2.4→2.5, onboarding 2.5→2.6).

## Verificación end-to-end (por fase)

- Cada item lleva su verificación arriba; además, al cerrar cada fase: `swift build` + `launchctl kickstart -k` + inyección de request de prueba (avisada) + selfie de tarjeta (`capture_card`/`capture_pet` flags) + revisión de CPU en reposo + commit/push por paquete de features como venimos haciendo.
- Los hooks instalados (`~/.config/claude-menubar-buddy/`) se sincronizan con `cp` en cada cambio de hook.sh/notify-done.sh.
