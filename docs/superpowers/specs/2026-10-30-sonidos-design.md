# Sonidos del buddy — diseño

Fecha: 2026-10-30 · Rama: `sonidos` (desde `personal`) · Estado: borrador para aprobación

## 1. Para qué es esto

El buddy suena en cuatro momentos, y los cuatro sonidos vienen fijos en el código desde el fork:

| Evento | Sonido de hoy | Dónde |
|---|---|---|
| Llega una tarjeta | `NSSound(named: "Ping")` | `ApprovalCard.swift`, al final de `setPending` |
| Termina un turno | `NSSound(named: "Glass")` | `Toast.swift`, en `processDoneMarkers` |
| Clic a la mascota | `NSSound(named: "Tink")` | `MoodEngine.swift`, en `petClicked` |
| ⌘⏎ bloqueado en una tarjeta crítica | `NSSound.beep()` | `CardDecision.swift`, en `decideViaHotKey` |

No hay ningún ajuste de sonido. El que más pesa es el de la tarjeta, porque suena con cada permiso: al usuario **el Ping ya le cansa porque es muy agudo y metálico**. Quiere algo **suave y grave, como una gota, madera o un "toc"**.

Esta ronda deja elegir el sonido de cada evento desde el menú de la barra, o silenciarlo. También trae sonidos propios, todos de licencia CC0 o de dominio público, porque el repo es público.

## 2. Metas, no-metas y anti-metas

**Metas**
1. **Elegir el sonido de cada uno de los cuatro eventos** desde el menú de la barra.
2. **Silenciar cada evento por separado.**
3. **Escuchar el sonido al elegirlo.**
4. **Sonidos propios suaves**, empezando por el de la tarjeta, con fuente y licencia comprobables en el repo.
5. **El "atajo bloqueado" se oye siempre que esté elegido**, sin depender de la configuración de alertas de macOS (sección 9).

**No-metas en esta ronda**
- Volumen propio del buddy, aparte del de la Mac (supuesto, sección 4.3).
- Un panel de sonidos en la ventana de Settings. El usuario lo pidió en el menú.
- Escuchar el sonido al pasar el mouse por encima, sin elegirlo.
- Cargar sonidos propios del usuario desde un archivo.
- Sonidos distintos según el agente (Claude Code u opencode), el proyecto o si la tarjeta es crítica.
- Respetar Concentración / No molestar.

**Anti-metas: fracaso aunque "funcione"**
- **Un archivo de sonido sin fuente o sin licencia comprobable en el repo.** Cualquiera debe poder ver de dónde salió cada archivo y bajo qué licencia, y un test lo vigila (sección 8).
- **Un sonido que no se puede reproducir** (por ejemplo, un OGG) y deja un evento mudo sin que nadie lo note.
- **Un ajuste que se pierde o deja un evento sin sonido por accidente.** Si el valor guardado ya no existe en el catálogo, se usa el sonido por defecto de ese evento, nunca el silencio.
- **Más consumo en reposo.** Nada de timers ni de trabajo en segundo plano: los sonidos se cargan la primera vez que suenan y se guardan en memoria (el usuario es sensible al CPU).

## 3. Restricciones

- **Swift + AppKit:** se compila con `swift build` usando solo Command Line Tools, sin Xcode, y apunta a macOS 13+. **Sin dependencias nuevas:** `NSSound` alcanza.
- **Dónde va la lógica:** la lógica pura (el catálogo, la resolución del valor guardado, el modelo del menú y las reglas de reproducción) va en `BuddyCore`, con tests. La app solo cablea. Los tests no importan la app.
- **Formatos:** solo WAV, AIFF o CAF dentro del repo. `NSSound` no reproduce OGG, y no hay convertidor instalado (no está `ffmpeg`; `afconvert` no lee OGG).
- **El buddy en vivo corre desde la carpeta principal del repo.** Todo el trabajo va en el worktree `~/Desktop/repos/claude-menubar-buddy-sonidos`.
- **El repo es público.**

## 4. Decisiones

### 4.1 Del usuario

- Se pueden cambiar los cuatro sonidos, pero **el de la tarjeta es el primero**.
- El de la tarjeta: **suave y grave, como una gota, madera o un "toc"**. Nada agudo ni metálico.
- Se cambian **desde el menú de la barra**.
- **El sonido suena al elegirlo.**
- **Cada evento tiene su opción de silencio.**
- Los sonidos nuevos son **CC0, de dominio público o hechos por nosotros**, con su fuente y su licencia en el repo.
- **La búsqueda de candidatos la hace DeepSeek** en opencode (resultados en `docs/superpowers/research/2026-10-30-sonidos-sin-licencia.md`).

### 4.2 Mías (revísalas)

