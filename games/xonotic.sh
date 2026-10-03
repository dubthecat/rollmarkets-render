#!/usr/bin/env bash
# Team deathmatch between built-in bots on a dedicated server, watched by a spectator client that is
# captured; the server's event log gives team scores and frags. $PLAYERS: [{name, team:"red"|"blue", skill}]
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
PLAYERS=${PLAYERS:-'[{"name":"Coach aggressive","team":"red","skill":7},{"name":"Coach tactical","team":"blue","skill":7}]'}
MAP=${MAP:-afterslime}; FRAGS=${FRAGS:-25}; TLIMIT=${TLIMIT:-4}; BOTS=${BOTS:-6}   # the map must list "gametype tdm" in its mapinfo (dance is CTF-only: the server silently switched modes)
XON=/opt/Xonotic
echo "match: map=$MAP fraglimit=$FRAGS timelimit=${TLIMIT}m bots=$BOTS"; echo "--- gpu diag"; cat $D/gpu.log; echo "---"
ls $XON | head -20 >$D/xon-ls.log 2>&1
# Darkplaces only execs cfg files from its game dirs: configs live in <userdir>/data/
mkdir -p /work/xon/data /work/xonc/data && cat > /work/xon/data/server.cfg <<CFG
sv_public 0
hostname "RollMarkets arena"
sv_eventlog 1
sv_eventlog_console 1
sv_eventlog_files 0
bot_number $BOTS
bot_join_empty 1
skill 7
minplayers 0
fraglimit $FRAGS
timelimit $TLIMIT
fraglimit_override $FRAGS
timelimit_override $TLIMIT
leadlimit_override 0
g_warmup 0
sv_vote_commands ""
sv_autodemo 0
g_warmup 0
g_tdm 1
g_dm 0
g_ctf 0
g_tdm_teams 2
sv_vote_gametype 0
map $MAP
CFG
cd $XON || echo "no $XON"
$XON/xonotic-linux64-dedicated -basedir $XON -userdir /work/xon +exec server.cfg >$D/xonsrv.log 2>&1 &
SRV=$!; sleep 10
# the spectator client renders the match; once in, "attack" makes it follow a player (chase camera)
cat > /work/xonc/data/spect.cfg <<CFG
_termsofservice_accepted 999
cl_welcome 0
cl_allow_uid2name 0
cl_allow_uidtracking 0
cl_allow_uidranking 0
vid_fullscreen 0
mastervolume 0
cl_autodemo 0
r_motionblur 0
crosshair 0
defer 25 "+attack"
defer 27 "-attack"
connect 127.0.0.1
CFG
echo "X before: $(xstate)"
# audio probe one minute into the match: is the game connected to the PulseAudio null sink? (goes into the RESULT diag)
( sleep 60; { echo "== audio probe $(date -u +%T)"; pactl list short sinks 2>&1; echo "-- sink-inputs (the game's streams)"; pactl list short sink-inputs 2>&1; echo "-- clients"; pactl list short clients 2>&1 | head -8; env | grep -E "^(PULSE_SERVER|PULSE_SINK|SDL_AUDIODRIVER|ALSOFT_DRIVERS|AUDIODEV)="; } > $D/audio.log 2>&1 ) &
timeout $((TLIMIT*60+180)) $RUN $XON/xonotic-linux64-glx -basedir $XON -userdir /work/xonc -window -width $W -height $H +seta _termsofservice_accepted 999 +seta cl_welcome 0 +exec spect.cfg >$D/xoncl.log 2>&1 &
CL=$!
# wait for the match to end (eventlog ":end"), or for the server to die
for i in $(seq 1 $((TLIMIT*60+150))); do grep -q "^:end" $D/xonsrv.log 2>/dev/null && { sleep 5; break; }; kill -0 $SRV 2>/dev/null || break; sleep 1; done
echo "X after: $(xstate)"
kill $CL 2>/dev/null; kill $SRV 2>/dev/null; sleep 1
echo "--- xonsrv.log tail"; tail -40 $D/xonsrv.log; echo "--- xoncl.log tail"; tail -20 $D/xoncl.log
# event log at the end: ":teamscores:see-labels:<score,...>:<team>" with team 5 = red, 14 = blue; ":player:see-labels:<score,kills,...>:<slot>:<team>:<name>"
RED=$(grep -E "^:teamscores:see-labels:" $D/xonsrv.log | awk -F: '$5=="5"{print $4}' | tail -1 | cut -d, -f1); BLUE=$(grep -E "^:teamscores:see-labels:" $D/xonsrv.log | awk -F: '$5=="14"{print $4}' | tail -1 | cut -d, -f1)
# per-player frags from the event log of the last game: ":join:<slot>:<id>:<ip>:<name>", ":team:<slot>:<team>:<old>", ":kill:frag:<attacker>:<victim>:…"
PLAYERS_OUT=$(python3 - "$D/xonsrv.log" <<'PY'
import sys, json, re
lines = open(sys.argv[1], errors='replace').read().split('\n')
try: start = max(i for i, l in enumerate(lines) if l.startswith(':gamestart:'))
except ValueError: start = 0
name, team, frags, deaths = {}, {}, {}, {}
for l in lines[start:]:
    f = l.split(':')
    if l.startswith(':join:') and len(f) >= 6: name[f[2]] = f[5]; frags.setdefault(f[2], 0); deaths.setdefault(f[2], 0)
    elif l.startswith(':team:') and len(f) >= 4: team[f[2]] = f[3]
    elif l.startswith(':kill:frag:') and len(f) >= 5: frags[f[3]] = frags.get(f[3], 0) + 1; deaths[f[4]] = deaths.get(f[4], 0) + 1
    elif l.startswith(':kill:suicide:') and len(f) >= 4: deaths[f[3]] = deaths.get(f[3], 0) + 1
tm = lambda t: {'5': 'red', '14': 'blue'}.get(t, t or '?')
out = [{'name': re.sub(r'\^\d|\^x[0-9a-fA-F]{3}', '', name[s]), 'team': tm(team.get(s)), 'frags': frags.get(s, 0), 'deaths': deaths.get(s, 0)} for s in name if name[s] and team.get(s) in ('5', '14')]
out.sort(key=lambda p: -p['frags']); print(json.dumps(out))
PY
)
DIAG=$( { echo "== audio"; cat $D/audio.log 2>/dev/null; grep -ai "snd\|openal\|audio\|sound" $D/xoncl.log 2>/dev/null | head -6; echo "== runner"; md5sum /games/xonotic.sh | cut -c1-8; head -14 $D/render.log; echo "== gpu"; cat $D/gpu.log; echo "== dir"; cat $D/xon-ls.log; echo "== X"; grep -E "^X (before|after)" $D/game.log 2>/dev/null; echo "== server head"; head -25 $D/xonsrv.log; echo "== gamestart"; grep -a "^:gamestart:" $D/xonsrv.log | head -3; echo "== server key"; grep -aiE "^:(end|teamscores|player|gamestart)|bot_|error|cannot|fail|gametype" $D/xonsrv.log | tail -60; echo "== client head"; head -20 $D/xoncl.log; echo "== client key"; grep -iE "error|fail|cannot|renderer|opengl|connect|spectat|video" $D/xoncl.log | tail -30; echo "== client tail"; tail -12 $D/xoncl.log; } 2>/dev/null | cut -c1-220 | head -c 14000 )
echo "RESULT $(jq -cn --arg red "${RED:-}" --arg blue "${BLUE:-}" --arg map "$MAP" --argjson players "${PLAYERS_OUT:-[]}" --arg diag "$DIAG" '{game:"xonotic",frags:{red:($red|tonumber? // null),blue:($blue|tonumber? // null)},players:$players,map:$map,ok:(($red|length)>0 and ($blue|length)>0),diag:$diag}')"
