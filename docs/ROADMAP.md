# claude-menubar-buddy — "Siguiente nivel" (roadmap en fases)

## Contexto

El fork ya replicó y superó a Masko en lo esencial (tarjetas estilizadas, hotkeys, always-allow, auto-edits, toast, límites). El usuario quiere llevarlo al siguiente nivel en 3 frentes: **productividad/automatización** (rescatar lo mejor del ecosistema: jump-to-terminal de Masko, aprobación remota, batch approve, burn-rate), **más vida para el pet** (estados nuevos + micro-comportamientos, manteniendo CPU ~0), y **UX/UI más intuitiva** (settings window, hotkeys remapeables, onboarding, ícono profesional).

Decisiones ya tomadas (research + usuario):
- **Animación**: mantener pipeline GIF+NSImageView (CPU casi cero) + Core Animation para transforms. NO SpriteKit/Lottie/Rive (8-25% CPU medido).
- **Dependencias aprobadas**: sindresorhus/KeyboardShortcuts, Defaults, Settings. (LaunchAtLogin-Modern NO sirve: requiere .app bundle; usar el LaunchAgent plist de SKILL.md.)
- **NO migrar a MenuBarExtra/SwiftUI completo**: la tarjeta no-activante (sagrada) debe seguir en AppKit; SwiftUI solo puntual (onboarding vía NSHostingView).
- El usuario eligió TODO el scope, en roadmap por fases.

Restricciones duras: CPU idle ~0 · panel no-activante intocable · build SPM-only (`swift build`, LaunchAgent → `.build/debug`) · hooks siempre aditivos (timeout → prompt nativo).

**Hallazgo del research**: `generate_species_gifs.py` apunta a `~/Downloads/claude-buddy-project/claude-desktop-buddy/` que **ya no existe** — re-clonar antes de la Fase 2.4.

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
- Poses panda nuevas en `generate_gifs.py`: `buddy_thinking` (mano en barbilla), `buddy_sad`, `buddy_excited`. Especies: fallback a `_idle` ya existe (`gifName(for:mood:)`); stressed/critical reusan tired/sleepy hasta 2.4.
- Verificar: prompt → thinking en ≤5s; `sleep 20` en tool → working; deny → flash sad; sesión nueva → excited una vez.
- Implementado: thinking/working NO se distinguen por "bytes nuevos" (una herramienta larga deja el transcript igual de callado que el modelo pensando) sino leyendo el último registro del transcript más reciente — `assistant` con `tool_use` = herramienta corriendo, `user`/tool_result = el modelo es lo que se espera. Lectura de cola de 64KB cacheada por (path, size), solo cuando hay turno en vuelo. `gifName` pasó de fallback plano a cadena de candidatos (`stressed→tired`, `critical→sleepy→tired`, `excited→celebrate→heart`, `sad→tired`) para que las 18 especies degraden a algo con sentido, no a idle. Fix de paso: `TIRED`/`SLEEPY` tenían filas de 17 celdas (se renderizaban 1 celda más anchas que el resto).
- Verificado en vivo vía selfies del pet + comparación contra los GIFs: working ✓, thinking ✓, excited ✓ (aparece ~3s y revierte solo). `sad` queda cableado — se verá en el próximo deny real.

### 1.4 Ícono template + accesibilidad
Sustituir `🐼✏️N` por imagen template generada en código (SF Symbol pawprint o silueta 18x18 programática, `isTemplate = true`) + count como `button.title` (`variableLength`); pending = símbolo con badge naranja; auto-edits = overlay lápiz. Key de Defaults "Icon style: Emoji/Template" para conservar el look actual. `setAccessibilityLabel` en status button, tarjeta, pills, pass button, pet.
- Verificar: dark/light adapta; VoiceOver (⌘F5) lee los controles.

### 1.5 Burn-rate v1
En `UsageStats.swift`: `readPlanUsage` devuelve samples recientes (no solo `.last`). Con datos frescos: fit lineal de `fh` sobre ≤60 min (≥3 samples, ≥10 min spread) → `"▲ 12%/h · 90% ≈ 16:40"` + notificaciones proyectadas 75/90% (keys `notifiedProj75/90`, patrón `checkThreshold`). Con datos stale: solo velocidad de tokens de transcripts (`velocitySamples` ring buffer en memoria, poda 2h, guarda contra rollover del día) → `"~120K tok/h (plan % stale)"`, sin proyección.
- Archivos: `UsageStats.swift`, `burnLineItem` en menú.
- Verificar: con Desktop abierto muestra slope plausible; sin Desktop degrada a velocidad sin notificar.

## Fase 2 — Features grandes (~7-10 días)

