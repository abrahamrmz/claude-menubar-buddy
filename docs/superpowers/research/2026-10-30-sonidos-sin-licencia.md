# Sonidos sin licencia para el buddy — investigación

Fecha: 2026-10-30 · Rama: `sonidos` · Fase: investigación (entrega 3)
Autor de la investigación: DeepSeek (opencode)

Busca candidatos de sonido, con licencia CC0 1.0 o dominio público **comprobada en la
fuente**, para los cuatro eventos del buddy. No se bajó ningún archivo: todo lo de
abajo se leyó de páginas web y de la API de GitHub (nombres, tamaños y hashes de
commit). Por eso **las duraciones no se pudieron medir**: donde la fuente no las
publica, dice "no dice".

Las fuentes de GitHub están fijadas al último commit de su rama por defecto, así que
la URL "raw" no cambia aunque el repositorio se mueva. Hashes usados:

- `Calinou/kenney-interface-sounds` → `4596a49eaf5a533948d49a47467f606bcdea70ff`
- `Calinou/kenney-ui-audio` → `8c3d81b9159d058c444f89d12d518276b0b09345`
- `sgossner/VCSL` → `c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e`

Las URLs de descarga de la sección 2 se comprobaron con una petición de solo
cabeceras (HTTP 200) y el tamaño reportado coincide con el de la API de GitHub; no se
bajó el contenido de ningún archivo.

---

## 1. Recomendación

### Tarjeta nueva (prioridad)

1. **`drop_001.wav`** (Kenney Interface Sounds) — el nombre dice literalmente "gota",
   que es justo lo que pidió el usuario; WAV, CC0 comprobado y muy chico (23 KB), así
   que lo más probable es que sea corto. Es el mejor primer candidato para escuchar.
2. **`wood_click_pp_rr3.wav`** (VCSL, Woodblock) — un golpe de woodblock suave
   (`pp` = pianissimo), es decir un "toc" de madera. CC0 comprobado. Es más grande
   (82 KB) y las muestras de VCSL son crudas y pueden traer cola/resonancia; hay que
   medir la duración al bajarlo y, si pasa de 0.6 s, recortarle la cola (CC0 lo permite).

### Turno terminado

1. **`confirmation_001.wav`** (Kenney Interface Sounds) — la familia "confirmation"
   es exactamente un "listo/confirmado" amable. WAV y CC0.
2. **`confirmation_003.wav`** (Kenney Interface Sounds) — misma familia, otra toma;
   sirve para comparar y elegir la que menos "metálica" suene.

### Clic a la mascota

1. **`click_004.wav`** (Kenney Interface Sounds) — clic muy corto (2 KB), juguetón.
2. **`select_007.wav`** (Kenney Interface Sounds) — "select" corto (5 KB); alternativa
   si `click_004` suena demasiado seco. Para un "pop/burbuja" literal, el mejor
   candidato externo es `3pops.zip` (ver tabla), pero su contenido no se pudo comprobar.

### Atajo bloqueado

1. **`LogDrumLo_MedM_v1_rr1_Sum.wav`** (VCSL, Slit Drum) — un tambor de tronco **bajo**
   (`Lo`), o sea un golpe sordo y grave: el "todavía no" que se pide. CC0.
2. **`bong_001.wav`** (Kenney Interface Sounds) — "bong" corto y grave; distinto de la
   gota de la tarjeta. WAV y CC0.

> Nota transversal: ninguna de estas fuentes publica la duración. Las duraciones
> pedidas (tarjeta ≤ 0.6 s, mascota ≤ 0.3 s, bloqueado ≤ 0.4 s, turno ≤ 1.5 s) hay que
> confirmarlas al bajar los archivos (Claude, con el OK del usuario, según la spec).
> Los WAV de Kenney son chicos y probablemente ya cumplen; los de VCSL son muestras
> crudas y pueden necesitar recorte.

---

## 2. Candidatos por evento

### 2.1 Tarjeta nueva (prioridad)

