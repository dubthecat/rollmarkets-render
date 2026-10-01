#!/usr/bin/env bash
# An AI-only race, watched from the game's own camera. Competitors come from $PLAYERS (JSON list of
# {name, kart, difficulty}); defaults race four built-in AIs. The result is read from STK's log.
set -uo pipefail
PLAYERS=${PLAYERS:-'[{"name":"Kart bot cautious","kart":"tux","ai":1},{"name":"Kart bot balanced","kart":"gnu","ai":2},{"name":"Kart bot reckless","kart":"sara_the_racer","ai":3},{"name":"Kart bot pro","kart":"nolok","ai":3}]'}
TRACK=${TRACK:-lighthouse}; LAPS=${LAPS:-3}
N=$(echo "$PLAYERS" | jq 'length'); KARTS=$(echo "$PLAYERS" | jq -r '[.[].kart] | join(",")')
echo "race: track=$TRACK laps=$LAPS karts=$KARTS"
# --demo-mode runs an AI race from the title screen; --numkarts/--laps/--track/--difficulty shape it
timeout 600 $RUN supertuxkart --no-console-log --log=1 --fullscreen=0 --screensize=${W}x${H} --no-start-screen --race-now \
  --numkarts=$N --laps=$LAPS --track=$TRACK --difficulty=2 --ai="$KARTS" --kart=tux --type=normal --history=0 --no-sound 2>&1 | tee /work/logs/stk.log | grep -E "finish|Finish|position|Race|race" | tail -40
# STK prints "[info   ] RaceResultGUI: ..."/"finished" lines; fall back to kart order from the log when present
ORDER=$(grep -oE "Kart [^ ]+ finished the race in position [0-9]+" /work/logs/stk.log | sort -t' ' -k8 -n | awk '{print $2}' | jq -R . | jq -cs .)
[ "$ORDER" = "[]" ] || [ -z "$ORDER" ] && ORDER=null
echo "RESULT $(jq -cn --argjson order "$ORDER" --arg track "$TRACK" '{game:"supertuxkart",order:$order,track:$track,ok:($order!=null)}')"