1. **Un solo catálogo para los cuatro eventos.** Cualquier evento puede usar cualquier sonido. Así el usuario arma su combinación sin listas distintas por evento.
2. **El catálogo incluye los 14 sonidos de macOS** (`/System/Library/Sounds`: Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine y Tink). Vienen en toda Mac y no se copian al repo, así que no tienen problema de licencia. Además, el que quiera puede volver a los sonidos de hoy.
3. **Valores por defecto:**
   - **Tarjeta nueva:** el sonido propio que el usuario elija como favorito al escuchar los candidatos (sección 6.1). Es el único que cambia sin que nadie toque el menú, porque el Ping es justo lo que se quiere quitar.
   - **Turno terminado:** Glass; **clic a la mascota:** Tink. Son los de hoy.
   - **Atajo bloqueado:** deja de ser `NSSound.beep()` y pasa a ser un sonido explícito del catálogo (sección 9). Cuál, se decide al escuchar los candidatos; si ninguno convence, Basso de macOS (grave, 0.77 s).
4. **El atajo bloqueado corta el sonido de la tarjeta** si sigue sonando. Así no lo tapa (sección 9).
5. **Si un sonido ya está sonando, vuelve a empezar.** `NSSound(named:)` devuelve siempre la misma instancia, y `play()` sobre una instancia que suena no hace nada. Por eso hoy, con dos tarjetas seguidas, la segunda llega muda.
6. **Ganancia por sonido.** Cada sonido del catálogo lleva su volumen relativo (de 0 a 1, aplicado con `NSSound.volume`) para que los de fuentes distintas suenen parejos. Se fija al escucharlos. Los de macOS van en 1.0.
7. **Cada fila del submenú dice qué sonido tiene**, por ejemplo "Tarjeta nueva — Gota", para no tener que abrirla para saberlo.
8. **"Sonidos" vive solo en el menú de reposo.** Mientras hay una tarjeta, el menú de la barra es el de la tarjeta, y no se toca.
9. **Elegir el que ya está marcado lo vuelve a tocar**, para escucharlo otra vez. Elegir "Sin sonido" no toca nada.
10. **Quién baja los archivos:** Claude, con el OK del usuario para cada descarga, antes del primer bloque del plan. DeepSeek no puede (`curl` y `wget` están negados en `opencode.jsonc`), y los tests del plan necesitan que los archivos ya estén en el repo.
11. **Si la investigación no da al menos tres sonidos suaves y graves que convenzan para la tarjeta**, se generan nosotros mismos con un script de síntesis (ondas senoidales amortiguadas, sin muestras de nadie):
    - El script es Swift, en `scripts/generate-sounds.swift`, y escribe WAV.
    - Claude lo corre con `swift scripts/generate-sounds.swift` antes del plan, igual que las descargas. DeepSeek no lo corre.
    - En `CREDITS.md`, la fuente de esos archivos es la ruta del script y la licencia es la MIT del repo. La auditoría (sección 8) acepta esa forma, siempre que el script exista.

### 4.3 Supuestos sin contestar

- **Volumen propio del buddy: no en esta ronda.** Los sonidos siguen el volumen de la Mac, y la ganancia por sonido (4.2.6) los deja suaves. Si se quiere, sería un submenú "Volumen" con tres niveles que multiplica la ganancia. Agregarlo después no cambia nada de lo demás.

## 5. Comportamiento

### 5.1 Los eventos

| Evento | Cuándo suena | Excepción que se conserva |
|---|---|---|
| **Tarjeta nueva** | Cuando aparece una tarjeta (permiso, pregunta o plan; Claude Code u opencode). Suena en `setPending`, donde suena hoy. **No se mueve a `showStatusBubble`**, porque `poll()` la vuelve a llamar cada vez que la cola crece o se achica, y sonaría con cada cambio de la cola. | No suena si el usuario cambia de tarjeta a mano en la cola (`switchingCardByHand`). |
| **Turno terminado** | Cuando sale el aviso de turno terminado: el toast junto a la mascota o, si la mascota está oculta, el banner que lo reemplaza (`showDoneToast`). Igual que hoy. | No suena cuando el aviso se degrada a banner porque hay una tarjeta en pantalla (hoy tampoco). |
| **Clic a la mascota** | Al dar clic a la mascota flotante. | — |
| **Atajo bloqueado** | Cuando ⌘⏎ (o el de "siempre") se rechaza en una tarjeta crítica antes de 1.5 s. | La sacudida de la tarjeta sigue igual. |

Con "Sin sonido" en "Atajo bloqueado" y Reducir movimiento prendido, el rechazo no se nota. Es la elección del usuario.

### 5.2 El menú

En el menú de reposo, justo antes de "Modo auto":

