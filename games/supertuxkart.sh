#!/usr/bin/env bash
# An AI-only race in SuperTuxKart's PROFILE mode (--profile-laps: every kart, including the "player"
# slot, is driven by the game's AI, the camera follows the first kart, the game prints every kart's
# finishing position to its log when the race is over and quits by itself). The result is parsed
# from those "profile:" lines. $PLAYERS: [{name, kart, ai}] (kart = STK kart ident).
set -uo pipefail
export PATH="$PATH:/usr/games:/usr/local/games"
# an empty player list means "use the defaults"
[ -z "${PLAYERS:-}" ] || [ "${PLAYERS}" = "[]" ] && unset PLAYERS
# GPU diagnostics once per run
{ echo "caps=${NVIDIA_DRIVER_CAPABILITIES:-} vgl=${VGL_DISPLAY:-} RUN=${RUN:-}"; ls /dev/nvidia* 2>/dev/null | tr '\n' ' '; echo; ls /usr/lib/x86_64-linux-gnu/libnvidia-egl* /usr/share/glvnd/egl_vendor.d/ 2>/dev/null | tr '\n' ' '; echo; grep -E "renderer|version" /work/logs/glx.log 2>/dev/null | head -4; } >/work/logs/gpu.log 2>&1
PLAYERS=${PLAYERS:-'[{"name":"Kart bot cautious","kart":"tux","ai":1},{"name":"Kart bot balanced","kart":"gnu","ai":2},{"name":"Kart bot reckless","kart":"sara_the_racer","ai":3},{"name":"Kart bot pro","kart":"nolok","ai":3}]'}
TRACK=${TRACK:-sandtrack}; LAPS=${LAPS:-1}
N=$(echo "$PLAYERS" | jq 'length'); FIRST=$(echo "$PLAYERS" | jq -r '.[0].kart'); REST=$(echo "$PLAYERS" | jq -r '[.[1:][].kart] | join(",")')
echo "race: track=$TRACK laps=$LAPS karts=$N ($FIRST + $REST) · profile mode (all AI)"; echo "--- gpu diag"; cat /work/logs/gpu.log 2>/dev/null; echo "---"
export XDG_DATA_HOME=/work/stk XDG_CONFIG_HOME=/work/stk XDG_CACHE_HOME=/work/stk HOME=/work/stk
mkdir -p /work/stk
supertuxkart --help >/work/logs/stk-help.log 2>&1 || true
timeout 600 $RUN supertuxkart --log=1 --windowed --screensize=${W}x${H} --no-start-screen --track=$TRACK --kart=$FIRST --ai=$REST --numkarts=$N --laps=$LAPS --profile-laps=$LAPS --difficulty=2 >/work/logs/stk.log 2>&1 &
STK=$!
# profile mode quits after the race; stop waiting as soon as the result table is logged (or the timeout hits)
for i in $(seq 1 590); do grep -qE "profile: *[A-Za-z0-9_]+ +[0-9]+ +[0-9]+ +[0-9.]+" /work/logs/stk.log 2>/dev/null && { sleep 4; break; }; kill -0 $STK 2>/dev/null || break; sleep 1; done
kill $STK 2>/dev/null; sleep 1
echo "--- stk.log head"; head -30 /work/logs/stk.log; echo "--- stk.log race lines"; grep -iE "profile|finish|position|result|rank|error|warn|renderer|opengl|shader|gl_version|loading|track" /work/logs/stk.log | head -60
# "[info   ] profile: <kart ident> <start position> <end position> <time> ..." → karts ordered by end position
ORDER=$(grep -oE "profile: *[A-Za-z0-9_]+ +[0-9]+ +[0-9]+ +[0-9.]+" /work/logs/stk.log | awk '{print $4" "$2}' | sort -n | awk '{print $2}' | jq -R . | jq -cs .)
[ "$ORDER" = "[]" ] || [ -z "$ORDER" ] && ORDER=null
# the diagnostic excerpt rides along in the result (the status route shows the result in full)
DIAG=$( { echo "== gpu"; cat /work/logs/gpu.log; echo "== glx"; head -12 /work/logs/glx.log 2>/dev/null; echo "== help (demo/profile/ai options)"; grep -iE "demo|profile|ai=|--ai|race-now|start-screen|numkarts|laps|log=|screensize|windowed" /work/logs/stk-help.log | head -20; echo "== stk.log head"; head -40 /work/logs/stk.log; echo "== stk.log key lines"; grep -iE "profile|finish|position|error|warn|renderer|opengl|version|loading|track|camera" /work/logs/stk.log | head -50; echo "== stk.log tail"; tail -20 /work/logs/stk.log; } 2>/dev/null | cut -c1-220 | head -c 14000 )
echo "RESULT $(jq -cn --argjson order "$ORDER" --arg track "$TRACK" --arg diag "$DIAG" '{game:"supertuxkart",order:$order,track:$track,ok:($order!=null),diag:$diag}')"
