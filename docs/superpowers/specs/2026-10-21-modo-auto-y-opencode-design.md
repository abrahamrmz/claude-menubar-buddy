# Modo auto y soporte de opencode — diseño

Fecha: 2026-10-21 · Rama: `modo-auto-y-opencode` (desde `personal`) · Estado: borrador para aprobación

## 1. Para qué es esto

Hoy el buddy muestra una tarjeta por cada comando que Claude Code quiere correr. Entre el 8 y el 21 de octubre de 2026 el historial (`decisions.jsonl`) registra **4,202 comandos Bash aprobados y 2 rechazados**, unos 300 al día. Aprobar todo a mano dejó de ser atención y se volvió ruido. Cuando llega el comando que de verdad importa, como un script que puede mandar mensajes reales a clientes o un deploy, llega enterrado entre cientos de `grep`.

Además, el usuario empezó a trabajar con **opencode v2**, que el buddy no ve.

Esta ronda cambia el papel del buddy. Deja de ser una puerta para todo y se vuelve **el guardián de los momentos importantes**: con el modo auto prendido, lo rutinario pasa solo y lo crítico se detiene y espera al usuario. Hay **una sola regla para Claude Code y opencode**.

Con la regla de este documento, el historial real se habría repartido así: ~57% lectura, ~13% cambios locales, ~15% Python, ~4% `ssh` (casi todo lectura de logs), ~2% `gh` y ~5% claramente crítico (tests, scripts, `push`, deploys, `rm`). En modo auto, el usuario vería alrededor de 2 o 3 de cada 10 tarjetas de hoy.

## 2. Metas, no-metas y anti-metas

**Metas**
1. **Modo auto.** Un interruptor global. Prendido, lo que la regla considera seguro pasa sin tarjeta; lo demás muestra tarjeta.
2. **Una regla, una implementación**, usada por Claude Code y por opencode.
3. **Lo crítico sin respuesta no se ejecuta**, en ningún agente.
4. **opencode** con tarjetas de permiso, de pregunta y aviso de turno terminado.
5. **Rastro.** Todo lo que pasa en automático queda registrado y se puede revisar.

**No-metas en esta ronda**
- Cline CLI.
- Estadísticas de tokens y consumo, ánimo del panda y contador de sesiones activas para opencode.
- Modo auto distinto por repo.
- Botón "ir a la sesión" para opencode, porque los eventos no dicen en qué terminal corre.
- opencode v1, porque su API de permisos es otra.
- Aprobación de planes en opencode, que no existe allá: el modo plan es un agente que se cambia con Tab.

**Anti-metas: fracaso aunque "funcione"**
- **Un comando crítico se ejecuta sin que el usuario lo vea.** Un "pasa" falso en una categoría crítica es el peor bug posible. Ante la duda, tarjeta.
- **Se pierde una protección que el hook ya tiene:**
  - rutas protegidas con su canonicalización;
  - el rechazo de prefijos de entorno (`PATH=…`, `DYLD_…`);
  - "siempre permitir" restringido a un solo comando;
  - si la app no corre, ninguna concesión.
- **Una concesión invisible.** El modo auto solo actúa si la app está corriendo y el ícono de la barra lo muestra.
- **La conexión con opencode congela o tumba la app** cuando opencode no está, se reinicia o cambia de versión.
- **Datos privados en el repo, que es público.** No se suben comandos reales del historial, ni capturas sin sanear, ni contraseñas.

**Contra qué protege** (decisión del usuario). El modo auto apunta sobre todo a los **errores** del agente. Contra un agente **manipulado** (instrucciones escondidas en una página, un issue o un archivo) cierra las salidas baratas y los secretos conocidos:
- la web, `curl`, `push` y `gh` cuando publica siempre piden tarjeta;
- la lista de archivos sensibles es amplia (5.1).

No persigue variables, comodines ni lecturas recursivas que *podrían* tocar un secreto (`F=.env; cat $F`), porque eso se comería buena parte del ahorro. Queda como riesgo aceptado (sección 11).

## 3. Restricciones

- **Swift + AppKit:** se compila con `swift build` usando solo Command Line Tools, sin Xcode, y apunta a macOS 13+. No se agregan dependencias: `URLSession` alcanza para SSE y HTTP.
- **Dónde va la lógica:** la lógica pura va en `BuddyCore` (target testeable con `swift test`). La app (`ClaudeMenuBarBuddy`) solo cablea.
- **Hooks:** `hook.sh` y `notify-done.sh` siguen pasando `shellcheck` (CI).
- **Tests:** `HookTests` (el arnés que ejecuta el `hook.sh` real) sigue pasando.
- **El buddy en vivo corre desde la carpeta principal del repo** (`LaunchAgent` → `.build/debug/ClaudeMenuBarBuddy`). Todo el trabajo va en el worktree `~/Desktop/repos/claude-menubar-buddy-opencode`. Hasta el merge, nada toca `~/.config/claude-menubar-buddy/`, el `LaunchAgent` ni `launchctl`.
- **El repo es público.**

