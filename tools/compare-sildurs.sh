#!/bin/zsh
# cmp.sh <name> [gradle flags...]: the same scene in Fulgor and in Sildur's Vibrant (Iris), into fulgor/bench-out/cmp-<name>-*.png
name=$1; shift
F=/Volumes/macexternal/DiegoBackup/Documents/proyectos/fulgor
M="$HOME/Library/Application Support/PrismLauncher/instances/Sildurs Ref 26.3/minecraft"
export JAVA_HOME="$HOME/Library/Application Support/PrismLauncher/java/java-runtime-epsilon/jre.bundle/Contents/Home" GRADLE_USER_HOME=/Volumes/macexternal/DiegoBackup/.gradle-fulgor
yabai -m rule --add label=fulgor-bench app='^java$' manage=off 2>/dev/null
cd $F && rm -rf run/screenshots
./gradlew runClient -PbenchWorld=fulgor-bench -Pbench=18 -PbenchShot=true "$@" --console=plain > bench-out/cmp-$name-fulgor.log 2>&1
echo "fulgor exit $?"; cp run/screenshots/*.png bench-out/cmp-$name-fulgor.png
mkdir -p "$M/saves" && rsync -a --delete run/saves/fulgor-bench "$M/saves/"
rm -f "$M/logs/latest.log"; rm -rf "$M/screenshots"
/Applications/Prism\ Launcher.app/Contents/MacOS/prismlauncher -l "Sildurs Ref 26.3" -w fulgor-bench > /dev/null 2>&1 &
n=0; until grep -q "joined the game" "$M/logs/latest.log" 2>/dev/null || [ $n -ge 150 ]; do sleep 2; n=$((n+1)); done
echo "joined after $((n*2))s: $(grep -c 'joined the game' "$M/logs/latest.log" 2>/dev/null)"
sleep 35
pid=$(pgrep -f "Sildurs Ref 26.3" | head -1); echo "pid $pid"
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" -e 'delay 1' -e 'tell application "System Events" to key code 120' 2>&1
sleep 4
if [ -n "$(ls "$M/screenshots" 2>/dev/null)" ]; then cp "$M/screenshots"/*.png bench-out/cmp-$name-sildur.png; echo "sildur shot ok"
else
  # The key did not reach the game (another window had the keyboard): photograph its window instead.
  wid=$(yabai -m query --windows | python3 -c 'import json,sys; w=[x for x in json.load(sys.stdin) if "Minecraft" in x["title"]]; print(w[0]["id"] if w else "")')
  if [ -n "$wid" ] && screencapture -x -o -l "$wid" bench-out/cmp-$name-sildur.png; then echo "sildur window shot ok"; else echo "no sildur shot"; fi
fi
grep -iE "iris|shader" "$M/logs/latest.log" | grep -iE "error|fail|pack|using" | tail -5 | cut -c1-200
pkill -f "Sildurs Ref 26.3"
yabai -m rule --remove fulgor-bench 2>/dev/null
