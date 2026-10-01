#!/usr/bin/env bash
# An AI-only race in SuperTuxKart's demo mode (every kart is driven by the game's AI), watched from the
# game's camera. The result is read from the game's verbose log at the end of the race.
set -uo pipefail
PLAYERS=${PLAYERS:-'[{"name":"Kart bot cautious","kart":"tux","ai":1},{"name":"Kart bot balanced","kart":"gnu","ai":2},{"name":"Kart bot reckless","kart":"sara_the_racer","ai":3},{"name":"Kart bot pro","kart":"nolok","ai":3}]'}
TRACK=${TRACK:-lighthouse}; LAPS=${LAPS:-2}
N=$(echo "$PLAYERS" | jq 'length'); KARTS=$(echo "$PLAYERS" | jq -r '[.[].kart] | join(",")')
echo "race: track=$TRACK laps=$LAPS karts=$N ($KARTS) · demo mode"
export XDG_DATA_HOME=/work/stk XDG_CONFIG_HOME=/work/stk
mkdir -p /work/stk
timeout 420 $RUN supertuxkart --log=1 --windowed --screensize=${W}x${H} --no-start-screen --demo-mode=1 --demo-tracks=$TRACK --demo-karts=$N --demo-laps=$LAPS --difficulty=2 --no-sound >/work/logs/stk.log 2>&1 &
STK=$!
# the race is over when the result screen is logged (or the timeout hits); demo mode would otherwise start another race
for i in $(seq 1 400); do grep -qiE "RaceResultGUI|race.*(over|finished)|GameOver|RaceOver" /work/logs/stk.log 2>/dev/null && break; kill -0 $STK 2>/dev/null || break; sleep 1; done
sleep 6; kill $STK 2>/dev/null
grep -iE "finish|position|result|rank" /work/logs/stk.log | tail -20
# known log shapes: "[info] RaceResultGUI: ..." and kart finish lines; try both
ORDER=$(grep -oE "([A-Za-z_]+) finished the race in position [0-9]+" /work/logs/stk.log | awk '{print $NF" "$1}' | sort -n | awk '{print $2}' | jq -R . | jq -cs .)
[ "$ORDER" = "[]" ] || [ -z "$ORDER" ] && ORDER=null
echo "RESULT $(jq -cn --argjson order "$ORDER" --arg track "$TRACK" '{game:"supertuxkart",order:$order,track:$track,ok:($order!=null)}')"
