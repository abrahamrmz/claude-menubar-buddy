# Reglas para agentes que trabajan en este repo

Este archivo lo lee opencode al empezar. Si algo de aquí choca con una instrucción del chat, gana este archivo; detente y pregunta.

## Qué estás construyendo

La entrega 3 es el control de los sonidos del buddy. Hoy está en su **fase de investigación**: todavía no hay plan ni se toca código. El prompt del chat dice qué buscar y en qué archivo escribir los resultados.

- En esta fase solo lees páginas web (webfetch y websearch) y escribes el archivo de resultados que pide el prompt. **No descargues archivos** (`curl` y `wget` están negados) y no edites nada más.
- Solo cuentan los sonidos con licencia CC0 o de dominio público. El repo es público: cada sonido necesita una fuente y una licencia que cualquiera pueda comprobar.

Las entregas 1 y 2 ya se completaron; sus planes en `docs/superpowers/plans/` son solo referencia. Cuando exista el plan de la entrega 3, este archivo apuntará a él. **No cambies decisiones de diseño.** Si algo no se puede hacer como dice el prompt o el plan, no improvises una alternativa:
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
