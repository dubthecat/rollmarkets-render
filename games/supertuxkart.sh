#!/usr/bin/env bash
# An AI-only race in SuperTuxKart's PROFILE mode (--profile-laps: every kart is driven by the game's AI,
# the camera follows the first kart, the game prints every kart's finishing position to its log when the
# race is over and quits by itself). $PLAYERS: [{name, kart, ai}] (kart = STK kart ident).
set -uo pipefail
export PATH="$PATH:/usr/games:/usr/local/games"
[ -z "${PLAYERS:-}" ] || [ "${PLAYERS}" = "[]" ] && unset PLAYERS
D=/work/logs; mkdir -p $D
export SDL_VIDEODRIVER=x11
# render.sh gives Xvfb 1.5 s; wait for the display properly, then re-probe the GPU through VirtualGL (EGL back end)
for i in $(seq 1 40); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 0.5; done
{ echo "display: $(xdpyinfo -display :99 2>&1 | grep -E "dimensions|vendor string" | head -2 | tr "\n" " ")"; echo "xvfb: $(pgrep -a Xvfb | head -1)"; echo "xvfb.log: $(tail -c 300 $D/xvfb.log 2>/dev/null | tr "\n" " ")"; } > $D/x.log 2>&1
if command -v vglrun >/dev/null && VGL_DISPLAY=egl vglrun -d egl glxinfo -B > $D/glx2.log 2>&1 && grep -q "OpenGL renderer" $D/glx2.log; then export VGL_DISPLAY=egl; RUN="vglrun -d egl"; unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER; echo "GL: VirtualGL/EGL → $(grep -m1 "OpenGL renderer" $D/glx2.log)" >> $D/x.log; else RUN=""; export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe; echo "GL: software (llvmpipe); vgl probe: $(head -c 240 $D/glx2.log 2>/dev/null | tr "\n" " ")" >> $D/x.log; fi
export RUN
{ echo "caps=${NVIDIA_DRIVER_CAPABILITIES:-} vgl=${VGL_DISPLAY:-} RUN=${RUN:-}"; ls /dev/nvidia* 2>/dev/null | tr "\n" " "; echo; cat $D/x.log; } > $D/gpu.log 2>&1
xstate() { echo "xvfb alive: $(pgrep -c Xvfb) · xdpyinfo: $(xdpyinfo -display :99 >/dev/null 2>&1 && echo ok || echo FAIL) · xvfb.log tail: $(tail -c 200 $D/xvfb.log 2>/dev/null | tr "\n" " ")"; }
PLAYERS=${PLAYERS:-'[{"name":"Kart bot cautious","kart":"tux","ai":1},{"name":"Kart bot balanced","kart":"gnu","ai":2},{"name":"Kart bot reckless","kart":"sara_the_racer","ai":3},{"name":"Kart bot pro","kart":"nolok","ai":3}]'}
TRACK=${TRACK:-sandtrack}; LAPS=${LAPS:-1}
N=$(echo "$PLAYERS" | jq 'length'); KARTS=$(echo "$PLAYERS" | jq -r '[.[].kart] | join(",")'); FIRST=$(echo "$PLAYERS" | jq -r '.[0].kart'); REST=$(echo "$PLAYERS" | jq -r '[.[1:][].kart] | join(",")')
echo "race: track=$TRACK laps=$LAPS karts=$N ($KARTS) · profile mode (all AI)"; echo "--- gpu diag"; cat $D/gpu.log; echo "---"
export XDG_DATA_HOME=/work/stk XDG_CONFIG_HOME=/work/stk
mkdir -p /work/stk
# the profile table: "profile: <kart ident> <controller name…> <start position> <end position> <finish time> …" — the
# controller name may be several words, so the parser locates the first "int int float" triple instead of fixed fields
parse_order() { python3 - "$D/stk.log" "$KARTS" <<'PY'
import re, sys, json
rows = []; karts = set(sys.argv[2].split(','))
for line in open(sys.argv[1], errors='replace'):
    if 'profile:' not in line: continue
    t = line.split('profile:', 1)[1].split()
    if not t or t[0] not in karts: continue   # only kart rows (the per-controller summary lines also carry numbers)
    for i in range(1, len(t) - 2):
        if re.fullmatch(r'\d+', t[i]) and re.fullmatch(r'\d+', t[i+1]) and re.fullmatch(r'\d+(\.\d+)?', t[i+2]):
            rows.append((int(t[i+1]), t[0])); break
rows.sort(); print(json.dumps([r[1] for r in rows]) if rows else 'null')
PY
}
echo "X before: $(xstate)"
timeout 600 $RUN supertuxkart --log=1 --windowed --screensize=${W}x${H} --no-start-screen --track=$TRACK --kart=$FIRST --ai=$REST --numkarts=$N --laps=$LAPS --profile-laps=$LAPS --difficulty=2 >$D/stk.log 2>&1 &
STK=$!
# profile mode quits after the race; stop waiting as soon as the result table is logged (or the timeout hits)
for i in $(seq 1 590); do [ "$(parse_order)" != null ] && { sleep 4; break; }; kill -0 $STK 2>/dev/null || break; sleep 1; done
echo "X after: $(xstate)"
kill $STK 2>/dev/null; sleep 1
echo "--- stk.log head"; head -30 $D/stk.log; echo "--- stk.log race lines"; grep -iE "profile|finish|position|result|rank|error|warn|renderer|opengl|shader|gl_version|loading|track|camera|fatal|Unable" $D/stk.log | head -60
ORDER=$(parse_order)
[ "$ORDER" = "[]" ] || [ -z "$ORDER" ] && ORDER=null
DIAG=$( { echo "== runner"; md5sum /games/supertuxkart.sh | cut -c1-8; head -14 $D/render.log; echo "== profile lines"; grep -a "profile:" $D/stk.log | tail -8; echo "== gpu"; cat $D/gpu.log; echo "== glx"; head -8 $D/glx2.log 2>/dev/null; echo "== X"; grep -E "^X (before|after)" $D/game.log 2>/dev/null; echo "== stk.log head"; head -40 $D/stk.log; echo "== stk.log key lines"; grep -iE "profile|finish|position|error|warn|renderer|opengl|version|loading|track|camera|fatal|Unable" $D/stk.log | head -50; echo "== stk.log tail"; tail -20 $D/stk.log; } 2>/dev/null | cut -c1-220 | head -c 14000 )
echo "RESULT $(jq -cn --argjson order "$ORDER" --arg track "$TRACK" --arg diag "$DIAG" '{game:"supertuxkart",order:$order,track:$track,ok:($order!=null),diag:$diag}')"
