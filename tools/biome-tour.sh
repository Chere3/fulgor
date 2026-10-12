#!/bin/zsh
# biome-tour.sh [biome...]: every biome in ONE session of each game. A data pack in a copy of the bench world moves
# the player from biome to biome and announces each in the log; this script photographs the game's window then.
# Pairs land in bench-out/cmp-biome-<biome>-{fulgor,sildur}.png, the table in bench-out/biomes.md.
#   SIDES="fulgor"  only Fulgor's side (after a shader change the reference pictures stay valid)
#   DWELL=20        seconds at each biome before the picture (chunks must load; Sildur's is the slow one)
cd "$(dirname "$0")/.."
F=$PWD
M="$HOME/Library/Application Support/PrismLauncher/instances/Sildurs Ref 26.3/minecraft"
export JAVA_HOME="$HOME/Library/Application Support/PrismLauncher/java/java-runtime-epsilon/jre.bundle/Contents/Home" GRADLE_USER_HOME=/Volumes/macexternal/DiegoBackup/.gradle-fulgor
biomes=("$@")
[ ${#biomes} -eq 0 ] && biomes=(plains forest birch_forest dark_forest taiga snowy_plains desert badlands savanna jungle swamp
  mangrove_swamp cherry_grove meadow jagged_peaks beach ocean warm_ocean frozen_ocean mushroom_fields)
DWELL=${DWELL:-20}; SIDES=${SIDES:-fulgor sildur}
yabai -m rule --add label=fulgor-bench app='^java$' manage=off 2>/dev/null

# Where each biome is: found once by the benchmark (from a fixed origin) and kept.
places=bench-out/biome-places.txt; touch $places
missing=(); for b in $biomes; do grep -q "^$b " $places || missing+=($b); done
if [ ${#missing} -gt 0 ]; then
  ./gradlew runClient -PbenchWorld=fulgor-bench -Pbench=3 -PbenchBiome=${(j:,:)missing} --console=plain 2>&1 \
    | sed -n 's/.*Ciderlight bench: biome minecraft:\([a-z_]*\) at \(-*[0-9]*\) \(-*[0-9]*\) \(-*[0-9]*\).*/\1 \2 \3 \4/p' >> $places
fi

# The tour: a copy of the bench world with a data pack that starts on load.
tour=run/saves/fulgor-tour; rm -rf $tour; cp -R run/saves/fulgor-bench $tour
pack=$tour/datapacks/tour; fn=$pack/data/tour/function; mkdir -p $fn $pack/data/minecraft/tags/function
print '{"pack":{"description":"Fulgor biome tour","min_format":121,"max_format":121,"pack_format":121}}' > $pack/pack.mcmeta
print '{"values":["tour:start"]}' > $pack/data/minecraft/tags/function/load.json
print "schedule function tour:s1 45s" > $fn/start.mcfunction
i=0; valid=()
for b in $biomes; do
  place=($(grep "^$b " $places | tail -1)); [ ${#place} -eq 4 ] || { echo "no place for $b"; continue; }
  i=$((i+1)); valid+=($b)
  print "gamemode spectator @a\ntime set 6000\nweather clear\ntp @a ${place[2]} $((place[3]+12)) ${place[4]} 135 15\nsay tour $b\nschedule function tour:s$((i+1)) $((DWELL+15))s" > $fn/s$i.mcfunction
done
print "say tour done" > $fn/s$((i+1)).mcfunction

shoot() { # shoot <side> <log>: a window picture DWELL seconds after each announcement in the log
  local side=$1 log=$2 seen=0 waited=0 b wid
  while [ $waited -lt $((120 + ${#valid} * (DWELL + 25))) ]; do
    b=$(grep -oE "\] tour [a-z_]+" "$log" 2>/dev/null | awk '!s[$0]++' | sed -n "$((seen+1))p" | cut -d' ' -f3)
    if [ -z "$b" ]; then sleep 1; waited=$((waited+1)); continue; fi
    seen=$((seen+1)); [ "$b" = done ] && break
    sleep $DWELL; waited=$((waited+DWELL))
    wid=$(yabai -m query --windows | OTHERS="$others" python3 -c 'import json,os,sys; o=os.environ["OTHERS"].split(); w=[x for x in json.load(sys.stdin) if "Minecraft" in x["title"] and str(x["id"]) not in o]; print(w[0]["id"] if w else "")')
    [ -n "$wid" ] || { sleep 2; wid=$(yabai -m query --windows | OTHERS="$others" python3 -c 'import json,os,sys; o=os.environ["OTHERS"].split(); w=[x for x in json.load(sys.stdin) if "Minecraft" in x["title"] and str(x["id"]) not in o]; print(w[0]["id"] if w else "")'); }
    [ -n "$wid" ] && screencapture -x -o -l "$wid" bench-out/cmp-biome-$b-$side.png && echo "$side $b ok" || echo "$side $b: no window"
  done
}

# Another Minecraft that is already open (someone playing) is never the one photographed.
others=$(yabai -m query --windows | python3 -c 'import json,sys; print(" ".join(str(x["id"]) for x in json.load(sys.stdin) if "Minecraft" in x["title"]))')
for side in ${=SIDES}; do
  if [ $side = fulgor ]; then
    log=bench-out/tour-fulgor.log; : > $log
    ./gradlew runClient -PbenchWorld=fulgor-tour -Pbench=36000 --console=plain > $log 2>&1 &
    shoot fulgor $log
    pkill -f "ciderlight.benchWorld=fulgor-tour"; wait 2>/dev/null
  else
    mkdir -p "$M/saves"; rsync -a --delete $tour "$M/saves/"; rm -f "$M/logs/latest.log"
    /Applications/Prism\ Launcher.app/Contents/MacOS/prismlauncher -l "Sildurs Ref 26.3" -w fulgor-tour > /dev/null 2>&1 &
    shoot sildur "$M/logs/latest.log"
    pkill -f "Sildurs Ref 26.3"
  fi
done
yabai -m rule --remove fulgor-bench 2>/dev/null
python3 tools/compare-stats.py ${valid/#/biome-} | tee bench-out/biomes.md
