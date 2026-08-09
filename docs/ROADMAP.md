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

### 2.3 Batch approve + selección de cola ✅ 2026-08-06
⌘1..9 en **Carbon** dinámico (solo mientras `queued > 0`; no vale la pena 9 nombres remapeables). ⌘k fija `pinnedRequestId` que `poll()` ordena al frente. El badge `+N` se vuelve botón → `NSMenu.popUp` (funciona desde panel no-activante) listando la cola (`"⌘2 Bash — proyX: git push…"`) + `Allow all (N)` / `Deny all (N)`. Allow-all con confirmación de doble-click ("Really allow N?"), escribe N response files + N entradas de log, un solo dismiss.
- Verificar: 3 requests en cola; ⌘2 intercambia tarjeta; Allow all libera los 3 hooks.

**Implementado 2026-08-06:**
- **Sin Carbon crudo.** El plan sugería Carbon dinámico para no meter 9 nombres remapeables, pero los nombres de KeyboardShortcuts no tienen por qué salir en la ventana de Settings — se agregaron `queue1..queue9` y simplemente no se exponen en los recorders. Un solo mecanismo de atajos en toda la app.
- **El choque ⌘1-4 se resolvió por exclusión, no por teclas nuevas**: `enable(jump:choices:queue:)` fuerza `queue = 0` cuando hay opciones en pantalla. Nunca están vivos los dos sentidos a la vez, y con tarjeta de opciones la cola sigue accesible por el badge.
- **Sin ⌘K.** El plan lo pedía para fijar la tarjeta actual, pero `poll()` ordena por antigüedad y solo reemplaza si `first.id != currentRequestId` — una request nueva jamás puede desplazar a la de enfrente. No arreglaba nada; elegir de la cola ya fija (`pinnedRequestId`).
- **Confirmación por submenú, no por diálogo.** Un `NSAlert` activaría la app y robaría el foco, que es justo lo que la tarjeta existe para evitar. El submenú pregunta lo mismo sin nada de eso. Los títulos llevan "…" (convención de macOS para "falta un paso") porque un ítem con submenú ignora el click directo y sin eso se siente roto.
- `respond()` se partió en `writeDecision()` (archivo de respuesta + línea de log + limpieza) y la animación: el lote hace lo primero N veces y lo segundo una sola.
- Sin Ping al cambiar de tarjeta a mano (`switchingCardByHand`) — no hay que avisarle de una tarjeta que acaba de pedir.
- **Verificado en vivo con 3 requests reales concurrentes** (llamadas paralelas de verdad, no archivos inyectados): badge `+2 ▾` ✓, el menú emerge desde el panel no-activante sin robar foco ✓ (era el riesgo técnico del plan), y `Allow all` dejó las 3 en `decisions.jsonl` **con 1 ms entre ellas** — a mano habían sido 4 s y 1.4 s.
- Sin verificar: ⌘2/⌘3 para intercambiar tarjeta (el usuario usó el menú).

### 2.4 Aprobación remota web local + QR — ⏸ pospuesta (2026-08-06, decisión del usuario)
Sigue viva y sin cambios; solo deja de ser la siguiente en la fila. Es la más independiente de todas, así que puede retomarse en cualquier momento sin arrastrar nada.

`WebApprovalServer.swift` (~250 líneas) con **Network.framework NWListener** (cero deps). Rutas: `GET /?t=<token>` (HTML self-contained con JS que pollea `GET /pending` cada 2s) y `POST /decide` `{id, decision}` → hop a main queue → mismo `respond()` (anima la tarjeta también y evita double-answer vía respondedIds). Token 128-bit regenerado por enable, puerto asignado por sistema, bind LAN; QR (CoreImage CIQRCodeGenerator) en Settings/menú. **Off por defecto**; listener ni se crea si está apagado (CPU 0). Sin TLS: aceptable por token + LAN + off-by-default + peor caso = aprobar un request visible (documentarlo).
- Riesgo: firewall de macOS puede preguntar por el binario sin firmar (documentar en SKILL.md).
- Verificar: QR desde el cel → request aparece ≤2s; Allow en el cel dismissa la tarjeta con ✓; disable → puerto cerrado.

