# CLAUDE.md

## Qué es

**Fulgor** (nombre provisional): mod de shaders para Minecraft Java **26.3** en Macs Apple Silicon, con el look de
Sildur's Vibrant como referencia visual y el rendimiento como prioridad. Es un fork de
[Ciderlight](https://github.com/riccqi/ciderlight) 0.1.16 (Apache-2.0, Richard Qi): backend nativo Metal sobre la API
`com.mojang.renderpearl` de 26.3 más un pipeline de shaders propio en MSL.

Reglas del fork:

- Conservar `LICENSE` y `NOTICE`; los archivos modificados respecto al upstream deben poder identificarse (git).
- El paquete y los ids siguen siendo `dev.ciderlight` / `ciderlight.*` para poder traer cambios del upstream
  (`git remote upstream`). No renombrar en masa sin que Diego lo pida.
- Sildur's es **sólo referencia visual**: no portar ni copiar su GLSL (su licencia no lo permite). Todo shader es MSL
  original. Lo mismo aplica a Complementary/BSL.
- El código, comentarios y commits del fork siguen en inglés (como el upstream); la conversación con Diego en español.

## Comandos

Java 25 y Gradle fuera del disco interno (tiene poco espacio):

```
export JAVA_HOME="$HOME/Library/Application Support/PrismLauncher/java/java-runtime-epsilon/jre.bundle/Contents/Home"
export GRADLE_USER_HOME=/Volumes/macexternal/DiegoBackup/.gradle-fulgor

./gradlew build                                        # jar en build/libs/ (+ checks de bindings y sombras)
./gradlew runClient -PbenchWorld=fulgor-bench          # cliente de desarrollo en un mundo normal de semilla fija
./gradlew runClient -PbenchWorld=fulgor-bench -Pbench=20 -PbenchShot=true
                                                       # benchmark: escribe run/ciderlight-bench.txt y una captura
python3 tests/check_shaders.py                         # compila variantes de shader y regresiones en GPU
```

Variantes del benchmark: `-Pvanilla` (backend de Mojang), `-Pnoshaders` (Metal con look vanilla), `-Pquality=low|high`,
`-PrenderScale=<0.25–1>`, `-Pvalidate` (capa de validación de Metal), `-PdumpShaders=<dir>`. Nunca correr dos Gradle a la vez.

Los resultados de referencia viven en `bench-out/` (no versionado).

## Arquitectura (resumen)

- `src/main/native/ciderlight.m`: puente Objective-C a Metal (ABI C `mc_*`), llamado por FFM desde `backend/MetalNative.java`.
- `backend/Metal*.java`: implementación del backend de renderpearl. `MetalRenderPipeline` traduce el SPIR-V de vanilla a
  MSL con SPIRV-Cross y sustituye el terreno por `terrain.metal`.
- `backend/MetalShaders.java`: orquesta el pipeline propio alrededor del pase vanilla `"Main"` (`prepareMain`,
  `finishMain`, `endMain`): sombras, volumétricos, GTAO, composite, upscale.
- `src/main/resources/assets/ciderlight/shaders/*.metal`: los shaders. `FrameData` (`frame.metal`) tiene offsets
  duplicados a mano en `MetalShaders.java`: cambiar ambos a la vez.
- El alfa del target principal es un canal de marcadores de material (ver `frame.metal`), no transparencia.

## Comparar contra Sildur's

`tools/compare-sildurs.sh <nombre> [flags de gradle]` saca la misma escena en Fulgor y en Sildur's Vibrant: corre el
benchmark (que deja el mundo `fulgor-bench` con hora y posición fijas), copia el mundo a la instancia de Prism
"Sildurs Ref 26.3" (Fabric + Sodium + Iris + Sildur's Vibrant High), la lanza y pulsa F2 con osascript. Los pares quedan
en `bench-out/cmp-<nombre>-{fulgor,sildur}.png`. Si la pantalla está bloqueada o la red caída, el lado de Sildur's falla
(Prism necesita renovar la sesión de Microsoft).

Validación (no basta con mirar): `python3 tools/compare-stats.py [nombre...]` parte cada par en tres bandas (cielo,
horizonte, suelo), compara el color medio y falla si algún canal se aleja más de 24/255; sin nombres revisa todos los
pares. `tools/compare-biomes.sh [bioma...]` saca el par de cada bioma (`-PbenchBiome=<id>` coloca la cámara 12 bloques
sobre el bioma más cercano) y deja la tabla en `bench-out/biomes.md`; unos dos minutos por bioma.
`tools/biome-tour.sh [bioma...]` hace lo mismo en una sola sesión por lado: un datapack en una copia del mundo
(`fulgor-tour`) teletransporta al jugador de bioma en bioma y lo anuncia en el log, y el script fotografía la ventana
(`SIDES=fulgor` para repetir sólo nuestro lado, `DWELL` segundos por bioma). Las nubes se mueven
entre corridas, así que una banda puede variar ~10/255 por sí sola.

Lo aprendido de esos pares: de cerca Vibrant es contrastado (sol inclinado que ilumina las caras laterales al mediodía,
cielo azul profundo, sombras oscuras); a distancia es pastel por la bruma azulada. Nubes en montones blancos con sombra
rosada; atardecer amarillo junto al sol que pasa a rosa; noche gris azulada y oscura. Nether claro (niebla gris
rosada, lava naranja que brilla) y End de piedra crema con obsidiana violeta bajo cielo negro.

Rendimiento medido en el M4 (1600x900, distancia 16, escena de mediodía, 12 oct 2026, load average 6-10), mismo
instrumento en ambos lados: contador de fps de F3, 30 lecturas con `screencapture` cada 5 s durante dos minutos y
medio, tras 25-40 s de calentamiento:

| | lecturas | mediana | benchmark propio (25 s) |
|---|---|---|---|
| Sildur's Vibrant High sobre Iris | 29-37 el primer minuto, luego 39-45 | 43 | - |
| Fulgor por defecto en el M4 (Low: sombras 2048, mundo al 67 %; con esto se validó el look) | 59-73 | 70 | 79 |
| Fulgor igualado a Sildur's High (`-Pquality=low -PrenderScale=1`: sombras 2048, resolución completa) | 50-63 | 59 | 66 |
| Fulgor High (sombras 4096 + cascada lejana 2048/4096 + volumétricos) | 31-51 | 49 | 61 |

Es decir ~1,6x por defecto, ~1,4x con ajustes igualados y ~1,1x en High. La comparación igualada se repitió en
rondas alternadas de 20 lecturas: Sildur's 43, 40 y 42 de mediana; Fulgor 59, 58, 53 y 58 (toda ronda de Fulgor por
encima de toda ronda de Sildur's). Ojo al medir Sildur's: comprobar que el mundo quedó en la escena de mediodía (tras
la escena del End da más de 100 fps mirando cielo negro). El High de Sildur's es un solo mapa de
2048 a 80 bloques, sin volumétricos (su `shaders.settings`), así que la fila comparable es la tercera. Sildur's tarda
un minuto en estabilizarse: sus lecturas del primer minuto (15-27 fps en mediciones anteriores) no valen.
Con `-PgpuProfile=true` el cuadro de High son ~18 ms de GPU y la geometría de sombras es lo más caro (mapa cercano
3,5 ms de vértices, lejano 2 ms); el lejano se reparte en `FAR_STRIPS = 8` cuadros (con 4 costaba 3,3 ms).
Para ver el contador sin teclado (osascript no entrega teclas al juego) se crea temporalmente `debug-profile.json`
con `{"custom":{"minecraft:fps":"alwaysOn"}}` en la carpeta del juego y se pone `inactivityFpsLimit:"minimized"` en
`options.txt` (con "afk" topa a 30 fps al minuto sin entrada); ambos se restauran después.

Estado de la validación (12 oct 2026): tres pasadas completas seguidas (las dos primeras con el mismo código, la tercera tras
`FAR_STRIPS = 8`) dieron 60/60 bandas en los 20 biomas y 27/27 en las 9 escenas fijas
(`bench-out/{biomes,scenes}-{D,E,F}.md`), peor banda 21-23. Lo que más costó
encontrar: el mar lejano de Sildur's es un espejo claro del horizonte (el cielo reflejado necesita la misma palidez
de bruma que el cielo en pantalla), el mar es de un solo color y se oscurece con la profundidad, las nubes no dan
sombra al suelo y son menos blancas, el hielo es azul pálido.

## Hoja de ruta

Hecho: target HDR + tonemap que conserva el tono, bloom, TAA (jitter por viewport; el historial se suelta al moverse
más de ~1,5 px por cuadro, `-Dciderlight.taa=false`), paleta de cielo y luz, sol inclinado 40 grados como el
`sunPathRotation` por defecto de Sildur's (`-Dciderlight.sunTilt`), nubes suaves con volumen, dither temporal y sombra
(`-Dciderlight.clouds=vanilla` para las del juego), sol redondo, agua turquesa, noche gris azulada y oscura, bruma
lejana, lluvia con bruma pálida, bajo el agua azul, lava emisiva (`SPRITE_LAVA`), Nether con niebla gris cálida hasta
la distancia de render (`AtmosphericFogEnvironmentMixin`) y End con luz propia (`FrameData.dimension`, sin la
desaturación nocturna de `grade()`).

Con shaders se cancela la viñeta del HUD de vanilla (`HudMixin`, como hace Iris): oscurecía las esquinas hasta la mitad
en sitios con poca luz. Residuales conocidos frente a Sildur's: el fuego de almas es cian (como vanilla) y no verde
pálido; bajo el agua no se ve el cielo a través de la superficie.

Pendiente:

1. Ajustes en la pantalla de opciones para bloom, TAA, nubes e inclinación del sol (hoy sólo por `-D`).
2. Sombra de nubes sobre terreno por encima de la altura de nubes de vanilla (192).
3. Optimizaciones portables de mcopt (QoS de hilos, continuación de encoder, animación de atlas en un pase); el
   renderer de terreno compacto con oclusión en GPU sólo si el benchmark dice que el terreno es el cuello de botella.

Cada paso se mide con el benchmark y se compara con los pares de `bench-out/` antes de darlo por bueno.
