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
sobre el bioma más cercano) y deja la tabla en `bench-out/biomes.md`; unos dos minutos por bioma. Las nubes se mueven
entre corridas, así que una banda puede variar ~10/255 por sí sola.

Lo aprendido de esos pares: de cerca Vibrant es contrastado (sol inclinado que ilumina las caras laterales al mediodía,
cielo azul profundo, sombras oscuras); a distancia es pastel por la bruma azulada. Nubes en montones blancos con sombra
rosada; atardecer amarillo junto al sol que pasa a rosa; noche gris azulada y oscura. Nether claro (niebla gris
rosada, lava naranja que brilla) y End de piedra crema con obsidiana violeta bajo cielo negro.

Rendimiento medido en el M4 (1600x900, distancia 16, misma escena, 11 oct 2026): Sildur's High sobre Iris ~15 fps;
Fulgor High ~44-49 fps; Fulgor Low (por defecto en el M4, mundo al 67 %) ~64-111 fps según la carga de la máquina.

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