Base de Kenney Interface Sounds:
`https://raw.githubusercontent.com/Calinou/kenney-interface-sounds/4596a49eaf5a533948d49a47467f606bcdea70ff/addons/kenney_interface_sounds/`
Base de VCSL:
`https://raw.githubusercontent.com/sgossner/VCSL/c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e/Idiophones/Struck%20Idiophones/`

| Archivo | Paquete y autor | Página de la fuente | URL directa (fijada a commit) | Licencia y dónde la dice | Formato, tamaño, duración | Cómo suena (por nombre/descripción) |
|---|---|---|---|---|---|---|
| `drop_001.wav` | Kenney Interface Sounds — Kenney | https://kenney.nl/assets/interface-sounds · https://github.com/Calinou/kenney-interface-sounds | `…/kenney_interface_sounds/drop_001.wav` | CC0 1.0, en `LICENSE.txt`: "License: (Creative Commons Zero, CC0)" | WAV · 23 374 B · duración no dice | El nombre dice "drop" (gota). No se pudo escuchar. |
| `drop_002.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/drop_002.wav` | CC0 1.0, en `LICENSE.txt` (frase de arriba) | WAV · 35 662 B · duración no dice | Otra toma de "drop" (gota). No se pudo escuchar. |
| `bong_001.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/bong_001.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 11 726 B · duración no dice | El nombre dice "bong": golpe grave y corto. No se pudo escuchar. |
| `pluck_001.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/pluck_001.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 19 790 B · duración no dice | El nombre dice "pluck": pizzicato/pluck de cuerda. No se pudo escuchar. |
| `tick_001.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/tick_001.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 4 046 B · duración no dice | El nombre dice "tick" (tictac/toc). No se pudo escuchar. |
| `wood_click_pp_rr3.wav` | VCSL (Woodblock) — Versilian Studios LLC | https://github.com/sgossner/VCSL | `…/Woodblock/wood_click_pp_rr3.wav` | CC0 1.0, en `LICENSE` ("CC0 1.0 Universal") y en el README: "under a Creative Commons 0 license" | WAV · 82 468 B · duración no dice (muestra cruda, puede traer cola) | El nombre dice woodblock, golpe suave (`pp`). "Toc" de madera. No se pudo escuchar. |
| `Claves2_Hit_v1_rr1_Mid.wav` | VCSL (Claves) — Versilian Studios LLC | https://github.com/sgossner/VCSL | `…/Claves/Claves2_Hit_v1_rr1_Mid.wav` | CC0 1.0, en `LICENSE` y README | WAV · 126 800 B · duración no dice | El nombre dice claves (palos de madera), intensidad media. "Toc" de madera. No se pudo escuchar. |

### 2.2 Turno terminado

| Archivo | Paquete y autor | Página de la fuente | URL directa (fijada a commit) | Licencia y dónde la dice | Formato, tamaño, duración | Cómo suena (por nombre/descripción) |
|---|---|---|---|---|---|---|
| `confirmation_001.wav` | Kenney Interface Sounds — Kenney | https://kenney.nl/assets/interface-sounds · https://github.com/Calinou/kenney-interface-sounds | `…/kenney_interface_sounds/confirmation_001.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 26 062 B · duración no dice | El nombre dice "confirmation" (confirmación/listo). No se pudo escuchar. |
| `confirmation_002.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/confirmation_002.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 49 614 B · duración no dice | Otra toma de "confirmation". No se pudo escuchar. |
| `confirmation_003.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/confirmation_003.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 28 622 B · duración no dice | Otra toma de "confirmation". No se pudo escuchar. |
| `confirmation_004.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/confirmation_004.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 44 238 B · duración no dice | Otra toma de "confirmation". No se pudo escuchar. |
| `ui_wav.zip` (paquete) | UI Sound Effects — Robin Lamb | https://opengameart.org/content/ui-sound-effects-button-clicks-user-feedback-notifications | https://opengameart.org/sites/default/files/ui_wav.zip | CC0, en la página: "License(s): CC0" | ZIP con WAV y OGG · 1 364 100 B (1.4 Mb según la página) · duración no dice | La descripción dice que son "button clicks, selections, notifications, user feedback" sacados de VCSL y VSCO 2 CE. Los nombres internos no se listan en la página: **no comprobado**. |

### 2.3 Clic a la mascota

| Archivo | Paquete y autor | Página de la fuente | URL directa (fijada a commit) | Licencia y dónde la dice | Formato, tamaño, duración | Cómo suena (por nombre/descripción) |
|---|---|---|---|---|---|---|
| `click_004.wav` | Kenney Interface Sounds — Kenney | https://kenney.nl/assets/interface-sounds · https://github.com/Calinou/kenney-interface-sounds | `…/kenney_interface_sounds/click_004.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 1 998 B · duración no dice | El nombre dice "click"; por tamaño, un clic muy corto. No se pudo escuchar. |
| `click_002.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/click_002.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 1 102 B · duración no dice | "click", aún más corto. No se pudo escuchar. |
| `select_007.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/select_007.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 5 326 B · duración no dice | El nombre dice "select". No se pudo escuchar. |
| `toggle_004.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/toggle_004.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 6 606 B · duración no dice | El nombre dice "toggle". No se pudo escuchar. |
| `click5.wav` | Kenney UI Audio — Kenney | https://kenney.nl/assets/ui-audio · https://github.com/Calinou/kenney-ui-audio | `https://raw.githubusercontent.com/Calinou/kenney-ui-audio/8c3d81b9159d058c444f89d12d518276b0b09345/addons/kenney_ui_audio/click5.wav` | CC0 1.0, en `LICENSE.txt`: "License (Creative Commons Zero, CC0)" | WAV · 6 222 B · duración no dice | El nombre dice "click5". No se pudo escuchar. |
| `3pops.zip` (paquete) | 3 Pop Sounds — wubitog | https://opengameart.org/content/3-pop-sounds | https://opengameart.org/sites/default/files/3pops.zip | CC0, en la página: "License(s): CC0" y "No Attribution Required." | ZIP · 90 641 B · duración no dice | La descripción dice "3 Pops. I use them for bubble/dot popping". El formato interno no se lista: **no comprobado** (probablemente WAV). |

