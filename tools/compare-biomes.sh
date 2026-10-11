#!/bin/zsh
# compare-biomes.sh [biome...]: the same view over each biome in Fulgor and in Sildur's Vibrant, then how far apart
# the pairs are (compare-stats.py). Pairs land in bench-out/cmp-biome-<biome>-{fulgor,sildur}.png and the table in
# bench-out/biomes.md. One Prism launch per biome: about two minutes each, and the game window takes the focus.
cd "$(dirname "$0")/.."
biomes=("$@")
[ ${#biomes} -eq 0 ] && biomes=(plains forest birch_forest dark_forest taiga snowy_plains desert badlands savanna jungle swamp
  mangrove_swamp cherry_grove meadow jagged_peaks beach ocean warm_ocean frozen_ocean mushroom_fields)
for b in $biomes; do
  echo "== $b"
  tools/compare-sildurs.sh biome-$b -PbenchBiome=$b -PbenchPitch=15 -PbenchYaw=135 2>&1 | grep -E "exit|joined|shot"
done
python3 tools/compare-stats.py ${biomes/#/biome-} | tee bench-out/biomes.md