### 2.5 ✅ Liberar poses del firmware + escalera stressed/critical
Re-clonar `anthropics/claude-desktop-buddy`; parametrizar `SRC_DIR` en `generate_species_gifs.py`; descubrir poses: `grep -ho 'static void do[A-Za-z]*' src/buddies/*.cpp | sort -u` (hoy solo se extraen doIdle/doAttention/doBusy/doDizzy/doSleep/doHeart/doCelebrate) y mapear doSad/doThink/etc. a los moods nuevos. Extender `first_array_in_function` para tomar TODOS los arrays de cada función → GIFs de 2-4 frames reales. Escalera: 50 tired · 70 stressed (pose nueva o doBusy acelerado) · 85 critical (doDizzy) · 100 asleep. Panda: dibujar stressed/critical en `generate_gifs.py`.
- Verificar: regeneración sin skips, build, forzar cada mood con plan-usage falso y ciclar especies.

**Reconocimiento previo 2026-08-06** (leído `cat.cpp` vía la API de GitHub, sin clonar todavía). El repo sigue público y tiene los 18 `.cpp`, pero **el supuesto del plan es falso**:
- Poses que existen: `doIdle`, `doAttention`, `doBusy`, `doCelebrate`, `doDizzy`, `doHeart`, `doSleep`. **No hay `doSad` ni `doThink`** — no hay poses nuevas que "liberar". Working/thinking/sad/excited para las 17 especies no salen de aquí: o se dibujan a mano, o se mapean con criterio (`doBusy`→working es el candidato natural).
- Lo que sí hay y estamos tirando: **5 a 10 arrays de frames por pose** (45 en total en `cat.cpp`), de los que `first_array_in_function` toma uno. Peor aún, el guardado es `append_images=[img]` — el mismo frame dos veces. **Las 17 mascotas ASCII hoy son estampas, no animaciones.**

Así que el objetivo real se reordena, y el primer punto es el grande:
1. **Que las 17 se muevan.** No agrega un mood: mejora de golpe los siete que ya tienen.
2. **Cerrar la escalera**: dibujar stressed/critical para el panda, y reacomodar el mapeo de especies — hoy `doBusy`=tired y `doDizzy`=sleepy es arbitrario; `doDizzy` (mareado) describe mucho mejor a `critical`.
3. Aceptar que working/thinking/sad/excited seguirán siendo exclusivos del panda salvo que se dibujen. **Importante para el usuario: usa "cat", así que hoy no ve nada de la Fase 1.3.**

Prerequisitos: re-clonar, parametrizar `SRC_DIR` (para que no vuelva a pudrirse), y Pillow — no está instalado en la máquina del usuario; en 1.3 se usó un venv desechable.

- Implementado 2026-08-06: la estructura del firmware resultó **más recuperable de lo previsto**. Cada pose no es sólo "varios arrays": es `P[]` (tabla de sprites) + `SEQ[]` (la coreografía real, con repeticiones) + a veces un array de offset por beat, y `beat = (t/D) % sizeof(SEQ)` con `TICK_MS = 200`. Así que las mascotas se mueven **exactamente como en el hardware**, al mismo tempo, en vez de con 2-4 frames inventados. 4108 frames sobre 228 combinaciones especie×mood, cero estampas.
- Dos bugs de parseo, misma clase — el regex no distinguía literal de código: (a) el conteo de llaves moría dentro de `"}}~(______)~{{"`, que dejó a **axolotl sin generar desde siempre** (18 `.cpp` → 17 especies); (b) `[^;]*?` cortaba en el `;` de `" (   ;;   ) "`, perdiendo un sprite de `chonk`. Ahora son 19 especies.
- Mapeo final, con el tempo como segundo eje (idiomático: el propio firmware corre `doCelebrate` a `t/3` y las poses calmas a `t/5`): idle=doIdle · pending=doAttention · working=doBusy · **tired=doIdle a 1.7×** · **stressed=doBusy a 0.6×** · **critical=doDizzy** · asleep=doSleep · heart · celebrate. `sleepy` era el placeholder de `critical` y desapareció (era inalcanzable desde `petMood`).
- De regalo: cada especie declara su color RGB565 y se estaba ignorando. Ahora el gato es atigrado, el axolotl rosa, el dragón rojo. Los grises puros (ghost/goose/rabbit/robot) se bajan a 168 para que no se borren sobre un menú claro — eso ya pasaba con las 18 cuando todas eran blancas.
- `SRC_DIR` → env `BUDDY_FIRMWARE_SRC`, y si no está clona solo en `.build/firmware` (ya gitignoreado). Corre en un checkout limpio sin setup.
- CPU medido A/B (12 muestras instantáneas de 5s cada una, antes y después): **~1.1% en ambos**. No hay regresión — de hecho el beat del firmware (1000ms) redibuja menos que las estampas viejas (500ms).

