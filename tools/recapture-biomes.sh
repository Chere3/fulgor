#!/bin/zsh
# recapture-biomes.sh [biome...]: only Fulgor's side of the pairs compare-biomes.sh took (after a shader change the
# reference pictures stay valid), then the table again. About a minute per biome.
cd "$(dirname "$0")/.."
export JAVA_HOME="$HOME/Library/Application Support/PrismLauncher/java/java-runtime-epsilon/jre.bundle/Contents/Home" GRADLE_USER_HOME=/Volumes/macexternal/DiegoBackup/.gradle-fulgor
biomes=("$@")
[ ${#biomes} -eq 0 ] && biomes=($(ls bench-out/cmp-biome-*-sildur.png | sed 's/.*cmp-biome-//;s/-sildur.png//'))
yabai -m rule --add label=fulgor-bench app='^java$' manage=off 2>/dev/null
for b in $biomes; do
  rm -rf run/screenshots
  # Long enough for the chunks of a far biome to load before the picture is taken.
  ./gradlew runClient -PbenchWorld=fulgor-bench -Pbench=18 -PbenchShot=true -PbenchBiome=$b -PbenchPitch=15 -PbenchYaw=135 --console=plain > bench-out/cmp-biome-$b-fulgor.log 2>&1
  echo "$b $?"; cp run/screenshots/*.png bench-out/cmp-biome-$b-fulgor.png
done
yabai -m rule --remove fulgor-bench 2>/dev/null
python3 tools/compare-stats.py ${biomes/#/biome-} | tee bench-out/biomes.md
