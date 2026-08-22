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

#### 2.8e ✅ Quitar la sombra de la ventana del pet (2026-08-08)
El usuario reportó una "silueta fantasma transparente", más visible al cambiar de animación, con la forma de los brazos del koala. Era la **sombra de la ventana**: macOS la deriva del alpha del contenido y la cachea, y no sigue a un GIF animado — se queda con el contorno de la pose que hubiera en pantalla al calcularla (los brazos de `celebrate` colgando detrás de un koala en reposo).
- `invalidateShadow()` corrige un instante, pero el sprite cambia de forma varias veces por segundo y perseguirla con un timer a velocidad de frame cuesta el CPU que el proyecto promete no gastar. `hasShadow = false`, y una sombra difuminada nunca fue el idioma de pixel art: si algún día se quiere, va **dibujada en el sprite**, donde anima gratis.
- Por qué apareció justo ahora y no antes: el artefacto siempre estuvo, pero el koala recortado (2.8d) es el doble de grande y su silueta tiene brazos definidos. El panda llena su lienzo al 100% y su sombra es un bloque que casi no cambia entre poses.
- **Descartado con evidencia antes de llegar ahí**: (a) el arte — los 4 frames de `celebrate` renderizados sobre magenta salen limpios, sin residuo; (b) el `disposal` del GIF, que era la sospecha propia más probable tras recodificar con ImageIO — parseados los bytes del GCE, los recortados traen `disposal 2, transparent 1`, idéntico a los originales de PIL y al panda.
- **No verificable localmente**: `CGWindowListCreateImage` —la vía para que un proceso se capture a sí mismo *con* sombra, sin permisos— está **obsoleta en macOS 15**, y su reemplazo exige Grabación de Pantalla. El diagnóstico se cerró con la confirmación visual del usuario, no con una captura.

#### 2.8f ✅ Botones armados por modificador (2026-08-10)
Con una tarjeta arriba, mantener los modificadores de un atajo (⌘ para Allow, ⇧⌘ para Deny, ⌥⌘ para la fila quiet, ⌘ solo para las opciones) ilumina el botón correspondiente — borde blanco + crecimiento leve — para ver dónde caerá el ⏎ antes de soltarlo.
- **Polling a 20Hz de `NSEvent.modifierFlags`, no monitor global**: el panel es no-activante, así que ningún `flagsChanged` local llega a la app, y un monitor global arrastraría el permiso de Accesibilidad que este proyecto evita a propósito. El timer vive **solo mientras hay tarjeta visible** — costo idle cero.
- Compara contra los atajos **grabados** del usuario (`KeyboardShortcuts.getShortcut`), así que los remaps siguen funcionando.
- `setPressed(false)` regresa a la pose armada (no a `.identity`) si el modificador sigue abajo; los bordes de acento de las opciones se guardan y restauran (`restingBorderWidth/Color`).
- Verificado en vivo con tarjeta real: ⌘ arma Allow, ⇧⌘ cambia a Deny, ⌥⌘ a la fila quiet, soltar desarma.

#### 2.8g ✅ Mano alzada en pending + meditación en compact (2026-08-10)
Dos gestos nuevos para el koala, validados por el usuario.
- **Pending — pata alzada + foquito.** `OVERRIDES` por (especie, mood) en `generate_pets.py` le da al koala una pata alzada como pidiendo la palabra. El foquito es `add_lightbulb()`: 6×8 píxeles compuestos **programáticamente** en la esquina superior derecha del crop congelado, parpadeando por frame alterno. Composición y no prompt por dos razones: la unión de sprites deja solo 2px libres directamente sobre la cabeza (centrarlo habría obligado a encoger al pet, lienzo 64→128), y un prompt sobre la posición es una esperanza mientras que un offset es un hecho — el precedente es el pixel art a mano del panda.
- **Meditate — flor de loto en PreCompact.** Hook nuevo `PreCompact` en `settings.json` → `notify-done.sh` escribe `compact_<session>.json` → `processCompactMarkers()` en el poll de 1s dispara `flashMood("meditate", 25s)`. Duración fija porque **no existe evento de "compact terminó"**. Una tarjeta activa conserva el spotlight (`currentRequestId == nil` de guarda), y las especies sin ese arte degradan a `thinking` — no a `asleep`, cuya Z significa "límite alcanzado".
- **`still_for` reusa el estado pagado aunque el prompt de edición cambie** (gotcha del generador): para regenerar `pending` hubo que borrar a mano `character_ids.pending` + `stills.pending` del manifest y el PNG cacheado.
- Costo: 42 generaciones (balance 1718/2000). Verificado en vivo con selfies: pata alzada + foquito en las coords exactas (x 58-63, y 0-7, encendido en frames 0/2), y loto tras un marcador de compact.
- Pendiente conocido: `meditate` solo existe para el koala (el buddy y las 19 restantes degradan) y **SKILL.md aún no documenta PreCompact** — va en Fase 4.

## Fase 3 — Pulido (~3-4 días)

### 3.1 Fidgets ambientales (solo Core Animation)
En `floatingImageView.layer`: bob = CABasicAnimation `transform.translation.y` ±2pt/3.5s autoreverse infinito (GPU, gratis); varianza = Timer de baja frecuencia (jitter 30-90s) que dispara squash de 0.2s (`scale.y` 0.94) para romper el metrónomo; cursor = NSTrackingArea (event-driven, cero polling) → scale-up + heart ocasional. **Pausado obligatorio**: remover animaciones en `hideFloatingPet()` y `windowDidChangeOcclusionState` (!visible); re-agregar al mostrar. Kill-switch "Calm pet" en Appearance.
- Riesgo: layer-backing puede afectar el render del GIF — probar `animates` con layer.
- Verificar: Activity Monitor: CPU idle igual que hoy con pet visible; 0.0% oculto/tapado.

### 3.2 Pulido final
Accesibilidad de la página web (botones reales, aria-live), campo `"via":"web"` en decisions.jsonl, copy de Settings, README + SKILL.md (campos nuevos del hook, nota de firewall, start-at-login por LaunchAgent), muestreo de CPU con `/usr/bin/time -l`.

---

# Segundo ciclo — Fases 4-6 (planeado 2026-08-10)

Sale de un inventario completo del repo (features, señales, assets, hardcodeos) + decisiones del usuario: entra todo lo de abajo; **la 2.4 (web + QR) sigue pospuesta** (reconfirmado 2026-08-10). La 3.1 (fidgets) se absorbe aquí como 5.1; la 3.2 se reparte entre la Fase 4 (docs/copy) y lo que la 2.4 desbloquee algún día (accesibilidad web).

## Fase 4 — Correcciones ✅ 2026-08-10

Todo salió del inventario; el 1 es de seguridad y no es opcional:

1. **Copy peligroso en `Onboarding.swift:252`**: describe ⌥⌘⏎ como "Deny quietly — no card, no note back to Claude". Es lo contrario — es always-allow / auto-approve-edits / auto-accept del plan: el usuario cree que niega y en realidad otorga un permiso permanente. Corregir también "There are 19 pets" (:297 — son 20).
2. **Matchers faltantes**: `MultiEdit` y `WebSearch` tienen acento/color en la tarjeta y fast-path en hook.sh, pero no están en `expectedMatchers` (Health.swift) ni en `settings.json` ni en SKILL.md — nunca llega una tarjeta de ellos. Cablearlos (aditivo, como siempre).
3. **SKILL.md no documenta PreCompact**: una reinstalación desde SKILL.md perdería el mood meditate.
4. **`petMoodText` default `🐼 Active and happy`**: emoji de panda hardcodeado para las 20 especies.
5. **Limpieza del config dir**: nada borra `response_*.json` huérfanos, `turn_start_*` de sesiones muertas ni `*_selfie.png`. Barrido al arrancar (edad > 1 día).
6. **Rotación de `decisions.jsonl`** (420 KB y creciendo): rotar a `decisions.1.jsonl` al pasar ~1 MB.
7. `moodGifCandidates("meditate")`: terminar la cadena explícitamente en idle (hoy depende del fallback implícito de `gifName`).

- Implementado 2026-08-10, los 7 en una sesión. Notas: el `settings.json` vivo ganó los matchers `MultiEdit`/`WebSearch` por jq aditivo (respaldo + validación antes de reemplazar); `hook.sh` además aprendió a armar el hint de ambos (multi-diff por edit para MultiEdit, `query` para WebSearch — antes habría caído al `tostring` del tool_input). El barrido de arranque se **verificó en vivo**: se llevó 6 `response_*` huérfanos, 3 selfies y un `turn_start` muerto, y conservó el de la sesión activa — ojo, el primer `find` tras el kickstart ganó la carrera al arranque y pareció que no barría; era el SIGKILL de codesigning documentado retrasando el relanzamiento. La rotación del log se verificó **aislada** con el bloque exacto de `writeDecision` (1.2MB → `.1`, log nuevo por la vía del fallback); en vivo se disparará sola al cruzar 1 MB (hoy va en ~420 KB).

## Fase 5 — Estética

### 5.1 ✅ Fidgets ambientales (2026-08-10; la 3.1 de arriba, sin cambios de diseño)
Bob ±2pt/3.5s con CABasicAnimation (GPU), squash ocasional con jitter 30-90s, NSTrackingArea para el cursor. Pausado obligatorio al ocultar/tapar; kill-switch "Calm pet" en Settings ▸ Appearance. Verificar: CPU idle idéntico en Activity Monitor.
- Implementado en `Fidgets.swift` nuevo. **La política de pausa cuelga de `applyAnimationPolicy`** — el mismo choke point que ya apaga los frames de GIF en lock/sleep/GIF-swap — más la oclusión vía `windowDidChangeOcclusionState` (el delegate ya era el AppDelegate) y el estado `isVisible` en `hideFloatingPet`. Una sola regla para frames y fidgets, imposible que deriven.
- Ancla del layer al centro con compensación de posición (mismo patrón que los botones de la tarjeta): el default de AppKit es la esquina inferior-izquierda y cada escala habría sido un ladeo.
- El squash es un one-shot que se reagenda con jitter fresco (30-90s) — un período fijo se lee como metrónomo en dos repeticiones.
- Hover: lean-in de 1.05 + corazón ocasional (1 de 6), nunca sobre una tarjeta activa ni encimando un flash en curso. `.activeAlways` porque esta ventana jamás es key.
- **El riesgo del plan (layer-backing vs `animates`) se verificó y no se materializó**: 4 selfies a intervalos irregulares dieron 3 frames distintos con `wantsLayer` activo. (La primera prueba con 2 selfies salió engañosamente idéntica: el espaciado ~2.3s casi calzó con el ciclo de 2.4s del idle.) CPU en régimen 0.6-1.5% — igual a la línea base ~1.1% de la 2.5.

### 5.2 ✅ Pet flotante acariciable (2026-08-10)
Hoy `DraggablePetImageView` solo arrastra; el clic→heart+Tink vive solo en el pet del menú (`petClicked`). Distinguir clic de drag por umbral de movimiento (~3pt entre mouseDown/mouseUp) y disparar el mismo `petClicked`. El pet más visible es hoy el único que no se puede acariciar.
- Implementado con `onPet`/`onHover` como closures del view (cableados en `showFloatingPet`), distancia al cuadrado contra `clickSlop²` en `mouseUp`. El drag queda intacto: solo un mouseUp a ≤3pt del mouseDown cuenta como caricia.

### 5.3 ✅ Burbujas de diálogo (2026-08-10)
Globito ocasional junto al pet flotante con contexto corto ("compactando…", "3 sesiones activas", "90% ≈ 16:40"). Reusar el patrón del Toast (panel `ignoresMouseEvents`, `originNearPet()`), tipografía pequeña, auto-dismiss. Frecuencia baja (no ruido) y suprimida con tarjeta visible.
- Implementado en `SpeechBubble.swift`: píldora HUD de 26pt, auto-dismiss 4s, sigue al pet si lo arrastras. **El trigger vive en `applyMoodGif`** — un solo punto donde cambia el mood — y `bubbleText(for:)` decide qué transiciones merecen narrarse: meditate, la escalera del límite (tired/stressed/critical/asleep), excited, sad y celebrate ("Back in business!", texto propio porque `petMoodText` no tiene caso celebrate y habría caído al default). idle/working/thinking/heart callan a propósito. La proyección del burn-rate también burbujea la versión corta ("⏳ 90% ≈ 16:40") junto a su notificación.
- **Las supresiones son el diseño**: nunca sobre una tarjeta (la tarjeta es el spotlight), nunca con el toast arriba (dos cromos diciendo cosas distintas), nunca la misma línea en 5 min ni dos líneas en 20s, nada con el pet oculto o la pantalla bloqueada. Kill-switch "Speech bubbles" en Settings ▸ Appearance (default on).
- **Gotcha de medición que costó dos vueltas**: ni `NSString.size` ni el `sizeToFit` de NSTextField miden el ancho real de dibujo cuando la línea abre con emoji (Apple Color Emoji + redondeo subpixel) — la píldora salía con "…" exactamente por esa diferencia. `sizeToFit` + 6pt de holgura; verificado con `capture_bubble` → `bubble_selfie.png` (flag de debug nuevo, hermano de capture_pet).
- Verificado en vivo: marcador de compact falso → koala en loto + burbuja "🧘 Meditating — compacting context" completa.