```
Sonidos                        ▸
    Tarjeta nueva — Gota          ▸   ✓ Gota
    Turno terminado — Glass       ▸     Madera
    Clic a la mascota — Tink      ▸     Toc
    Atajo bloqueado — Basso       ▸     …(los propios)
                                        ─────────
                                        macOS            (encabezado, no se puede elegir)
                                        Basso
                                        …
                                        Tink
                                        ─────────
                                        Sin sonido
```

- Los textos nuevos van en español: "Sonidos", los nombres de los eventos, los nombres de los sonidos propios y "Sin sonido". Los de macOS conservan su nombre.
- La palomita marca el sonido actual del evento.
- Al elegir uno, se guarda, se reconstruye el menú y se toca una vez el sonido elegido, con su ganancia. Para reconstruir, se sigue el patrón de `toggleAutoMode` y `toggleFloatingPet`: `buildIdleMenu()` y luego `setIdle()` si no hay tarjeta. Solo `setIdle()` le asigna el menú nuevo a `statusItem.menu`. **`petSizeChanged` no sirve de modelo:** no llama a `setIdle()`, así que la palomita nueva no se vería hasta la siguiente tarjeta, y su `return` temprano cuando el valor no cambia contradice 4.2.9.
- Si un sonido de macOS no existe en la Mac (`NSSound(named:)` da `nil`), su fila no aparece.

### 5.3 Reproducción

- Cada sonido del catálogo se carga una sola vez, la primera vez que suena, y se guarda en memoria. Los propios salen del bundle (`Bundle.module`, subcarpeta `Resources/Sounds`) y los de macOS de `NSSound(named:)`.
- Antes de tocar un sonido se detiene si ya sonaba (4.2.5) y se le aplica su ganancia.
- Antes de tocar el de "Atajo bloqueado" se detiene el de "Tarjeta nueva" (4.2.4).
- Si un archivo propio falta o no se puede abrir, el evento queda mudo esa vez y no truena. El test de auditoría (sección 8) existe para que eso no llegue a pasar.

### 5.4 Lo que se guarda

Cuatro llaves de `Defaults` (en `Prefs.swift`, con el resto), una por evento: `cardSound`, `turnDoneSound`, `petClickSound` y `blockedSound`. Cada una guarda el id del sonido o `none`.

- **Ids:** los propios llevan un id corto en inglés (`drop`, `wood`…), los de macOS `macos.<Nombre>` (`macos.Ping`) y el silencio `none`.
- **Al leer:** un id desconocido (un sonido retirado, un valor corrupto) se resuelve al sonido por defecto de ese evento. Es el mismo patrón que `CardPalette.resolve` y `MoodPolicy.resolvedSpecies`.

## 6. Catálogo

### 6.1 Sonidos propios

**Pendiente de la investigación.** DeepSeek busca candidatos CC0 o de dominio público para los cuatro eventos. Luego:

1. el usuario escucha los mejores (Claude los baja al scratchpad, con su OK, y los toca);
2. se eligen **entre 6 y 8 sonidos propios en total, con al menos 3 para la tarjeta** (gota, madera, toc);
3. se fijan aquí su id, su nombre en español, su archivo, su ganancia, su fuente, su licencia y cuál es el favorito de la tarjeta.

Si hace falta recortar un archivo (quitarle silencio o una cola larga) o pasarlo a WAV, Claude lo hace al bajarlo y lo anota en los créditos. CC0 lo permite.

### 6.2 Sonidos de macOS

Los 14 de `/System/Library/Sounds`, en orden alfabético, con su nombre tal cual y ganancia 1.0.

### 6.3 Créditos y licencias

- Los archivos van en `Sources/ClaudeMenuBarBuddy/Resources/Sounds/`, con un `CREDITS.md` al lado. Es el mismo patrón que `Resources/Fonts/`, que trae su `OFL-*.txt` junto a cada fuente.
- Por cada archivo, `CREDITS.md` dice:
  - el nombre del archivo y el id del catálogo;
  - el autor y el paquete;
  - la página de la fuente y la URL exacta de descarga (fijada a un commit si es GitHub);
  - la licencia, con el enlace donde se declara;
  - el SHA-256 del archivo tal como se bajó;
  - si se modificó, qué se le hizo (recorte, conversión).
- El README suma una línea de créditos de sonidos junto a la de las fuentes.

## 7. Arquitectura

**`Sources/BuddyCore/Sounds.swift`** (nuevo, todo `public`):
- `SoundEvent`: los cuatro eventos, con el nombre que se ve en el menú, la llave de `Defaults` y el id por defecto.
- `SoundOption`: id, nombre visible, origen (archivo propio con su nombre y extensión, o sonido de macOS por nombre) y ganancia.
- `SoundCatalog`:
  - la lista ordenada: primero los propios y luego los de macOS;
  - buscar por id;
  - resolver un valor guardado para un evento: da la opción, o el silencio, o el valor por defecto si el id es desconocido.
