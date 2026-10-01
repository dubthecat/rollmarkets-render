#!/usr/bin/env bash
# Team deathmatch between built-in bots on a dedicated server, watched by a spectator client that is
# captured; the server's event log gives team scores and frags. $PLAYERS: [{name, team:"red"|"blue", skill}]
set -uo pipefail
export PATH="$PATH:/usr/games:/usr/local/games"
# an empty player list means "use the defaults"
[ -z "${PLAYERS:-}" ] || [ "${PLAYERS}" = "[]" ] && unset PLAYERS
# GPU diagnostics once per run
{ echo "caps=${NVIDIA_DRIVER_CAPABILITIES:-} vgl=${VGL_DISPLAY:-} RUN=${RUN:-}"; ls /dev/nvidia* 2>/dev/null | tr '\n' ' '; echo; grep -E "renderer|version" /work/logs/glx.log 2>/dev/null | head -4; } >/work/logs/gpu.log 2>&1
PLAYERS=${PLAYERS:-'[{"name":"Coach aggressive","team":"red","skill":7},{"name":"Coach tactical","team":"blue","skill":7}]'}
MAP=${MAP:-dance}; FRAGS=${FRAGS:-20}; TLIMIT=${TLIMIT:-5}; BOTS=${BOTS:-6}
XON=/opt/Xonotic
echo "match: map=$MAP fraglimit=$FRAGS timelimit=${TLIMIT}m bots=$BOTS"; echo "--- gpu diag"; cat /work/logs/gpu.log; echo "---"
ls $XON | head -20 >/work/logs/xon-ls.log 2>&1
mkdir -p /work/xon /work/xonc && cat > /work/xon/server.cfg <<CFG
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
sv_vote_commands ""
sv_autodemo 0
g_warmup 0
gametype tdm
map $MAP
CFG
cd $XON && ./xonotic-linux64-dedicated -basedir $XON -userdir /work/xon +exec /work/xon/server.cfg >/work/logs/xonsrv.log 2>&1 &
SRV=$!; sleep 10
# the spectator client renders the match; once in, "attack" makes it follow a player (chase camera)
cat > /work/xonc/spect.cfg <<CFG
vid_fullscreen 0
mastervolume 0
cl_autodemo 0
r_motionblur 0
crosshair 0
defer 25 "+attack"
defer 27 "-attack"
connect 127.0.0.1
CFG
timeout $((TLIMIT*60+120)) $RUN ./xonotic-linux64-glx -basedir $XON -userdir /work/xonc -window -width $W -height $H +exec /work/xonc/spect.cfg >/work/logs/xoncl.log 2>&1 &
CL=$!
# wait for the match to end (eventlog ":end"), or for the server to die
for i in $(seq 1 $((TLIMIT*60+90))); do grep -q "^:end" /work/logs/xonsrv.log 2>/dev/null && { sleep 5; break; }; kill -0 $SRV 2>/dev/null || break; sleep 1; done
kill $CL 2>/dev/null; kill $SRV 2>/dev/null; sleep 1
echo "--- xonsrv.log tail"; tail -40 /work/logs/xonsrv.log; echo "--- xoncl.log tail"; tail -20 /work/logs/xoncl.log
# event log at the end: ":teamscores:see-labels:<score,...>:<team>" with team 5 = red, 14 = blue; ":player:see-labels:<score,kills,...>:<slot>:<team>:<name>"
RED=$(grep -E "^:teamscores:see-labels:" /work/logs/xonsrv.log | awk -F: '$5=="5"{print $4}' | tail -1 | cut -d, -f1); BLUE=$(grep -E "^:teamscores:see-labels:" /work/logs/xonsrv.log | awk -F: '$5=="14"{print $4}' | tail -1 | cut -d, -f1)
PLAYERS_OUT=$(grep -E "^:player:see-labels:" /work/logs/xonsrv.log | tail -$((BOTS+2)) | awk -F: '{print $7"|"$6"|"$4}' | jq -R 'split("|") | {name:.[0], team:(if .[1]=="5" then "red" elif .[1]=="14" then "blue" else .[1] end), score:(.[2]|split(",")[0]|tonumber? // null)}' | jq -cs .)
DIAG=$( { echo "== gpu"; cat /work/logs/gpu.log; echo "== dir"; cat /work/logs/xon-ls.log; echo "== server head"; head -25 /work/logs/xonsrv.log; echo "== server key"; grep -iE "^:|bot|error|map|gametype|cannot|fail" /work/logs/xonsrv.log | tail -60; echo "== client head"; head -20 /work/logs/xoncl.log; echo "== client key"; grep -iE "error|fail|cannot|renderer|opengl|connect|spectat|video" /work/logs/xoncl.log | tail -30; echo "== client tail"; tail -12 /work/logs/xoncl.log; } 2>/dev/null | cut -c1-220 | head -c 14000 )
echo "RESULT $(jq -cn --arg red "${RED:-}" --arg blue "${BLUE:-}" --arg map "$MAP" --argjson players "${PLAYERS_OUT:-[]}" --arg diag "$DIAG" '{game:"xonotic",frags:{red:($red|tonumber? // null),blue:($blue|tonumber? // null)},players:$players,map:$map,ok:(($red|length)>0 and ($blue|length)>0),diag:$diag}')"