### 5.4 Arte PixelLab (~570 de 1718 generaciones del mes)
- **Terminar kitty, panda y piglet** (~169 c/u; base ya pagada en sus manifests, cero GIFs hoy). Antes, resolver la colisión de nombres del picker: `panda` (PixelLab) vs `buddy` (panda dibujado) y `kitty` vs `cat` (firmware) — nombres de display distintos en Settings ▸ Appearance (los ids internos ya son distintos). Añadirlas a `species.txt`.
- **2-3 gestos nuevos del koala** (~21 c/u): saludo al detectar sesión nueva (hoy `excited` genérico), bostezo/estiramiento como variación de idle largo (engancha con 5.1), baile para celebrate. Prompts en `OVERRIDES`/`MOODS`, mismo pipeline, crop congelado.
- Decidir por gesto si las especies nuevas lo reciben o degradan vía `moodGifCandidates`.

**Los tres pets salieron en 2.8/5.4 (commits `3353f71`, `bfa61e0`) con el set CORE de diez.** La colisión de nombres se resolvió sola al retirar `buddy` y `cat` en la 4.x.

#### 5.4b ✅ Las cuatro mascotas completan los trece moods (2026-08-19)
`thinking`, `sad` y `excited` para piglet, panda y kitty — los tres que quedaban degradando a working/tired/celebrate. **189 generaciones** (1080 → 891), 63 por pet, cero abortos de recorte.

- **Las cajas de recorte estaban al límite y eso decidió el orden de trabajo.** Medida la holgura de cada mood ya publicado contra su lienzo de 64px: el `working` del panda toca arriba *y* abajo (holgura 0), piglet queda en 1px arriba y abajo, kitty es la más suelta (3 y 2). Con el crop congelado en el manifest, una pose más alta aborta `crop_frames` — así que kitty fue primero, de canario, antes de gastar en las dos apretadas.
- **La palanca barata es el movimiento, no la edición.** Cambiar el `motion` re-anima por 1 generación reusando el estado pagado; cambiar el `edit` obliga a borrar el estado del manifest y volver a pagar 20. Por eso los prompts de edición se afinaron *antes* de correr y el movimiento quedó de reserva. No hizo falta usarla.
- **Un `OVERRIDE` preventivo para el panda**, por precedente documentado y no por sorpresa: sus parches negros ya se habían tragado los ojos de tired/stressed/critical, y `excited` es literalmente "ojos de estrella". Escrito como estrellas blancas **encima** de los parches — la misma frase que rescató los ojos de `heart` y las X de `critical`. Funcionó: las estrellas se leen nítidas.
- **La métrica de diferencia de píxeles se queda corta con el panda, y eso también es un hallazgo.** Su `sad` vs `tired` da 16.4% y `asleep` vs `excited` 19.9%, los números más bajos de la tabla — pero a la vista son inconfundibles. La diferencia vive en la cara y el cuerpo del panda es enorme y uniforme, así que domina el conteo sobre 64×64. En el gato, de cuerpo delgado y cola que se mueve, los mismos pares dan 40% y 27%. La métrica compara *sprites*, no *expresiones*: sirve para detectar poses que salieron idénticas, no para rankear pets entre sí.
- Comparados contra la vara ya aceptada: el par más parecido del koala publicado es 18.4% (sad/tired). piglet 27.6%, kitty 25.6%, panda 16.4%. Sólo el panda queda por debajo, por la razón de arriba.
- `CORE` deja de ser "lo que estas tres llevan" y pasa a ser el piso que cualquier pet futuro tiene que alcanzar. Las cadenas de degradación de `MoodPolicy` **no se borran** aunque hoy ninguna dispare: son lo que permite que un pet llegue por partes, que es exactamente como llegaron los cuatro.
- Verificado: 4 × 13 = 52 combinaciones, ninguna resolviendo a un sustituto. Arte total 424 KB.
- Mientras esto se escribía, `swift test` todavía fallaba con `no such module 'XCTest'` (sólo hay CommandLineTools, sin Xcode.app), así que la cobertura especie×mood se comprobó con un script aparte. La Fase 7.1 lo resolvió después; hoy los 40 tests corren y auditan justo eso.

#### 5.4c ✅ Tres gestos para el koala (2026-08-19)
`greet`, `yawn` y `dance` — la otra mitad de la 5.4. **63 generaciones** (891 → 828). Sólo el koala; las otras tres degradan.

Salió en dos commits, no por diseño: el arte (`63c9b98`) se subió solo porque el cableado había quedado entrelazado con el refactor de `BuddyCore` que corría en paralelo — `MoodEngine.swift` ya importaba ese módulo y subirlo sin él dejaba el repo sin compilar. Con las Fases 7.1/7.2 ya en `main`, el cableado aterrizó detrás. Entre uno y otro los tres GIFs quedaron inertes y cubiertos por las cadenas de degradación, que es exactamente el estado para el que existen.

- **`GESTURES` se separa de `MOODS` en el generador.** `MOODS` es el vocabulario que toda mascota habla; esto es el acento que tiene una. La entrada en `PETS` decide quién los recibe, así que un run del piglet no intenta generarlos.
- Disparadores: **greet** reemplaza al `excited` genérico al detectar sesión nueva (saludo con la pata, no una cara); **dance** se sortea con `celebrate` cuando el límite de 5h se renueva — dos poses para la misma buena noticia, porque una celebración pixel-idéntica cada vez deja de leerse como celebración; **yawn** es nuevo: cinco minutos ininterrumpidos de idle y luego 1 de cada 12 refrescos, o sea ~6 min de promedio. El primer borrador (2 min + 1 de 6) daba uno cada dos minutos y medio, que es un tic nervioso, no una señal de vida.
- **El bostezo no lleva burbuja de diálogo, a propósito.** Existe para darle textura al tiempo muerto; narrarlo convertiría "no pasa nada" en un anuncio, que es justo la lectura que no debe tener. Y `moodGifCandidates("yawn")` termina en `idle`: nada suplanta a un bostezo, así que una mascota sin ese arte simplemente no bosteza.
- Los prompts mantienen los brazos bajos o al costado porque la caja del koala lleva congelada desde sus primeros trece moods y una pose de brazos arriba es la que más se le acerca al techo. Resultado: `greet` L6 T2 R5 B4, dentro de la caja.
- **Hallazgo de medición: el lote de gestos redibujó el cuerpo entero.** Contra los moods viejos la diferencia real (>8/255) tiene mediana **47.7%**, cuando viejo-contra-viejo es 32.0% y los tres gestos entre sí 28.7%. El mapa de diferencias lo confirma: en `greet` vs `excited` el rojo cubre todo el cuerpo, no sólo el brazo y la cara, mientras que en `sad` vs `tired` se limita a la cara. **No es corrimiento de paleta** — el blanco del vientre es idéntico (229,233,225) y el negro del contorno varía tanto entre los viejos como contra los nuevos; es el dither del pelaje redibujado. Los nueve GIFs de la 5.4b **no** tienen el problema: salen en 27-29%, dentro de la línea base. Se acepta a sabiendas: regenerar no tiene mecanismo para salir distinto, y a la vista es el mismo koala.
- **Trampa que costó una vuelta**: el primer test end-to-end dibujó `excited` en vez de `greet`. No era el cableado — SPM copia `Resources/` al bundle **en tiempo de build**, y yo había compilado antes de que existieran los GIFs. El fallback hizo exactamente su trabajo y por eso el fallo fue invisible salvo por la comparación contra los frames de referencia.
- Verificado en vivo: instancia aislada vía `CLAUDE_BUDDY_CONFIG_DIR` (sin tocar la cola real), sesión falsa nueva → el koala saluda con la pata → revierte solo. 4 × 16 = 64 combinaciones, ninguna sin resolver, ningún arte inalcanzable.