- El modelo del submenú de un evento: la lista de filas (sonido marcado o no, encabezado "macOS", separador, "Sin sonido"), para que la app solo la pinte.
- La regla de qué sonidos se detienen antes de tocar cada evento.

**App:**
- `Sources/ClaudeMenuBarBuddy/SoundPlayer.swift` (nuevo): el caché de `NSSound` por id, `play(event)` (lee `Defaults`, resuelve, detiene lo que diga la regla y toca) y `preview(option)`.
- `Prefs.swift`: las cuatro llaves.
- `Menus.swift`: el submenú "Sonidos" en `buildIdleMenu` y su acción.
- Los cuatro sitios de hoy llaman a `play(event)` en lugar de `NSSound` directo.

**`Package.swift` no cambia.** El target de la app ya declara `resources: [.copy("Resources")]`, que copia la carpeta entera, con sus subcarpetas, al bundle. Las fuentes ya se cargan así con `subdirectory: "Resources/Fonts"`, y los sonidos usarán `subdirectory: "Resources/Sounds"`. El `CREDITS.md` también viaja en el bundle, como los `OFL-*.txt`.

## 8. Tests

En `BuddyCore`, con Swift Testing:
- los ids del catálogo son únicos, y el de cada evento por defecto existe;
- resolver: un id conocido da su opción, `none` da silencio, y uno desconocido o vacío da el de por defecto del evento;
- el modelo del submenú: el orden, la palomita en la fila correcta, el encabezado y "Sin sonido" al final;
- la regla de reproducción: "Atajo bloqueado" detiene "Tarjeta nueva", y los demás no detienen nada;
- **auditoría contra el repo** (como la de `MoodPolicyTests`, que lee `Resources` vía `#filePath`):
  - cada sonido propio del catálogo tiene su archivo en `Resources/Sounds/`;
  - cada archivo de audio de esa carpeta está en el catálogo, para que no haya archivos sin licencia;
  - cada uno aparece en `CREDITS.md` con su licencia y su fuente: CC0 o dominio público con una URL, o MIT con la ruta de un script del repo que existe (4.2.11);
  - ninguno es OGG.

La app (el menú, `NSSound`) no tiene tests; se prueba en vivo.

## 9. Por qué no sonó el beep en la prueba

Esto se comprobó en la Mac del usuario el 2026-10-30:

- `NSSound.beep()` no tiene sonido propio: toca **el sonido de alerta del sistema**, que en esta Mac es Tink (`com.apple.sound.beep.sound`), de 0.56 s y muy suave.
- Usa el volumen de alertas de macOS y la salida de "efectos de sonido", no la del resto de la app. Si cualquiera de los dos está bajo o en otro dispositivo, no se oye.
- **La tarjeta crítica rechaza ⌘⏎ durante 1.5 s** (`CardSafety.criticalHotKeyDelay`), y **el Ping dura 1.50 s**. Todo ⌘⏎ rechazado cae mientras el Ping de esa misma tarjeta sigue sonando, y el Tink queda tapado.

Lo arreglan tres decisiones: un sonido explícito para el evento (4.2.3), cortar el de la tarjeta (4.2.4) y un sonido de tarjeta más corto (6.1).

## 10. Lo que queda al constructor

- Los nombres internos que esta spec no fija (los tipos de los casos, los nombres de las funciones). El plan los fija para DeepSeek.
- Cómo se pinta el encabezado "macOS" (un `NSMenuItem` deshabilitado o `sectionHeader` donde exista; macOS 13 no lo tiene).
- Cómo sabe el modelo del submenú qué sonidos de macOS existen: un predicado inyectado, como el `available:` de `MoodPolicy.resolvedSpecies`. En la app, conviene revisar que exista el archivo en `/System/Library/Sounds` en lugar de cargar los 14 con `NSSound(named:)` cada vez que se arma el menú.
- El formato exacto de `CREDITS.md`, siempre que la auditoría lo pueda leer y traiga lo de la sección 6.3.
- El texto exacto de la línea de créditos del README.

## 11. Riesgos

- **Los sonidos CC0 pueden no convencer.** Si pasa, se generan nosotros mismos (4.2.11).
- **Un paquete CC0 puede cambiar o desaparecer.** Por eso `CREDITS.md` guarda la URL fijada al commit y el SHA-256: aunque la fuente cambie, queda constancia de qué se bajó y bajo qué licencia.
- **Ganancias mal calibradas** hacen que un sonido brinque sobre los demás. Se ajustan en la prueba en vivo; es un número en el catálogo.