## 4. Decisiones

**Del usuario**
- **Detiene:**
  - cualquier Python: script, `-c`, `-m` o pegado con `<<EOF`;
  - `manage.py` y cualquier tipo de test.
- **Cambios locales:** pasan si se pueden deshacer. Detienen si no se deshacen, si escriben en rutas protegidas o si tocan archivos sensibles.
- **`ssh`:** pasa si el comando remoto solo lee; cualquier otra cosa detiene.
- **`gh`:** pasa si solo lee (`pr view/list`, búsquedas) y detiene si publica (`pr create/merge/comment`…).
- **Interruptor:** uno solo para todo.
- **Crítico sin respuesta:** no se ejecuta; es mejor esperar.
- **Preguntas del agente y aprobación de planes:** siempre muestran tarjeta.
- **Alcance:** la regla aplica igual a Claude Code y a opencode, y vive en el buddy, no en la configuración de cada agente.
- **opencode se configura para preguntar por todo** comando y toda edición. Si el buddy no está abierto, opencode pregunta en su terminal.
- **Orden:** primero la regla y el modo auto con Claude Code; después opencode. Son dos entregas con un PR cada una.
- **Leer la web pide tarjeta**, y la lista de archivos sensibles crece; las variables y los comodines en lecturas no se persiguen (sección 2, "Contra qué protege").
- **Durante el desarrollo**, `swift build` y `swift test` se permiten en el worktree. Editar `opencode.jsonc`, `.opencode/`, `AGENTS.md` y `Package.swift` pregunta (sección 9).

**Mías: el usuario puede revertirlas**
- Builds e instalaciones detienen: `swift build`, `npm`/`pnpm`, `uvx`, `brew`…
- `curl`, `wget`, `scp` y `rsync` detienen.
- Lo desconocido o lo que no se puede analizar → tarjeta.
- "Siempre permitir" se ofrece para comandos desconocidos, nunca para los críticos.
- La lista de "siempre permitir" es la del buddy (`always_allow.json`), también para opencode. No se usa el "always" nativo de opencode.
- El modo auto reemplaza al "auto-aprobar ediciones" actual.
- Lo que pasa en automático se registra en un archivo aparte (`auto_decisions.jsonl`), para que las estadísticas de decisiones sigan contando solo decisiones humanas.
- En una instalación nueva el modo auto empieza apagado.
- La regla vive en `BuddyCore`. El hook la consulta con un ejecutable pequeño (`buddy-rule`) y la app la usa directo para opencode.
- La tarjeta muestra de qué agente viene y por qué se detuvo.
- La app no edita la configuración de opencode, igual que nunca edita `settings.json` de Claude: el README da las instrucciones y el chequeo de salud avisa si falta.

## 5. La regla

**Entrada:**
- el agente (`claude` | `opencode`);
- la herramienta (Bash/shell, Edit/Write/…, WebFetch, preguntas…);
- el comando completo o las rutas;
- el directorio de trabajo;
- el estado del modo auto y la lista `always_allow.json`.

**Salida:**
- **`veredicto`:** `pasa` | `tarjeta`.
- **`categoría`.**
- **`crítico`** (Bool): si es crítico, no se ofrece "siempre permitir", y sin respuesta no se ejecuta.
- **`motivo`:** frase corta en español para la tarjeta, por ejemplo "ejecuta Python", "escribe en .zshrc", "ssh con sudo".

**Con el modo auto apagado,** todo es `tarjeta`, salvo "siempre permitir" (como hoy). La categoría y el `crítico` se calculan igual, porque deciden qué pasa si la tarjeta no recibe respuesta.

### 5.1 Categorías