## Fase 6 — Productividad

### 6.1 ✅ Estadísticas de decisiones (2026-08-19)
`decisions.jsonl` ya tiene ts/tool/project/decision/host/answers. El submenú Decision History gana cabecera de resumen (hoy/semana: N aprobadas, M denegadas, tool más frecuente, proyecto más activo). Sin ventana nueva de entrada — el menú es el hábitat de la app.

- **Ventana rodante en memoria, no cuentas persistidas** (`DecisionStats.swift`). Unas cuentas "hoy/semana" tendrían que enterarse de la medianoche y resetearse solas, y una que se saltara el rollover reportaría el número de ayer como el de hoy para siempre. Una ventana simplemente olvida lo que se le cae por atrás.
- Sembrada una vez al arrancar desde el log **y su rotación**, en background; `writeDecision` la mantiene al día. Abrir el menú cuesta aritmética sobre unos cientos de structs en vez de reparsear 780 KB — que además se abre seguido. El merge deduplica por `ts` para no contar doble lo que se escribió mientras la siembra leía.
- Las cuatro decisiones se cuentan aparte porque son cuatro cosas distintas: una respuesta a `AskUserQuestion` no es una aprobación, y un `pass` no es un deny sino la app absteniéndose. Las categorías en cero no se imprimen — un "0 denied" se lee como contador roto.
- Verificado contra sus datos reales: `jq` sobre el log dio 1037 en la ventana / 77 hoy / 1033 allow / Bash 984 / pdl_mty 643, y la app dijo 1040 / 80 / 1036 / Bash 987 / pdl_mty 643 — los mismos **+3** en todos los contadores que se movieron, que son las decisiones ocurridas entre una medición y otra. Flag de debug nuevo `capture_stats` → `decision_stats.txt`, hermano de los selfies, porque un encabezado que vive en un `NSMenu` no es capturable.
- De paso: el README afirmaba que `decisions.jsonl` "deliberately never rotated" — la Fase 4 le puso rotación a 1 MB y la frase se quedó. Corregida.

### 6.2 ✅ Always-allow por proyecto (2026-08-19)
Hoy `always_allow.json` es global. La fila quiet ofrece "Always allow `git push` **in proyX**"; `hook.sh` compara contra `{global: [...], projects: {...}}` usando el `cwd` que ya captura. Migración: la lista actual pasa a `global`. La tabla de Settings ▸ Safety gana columna de proyecto.

- **La llave es el `cwd` absoluto, no el nombre del proyecto**, y el match es exacto. Dos checkouts pueden llamarse `api` los dos, y un permiso filtrándose entre ellos es exactamente lo que nadie notaría nunca; un prefijo, por su parte, convertiría un grant sobre `/repo` en uno sobre `/repo-secrets`.
- **La tarjeta sólo puede estrechar; ensanchar cuesta más.** El botón ⌥⌘⏎ otorga siempre en el proyecto que preguntó. Pasar un permiso a "everywhere" es una decisión distinta y vive en Settings ▸ Safety, detrás de una confirmación que dice en cuántos proyectos va a valer. Que lo ancho cueste un viaje y lo estrecho un clic es el diseño, no un descuido.
- Sin `cwd` (ssh/tmux, o un `hook.sh` viejo) no hay proyecto al que acotar: ahí el único permiso expresable es el global, y el botón dice "everywhere" en vez de prometer una estrechez que no puede cumplir.
- **Compatibilidad hacia atrás en el hook, no en una migración.** Un array pelado es la forma pre-scopes del archivo; el hook lo normaliza en la misma expresión jq (`if type == "array" then {global: ., projects: {}}`), así que un usuario a medio actualizar nunca pierde permisos. La app reescribe en la forma nueva en su siguiente cambio.
- `CWD`/`PROJECT_NAME` subieron al principio de `hook.sh` — el fast path los necesita para decidir y corría mucho antes de donde se calculaban.
- La tabla de Settings desambigua los basenames que chocan mostrando también la carpeta padre (`work/api` vs `personal/api`). Dibujar los dos como "api" habría escondido justo el caso por el que existe la feature.
- Verificado: los 8 casos de la expresión de lookup aislada (incluidos homónimos, `api-x` contra `api`, subdirectorio, y archivo corrupto → falla cerrado), luego 8 end-to-end contra el `hook.sh` real con payloads de `PreToolUse` — 3 fast-path con la redacción de scope correcta, 5 cayendo a la tarjeta — y las 3 formas vacías que la app puede escribir. La tabla, renderizada desde la app con dos checkouts homónimos sembrados.
- **Trampa de verificación**: `launchctl bootout` **desregistra** el servicio, así que `kickstart` ya no lo encuentra y la app se queda caída; restaurar pide `bootstrap` con la ruta del plist. Distinto del gotcha de codesigning que ya estaba documentado (ése es sólo `kickstart` dos veces).

### 6.3 Configurables
Toggle "Sounds" en Settings ▸ Behavior (Ping/Tink/Glass) · duración de meditación y staleness del plan como keys de Defaults (primero la key, UI solo si se pide) · unificar el umbral duplicado `MIN_SECONDS_TO_NOTIFY=30` (notify-done.sh) vs `toastMinSeconds` (app).

## Fase 7 — Madurez (veredicto de la revisión 2026-08-19)

Sale de una revisión completa del repo (2026-08-19). El diagnóstico: el diseño de seguridad y la documentación de decisiones están por encima de la media, pero **la verificación del proyecto es rigurosa y efímera** — selfies, inyección manual de requests, tests aislados que se escriben, prueban y se tiran. Excelente para cerrar cada fase, cero protección contra regresiones. Esta fase convierte ese veredicto en trabajo, empezando por lo que protege a todo lo demás.