### 2.1 Settings window + adelgazar menú
`sindresorhus/Settings`, 3 tabs: **Behavior** (recorders de hotkeys, umbral de toast, umbrales burn-rate, Start at login vía LaunchAgent plist de SKILL.md con `launchctl bootstrap`), **Appearance** (especie, floating pet, icon style, fidgets on/off), **Safety** (auto-edits, tabla de always-allow con remove, log de decisiones, web approval + QR). El menú conserva: pet+mood, líneas de status/uso/burn, Active Sessions, Decision History, los 2 toggles de seguridad (visibles a un click: Floating Pet, Auto-approve Edits), `Settings…`, `Quit`. Fallback si Settings falla sin bundle: NSWindow + NSTabViewController.
- Verificar: cada toggle migrado hace round-trip (flag files siguen moviendo hook.sh); remap de hotkey aplica a la siguiente tarjeta.

### 2.2 Batch approve + selección de cola
⌘1..9 en **Carbon** dinámico (solo mientras `queued > 0`; no vale la pena 9 nombres remapeables). ⌘k fija `pinnedRequestId` que `poll()` ordena al frente. El badge `+N` se vuelve botón → `NSMenu.popUp` (funciona desde panel no-activante) listando la cola (`"⌘2 Bash — proyX: git push…"`) + `Allow all (N)` / `Deny all (N)`. Allow-all con confirmación de doble-click ("Really allow N?"), escribe N response files + N entradas de log, un solo dismiss.
- Verificar: 3 requests en cola; ⌘2 intercambia tarjeta; Allow all libera los 3 hooks.

### 2.3 Aprobación remota web local + QR
`WebApprovalServer.swift` (~250 líneas) con **Network.framework NWListener** (cero deps). Rutas: `GET /?t=<token>` (HTML self-contained con JS que pollea `GET /pending` cada 2s) y `POST /decide` `{id, decision}` → hop a main queue → mismo `respond()` (anima la tarjeta también y evita double-answer vía respondedIds). Token 128-bit regenerado por enable, puerto asignado por sistema, bind LAN; QR (CoreImage CIQRCodeGenerator) en Settings/menú. **Off por defecto**; listener ni se crea si está apagado (CPU 0). Sin TLS: aceptable por token + LAN + off-by-default + peor caso = aprobar un request visible (documentarlo).
- Riesgo: firewall de macOS puede preguntar por el binario sin firmar (documentar en SKILL.md).
- Verificar: QR desde el cel → request aparece ≤2s; Allow en el cel dismissa la tarjeta con ✓; disable → puerto cerrado.

### 2.4 Liberar poses del firmware + escalera stressed/critical
Re-clonar `anthropics/claude-desktop-buddy`; parametrizar `SRC_DIR` en `generate_species_gifs.py`; descubrir poses: `grep -ho 'static void do[A-Za-z]*' src/buddies/*.cpp | sort -u` (hoy solo se extraen doIdle/doAttention/doBusy/doDizzy/doSleep/doHeart/doCelebrate) y mapear doSad/doThink/etc. a los moods nuevos. Extender `first_array_in_function` para tomar TODOS los arrays de cada función → GIFs de 2-4 frames reales. Escalera: 50 tired · 70 stressed (pose nueva o doBusy acelerado) · 85 critical (doDizzy) · 100 asleep. Panda: dibujar stressed/critical en `generate_gifs.py`.
- Verificar: regeneración sin skips, build, forzar cada mood con plan-usage falso y ciclar especies.

### 2.5 Onboarding first-run
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
Fase 0 ─► 1.1 ─► 2.1 ─► 2.5
      ├─► 1.3 ─► 2.4 ─► 3.1
      ├─► 1.4 ─► 3.2
      ├─► 1.5 ─► 2.1 (config umbrales)
      └─► 1.2 (campos hook) ─► 2.3 (JSON más rico)
2.2 solo depende de 1.1 · 2.3 independiente salvo QR-en-Settings (interino: QR en menú)
2.4 bloqueado por re-clone del firmware
```
Camino crítico: 0 → 1.1 → 2.1 → 2.5. Esfuerzo total: **~14-18 días** (2.2/2.3/2.4 paralelizables tras Fase 1).

## Verificación end-to-end (por fase)

- Cada item lleva su verificación arriba; además, al cerrar cada fase: `swift build` + `launchctl kickstart -k` + inyección de request de prueba (avisada) + selfie de tarjeta (`capture_card`/`capture_pet` flags) + revisión de CPU en reposo + commit/push por paquete de features como venimos haciendo.
- Los hooks instalados (`~/.config/claude-menubar-buddy/`) se sincronizan con `cp` en cada cambio de hook.sh/notify-done.sh.