### 2.6 ✅ Onboarding first-run
`Onboarding.swift`: SwiftUI en NSHostingView dentro de NSWindow normal (puede activar la app, ok). 3-4 páginas: qué es → check de instalación del hook (verifica settings.json + hook.sh, botón "copy snippet", NUNCA auto-edita config de Claude) → hotkeys → tour del pet. Gate: `Defaults[.onboardingCompleted]`.
- Verificar: borrar la key → aparece una vez; check del hook refleja realidad.

**Reorientación 2026-08-08 (aprobada por el usuario).** La premisa del plan era un instalador manual, pero el camino documentado es SKILL.md: Claude Code genera los GIFs, compila, instala `hook.sh`, fusiona `settings.json` y lanza la app. Para el primer arranque **ya está todo instalado**, así que una página "copia este snippet" resuelve un problema que el camino principal ya resolvió. Se invirtió a **diagnóstico, no instalador**: `Health.swift` lee la realidad y sólo ofrece el remedio cuando el check falla — y eso sirve para siempre, no sólo el primer día.

- Implementado 2026-08-08. **AppKit, no SwiftUI**, en contra del plan: SwiftUI + `NSHostingView` sí compila en este binario sin bundle (verificado, no asumido), pero la razón que da `SettingsWindow.swift` para quedarse en AppKit aplica igual, y el tour del pet son GIFs animados, que AppKit da nativo.
- Cinco checks: hook instalado y ejecutable · wiring real en `settings.json` (parsea el JSON, cuenta `Edit|Write` como dos, ignora hooks ajenos, nombra los matchers faltantes) · `jq` — buscado en rutas conocidas, **no en `$PATH`**, porque launchd le da a este proceso un PATH mínimo mientras el hook corre con el entorno de Claude Code · deriva entre el `hook.sh` del repo y el instalado · `notify-done.sh` (opcional).
- **El check encontró un problema real en su primer uso**: al `hook.sh` instalado le faltaba el `mkdir -m 700` del commit de seguridad `f7962c2` — el endurecimiento estaba a medias desde entonces. Sincronizado.
- El menú gana una línea `⚠︎ Setup needs attention…`, oculta salvo que haya un fallo **bloqueante** (los opcionales no la disparan). Es la paga de la reorientación: la app se ve idéntica con el hook cableado o no.
- Gate: se marca completo **al mostrar**, no al terminar. El LaunchAgent arranca en cada login, y un gate que sólo cierra al llegar a la última página le robaría el foco cada mañana a quien la cierre antes. Cuesta que un crash en el primer arranque se coma el onboarding — aceptable, porque se reabre desde el menú.
- Verificado: `kickstart` limpio con la key borrada → ventana 580x548 en layer 0 (vía `CGWindowListCopyWindowInfo`, no a ojo); segundo arranque → sólo icono y pet. Los tres modos de fallo del wiring (parcial / ausente / JSON roto) probados con configs fabricadas contra un binario aislado; por eso `inspect(claudeSettings:)` toma la ruta como parámetro.
- Layout: la página 1 se encimaba porque un `NSBox` y un contenedor `NSView` no tienen ancho intrínseco, y un `NSStackView` vertical dimensiona por eso. La regla quedó dicha una vez en `page(_:)` — cada fila se ancla al ancho de la página.

### 2.7 ✅ No ir a ciegas cuando Claude Code se actualiza
No estaba en el plan; salió de una conversación (2026-08-08). Dependemos de cuatro superficies de Claude Code y ninguna nos debe compatibilidad: el contrato del hook (incluido `updatedInput` + el campo `answers` de AskUserQuestion, que **descubrimos empíricamente** y no está documentado), el formato del transcript (`message.usage.output_tokens`, `content[].type == "tool_use"`), el `plan-usage-history.json` que escribe **otra app** (Claude Desktop), y la lista de herramientas que piden permiso.

Las aprobaciones nunca se rompen — los hooks son aditivos, si el nuestro falla aparece el prompt nativo. Lo que estas tres verificaciones atrapan es el daño callado: un contrato que se mueve debajo y la app siguiendo tan campante mientras deja de tener razón. Todas son `optional`, así que ninguna dispara la advertencia del menú.

