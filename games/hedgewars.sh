#!/usr/bin/env bash
# Two AI teams on a random map, played by hwengine driven through its frontend protocol over stdin;
# the engine records a demo and --stats-only style output gives the winner. Best effort: the
# protocol is version-sensitive (Hedgewars 1.0.x). $PLAYERS: [{name, level}] (AI level 1 strong … 5 weak)
set -uo pipefail
export PATH="$PATH:/usr/games:/usr/local/games"
# an empty player list means "use the defaults"
[ -z "${PLAYERS:-}" ] || [ "${PLAYERS}" = "[]" ] && unset PLAYERS
# GPU diagnostics once per run
{ echo "caps=${NVIDIA_DRIVER_CAPABILITIES:-} vgl=${VGL_DISPLAY:-} RUN=${RUN:-}"; ls /dev/nvidia* 2>/dev/null | tr '\n' ' '; echo; ls /usr/lib/x86_64-linux-gnu/libnvidia-egl* /usr/share/glvnd/egl_vendor.d/ 2>/dev/null | tr '\n' ' '; echo; cat /work/logs/glx.log 2>/dev/null | head -5; } >/work/logs/gpu.log 2>&1
PLAYERS=${PLAYERS:-'[{"name":"Hog bot rookie","level":4},{"name":"Hog bot veteran","level":2}]'}
SEED=${SEED:-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')}
A=$(echo "$PLAYERS" | jq -r '.[0].name'); AL=$(echo "$PLAYERS" | jq -r '.[0].level'); B=$(echo "$PLAYERS" | jq -r '.[1].name'); BL=$(echo "$PLAYERS" | jq -r '.[1].level')
mkdir -p /work/hw
cfg() { printf '%s\n' "$@"; }
# the frontend protocol: each line is a command; teams with 3 hogs each, default ammo, 30 s turns, sudden death at 15 turns
{ cfg "TL" "eseed {$SEED}" "e\$gmflags 0" "e\$turntime 30000" "e\$sd_turns 15" "e\$casefreq 5" "e\$minestime 3000" "e\$minesnum 4" "e\$explosives 2" "etheme Nature" "escript Normal.lua" "e\$template_filter 0" "e\$mapgen 0" "e\$maze_size 0" "e\$feature_size 12" \
  "eaddteam 11111111111111111111111111111111 $AL $A" "erdriveteam $A" "eammloadt 9391929422199121032135111131121010012110104" "eammprob 0405040541600101021002020000011002000400010" "eammdelay 0000000000000002055000000040070000000020000" "eammreinf 1311110312111111102111011110000111111111111" "eammstore" \
  "eaddhh $AL 100 A1" "ehat NoHat" "eaddhh $AL 100 A2" "ehat NoHat" "eaddhh $AL 100 A3" "ehat NoHat" \
  "eaddteam 22222222222222222222222222222222 $BL $B" "erdriveteam $B" "eammloadt 9391929422199121032135111131121010012110104" "eammprob 0405040541600101021002020000011002000400010" "eammdelay 0000000000000002055000000040070000000020000" "eammreinf 1311110312111111102111011110000111111111111" "eammstore" \
  "eaddhh $BL 100 B1" "ehat NoHat" "eaddhh $BL 100 B2" "ehat NoHat" "eaddhh $BL 100 B3" "ehat NoHat" "!"; sleep 900; } | \
timeout 900 $RUN hwengine --internal --port 0 --prefix /usr/share/games/hedgewars/Data --user-prefix /work/hw --fullscreen-width $W --fullscreen-height $H --width $W --height $H --nosound --nomusic --nodampen --stats-only --no-teamtag 2>&1 | tee /work/logs/hw.log | tail -40
WIN=$(grep -oE "(WINS|wins) *: *.*" /work/logs/hw.log | head -1 | sed 's/.*: *//')
echo "RESULT $(jq -cn --arg w "${WIN:-}" --arg a "$A" --arg b "$B" '{game:"hedgewars",winner:(if ($w|length)>0 then $w else null end),teams:[$a,$b],ok:(($w|length)>0)}')"