### 7.1 ✅ Tests committeados — primero los que guardan las promesas de seguridad (2026-08-19)
Target `ClaudeMenuBarBuddyTests` en `Package.swift` para que `swift test` corra sin Xcode (mismo espíritu SPM-only del build). En orden de riesgo:
1. **La validación de comandos del always-allow** (hook.sh). Es la pieza que decide qué corre sin tarjeta: los metacaracteres `;` `|` `&` `$` `` ` `` etc. deben mandar a tarjeta *siempre*, sin importar la primera palabra. Como vive en bash, el arnés es de fixtures, no XCTest: un script en `Tests/hook/` que alimenta requests JSON al `hook.sh` real con un config dir temporal y asserta la decisión (allow del fast-path / caída a tarjeta / `{}` en multiSelect). Los casos son los del README más los que un refactor rompería callado: `git; rm`, `cat $(x)`, newline embebido, entrada del allowlist con espacios.
2. **La matemática del burn-rate** (`fiveHourSlope`). Los tests aislados de la 1.5 ya cubrieron los shapes reales (rollover, plano, recuperando, spread corto, fuera de ventana) — esta vez se committean en vez de tirarse. Si algo de esa lógica quedó pegado a I/O, extraerlo a función pura es parte del ítem.
3. **Las cadenas de degradación de moods** (`gifName`/`moodGifCandidates` + el fallback de especie sin arte de la 4.x): 4 especies × 13 moods sin combinación muerta, y `selectedSpecies` huérfano cae al default. Hoy eso se verifica a mano en cada retiro de pet; un test lo hace en cada build.
- Verificar: `swift test` verde en checkout limpio; romper a propósito un metacaracter del hook y un corte de rollover → ambos tests fallan.

**Implementado 2026-08-19** — 40 tests, ~5s la suite entera:
- **Swift Testing, no XCTest.** Los Command Line Tools no traen XCTest para macOS (el primer `swift test` murió en `no such module 'XCTest'`), pero el toolchain 6.1 sí trae `Testing.framework`. Mismo `swift test`, y de regalo corre en paralelo — que es lo que deja al arnés del hook (polls de 0.5s) caber en ~5s.
- **La extracción a función pura tomó la forma de un target `BuddyCore`**: SPM no puede linkear tests contra los símbolos de un ejecutable sin maquinaria de Xcode, así que la matemática del burn-rate (`BurnRate` + `PlanSample`) y la política de moods (`MoodPolicy`: escalera, cadenas de degradación, resolución de GIF, fallback de especie) viven ahí y el ejecutable delega con wrappers de una línea. `now` pasó a parámetro con default — los fixtures fijan el reloj en vez de depender de cuándo corre la suite.
- **El arnés del hook corre el `hook.sh` real**, no una reimplementación: `$HOME` desechable por test, shim de `pgrep` en `$PATH` (que la app "esté corriendo" es fixture, no un hecho de esta máquina — el buddy real suele estar arriba mientras la suite corre), y para los casos de tarjeta el response file se escribe como lo escribiría la app. Sin respuesta, SIGTERM — la misma señal que manda Claude Code cuando contestas en la terminal, así que el caso "limpia el request file al morir" salió gratis.
- **La auditoría de arte no usa Bundle**: lee `Resources/` del repo vía `#filePath` y recorre especies×moods en ambas direcciones — toda combinación resuelve a un GIF que existe, y todo GIF embarcado pertenece a una especie de `species.txt` con un mood que `MoodPolicy` conoce. La deriva entre `generate_pets.py` y la política ahora truena en el build, no en un pet congelado.
- **Verificado por mutación, como pedía el ítem**: quitar `;` del guard de metacaracteres → `metacharactersAlwaysGetACard` falla mostrando exactamente el ataque del README (`echo hi ; rm -rf ~` aprobado como "echo"); `resetDrop` 10→10000 → los tres tests de rollover fallan (el fit a través del salto reporta -73%/h). Restaurado, 40/40 verdes y `git diff` de hook.sh vacío.
- Gotcha del arnés: `jq > request.json` crea el archivo un instante antes de llenarlo; el poll que lo lee a medio escribir debe tratarlo como "aún no está", no como JSON roto. Costó los únicos dos flakes de la primera corrida.

### 7.2 ✅ Partir `ApprovalCard.swift` y re-adelgazar `main.swift` (2026-08-19)
La Fase 0 partió un `main.swift` de ~1400 líneas; hoy `ApprovalCard.swift` va en ~1100 y `main.swift` volvió a ~920. La tarjeta concentra layout + decisión + verdict + badge de cola, y es donde más se agrega feature por feature — mismo patrón que motivó la Fase 0. Cortes naturales: `CardLayout` (construcción visual por tipo de tool), `CardDecision` (respond/writeDecision/verdict) y dejar el badge de cola con `Queue.swift`, que ya es su tema. Sin cambios de comportamiento: es mover, no reescribir — hacerlo *antes* de la 6.x para que esas features caigan en archivos del tamaño correcto.
- Verificar: `swift build` limpio, tarjeta sigue no-activante, selfie idéntica antes/después (`capture_card`).

**Implementado 2026-08-19.** Los cortes planeados aguantaron; los números: `ApprovalCard.swift` 1133 → 550 (se queda con ensamblaje, armado por modificador, `setPending` y el capture), `CardLayout.swift` 264 (los dos views custom + fábricas de pills + `bodyText`/`attributedHint`), `CardDecision.swift` 325 (de `commandBase` a `deny()`, con `writeDecision`/`respond`), `main.swift` 938 → 614, `Menus.swift` 343 (todo el dropdown y su refresh in-place). El badge `+N ▾` se construye ahora en `Queue.swift` (`queueBadgeButton`), que ya era su tema; la tarjeta sólo lo coloca. Todo movido verbatim — los rangos se extrajeron con script, no retecleados.
- **Verificado como pedía el ítem, y con mejor herramienta**: selfies de la tarjeta Bash (fila quiet + badge de cola) y de la de opciones, antes y después — la de opciones **byte-idéntica**, la Bash con 0 píxeles de diferencia (67 bytes de ruido del encoder PNG; `ImageChops.difference` → bbox `None`). `swift build` limpio y los 40 tests de la 7.1 verdes.
- **De paso, `CLAUDE_BUDDY_CONFIG_DIR`**: la instancia debug de las selfies ahora corre sobre un config dir aislado. Salió de un fallo real del arnés compartido: la primera tarjeta falsa inyectada en el dir real fue **aprobada por el usuario con ⌘⏎ en ~2 segundos, por reflejo** — la selfie capturó la tarjeta de atrás, y `decisions.jsonl` ganó aprobaciones de utilería. Con el dir aislado la app real ni se entera, los hotkeys reales siguen respondiendo tarjetas reales, y el bootout/bootstrap de la app durante capturas ya no hace falta. No amplía la superficie de confianza: quien puede poner env vars a esta app ya controla el plist que la lanza.
- Nota de convivencia: se implementó con la 5.4 corriendo **en otra sesión en paralelo** (MoodEngine/arte). Por eso los movimientos fueron ediciones quirúrgicas (nunca reescrituras de archivo completo), el commit se armó por staging selectivo, y no hubo `kickstart` — el refactor no cambia comportamiento, así que la app corriendo puede esperar al siguiente relanzamiento natural.

