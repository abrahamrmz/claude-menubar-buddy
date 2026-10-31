# Reglas para agentes que trabajan en este repo

Este archivo lo lee opencode al empezar. Si algo de aquí choca con una instrucción del chat, gana este archivo; detente y pregunta.

## Qué estás construyendo

Sigue el plan vigente, tarea por tarea y en orden. Hoy es `docs/superpowers/plans/2026-10-30-entrega-3-sonidos.md`: el control de los sonidos del buddy desde el menú de la barra. El diseño que lo respalda está en `docs/superpowers/specs/2026-10-30-sonidos-design.md`. Los planes de las entregas 1 y 2 ya se completaron y son solo referencia.

- El plan va por **bloques de revisión**. Al terminar cada bloque, detente y avisa en el chat; no empieces el siguiente hasta que te lo digan.
- **No toques los archivos de `Sources/ClaudeMenuBarBuddy/Resources/Sounds/`** (los `.wav` y `CREDITS.md`). Los puso Claude con sus créditos, y un test compara sus SHA-256.
- **No descargues archivos** (`curl` y `wget` están negados).

**No cambies decisiones de diseño.** Si una tarea no se puede hacer como dice el plan, no improvises una alternativa:
1. Escribe la duda en `docs/superpowers/plans/NOTAS-EJECUCION.md` (qué tarea, qué paso, qué falló, qué intentaste).
2. Detente y avisa en el chat.

## Dónde puedes trabajar

- Solo dentro de esta carpeta (el worktree `claude-menubar-buddy-sonidos`).
- **Nunca** toques, leas ni compiles en:
  - `~/Desktop/repos/claude-menubar-buddy` (la carpeta principal: de ahí corre el buddy que el usuario usa a diario);
  - `~/.config/claude-menubar-buddy/`;
  - `~/Library/LaunchAgents/`.
- **Nunca** corras `launchctl`, `swift run`, `open` ni el binario de la app. La app no se prueba ejecutándola; se prueba con `swift test`.
- No edites `opencode.jsonc`, `.opencode/`, `AGENTS.md` ni la spec. `Package.swift` solo cuando una tarea lo diga.

## Comandos

- Compilar y probar, **siempre los dos y en este orden**:
  ```bash
  swift build && swift test
  ```
  `swift test` solo no reconstruye el ejecutable `buddy-rule` que usan los tests del hook. Sin `swift build` antes, esos tests corren contra un binario viejo.
- Un solo grupo de tests: `swift build && swift test --filter NombreDeLaSuite`.
- Hooks de shell: `shellcheck hook.sh notify-done.sh` (debe salir sin avisos).
- El punto de partida de la entrega 3 está en verde: 225 tests pasan. Lo que imprime la terminal como `Terminated: 15` durante los tests del hook es normal.

## Cómo escribir el código

- **Swift 5.9 o posterior, macOS 13+, solo Command Line Tools** (no hay Xcode). Sin dependencias nuevas.
- **La lógica pura va en `Sources/BuddyCore/`**, con `public` en todo lo que usan los tests o la app. Los tests solo pueden importar `BuddyCore`, nunca la app.
- **Tests:** usan Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), igual que los que ya existen en `Tests/ClaudeMenuBarBuddyTests/`.
- **Comentarios y nombres en inglés,** como el resto del código. Los textos nuevos que ve el usuario (motivos de la tarjeta, "Modo auto") van en español, tal como los da el plan.
- **TDD:** primero el test, verlo fallar, luego el código, verlo pasar.
- **Nunca** copies a los tests comandos reales de `~/.config/claude-menubar-buddy/decisions.jsonl` ni de otro historial: el repo es público. Escribe casos inventados.

## Commits

- Un commit por tarea, al terminarla y con todos los tests en verde.
- Mensaje en español, una frase que diga qué cambia en el comportamiento, como los del historial (`git log --oneline`). Por ejemplo: `La regla clasifica los comandos de git por subcomando`.
- **Nunca** `git push`, ni `git commit --amend` sobre commits de otra tarea, ni `git reset --hard`.