1. **Ancla de versión.** Guarda contra qué serie de Claude Code validamos (`verified_claude_version` en el dir de config) y avisa cuando cambia. **Sólo major.minor**: Claude Code publica parches constantemente y un aviso que grita en cada uno se desaprende en una semana. `claude --version` cuesta 0.66s en frío, así que se calienta en background al arrancar — nunca en `menuWillOpen`. Botón para marcar la versión nueva como revisada: registra tu criterio, no inventa uno.
2. **Aserciones de forma.** Lee el último registro `assistant` del transcript más reciente (cola de 256KB, no el archivo entero: pesan decenas de MB) y comprueba que siguen ahí los campos que leemos, nombrando cuál se movió y qué deja de funcionar.
3. **Herramientas que van por fuera de la tarjeta.** Los nombres se cosechan **gratis** dentro de `tokensFromLine`, que ya está parseando esa línea para contar tokens — escanear aparte serían ~95MB de transcripts (medido). Se acumulan en `seen_tools.json`, se escribe sólo cuando aparece un nombre nuevo. Contra `expectedMatchers` y una lista explícita de `deliberatelyUngated` (sólo-lectura y bookkeeping), lo que sobra se reporta. Es la clase entera del problema AskUserQuestion, resuelta sola y para siempre.

- **Encontró algo en la primera corrida**: usas **WebSearch** y no la interceptamos — sí `WebFetch`, no `WebSearch`.
- Verificado con el arnés aislado (por eso `Health.swift` no llama a `UsageReader`, lee `seen_tools.json` como artefacto): las tres transiciones del ancla de versión (primera vez / misma serie / salto 1.9→2.1) y el check de herramientas con tus datos reales y con una herramienta inventada.

### 2.8 ✅ Mascota propia generada (koala cyberpunk)
Tampoco estaba en el plan; salió de una conversación (2026-08-08). El usuario quería una mascota más visual y personalizada, aceptando opciones de pago y algo más de CPU. Se evaluaron cinco herramientas (Layer AI, PixelLab, SpriteFlow, AutoSprite, spritesheets.ai) y **sólo PixelLab encaja**, por una razón que ninguna publica: nuestras 12 moods **no son ciclos de videojuego**. Sólo se solapa `idle`. Mirando el arte del panda, `BASE`/`BLINK`/`TIRED`/`SHUT` sólo difieren en las filas de los ojos — es *edición de sprite preservando estilo*, no generación de animación. Las otras cuatro ofrecen catálogos fijos de caminar/correr/atacar; AutoSprite dice explícitamente que no soporta expresiones faciales.

Decisión: **se suma como especie 20, el panda queda de respaldo.** Cuesta lo mismo y deja marcha atrás.

- **Quedarse en pixel art abarató todo**: alpha binario (medido: 2 niveles en GIF vs 8 en APNG), así que **cero cambios al pipeline**. Sin Rive (probado: su XCFramework sí carga sin `.app` bundle, pero suma 12 MB y sube el mínimo a macOS 13.1), sin APNG, sin cambio de CPU.
- **Endpoint correcto: `create-character-state`, no `inpaint-v3`.** Cuestan **lo mismo** (20 generaciones, medido — mi hipótesis de que inpaint sería más barato era falsa), pero inpaint sólo ve una máscara y borró el implante biónico: 90 → 37 píxeles cian. `create-character-state` recibe el `character_id`, y por eso conserva la identidad.
- **La animación se resolvió con `last_frame`, no con `drift_threshold`.** Poniendo `last_frame = first_frame`: frames 0 y N vuelven **pixel-idénticos** al original y sólo se mueve el medio. Deriva del implante 27 → 11. El `drift_threshold` casi no movió la aguja (27 vs 29 entre 0 y 0.10). 1 generación por animación.
- **Economía real**: Tier 1 son **2000 generaciones/mes** por $12 (dato que no publican en ningún lado; sólo se ve al pagar). El set completo costó ~193 — el 10%.
- **Fallos encontrados**: (a) el almacenamiento devuelve **403 al User-Agent de `urllib`** (con `curl` funciona), lo que costó un estado a medias — ahora el `character_id` se guarda *antes* de descargar y un reintento reutiliza el estado ya pagado; (b) `celebrate` con "brazos en alto" devolvió **un bulto gris sin cara** (0 píxeles de implante) — los prompts de edición dirigen el sprite entero, no sólo lo nombrado; se arregló pidiendo patas al costado y cara visible; (c) `generate_species_gifs.py` **habría borrado al koala** de `species.txt` en su siguiente corrida, porque reconstruía la lista desde el firmware — ahora descubre especies extra buscando su `_idle.gif`.
- **Se descartó el MCP de PixelLab** pese a existir: los prompts, semillas e IDs tienen que vivir en un script commiteado y reproducible. Un MCP no deja rastro versionable, y ya sabemos lo que cuesta eso — así perdimos el axolotl.
- Lo que se acepta a sabiendas: el arte es **PNG binario de 47 colores**, así que se pierde el `Edit` quirúrgico sobre la rejilla de texto que permite el panda.
- Verificado: 240 combinaciones especie×mood, cero estampas, **cero fallbacks del koala** (tiene las 12 propias).