### 7.3 ✅ El techo de 60s del hook, visible en vez de silencioso (2026-08-19)
El hook espera respuesta 60s y luego cae al prompt nativo — correcto y es la base del fail-safe. Lo que falta es el otro lado: **la tarjeta se queda en pantalla pidiendo una decisión que ya nadie escucha**; responder después escribe un response file huérfano y el usuario cree que decidió. Dos remedios, el segundo barato porque el request JSON ya trae timestamp:
1. Documentar el techo en README ("What it can see"): una decisión que tarda más de ~60s se responde en el prompt nativo, no en la tarjeta.
2. Al vencer el plazo, la tarjeta se retira sola (o se marca "expiró — respóndelo en el prompt nativo") en el mismo poll de 1s que ya la maneja. Sin timer nuevo.
- Verificar: inyectar request y no responder → a los ~60s la tarjeta se retira y el prompt nativo queda como único dueño de la decisión; `decisions.jsonl` no gana entrada fantasma.

**Implementado 2026-08-19 — y la premisa del ítem resultó exagerada, lo cual acota el trabajo.** En el caso normal la tarjeta ya se retiraba sola: el hook borra su request file al rendirse (~55s) y `poll()` la desvanece al tick siguiente. Los huecos reales eran tres, y los tres se cerraron:
1. **El hook matado con SIGKILL** (terminal cerrada a la brava) deja la request huérfana, y la tarjeta se quedaba pidiendo hasta la barrida de 75s. La constante ahora es `hookAnswerWindow = 60` (55s de poll del hook + margen), compartida entre `scanRequests` y `respond()` — peor caso 20s más corto, y con nombre en vez de dos números mágicos.
2. **La decisión fantasma**: responder en ese hueco escribía un response file que nadie lee y una línea en `decisions.jsonl` afirmando que Claude recibió una decisión que no recibió. `respond()` ahora se rehúsa pasada la ventana: retira la request y pasa por `poll()`, que desvanece neutro (sin ✓/✕ — el buddy no decidió nada) o trae la siguiente de la fila. Cubre la carrera de sub-segundo que la barrida de 1s no alcanza.
3. **README**: párrafo nuevo en el modelo de amenazas — la tarjeta es respondible ~60s, después decide el prompt nativo, y el ↗ existe justo para las decisiones que van a tomar tiempo real de lectura.
- **Verificado con la instancia aislada** (`CLAUDE_BUDDY_CONFIG_DIR`): una request con ts 61s en el pasado se barre en <3s, ninguna tarjeta llega a mostrarse, `decisions.jsonl` queda vacío y cero response files. Que la barrida no se pasa de lista lo prueban las tarjetas reales frescas respondidas tras el relanzamiento. Los 40 tests de la 7.1 verdes.
- **El arnés compartido volvió a perder contra el reflejo del usuario**: el primer intento de "inyectar y no responder" duró 4 segundos antes de que la tarjeta falsa recibiera su ⌘⏎ (segunda vez en dos fases — es un patrón, no un accidente, y es la razón de ser del config dir aislado). El test se rediseñó para que la request ya llegara expirada: lo que no muestra tarjeta no puede ser aprobado por reflejo.

**Fase 7 completa** (7.1 ✅ · 7.2 ✅ · 7.3 ✅).

## Fase 8 — De proyecto personal a proyecto (análisis 2026-08-20)

Sale de una segunda mirada tras cerrar la Fase 7, con una meta explícita del usuario: **que deje de ser solo un proyecto personal**. El diagnóstico esta vez no es de código sino de dependencias humanas: el proyecto descansa en disciplina (correr la suite, recordar qué commit era bueno, tener a Claude en la sesión para diagnosticar) en tres lugares donde podría descansar en máquinas. Cada ítem convierte una de esas disciplinas en infraestructura.

### 8.1 ✅ CI — que los tests corran porque sí, no porque alguien se acordó (2026-08-20)
Los 40 tests de la 7.1 protegen contra regresiones *si se corren*, y en este repo los commits salen de sesiones largas donde saltárselos es fácil. Workflow de GitHub Actions con runner de macOS: `swift build` + `swift test` en cada push a `personal`. Los runners traen toolchain de Swift y `jq` preinstalados, y el arnés del hook ya es autónomo (HOME desechable, shim de `pgrep`) — debería correr casi sin adaptación. De paso, `shellcheck` sobre `hook.sh` y `notify-done.sh`: el hook es la pieza de seguridad del proyecto, está en bash, y es lo único embarcado sin ningún analizador encima.
- Riesgo: el arnés del hook asume timing local (polls de 0.5s); un runner lento puede necesitar márgenes más holgados. Ajustar el fixture, no el hook.
- Verificar: push con la suite verde → check verde; romper a propósito un metacaracter del hook en una rama → el check falla en GitHub, no solo localmente. `shellcheck` limpio o con excepciones anotadas en el propio script.

**Implementado 2026-08-20** (`.github/workflows/ci.yml`, commits `6fc9c6e` + `da8d16f`):
- **Dos jobs, dos runners, a propósito**: `swift build` + `swift test` en `macos-15` (AppKit y Swift Testing no viven en Linux) y `shellcheck` en `ubuntu-latest` — el análisis de dos scripts de bash no amerita el runner caro. Trigger: push a `personal` y todo PR; `concurrency` con `cancel-in-progress` para que un push encimado no pague dos corridas.
- **`shellcheck` encontró tres cosas antes de estrenarse como check**, y la política del ítem ("limpio o con excepciones anotadas") se aplicó tal cual: el patrón `"$HOME"/Library/"Application Support"/...` del case de rutas protegidas se reescribió a la forma canónica (equivalente, y los tests de rutas protegidas lo confirman), la variable de loop que nadie leía pasó a `_`, y el `mkdir -m 700 -p` quedó **anotado como decisión** — el `-m` solo alcanza al directorio hondo, que es exactamente el que guarda los archivos sensibles; `~/.config` queda con el umask como cualquier directorio XDG.
- **El riesgo del plan no se materializó**: el arnés del hook corrió en el runner sin tocar un solo margen. Primera corrida completa 1m01s; con el cache de SPM tibio (llave = hash de `Package.resolved`), 32-37s.
- **Verificado como pedía la cláusula, con sonda real**: rama `ci-probe-metachar` + PR borrador #3 quitando el `;` del guard de metacaracteres → el check falló **en GitHub** en `metacharactersAlwaysGetACard`, mostrando textualmente el ataque del README (`echo hi ; rm -rf ~` aprobado como "echo"). PR cerrado sin fusionar, rama borrada — la mutación vivió exactamente lo que duró su demostración.
- `checkout` a v5 tras la primera corrida: v4 apunta a Node 20 deprecado y la anotación saldría en cada corrida — un aviso permanente se desaprende en una semana.
- Gotcha de `gh` en este repo: con dos remotes (es fork de `spyza008`), `gh run list` responde **vacío sin error** hasta fijar `gh repo set-default abrahamrmz/claude-menubar-buddy`. Costó creer que el workflow no había registrado.