| Categoría | En modo auto | Crítica | Incluye (lista inicial; se amplía con tests) |
|---|---|---|---|
| Lectura | pasa | no | `grep rg cat head tail less wc ls find`¹ `jq awk`² `cut sort uniq tr diff comm stat file du df which pwd echo printf date basename dirname realpath readlink nl column od xxd shasum pgrep ps lsof id whoami uname sleep true test [` · `sed` sin `-i` ni comandos `w`/`W`/`e` · `git status log diff show blame grep rev-parse ls-files describe shortlog fetch` · `git branch` solo para listar · `git remote -v` · `git worktree list` · `git config --get/--list` · `gh pr view/list/diff/checks`, `gh issue view/list`, `gh search …`, `gh repo view`, `gh run view/list` |
| Cambio local | pasa salvo rutas | no | `git add commit checkout <rama> switch merge stash push/apply pull worktree add` · `mkdir cp mv touch ln tee` · `sed -i` · redirección `>`/`>>` a un archivo |
| Edición del agente | pasa salvo rutas | no | Claude: `Edit Write MultiEdit NotebookEdit` · opencode: `edit` |
| Ejecuta código | tarjeta | **sí** | `python*` (cualquier forma, cualquier ruta como `venv/bin/python`) · `manage.py` · `pytest unittest` · `node bun deno ruby perl php` · `bash sh zsh` con script o `-c` · `./algo` · `source .` · `make` · `swift build/test/run` · `xcodebuild` · `npm pnpm yarn npx pnpx` · `uv uvx pip` · `celery gunicorn` · `docker` · `brew` · `osascript open launchctl` · `sqlite3 psql` · `eval exec` · `xargs`³ |
| Irreversible | tarjeta | **sí** | `rm rmdir` · `find -delete` · `git reset --hard` · `git clean` · `git checkout -- <rutas>` · `git restore` · `git branch -D` · `git stash drop/clear` · `git push --force` · `kill pkill killall` |
| Sale de la máquina | tarjeta | **sí** | `git push` · `gh pr create/merge/comment/close/edit/review` · `gh issue create/comment` · `gh release` · `gh api` · `curl wget scp rsync` · cualquier `*deploy*` · Claude: `WebFetch WebSearch` · opencode: la acción de lectura web, si la tiene. En dos semanas de historial hubo 5 de estas, así que la tarjeta casi no cuesta. |
| `ssh` | según el comando remoto | si no es lectura | `ssh [opciones] host '<cmd>'`: si todos los segmentos remotos son lectura, o `systemctl status`, `journalctl`, `free`, `uptime`, `docker ps`, `docker logs`, pasa. Cualquier otro caso, o `ssh` sin comando remoto (sesión interactiva), da tarjeta crítica. |
| Rutas protegidas | tarjeta | **sí** | Cualquier escritura (edición del agente, redirección, `cp`/`mv`/`tee`/`sed -i`/`ln` con destino) que caiga en la lista protegida de `hook.sh` **ampliada**⁴. Incluye `git config` con escritura, `git remote add/set-url` y cualquier `git -c …`, porque escriben `.git/config` o lo sustituyen. |
| Sensibles | tarjeta | **sí** | Leer o escribir: `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `id_rsa*`, `id_ed25519*`, `.netrc`, `.pgpass`, `.npmrc`, `.pypirc`, `**/credenciales/**`, `**/secrets.json`, `*service_account*.json`, `google_sa*.json`, `*cookies*.json` · archivos con contraseñas o tokens de herramientas: `~/.local/state/opencode/service*.json`, `~/.claude.json`, `**/.claude/settings*.json`, `~/.aws/**`, `~/.kube/**`, `~/.config/gh/**`, `~/.docker/config.json`, `~/.cline/data/**`, `~/Library/Keychains/**` |
| Preguntas y planes | tarjeta siempre | no | Claude: `AskUserQuestion`, `ExitPlanMode` · opencode: formularios `question` |
| Desconocido | tarjeta | no | Todo lo no reconocido; fallas de análisis; definiciones de funciones; una variable o sustitución como palabra de comando |

¹ `find` con `-exec`, `-execdir` u `-ok` se clasifica por el comando que ejecuta; con `-delete` es irreversible.
² `awk` cuyo programa contenga `system(`, `|`, `print >` o `getline <` se trata como ejecuta código.
³ `xargs` y `find -exec` se clasifican por el comando que lanzan. Si no se puede determinar, ejecuta código.
⁴ La lista de `hook.sh` de hoy, más lo que en modo auto sería código que corre después:
- **Configuración de opencode:** `~/.config/opencode/**`, `**/opencode.json`, `**/opencode.jsonc`, `**/.opencode/**`. Sus plugins son código, y ahí un agente podría darse permisos.
- **Hooks versionados:** `**/.husky/**`, `**/.githooks/**`, `**/.pre-commit-config.yaml`, `**/lefthook.yml`.
- **Directorios del `$PATH`:** cualquier carpeta del `$PATH` en el momento de evaluar, por ejemplo `/opt/homebrew/bin` o `~/.local/bin`. Un `cp x /opt/homebrew/bin/ls` convertiría el siguiente `ls` en otra cosa, incluso los `jq`/`pgrep` que usa el propio hook.
- **Compilados del buddy:** `**/claude-menubar-buddy*/.build/**`, porque el `LaunchAgent` arranca desde ahí.

Con esto, el riesgo aceptado de `git commit` (sección 11) se limita a los hooks que ya existían. El agente no puede escribir un hook nuevo sin tarjeta (decisión mía).

**Qué cuenta como "se puede deshacer"** (decisión mía). La tabla es la definición, más una revisión barata del disco, sin correr `git`. Una escritura con `>`, `cp`/`mv` hacia destino, `tee` o `sed -i` sobre un archivo que **ya existe**, fuera de un repo git (no hay `.git` subiendo desde la ruta) y fuera de las carpetas temporales (`/tmp`, `/private/tmp`, `$TMPDIR`), da tarjeta no crítica: ahí no hay cómo recuperar lo que se pisa. Esta revisión es solo para escrituras desde el shell. Las ediciones del agente pasan, porque Claude Code y opencode guardan su propio punto de restauración; el test actual con `~/Documents/notas.txt` lo espera así. `git checkout X` es irreversible si lleva `--` o si `X` es una ruta que existe; si no, es un cambio de rama y pasa.

### 5.2 Cómo se analiza un comando de shell

Hay que analizarlo completo, no solo la primera palabra. Es la parte con más riesgo, así que va con muchas pruebas.

- **Segmentos.** Se parte en `;`, `&&`, `||`, `|`, `&`, saltos de línea, subshells `( … )` y grupos `{ …; }`. Se respetan las comillas simples y dobles y el escape. **El veredicto es el del segmento más severo**, en este orden: crítico > desconocido > cambio local > lectura.
- **Prefijos.**
  - `time`, `nohup`, `timeout N`, `nice`, `command` y `env` sin asignaciones se quitan, y se clasifica lo que envuelven.
  - `sudo` es siempre crítico.
  - Una asignación `VAR=valor` delante de un comando da tarjeta (como hoy en `hook.sh`), con una excepción: si el comando que envuelve ya es crítico, sigue siendo crítico.
  - `PATH=`, `DYLD_*`, `LD_*` y `GIT_*` en cualquier lugar dan tarjeta crítica.
- **Asignaciones sueltas.** `D=/ruta` como sentencia propia es neutra. Una variable `$D` usada como argumento de un comando de lectura no cambia su categoría. En cambio, `$D` como destino de escritura da desconocido, porque no se puede revisar la ruta.
- **Sustituciones.** El comando dentro de `$( … )` y de las comillas invertidas se clasifica recursivamente. Si la sustitución es la palabra de comando, es desconocido.
- **Heredocs.** El cuerpo de `<<EOF … EOF` es dato, no comandos. Se clasifica el comando que lo consume: `python3 - <<EOF` ejecuta código; `cat <<EOF > f` es cambio local con destino `f`.
- **Ciclos y condicionales.** En `for`/`while`/`until`/`if`/`case` se clasifican los comandos del cuerpo; las palabras clave son neutras.
- **Funciones.** Definir una función (`f() { … }`) da desconocido.
- **Redirecciones.**
  - `>`, `>>` y `&>` hacia un archivo son una escritura en esa ruta, que se revisa contra la lista protegida y la de sensibles.
  - `2>&1`, `>/dev/null` y `2>/dev/null` son neutras.
  - `< archivo` es una lectura de esa ruta y se revisa contra la lista de sensibles.
- **Rutas relativas.**
  - Se resuelven contra el directorio de trabajo.
  - Los `cd <literal>` anteriores dentro del mismo comando lo actualizan.
  - Un `cd` con variable o sustitución hace desconocidas las escrituras relativas que vengan después.
  - La canonicalización y la comparación contra rutas protegidas reproducen exactamente las de `hook.sh` de hoy: barras repetidas, `./`, enlaces simbólicos con `pwd -P` o su equivalente en Swift, el padre existente más cercano para archivos que todavía no existen, y la comparación sin distinguir mayúsculas.
- **Fallas.** Cualquier cosa que el analizador no entienda da desconocido, es decir, tarjeta.

### 5.3 "Siempre permitir"

Mantiene la semántica actual de `always_allow.json`:
- una sola palabra base;
- un comando sin metacaracteres ni prefijos de entorno;
- alcance global o por directorio exacto.

Se evalúa en modo auto prendido o apagado, **nunca concede algo crítico** y ahora también aplica a opencode (el directorio es el de la sesión). El botón de la tarjeta solo aparece en tarjetas no críticas con una palabra base extraíble.

## 6. El modo auto

- **El interruptor:**
  - es el archivo de bandera `auto_mode` en `~/.config/claude-menubar-buddy/`;
  - lo lee el hook y lo cambia la app;
  - se maneja desde un elemento del menú "Modo auto" y una casilla en Settings;
  - se recuerda entre reinicios porque es un archivo;
  - empieza apagado en una instalación nueva.
- **Siempre visible.** Mientras está prendido, el ícono de la barra lleva una marca propia (reemplaza al lápiz) y la etiqueta de accesibilidad lo dice.
- **Reemplaza a "auto-aprobar ediciones":**
  - desaparecen su menú, su casilla, su fila en la tarjeta y su bandera;
  - si al arrancar existe el archivo viejo `auto_approve_edits`, se borra y el modo auto **no** se prende por eso.
- **Rastro:**
  - cada concesión automática agrega una línea JSON a `auto_decisions.jsonl` con `{ts, agent, project, cwd, tool, hint (recortado), category}`;
  - tiene la misma rotación que `decisions.jsonl`;
  - el submenú Decision History las muestra marcadas como "auto";
  - `DecisionStats` sigue contando solo las decisiones humanas.
- **App cerrada = sin modo auto:**
  - Claude Code recibe `{}` de inmediato, como hoy;
  - opencode pregunta en su terminal.

## 7. Entrega 1: la regla y el modo auto con Claude Code

### 7.1 `buddy-rule`
Es un nuevo `executableTarget` que depende solo de `BuddyCore`.
- **Lee:**
  - el JSON del hook de Claude por stdin;
  - la bandera `auto_mode` y `always_allow.json` del directorio de configuración, que es `$HOME/.config/claude-menubar-buddy`, para que el arnés de pruebas pueda cambiar `$HOME`.
- **Imprime:** `{"verdict":"pass"|"card","category":"…","critical":true|false,"reason":"…","grant":"auto"|"always"|null}`.
- **Debe ser rápido:** algunos milisegundos, porque corre en cada herramienta.
- **Instalación:** se copia a `~/.config/claude-menubar-buddy/` junto a `hook.sh`. El hook lo busca ahí, o en `$BUDDY_RULE` si la variable está definida, para los tests.

### 7.2 Nuevo flujo de `hook.sh`
1. Si la app no está corriendo, devuelve `{}`. **Sin cambios.**
2. Consulta `buddy-rule`. Si no existe o falla, toma `{verdict: card, critical: true, reason: "no se pudo evaluar la regla"}`. Es el lado seguro; el chequeo de salud debe avisar.
3. Si `verdict == pass`:
   - responde `allow` con el motivo `"Modo auto (<categoría>) vía Claude Menu Bar Buddy"` o el de "siempre permitir";
   - si es modo auto, agrega la línea a `auto_decisions.jsonl`.
4. Si no, crea la tarjeta como hoy. El archivo `request_<id>.json` suma `agent: "claude"`, `category`, `critical` y `reason`.
5. La espera y las respuestas siguen igual (`allow`/`deny`/`answer`), salvo `pass` (el botón ↗ "responder en la terminal"), que ahora responde `ask` y no `{}`. Con `{}`, el modo auto de Claude dejaría decidir a su clasificador; `pass` significa que el usuario contesta allá (revisión en vivo del 2026-10-22).
6. **Si se acaba el tiempo:**
   - si es crítico, responde `ask` con el motivo *"Claude Menu Bar Buddy no recibió respuesta a tiempo (MOTIVO). Confirma aquí si quieres que se ejecute."*. Claude Code muestra entonces su propio prompt, que espera sin límite de tiempo, y ningún modo, ni el auto, puede aprobarlo en silencio (documentación de hooks de Claude Code). Así no se ejecuta y la sesión tampoco se corta. Decisión del usuario en la prueba en vivo del 2026-10-22; antes era `deny`.
   - si no es crítico, responde `{}`, como hoy.
7. Se elimina el camino rápido de `auto_approve_edits`. Las ediciones pasan por la regla.
8. El camino rápido de "siempre permitir" en bash se reemplaza por la respuesta de `buddy-rule`, para que la regla tenga una sola implementación.
9. Si el JSON del hook trae `permission_mode == "plan"`, el buddy nunca concede en automático: donde la regla diría "pasa", responde `{}` y deja que el modo plan de Claude decida (decisión mía). Las tarjetas se muestran igual.

`notify-done.sh` no cambia.

**Consecuencia que hay que conocer.** Con la app corriendo, una tarjeta crítica sin respuesta regresa al prompt de Claude (`ask`) aunque `~/.claude/settings.json` tenga una regla `allow` para ese comando. Hoy hay reglas así para `venv/bin/python …`, `manage.py test`, `scp`, `curl` y `ssh`. Hoy esas reglas lo ejecutarían al agotarse el tiempo; con este diseño gana la decisión del usuario: lo crítico espera. Aplica también a sesiones que corren sin nadie mirando.

### 7.3 La app
- **La tarjeta:**
  - muestra el motivo ("Te detuve: ejecuta Python") y el agente;
  - en las críticas oculta "siempre permitir".
- **Tarjetas críticas y atajos** (decisión mía). Con el modo auto, casi todas las tarjetas que quedan son críticas, y la costumbre de aprobar con ⌘⏎ es justo el hueco que esta ronda quiere cerrar (un comentario en `main.swift` registra una aprobación por costumbre en dos segundos). Por eso:
  - el atajo global de aprobar no responde en una tarjeta crítica hasta 1.5 s después de que apareció; el clic con el mouse sí funciona de inmediato;
  - las críticas quedan fuera de "Allow all (N)" y de cualquier aprobación por lote.
- **Menú, Settings e ícono:** el modo auto reemplaza a "auto-aprobar ediciones".
- **Historial:** agrega las entradas "auto".
- **Chequeo de salud:** que `buddy-rule` exista, sea ejecutable y responda.
- **Instrucciones (README/SKILL.md):** qué copiar a `~/.config/claude-menubar-buddy/` después de compilar (`hook.sh` y `buddy-rule`).

### 7.4 Pruebas
- **Tabla de la regla en `BuddyCore`.** Cientos de casos: uno o más por fila de la sección 5.1 y por cada regla de la 5.2. Incluye por lo menos estos casos adversarios, todos con resultado tarjeta y crítico:
  - `grep x f; python3 y.py`
  - `cat $(python3 -c 'print(1)')`
  - `echo x >> ~/.zshrc`
  - `ssh h "tail -n5 log; sudo reboot"`
  - `ssh h`
  - `find . -name '*.pyc' -exec rm {} \;`
  - `awk 'BEGIN{system("touch /tmp/x")}'`
  - `git -c core.pager=sh log`
  - `GIT_PAGER=sh git log`
  - `sed -n '1w /tmp/x' f`
  - `PATH=/tmp/evil ls`
  - `cd ~/.ssh && echo k > authorized_keys`
  - `cp a ~/Library/LaunchAgents/x.plist`
  - `bash -c 'ls'`
  - `cat .env`
  - `venv/bin/python manage.py test`
  - `python3 - <<EOF … EOF`
- **Contrato de `buddy-rule`.** La entrada por stdin y la salida JSON exacta.
- **`HookTests`:**
  - cada caso que existe hoy conserva su resultado;
  - los casos de `autoEdits` pasan a usar el modo auto, con las mismas entradas y los mismos resultados;
  - se agregan casos nuevos: pasa en modo auto (con su línea en el log), un crítico agotado devuelve `deny`, un no crítico agotado devuelve `{}`, y si falta `buddy-rule` hay tarjeta.
  - Para no esperar 55 s, se agrega una variable de entorno solo para tests que acorta la espera, por ejemplo `BUDDY_HOOK_WAIT_TICKS`.
- **Sin comandos reales del historial.** Los casos se escriben a mano, porque el repo es público.

## 8. Entrega 2: opencode

### 8.1 Lo que ya está verificado en el servicio real (opencode 2.1.2, 2026-10-21)

**Descubrimiento**
- El archivo `~/.local/state/opencode/service.json` (modo 0600) trae `{id, version, url, pid, password}`. La URL es `http://127.0.0.1:49374`.
- Se autentica con `Basic opencode:<password>`.
- La especificación está en `GET /openapi.json`.

**Eventos**
- `GET /api/event` es SSE: líneas `data: {json}` y latidos `: heartbeat`.
- Envoltorio: `{id, created, type, location?: {directory}, data, durable?}`.
- Llegan eventos de todas las carpetas y sesiones.

**Permisos**
- `permission.asked`:
  - trae `data = {id: "per…", sessionID, action: "shell"|"edit"|"read"|…, resources: [..], save: [..], metadata?, source: {type:"tool", messageID, id: <callID>}}`;
  - en `shell`, `resources` es el comando **partido en piezas** (por ejemplo `["ls -la f 2>&1", "echo \"---\"", "cat -A f 2>&1", "tail -20"]`);
  - en `edit`, `metadata.files[] = {file, patch (diff unificado), status, additions, deletions}`.
- `session.tool.called` llega unos 12 ms **antes** que el permiso, con `data = {sessionID, id: <callID>, input}`:
  - en shell, `input = {command: "<comando completo>"}`;
  - en edit, `input = {path (absoluta), oldString, newString}`;
  - el permiso y su comando se relacionan por `source.id == callID`.
- **Responder:** `POST /api/session/{sessionID}/permission/{requestID}/reply` con `{"decision":"once"|"always"|"reject","message"?:string}`:
  - devuelve **204**;
  - la terminal de opencode quita su prompt sola;
  - `reject` con `message` le hace llegar el mensaje al modelo, que sigue trabajando;
  - el evento `permission.replied` trae `{sessionID, requestID, reply}`.
- **Consultar si sigue pendiente:** `GET /api/session/{sid}/permission/{rid}` devuelve 200 con el `Permission.Request`. Si ya se contestó, la respuesta es 404 (`PermissionNotFound`), según la especificación; no se probó.

**Preguntas**
- `form.created` trae `data.form = {id: "frm_…", sessionID, title, metadata: {kind:"question", tool:{messageID,id}}, fields: [{key:"q0", title, description, type:"string", options:[{value,label,description}], custom: true}]}`.
- **Responder:** `POST /api/session/{sid}/form/{fid}/reply` con `{"answer":{"q0":"Rojo"}}` devuelve **204**, y `form.replied` trae `{id, sessionID, answer}`.
- Existen `Form.MultiselectField` (valor de tipo arreglo) y `DELETE /api/session/{sid}/form/{fid}`.

**Turnos**
- `session.execution.started` y `session.execution.succeeded/failed/interrupted` traen solo `{sessionID}`, sin `location`.
- `GET /api/session/{sid}` da `{title, location.directory, model, tokens, cost, time}`.
- `session.created` sí trae `location`.

Hay capturas de estos eventos (192, de una sesión de prueba) que sirven como fixtures. Antes de subirlas al repo hay que **sanearlas**: las rutas reales se reemplazan por `/tmp/oc-prueba`.

### 8.2 Cómo funciona

- **El puente con opencode (app)**
  - **Conexión:** lee `service.json`; solo se conecta si la URL es loopback (`127.0.0.1`/`localhost`); nunca registra la contraseña en los logs.
  - **Si no está opencode:** sin archivo o sin conexión, queda inactivo y reintenta con espera creciente (1 s → 30 s), sin bloquear el hilo principal.
  - **Al (re)conectar:** recupera los permisos y formularios pendientes. El endpoint para listar pendientes de todas las carpetas no está verificado: confirmarlo contra `/openapi.json` en la tarea correspondiente.
- **Partes puras en `BuddyCore`**, con tests a partir de las fixtures:
  - modelos `Codable` del envoltorio y de los eventos que se usan;
  - el caché `callID → input`, con caducidad;
  - el caché `sessionID → directorio y título`;
  - la conversión de un permiso más su `tool.called` en una solicitud del buddy.
- **Una cola para los dos agentes.** Las solicitudes de opencode entran a la misma cola y a la misma tarjeta que las de Claude, con `agent: "opencode"`. Lo que cambia es **cómo se contestan**: Claude por archivo de respuesta, opencode por HTTP. Esa diferencia se modela explícitamente; no se reparte en `if`s por toda la app.
- **Cuando llega un `permission.asked`:**
  1. Clasifica con la regla. Usa el comando completo de `tool.called`; si no llegó, las `resources` unidas con `; `. En ediciones usa la ruta absoluta de `input.path`, o `resources` resuelto contra el directorio de la sesión.
  2. Si pasa (modo auto o "siempre permitir"), responde `once` de inmediato y registra en `auto_decisions.jsonl`.
  3. Si no pasa, espera unos 300 ms y confirma con `GET` que siga pendiente, por el bug #47545 de opencode (el auto-aceptar de su terminal aprueba del lado del cliente). Si sigue pendiente, muestra la tarjeta.
- **Botones de la tarjeta:**

  | Botón | Qué hace |
  |---|---|
  | Permitir | `once` |
  | Rechazar | `reject` con el mensaje `"El usuario lo rechazó desde el buddy."` (o el motivo específico de la tarjeta) |
  | Siempre permitir | Solo en tarjetas no críticas: agrega la palabra base a `always_allow.json` (alcance: el directorio de la sesión) y responde `once` |
  | Pasar a la terminal | Quita la tarjeta sin responder; la terminal de opencode conserva su prompt |

- **Si se contesta en la terminal:** cuando llega `permission.replied` de algo que está en la tarjeta, la tarjeta se retira en silencio. Un 404 al responder significa lo mismo: alguien ya contestó.
- **Sin límite de tiempo.** Las solicitudes de opencode no tienen la ventana de 60 s de Claude: esperan hasta que alguien conteste, aquí o en la terminal. Lo crítico, por lo tanto, nunca se ejecuta sin respuesta.
- **Ediciones.** La tarjeta muestra el diff de `metadata.files[].patch` en el estilo de mini-diff que ya existe.
- **Preguntas.**
  - Si todos los campos son de una opción con `options`, la tarjeta ofrece las opciones y responde `{answer: {key: value}}`.
  - Si algún campo es de varias opciones o sin opciones, no se muestra tarjeta y se contesta en la terminal (igual que hoy con `multiSelect` de Claude).
  - `form.replied` y `form.cancelled` retiran la tarjeta.
- **Turno terminado.** Usa `execution.started` → `succeeded`/`failed`/`interrupted` por sesión, con el mismo aviso y el mismo umbral que Claude. El nombre del proyecto sale de `GET /api/session/{sid}`, con caché. Ignora las sesiones hijas (subagentes) si el campo `parentID` existe; verificarlo.
- **Encabezado de la tarjeta.** "opencode · <proyecto>"; sin botón de "ir a la sesión".
- **Chequeo de salud:**
  - si opencode está conectado o no;
  - si la configuración global de opencode tiene `shell` y `edit` en `ask`. Solo avisa, no edita.
- **README.** Qué agregar a `~/.config/opencode/opencode.json`:

  ```json
  "permissions": [
    { "action": "shell", "resource": "*", "effect": "ask" },
    { "action": "edit",  "resource": "*", "effect": "ask" }
  ]
  ```

  Las reglas `allow`/`deny` de cada proyecto siguen aplicando antes que el buddy.

## 9. Cómo se construye: el experimento

- **Dónde:** el worktree `~/Desktop/repos/claude-menubar-buddy-opencode`, rama `modo-auto-y-opencode`.
- **El plan:** se escribe con *superpowers:writing-plans* en `docs/superpowers/plans/`, en tareas pequeñas con archivos, código esperado, test y comando de verificación. Agrega un `AGENTS.md` con las reglas del repo.
- **Quién lo ejecuta:** **DeepSeek V4.1 Flash** en opencode. Si se atora dos veces en una tarea, esa tarea se repite con Kimi K3 y se anota. La bitácora de comportamiento del modelo vive fuera del repo.
- **Permisos de opencode en el worktree** (`opencode.jsonc`, decisión del usuario):
  - **shell** pregunta por defecto;
  - **permite:** `swift build`, `swift test …`, `shellcheck …` y `git status/diff/log/show/add/commit`;
  - **niega:** `git push`, `rm`, `sudo`, `ssh`, `curl` y `launchctl`;
  - **edit:**
    - dentro del worktree se permite, salvo `opencode.jsonc`, `.opencode/**`, `AGENTS.md` y `Package.swift`, que preguntan;
    - fuera del worktree se niega.
  - **Riesgo aceptado:** `swift build` y `swift test` corren código que escribe el modelo, y en esta máquina hay llaves SSH a servidores. Durante el desarrollo, esta configuración es la única barrera, porque el buddy en vivo todavía no ve opencode. Lo mitiga la revisión al final de cada bloque.
- **Revisión:** Claude revisa al final de cada bloque. Hay dos PRs a `personal` (entrega 1 y entrega 2) y el merge lo hace el usuario.
- **Puesta en vivo:** solo después de cada merge: compilar en la carpeta principal, copiar `hook.sh` y `buddy-rule` a `~/.config/claude-menubar-buddy/` y reiniciar con `launchctl kickstart`.

## 10. Lo que queda al constructor

- La organización interna de tipos y archivos y los nombres.
- La implementación del analizador de shell: a mano, sin dependencias.
- Los detalles visuales de la marca del modo auto, la línea de motivo y la etiqueta de agente, dentro de `CardTheme`.
- Los tiempos de reintento y la caducidad de los cachés.
- Ampliar las listas de la sección 5.1, siempre con un test por cada comando agregado.

## 11. Riesgos y temas abiertos

- **El analizador de shell es la pieza de mayor riesgo.** El sesgo es deliberado: lo que no se entiende da tarjeta. Las pruebas adversarias de 7.4 son el mínimo.
- **`git commit` puede ejecutar los hooks del repo** (por ejemplo `pre-commit`) y aun así pasa, porque es un cambio local y así lo decidió el usuario. Queda documentado como riesgo aceptado. Solo cubre hooks que ya existían; escribir uno nuevo es ruta protegida.
- **Lecturas indirectas de secretos.** Variables, comodines y búsquedas recursivas (`F=.env; cat $F`, `cat .en?`, `grep -r TOKEN .`) pueden leer un secreto sin tarjeta. Sacarlo de la máquina sí pide tarjeta (web, `curl`, `push`, `gh` cuando publica, `ssh` con algo que no sea lectura). Queda un hueco aceptado: `ssh` a un servidor propio con un comando de lectura que lleve el secreto en sus argumentos.
- **opencode v2 cambia cada semana.** El puente falla cerrado: los eventos desconocidos se ignoran, los errores de decodificación se registran sin tumbar la app, y si una respuesta falla la tarjeta se queda.
- **Sin verificar:**
  - el endpoint para recuperar pendientes de todas las carpetas;
  - el campo `parentID` de las sesiones;
  - el comportamiento con el auto-aceptar de la terminal de opencode (#47545);
  - la reconexión del SSE tras un reinicio de opencode.