#### 2.8b ✅ El selector de especie viste a los dos pets (2026-08-08)
Elegir koala cambiaba el pet del menú pero **no el flotante**, que seguía siendo panda: estaba fijado a `"buddy"` en tres call-sites, con un comentario que citaba la decisión de upstream (`Ray, 2026-07-12`). Esa decisión tenía sentido cuando el dropdown sólo ofrecía especies del firmware sin set de moods; con el koala dejó de tenerlo. Ahora los tres pasan por `gifName(for: selectedSpecies, ...)` — creación, cambio de mood y pose `pending` (esta última además gana el fallback a idle que el literal `"buddy_pending"` no tenía).
- La ventana es un cuadrado de 120pt con escalado proporcional: el koala mide 120×120 y cae **pixel-exacto**, el panda 160×160 baja, y las del firmware (108×80) quedan con transparencia arriba y abajo en vez de estirarse.
- **Bug encontrado de paso**: `speciesPopupChanged` llamaba `setIdle()` sin guarda, así que cambiar de especie con una tarjeta en pantalla **olvidaba el request vivo** y dejaba al hook esperando su propio timeout (~55s, que degrada al prompt nativo — malo pero no fatal). Sus dos handlers hermanos ya se protegían con `currentRequestId == nil`; ahora este también, y con tarjeta arriba sólo cambia la pose sin tocar el request.
- Verificado con instancia de depuración y `capture_pet`: pose `working` (koala tras la laptop) y pose `pending` (koala alerta, orejas erguidas) — ninguna es el panda.

#### 2.8c ✅ Tres tamaños para el pet flotante (2026-08-08)
El pet medía 120pt fijos contra una tarjeta de 430pt de ancho — 28%, se veía chico. Menú → `Pet Size`: small/medium/large. **Default nuevo: medium.**
- **Tres pasos y no un slider, por una razón medible.** El arte del koala era de 120px y la pantalla dibuja 2 píxeles de respaldo por punto, así que 120pt = 2 px por píxel de origen, 180pt = 3 y 240pt = 4. (La escalera pasó a **128/192/256** en 2.8d, cuando el lienzo se recortó a 64px; el razonamiento es el mismo, los números no.) Cualquier valor intermedio parte un píxel de origen entre dos de pantalla, y en pixel art eso se ve como bloques de ancho desigual. Las demás especies tienen su propio tamaño nativo (panda 160, firmware 108×80) y no pueden ser todas enteras a la vez; la escalera limpia es para el koala porque es el pet dibujado para esta app.
- **`NSImageView` interpola por defecto y eso emborrona el pixel art al agrandar.** `DraggablePetImageView` ahora pone `imageInterpolation = .none` en `draw`, pero **sólo al magnificar**: al reducir (el panda son 160pt de origen en una caja de 120) tirar la interpolación descarta píxeles en vez de promediarlos, que es el único caso donde suavizar es mejor.
- El resize es en vivo, alrededor del **centro** y no del origen (el pet está donde el usuario lo dejó, y la vista sigue el medio), con clamp a la pantalla — un pet grande en una esquina se saldría — y `invalidateShadow()`, porque la ventana es transparente y su sombra se deriva del alpha del contenido.
- Verificado con `capture_pet` en los tres: 240px / 360px / 480px, es decir 120pt / 180pt / 240pt. A 4× del nativo el arte sigue con bloques cuadrados. **No probado con click**: el cambio en vivo desde el menú (centrado y clamp) está construido, no ejercitado — automatizarlo pedía permisos de accesibilidad que el proyecto evita a propósito.
- **Trampa de verificación que costó una vuelta**: la app no tiene bundle ID, así que su dominio de preferencias es `ClaudeMenuBarBuddy` (el nombre del ejecutable), **no** `com.claudemenubarbuddy.app`. Escribir en el segundo crea un dominio basura que nadie lee, y la app cae a su default como si el código fallara.
- **`OS_REASON_CODESIGNING` es reproducible**: el primer `launchctl kickstart` después de matar una instancia manual del mismo binario ad-hoc falla, el segundo levanta. No lo dispara reconstruir el binario (se repitió sin recompilar) sino el respawn inmediato tras el kill.