### 8.2 ✅ Releases etiquetados — un ancla llamada "esto funcionaba" (2026-08-20)
El historial narra bien, pero ningún commit se llama "estado bueno conocido". Quien instala desde SKILL.md compila la punta de `personal`, incluido un commit a medias entre dos sesiones concurrentes — que ya existió: `63c9b98` dejó GIFs inertes esperando un cableado que llegó commits después. Un tag anotado (`v0.x`) por cada paquete de fases cerrado da a dónde regresar cuando algo se rompa, y SKILL.md gana la opción de recomendar el último tag en vez de la punta. Sin CHANGELOG: este roadmap ya es eso, y mantener dos historias es cómo una de las dos empieza a mentir.
- Verificar: `git tag` lista al menos el estado post-Fase-7; `git checkout <tag>` + `swift build` + `swift test` verde en ese punto; SKILL.md menciona el tag.

**Implementado 2026-08-20** — `v0.1.0` sobre `8ce2fbb`, con Release en GitHub:
- **El orden fue el punto**: primero SKILL.md y el install manual del README aprendieron a recomendar el último tag, luego el CI bendijo ese commit, y *entonces* se etiquetó — así el estado etiquetado ya se documenta a sí mismo. La instrucción es genérica (`git describe --tags --abbrev=0`) para que no envejezca con cada release.
- **`v0.1.0` y no `v0.7` ni `v0.8`**: las fases no mapean a versiones (la numeración del roadmap es historia de trabajo, no de releases) y semver deja el `1.0` reservado para cuando el proyecto deje de ser personal — que es la meta declarada de esta fase.
- **Anotado, con el CI de testigo en el mensaje**: el tag dice qué contiene y que ese commit exacto compiló y pasó la suite en un runner limpio antes de llevar nombre. El Release de GitHub lo hace visible en la portada y enlaza SKILL.md y este roadmap *en la versión etiquetada*.
- **Verificado como pedía la cláusula, y en checkout de verdad limpio**: worktree desechable en el tag → `swift build` desde cero (50s) + 40/40 tests. No fue redundante con el CI por un matiz: el runner probó el commit; el worktree probó el *checkout del tag* — que el ancla que recomendamos instalar resuelve a ese mismo estado.
- **De paso, SKILL.md dejó de describir la app de hace tres semanas**: decía "panda by default, 17 pets via Choose Buddy" (retirado todo en la 4.x). Un tag que apunta a docs que mienten no es un estado bueno conocido — la corrección viajó en el mismo commit que el tag señala.

### 8.3 ✅ BuddyCore como regla, no como fase (2026-08-22)
La extracción de la 7.1 cubrió burn-rate y mood policy, pero queda lógica pura atrapada en el ejecutable que ya demostró ser delicada: el ordenamiento y pinning de la cola (`orderedRequests` — un bug ahí reordena qué apruebas), la ventana rodante de `DecisionStats` (el razonamiento de medianoche/rollover documentado en 6.1 no tiene test), y los checks de `Health.swift` (`inspect(claudeSettings:)` toma la ruta como parámetro *justo para ser testeable*, y no lo está). No es una fase monolítica de mudanza: es la regla de que **cada vez que se toque uno de estos, se mueve a BuddyCore y se testea en el mismo commit**. La fase se marca completa cuando los tres nombrados estén bajo test, lleguen como lleguen.
- Verificar: por cada extracción, la mutación obvia falla (invertir el orden de la cola, romper el corte de medianoche, quitar un matcher esperado) y el ejecutable delega con wrappers de una línea, como en 7.1.

**Progreso 2026-08-21 — la cola ✅ (primera de las tres).** `QueuePolicy.ordered` en BuddyCore, genérica sobre `(id, ts)` porque `PendingRequest` vive en el ejecutable y BuddyCore no tiene por qué conocerlo. `scanRequests` ahora devuelve sin ordenar — el orden es de la política, y todos los consumidores pasan por `orderedRequests()`, que delega y conserva el pin sobreviviente.
- **La extracción encontró un bug latente, que es el argumento entero de esta fase**: el sort empataba por `ts` sin desempate, y el sort de Swift no es estable — dos requests con el mismo timestamp podían intercambiar el frente entre scans, y como `poll()` reemplaza la tarjeta cuando cambia el id del frente, eso es una tarjeta parpadeando entre dos requests. Ahora desempata por id: ambos órdenes de scan producen el mismo frente.
- 8 tests nuevos (48 en total). Mutaciones verificadas una por una: invertir el orden cayó en 4 tests, el pin muerto que no se suelta en 2, quitar el desempate en el de determinismo — cada una en el test diseñado para ella.
- Sin kickstart: nada user-visible cambia en el caso común; la app corriendo espera su relanzamiento natural, como en la 7.2.

**Progreso 2026-08-22 — DecisionStats ✅ (segunda de las tres).** `DecisionWindow` en BuddyCore se lleva la ventana entera: record + parseo de línea del log, summary con las cuatro decisiones aparte, `busiest` con su desempate por nombre, poda, y el merge siembra-vs-vivo. En el ejecutable, `DecisionStats.swift` pasó de 168 líneas a ~60 de puro I/O (la siembra en background y el dump de `capture_stats`); `recentDecisions` desapareció de AppDelegate — el estado ES la ventana.
- Lo que quedó pinneado es exactamente el razonamiento de la 6.1 que no tenía test: el corte de medianoche (ayer 23:59 no es "hoy"), la ventana que olvida por atrás, el borde exacto de los 7 días (`>=` sobrevive), la dedup por ts del merge **en las dos direcciones** (lo doble no se cuenta, lo que la siembra no vio no se pierde), y las cuatro decisiones contadas aparte.
- `now` y `calendar` inyectables (patrón de BurnRate); los tests usan UTC y epochs alineados al día para que "medianoche" esté donde el test dice, no donde corra la suite.
- 12 tests nuevos (60 en total). Mutaciones: medianoche = "hace 24h" cayó en 2 tests, la poda que no poda en 1, el merge que cuenta doble en 1.
- **Gotcha de la propia verificación**: al restaurar la mutación del merge, el replace alcanzó también el loop idéntico de `busiest` — el "error: fatalError" de la corrida final fue eso, no un test. Restaurar mutaciones con contexto único o con `git checkout`, no con la línea pelada.