### 2.4 Atajo bloqueado

| Archivo | Paquete y autor | Página de la fuente | URL directa (fijada a commit) | Licencia y dónde la dice | Formato, tamaño, duración | Cómo suena (por nombre/descripción) |
|---|---|---|---|---|---|---|
| `LogDrumLo_MedM_v1_rr1_Sum.wav` | VCSL (Slit Drum) — Versilian Studios LLC | https://github.com/sgossner/VCSL | `…/Slit%20Drum/LogDrumLo_MedM_v1_rr1_Sum.wav` | CC0 1.0, en `LICENSE` y README | WAV · 198 684 B · duración no dice | El nombre dice log drum **bajo** (`Lo`): golpe sordo y grave. No se pudo escuchar. |
| `bong_001.wav` | Kenney Interface Sounds — Kenney | https://kenney.nl/assets/interface-sounds · https://github.com/Calinou/kenney-interface-sounds | `…/kenney_interface_sounds/bong_001.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 11 726 B · duración no dice | "bong": golpe grave y corto. No se pudo escuchar. |
| `error_008.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/error_008.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 12 366 B · duración no dice | El nombre dice "error": el "todavía no". Puede ser más agudo/buzo que un golpe sordo. No se pudo escuchar. |
| `error_004.wav` | Kenney Interface Sounds — Kenney | ídem | `…/kenney_interface_sounds/error_004.wav` | CC0 1.0, en `LICENSE.txt` | WAV · 18 510 B · duración no dice | Otra toma de "error". No se pudo escuchar. |
| `wood_click_pp_rr1.wav` | VCSL (Woodblock) — Versilian Studios LLC | https://github.com/sgossner/VCSL | `…/Woodblock/wood_click_pp_rr1.wav` | CC0 1.0, en `LICENSE` y README | WAV · 107 200 B · duración no dice | Woodblock suave (`pp`): "toc" seco y no metálico. No se pudo escuchar. |

---

## 3. Fuentes descartadas

- **Pixabay, Mixkit, Zapsplat, Uppbeat, Sonniss y sitios de sonidos hechos con IA:** excluidos por regla del encargo; no se consultaron.
- **Kenney Impact Sounds (mirror `Boyquotes/kenney-impact-sounds-for-godot`):** el único mirror en GitHub que se encontró viene **solo en OGG** (todos los `impact_*.ogg`), que macOS no reproduce. Su `LICENSE` sí es CC0, pero el formato lo descarta. Kenney lo publica en kenney.nl como ZIP; no se pudo comprobar que traiga WAV sin bajarlo.
- **OpenGameArt "bubble-pop" (pokmon63):** licencia **CC-BY 3.0**, no CC0. Descartado. (Su único archivo es `Plop.ogg`, además OGG.)
- **OpenGameArt "pop-sounds" (cogitollc):** CC0, pero **todos los archivos son `.ogg`** (`pop1.ogg`…`pop10.ogg`). Descartado por formato.
- **OpenGameArt "free-bubble-game-button-pack" (pzUH):** CC0, pero es un **pack de gráficos** de botones, no de sonidos. Descartado.
- **Freesound:** no se pudo comprobar ningún sonido individual (la búsqueda y las fichas necesitan JavaScript y, para bajar, cuenta). Queda pendiente y no se recomienda en esta ronda.
- **VCSL Marimba:** CC0, pero cada archivo pesa entre ~370 KB y ~2.2 MB, por encima del límite de 300 KB. Descartado por tamaño (queda como idea si se recorta, pero hay mejores opciones).
- **VCSL otros (Cajón, Gong, Tubular Bells, etc.):** CC0 y algunos bajo 300 KB, pero no aportan un timbre claramente mejor que el woodblock, las claves o el log drum ya listados. Se dejan fuera para no inflar la lista.

---

## 4. Cómo se comprobó cada licencia

- **Kenney Interface Sounds:** se leyó `LICENSE.txt` en el commit fijado (https://raw.githubusercontent.com/Calinou/kenney-interface-sounds/4596a49eaf5a533948d49a47467f606bcdea70ff/LICENSE.txt). Dice literalmente: "License: (Creative Commons Zero, CC0)" y enlaza a http://creativecommons.org/publicdomain/zero/1.0/.
- **Kenney UI Audio:** se leyó `LICENSE.txt` en el commit fijado (https://raw.githubusercontent.com/Calinou/kenney-ui-audio/8c3d81b9159d058c444f89d12d518276b0b09345/LICENSE.txt). Dice literalmente: "License (Creative Commons Zero, CC0)".
- **VCSL:** se leyó `LICENSE` (https://raw.githubusercontent.com/sgossner/VCSL/master/LICENSE), que es el texto completo de "CC0 1.0 Universal", y el `README.md`, que dice: "This collection is under a Creative Commons 0 license."
- **UI Sound Effects (Robin Lamb, OpenGameArt):** la propia página (https://opengameart.org/content/ui-sound-effects-button-clicks-user-feedback-notifications) muestra "License(s): CC0".
- **3 Pop Sounds (wubitog, OpenGameArt):** la propia página (https://opengameart.org/content/3-pop-sounds) muestra "License(s): CC0" y "Copyright/Attribution Notice: No Attribution Required."
- **Kenney Impact Sounds (mirror Boyquotes):** se leyó su `LICENSE` (https://raw.githubusercontent.com/Boyquotes/kenney-impact-sounds-for-godot/master/LICENSE), que es el texto CC0; aun así, se descarta por formato OGG.

---

## 5. Pendientes al bajar (para la siguiente fase)

1. **Medir la duración real** de cada archivo elegido y recortar los que pasen de su tope (CC0 lo permite). Los de VCSL son muestras crudas y son los más probables de necesitar recorte.
2. **Escuchar** los candidatos: esta investigación solo se guio por nombres y descripciones, nunca por el audio.
3. **Revisar el contenido de los ZIP** de OpenGameArt (`ui_wav.zip` de Robin Lamb y `3pops.zip` de wubitog): la página no lista los nombres internos ni confirma el formato.
4. **Buscar un "pop/burbuja" propio** si ninguno de los clics de Kenney convence: es el hueco más flojo de esta ronda. Si no aparece, la spec (4.2.11) ya contempla generar el sonido con un script de síntesis.
