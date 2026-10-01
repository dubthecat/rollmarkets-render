#!/usr/bin/env bash
# Team deathmatch between built-in bots on a dedicated server, watched by a spectator client that is
# captured; the server's event log gives frags and the winner. $PLAYERS: [{name, team:"red"|"blue", skill}]
set -uo pipefail
PLAYERS=${PLAYERS:-'[{"name":"Coach aggressive","team":"red","skill":7},{"name":"Coach tactical","team":"blue","skill":7}]'}
MAP=${MAP:-dance}; FRAGS=${FRAGS:-20}; TLIMIT=${TLIMIT:-5}
mkdir -p /work/xon && cat > /work/xon/server.cfg <<CFG
sv_public 0
hostname "RollMarkets arena"
g_tdm 1
gametype tdm
sv_eventlog 1
sv_eventlog_console 1
sv_autodemo 1
bot_number 6
skill 7
minplayers 0
fraglimit $FRAGS
timelimit $TLIMIT
sv_vote_commands ""
map $MAP
CFG
xonotic-dedicated -userdir /work/xon +exec /work/xon/server.cfg >/work/logs/xonsrv.log 2>&1 &
SRV=$!; sleep 8
# the spectator client renders the match
timeout $((TLIMIT*60+90)) $RUN xonotic-glx -userdir /work/xonc -window -width $W -height $H +connect 127.0.0.1 +spectate 1 +cl_autodemo 1 +vid_fullscreen 0 +mastervolume 0 >/work/logs/xoncl.log 2>&1 &
CL=$!
# wait for the match to end (eventlog ":end")
for i in $(seq 1 $((TLIMIT*60+60))); do grep -q "^:end" /work/logs/xonsrv.log 2>/dev/null && break; sleep 1; done
kill $CL 2>/dev/null; kill $SRV 2>/dev/null
RED=$(grep -oE "^:teamscores:[^:]*:5:[0-9]+" /work/logs/xonsrv.log | tail -1 | awk -F: '{print $NF}'); BLUE=$(grep -oE "^:teamscores:[^:]*:14:[0-9]+" /work/logs/xonsrv.log | tail -1 | awk -F: '{print $NF}')
echo "RESULT $(jq -cn --arg red "${RED:-}" --arg blue "${BLUE:-}" --arg map "$MAP" '{game:"xonotic",frags:{red:($red|tonumber? // null),blue:($blue|tonumber? // null)},map:$map,ok:(($red|length)>0 and ($blue|length)>0)}')"