**2026-08-22 — Health ✅ (tercera de las tres; la fase cierra).** `HealthPolicy` en BuddyCore se lleva los cuatro análisis puros y las dos listas: el wiring del `settings.json` (enum `Wiring` de cuatro salidas), las aserciones de forma del transcript, el barrido de herramientas sin tarjeta, y el ancla de versión (`series` + las tres transiciones). `Health.swift` conserva el I/O y la redacción de remedios — leer archivos, correr `claude --version` y componer rutas del usuario no son política.
- **Las listas bajaron por necesidad, no por gusto**: los tests solo pueden linkear BuddyCore (SPM no presta símbolos de un ejecutable), así que `expectedMatchers` y `deliberatelyUngated` tenían que mudarse para ser auditables. Eso habilitó los dos tests de política: los nueve matchers pinneados por extenso (quitar uno es un test rojo, no un hueco callado en cada instalación nueva) y el invariante de que ninguna herramienta esté en ambas listas — una contradicción que nada detectaba.
- **Los fixtures de la 2.6 y la 2.7 quedaron recommitteados**, que era el punto: los tres modos de fallo del wiring (JSON roto / sin hooks / parcial), el hook ajeno que no prueba nada del nuestro, `Edit|Write` contando como dos, las tres transiciones del ancla (primera vez / misma serie / 1.9→2.1), y la clase WebSearch del barrido — la herramienta nueva que aflora a la primera usada.
- 14 tests nuevos (74 en total). Mutaciones: quitar `MultiEdit` de la lista cayó en el pin de los nueve (la mutación que nombra la cláusula de esta fase), aceptar cualquier hook como nuestro en el test del hook ajeno, y tratar el matcher combinado como string opaco en el suyo.
- **La fase cierra pero la regla no**: los tres nombrados están bajo test, y cualquier lógica pura que se toque de aquí en adelante sigue el mismo camino — mover, testear, mutar, en el mismo commit.

### 8.4 Log de diagnóstico opt-in
Hoy, cuando algo se comporta raro, el método es selfies + inyección de requests — funciona, pero solo funciona con Claude en la sesión. Un `debug.log` en el config dir que solo escriba con `CLAUDE_BUDDY_DEBUG=1` (requests vistas y barridas por el poll, decisiones escritas, por qué se rehusó un `respond`, transiciones de mood) permite diagnosticar un "la tarjeta no salió" *después de que pasó*, sin reconstruir el momento. Mismo espíritu que los selfies: instrumentación que duerme a costo cero — sin el flag, ni se abre el archivo.
- Riesgo: el log ve lo mismo que la tarjeta (comandos, diffs) — hereda la advertencia de los capture flags en el README y el `0700` del directorio; rotación como la de `decisions.jsonl`.
- Verificar: sin flag, el archivo no existe y no hay I/O nuevo; con flag, una request inyectada deja su rastro completo (vista → mostrada → respondida/barrida); el README lo documenta junto a los capture flags.

**Fuera de alcance, a sabiendas**: bundle `.app` firmado/notarizado (rompería la restricción SPM-only por un beneficio que este proyecto no necesita) y la 2.4 (sigue pospuesta por decisión del usuario; nada la bloquea).

## Orden del segundo ciclo

**4 → 5.1+5.2 → 5.4 → 5.3 → 6.1 → 6.2 → 6.3.** El arte (5.4) se intercala donde convenga: generar es esperar API. La 2.4 sigue disponible sin bloquear a nadie.

**Fase 7 (agregada 2026-08-19): la 7.1 va primero de lo que reste** — es la que protege a las demás, y cada fase que se cierre sin ella es verificación que vuelve a evaporarse. La 7.2 conviene antes de entrar a la 6.x (que esas features caigan en archivos ya partidos); la 7.3 es independiente y chica, se intercala cuando toque tocar la tarjeta.

**Fase 8 (agregada 2026-08-20): la 8.1 primero** — es medio día y es la que vuelve permanente todo lo que la Fase 7 construyó; la 8.2 le sigue natural (el primer tag debería nacer con el CI ya verde, para que "estado bueno conocido" signifique algo verificado por máquina). La 8.3 no se agenda: es una regla que aplica en cada commit que toque esos archivos. La 8.4 se intercala cuando toque tocar el poll.

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

#### 4.x ✅ Un solo pet, y sólo los generados (2026-08-15)
Dos limpiezas pedidas juntas, y la segunda arrastró más de lo que parecía.

**El pet del menú se fue.** Un GIF que sólo existe mientras el dropdown está abierto es un pet que nadie mira, y el del escritorio ya es visible sin click y responde a que lo acaricien. La línea de mood se queda: eso es texto de estado, que es para lo que sirve un menú. El pet del menú de pendientes se va por la misma razón.
- Efecto en cadena: sin pets en menús, **ningún `NSMenuItem` tiene vista propia**, así que murieron `gifMenuItem`, `setMenuAnimations`, `menuIsOpen`, `petImageView` y el `menuDidClose` entero. `menuWillOpen` conserva sólo el refresco de uso, que ya estaba guardado por identidad.
- `gifMenuItem` tenía un último usuario que no era un menú: el onboarding lo usaba para fabricarse un `NSImageView` y tiraba el `NSMenuItem`. Ahora construye la vista directamente.

**Se retiran las 19 mascotas sin arte de PixelLab**: las 18 del firmware y el panda dibujado a mano. Quedan koala, piglet, panda y kitty. 174 GIFs y 2.2 MB fuera; `Resources/` pasa de ~2.5 MB a 352 KB.
- Se borran también `generate_species_gifs.py` y `generate_gifs.py`. El primero no era sólo código muerto: **reescribe `species.txt` desde el firmware**, así que dejarlo habría resucitado las 18 y machacado la lista en su siguiente corrida.
- **El riesgo real no era borrar, era la preferencia guardada.** `selectedSpecies` seguía diciendo `buddy` o `cat` en instalaciones reales, y un nombre sin arte resuelve a un GIF que no está en el bundle: `setGif` sale temprano y el pet queda **invisible, sin nada en pantalla que lo explique**. El accessor ahora verifica que exista el `_idle.gif` y cae al default si no. Comprobado poniendo `buddy` a mano: dibuja el koala, no un hueco. Se valida en cada lectura y no en una migración de arranque, para que retirar cualquier pet futuro se cure igual.
- El default pasa de `buddy` a `koala`.
- Verificado: 4 especies × 13 moods = 52 combinaciones, ninguna sin arte.
