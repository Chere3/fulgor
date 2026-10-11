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

## Hoja de ruta

1. Target del mundo en HDR (RGBA16F) + tonemap/exposición en el pase final.
2. Bloom. 3. TAA. 4. Ajuste del look (godrays, cielo, agua). 5. DoF y motion blur.
6. Optimizaciones portables de mcopt (QoS de hilos, continuación de encoder, animación de atlas en un pase); el
   renderer de terreno compacto con oclusión en GPU sólo si el benchmark dice que el terreno es el cuello de botella.

Cada paso se mide con el benchmark contra `bench-out/` antes de darlo por bueno.