#### 2.8d ✅ Recortar el lienzo del koala (2026-08-08)
Agrandar la ventana no resolvía la queja de fondo, porque **estábamos escalando aire**. Medido con el bounding box del alpha sobre todos los frames de todas las moods:

| especie | lienzo | sprite | llena |
|---|---|---|---|
| buddy | 160×160 | 160×160 | 100% |
| dragon | 108×80 | 109×74 | ~100% × 93% |
| cat | 108×80 | 82×60 | 76% × 75% |
| **koala** | 120×120 | **53×62** | **44% × 52%** |

El relleno transparente era **exclusivo del koala** — PixelLab devuelve el personaje pequeño y centrado. A 120pt el panda dibujaba 120pt de panda y el koala 52pt de koala: menos de la mitad, con la misma configuración.

- **Recortar y no escalar al vuelo**, por tres razones: el problema es de un archivo y no del sistema (escalar sería código de render que no hace nada para 19 de 20 pets); escalar congelaría la inconsistencia en el renderer en vez de arreglarla, cuando "tamaño nativo = tamaño del sprite" es un invariante que las otras 19 ya cumplen; y el factor para llenar la ventana sería 120/53 ≈ 2.26, no entero, reintroduciendo el desenfoque que 2.8c acababa de quitar.
- **Lienzo 64×64, escalera 128/192/256.** El lienzo no puede bajar de 62 (la unión es 53×62) y para que las tres medidas caigan en píxeles enteros debe dividir a `2W`; con la escalera vieja los únicos candidatos eran 120 y 60, y 60 se queda 2px corto. Con 64 la escalera es 4×/6×/8×.
- **Bug propio, encontrado por la medición**: `CGImage.cropping(to:)` usa origen **abajo-izquierda**, no arriba. Mi aserción de "el sprite cabe en la caja" estaba escrita en coordenadas arriba-izquierda, así que validaba un rectángulo distinto al que recortaba y dejó pasar el corte de **una fila** en la parte baja del sprite. Se detectó porque la unión bajó de 62 a 61 y el sprite quedó pegado al borde. Ahora la aserción vive en el mismo espacio que el recorte, que es la única forma de que signifique algo.
- El script lleva `CROP` y `crop_frames`, que **aborta** si algún frame se sale de la caja: regenerar no puede deshacer el recorte ni, peor, decapitar al pet en un frame que nadie mire.
- **`PixelArtImageView` compartido con el menú.** Con 64px nativos el koala pasó de reducirse (120→80pt) a ampliarse (64→80pt), así que el recorte habría metido desenfoque justo donde no lo había. La condición exige que *ambos* ejes quepan, de modo que el panda (160px) y los del firmware (108 de ancho) conservan el suavizado de siempre.
- Peso: **82 KB → 65 KB**.
- Verificado: 256 / 384 / 512 px en los tres tamaños, llenado 81% × 92% en todos, nada cortado. El Small nuevo (≈104pt de koala visible) ya es más grande que el Medium viejo (≈77pt).
- De paso: el origen guardado ahora se acota a la pantalla al restaurarlo, porque se grabó bajo el tamaño y los monitores de entonces.

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

**Orden 2026-08-06**: el usuario pospuso la 2.4 (web+QR). Los números se quedan como están — renumerar dos veces en dos días vuelve ilegible el historial. Orden real de aquí en adelante: **2.5 → 2.6 → 3.1 → 3.2**, con la 2.4 disponible para retomarse cuando quiera (no bloquea a nadie).

## Verificación end-to-end (por fase)

- Cada item lleva su verificación arriba; además, al cerrar cada fase: `swift build` + `launchctl kickstart -k` + inyección de request de prueba (avisada) + selfie de tarjeta (`capture_card`/`capture_pet` flags) + revisión de CPU en reposo + commit/push por paquete de features como venimos haciendo.
- Los hooks instalados (`~/.config/claude-menubar-buddy/`) se sincronizan con `cp` en cada cambio de hook.sh/notify-done.sh.
