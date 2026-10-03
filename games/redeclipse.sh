#!/usr/bin/env bash
# Red Eclipse (the eclipse arena): a four-minute team deathmatch between the engine's bots on a private dedicated
# server, watched by a spectator client in TV mode that render.sh captures. Result = the client scoreboard's team totals.
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

# Red Eclipse team deathmatch: built-in bots on a dedicated server, watched by a spectator client in TV mode
# (specmode 1) whose window is captured. Team scores come from the client's own scoreboard, echoed to its console
# every 5 s as "SCORES" lines; the last line before the end is the result. $PLAYERS: [{name, team:"alpha"|"omega", skill 1-100}]
PLAYERS=${PLAYERS:-'[{"name":"Eclipse rusher","team":"alpha","skill":85},{"name":"Eclipse warden","team":"omega","skill":65}]'}
TLIMIT=${TLIMIT:-4}; BOTS=${BOTS:-6}; RE=${RE:-/opt/redeclipse}; PORT=28801; MAP=${MAP:-octavus}   # the server picks FFA for its first game; the admin spectator restarts it as team deathmatch on a fixed map
read -r SMIN SMAX < <(python3 -c "
import json, os
p = json.loads(os.environ.get('PLAYERS') or '[]'); sk = [int(x.get('skill', 70)) for x in p if isinstance(x, dict)] or [70]
m = sum(sk) / len(sk); print(max(1, int(m) - 10), min(100, int(m) + 10))")
echo "match: team deathmatch timelimit=${TLIMIT}m bots=$BOTS skill=$SMIN-$SMAX size=${W}x${H}"; echo "--- gpu diag"; cat $D/gpu.log; echo "---"
[ -x $RE/redeclipse.sh ] || { ls -la $RE 2>&1 | head -5; echo 'RESULT {"game":"redeclipse","ok":false,"error":"engine missing"}'; exit 0; }
ls $RE/bin/amd64 2>/dev/null | head -12 | tr '\n' ' ' > $D/re-ls.log; echo "bin: $(cat $D/re-ls.log)"
mkdir -p /work/re /work/rec
# dedicated server: private (no master), team deathmatch (mode 2, no FFA mutator), bots fill both teams
cat > /work/re/servinit.cfg <<CFG
servertype 1
serverip 127.0.0.1
serverport $PORT
sv_serverclients 8
sv_serverspectators 2
sv_defaultmode 2
sv_defaultmuts 0
sv_timelimit $TLIMIT
sv_overtimelimit 0
sv_botlimit $BOTS
sv_botbalance $BOTS
sv_botskillmin $SMIN
sv_botskillmax $SMAX
adminpass rollmarkets-arena
verbose 2
CFG
cp /work/re/servinit.cfg /work/re/localinit.cfg   # a non-dedicated servertype execs localinit.cfg; servinit.cfg is read first either way
( cd $RE && ./redeclipse_server.sh -h/work/re -g/work/logs/resrv.log -v2 >$D/resrv-out.log 2>&1 ) &
SRV=$!; sleep 10
echo "server alive: $(kill -0 $SRV 2>/dev/null && echo yes || echo NO) · $(tail -c 300 $D/resrv.log 2>/dev/null | tr '\n' ' ')"
# spectator client: silent, windowed at the capture size, joins as spectator, TV camera, dumps team scores every 5 s.
# init.cfg is executed before the display exists: Xvfb reports 0 Hz and the loading screen divides by the refresh
# rate unless progressfps/maxfps are pinned (SIGFPE in "Loading world..")
cat > /work/rec/init.cfg <<CFG
progressfps 30
maxfps 60
menufps 60
connectguidelines 1
playername RollMarkets
CFG
export SDL_AUDIODRIVER=dummy
cat > /work/rec/arena.cfg <<CFG
mastervol 0
musicvol 0
soundvol 0
specmode 1
followthirdperson 1
scoredump = [ refreshscoreboard; echo (concatword "SCORES t" (getscoreteam 0) ":" (getscoretotal 0) " t" (getscoreteam 1) ":" (getscoretotal 1) " n=" (numscoreboard 0) "/" (numscoreboard 1) " spec=" (numspectators 0) " tr=" (gametimeremain) " im=" (intermission)); sleep 5000 [scoredump] ]
connectguidelines 1
sleep 6000 [spectate 1]
sleep 7000 [setpriv rollmarkets-arena]
sleep 9000 [sv_timelimit $TLIMIT; sv_overtimeallow 0; sv_defaultmode 2; sv_defaultmuts 0]
sleep 11000 [mode 2 0; map $MAP]
sleep 16000 [spectate 1]
sleep 18000 [scoredump]
connect 127.0.0.1 $PORT
CFG
echo "X before: $(xstate)"
# the launcher word-splits its arguments (so "-xexec arena.cfg" became "-xexec"): run the binary directly, like the launcher does
( cd $RE && LD_LIBRARY_PATH=$RE/bin/amd64:${LD_LIBRARY_PATH:-} timeout $((TLIMIT*60+240)) $RUN ./bin/amd64/redeclipse_linux -h/work/rec -dw$W -dh$H -df0 -g/work/logs/recl-con.log "-xexec arena.cfg" >$D/recl.log 2>&1 ) &   # -g: the console (echo, obituaries) goes to a file as well as stdout
CL=$!
# wait for the match: the time limit plus a grace, or until the client or server dies; the scores keep arriving meanwhile
for i in $(seq 1 $((TLIMIT*60+150))); do kill -0 $CL 2>/dev/null || break; kill -0 $SRV 2>/dev/null || break; [ $i -gt 75 ] && grep -aq "im=1" $D/recl-con.log 2>/dev/null && { echo "intermission at ${i}s"; sleep 6; break; }; sleep 1; done
echo "X after: $(xstate)"
cat $D/recl-con.log >> $D/recl.log 2>/dev/null; LAST=$(grep -a "SCORES t" $D/recl.log | tail -1); NSCORES=$(grep -ac "SCORES t" $D/recl.log)
kill $CL 2>/dev/null; sleep 1; kill $SRV 2>/dev/null; sleep 1
echo "--- resrv.log tail"; tail -c 1500 $D/resrv.log 2>/dev/null; echo; echo "--- recl.log tail"; tail -c 1500 $D/recl.log 2>/dev/null; echo
echo "scores lines: $NSCORES · last: $LAST"
# obituaries on the client console count kills per name (best effort); team totals decide the result
RESULT_JSON=$(python3 - "$D/recl.log" "$LAST" "$TLIMIT" "$BOTS" <<'PY'
import sys, re, json
log, last, tl, bots = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
res = {'game': 'redeclipse', 'ok': False, 'timelimit': tl, 'bots': bots}
m = re.findall(r't(-?\d+):(-?\d+)', last)
if len(m) >= 2:
    teams = {int(t): int(s) for t, s in m[:2]}
    ids = sorted(teams); a = teams.get(1, teams[ids[0]]); o = teams.get(2, teams[ids[-1]] if len(ids) > 1 else 0)   # 1 = alpha, 2 = omega
    res.update({'ok': True, 'frags': {'alpha': a, 'omega': o}, 'teams': {str(k): v for k, v in teams.items()}, 'winner': 'alpha' if a > o else 'omega' if o > a else 'draw'})
else:
    res['error'] = 'no scoreboard lines from the spectator'
try:
    txt = open(log, errors='replace').read(); txt = re.sub(r'\f[sS]|\f[a-zA-Z0-9]', '', txt)
    kills = {}
    for line in txt.split('\n'):
        mm = re.search(r'(\S.{0,30}?) (?:fragged|killed|sprayed|gunned down|obliterated|gibbed|splattered) (\S.{0,30}?)\s*$', line)   # console lines may carry a time prefix
        if mm: kills[mm.group(1).strip()] = kills.get(mm.group(1).strip(), 0) + 1
    if kills: res['players'] = dict(sorted(kills.items(), key=lambda kv: -kv[1])[:12])
except Exception as e: res['parseNote'] = str(e)[:80]
print(json.dumps(res))
PY
)
DIAG=$( { echo "== runner"; md5sum /games/redeclipse.sh | cut -c1-8; echo "== gpu"; cat $D/gpu.log; echo "== bin"; cat $D/re-ls.log; echo "== X"; grep -aE "^X (before|after)" $D/game.log 2>/dev/null | tail -2; echo "== server"; tail -c 900 $D/resrv.log 2>/dev/null; echo; echo "== client"; grep -a "SCORES t\|connected\|spectat\|intermission\|error\|failed" $D/recl.log 2>/dev/null | tail -12; echo "== client tail"; tail -c 700 $D/recl.log 2>/dev/null; } 2>&1 | tr -cd '\11\12\15\40-\176' | head -c 6000 )
echo "RESULT $(jq -cn --argjson r "$RESULT_JSON" --arg diag "$DIAG" '$r + {diag:$diag}')"
