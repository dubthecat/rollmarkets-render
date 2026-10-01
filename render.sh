#!/usr/bin/env bash
# Env: GAME MATCH_ID ARENA SRT_URL VIA ENGINE PUBLISH_KEY (also PLAYERS as JSON), W H FPS BITRATE optional.
set -uo pipefail
: "${GAME:=test}" "${MATCH_ID:=demo}" "${ARENA:=kart}" "${SRT_URL:?SRT_URL required}" "${VIA:=srt}" "${ENGINE:=https://rollmarkets.com}" "${W:=960}" "${H:=540}" "${FPS:=30}" "${BITRATE:=3M}" "${PUBLISH_KEY:=}"
export DISPLAY=:99 W H FPS GAME MATCH_ID ARENA ENGINE
mkdir -p /work/logs; LOG=/work/logs/render.log; : > $LOG
log() { echo "$(date -u +%H:%M:%S) $*" | tee -a $LOG; }
# ---- report logs and results to the engine (auth = the publish key) ----
report() { curl -s -m 8 -X POST "$ENGINE/v1/stream/pod/$1" -H 'content-type: application/json' -H "x-pod-key: $PUBLISH_KEY" -d "$2" >/dev/null 2>&1 || true; }
tails() { for f in render.log gpu.log glx.log game.log stk.log xonsrv.log xoncl.log hw.log ffmpeg.log xvfb.log; do [ -s /work/logs/$f ] && { echo "==> $f"; tail -c ${1:-1500} /work/logs/$f; echo; }; done; }
logpump() { while true; do sleep 20; report log "$(jq -cn --arg id "$MATCH_ID" --arg arena "$ARENA" --arg game "$GAME" --arg tail "$(tails 1200)" '{matchId:$id,arena:$arena,game:$game,tail:$tail}')"; done; }
# runners are fetched fresh from the repo at start (iterate without rebuilding the image); RUNNER_RAW="" disables
: "${RUNNER_RAW:=https://raw.githubusercontent.com/dubthecat/rollmarkets-render/main}"
fetch_runner() {   # the raw CDN caches for minutes; the contents API is not cached (60 requests/h anonymous is plenty), raw is the fallback
  local f=/games/$GAME.sh
  if curl -fsSL -m 20 -H 'Accept: application/vnd.github.raw' "https://api.github.com/repos/dubthecat/rollmarkets-render/contents/games/$GAME.sh?ref=main" -o $f.new && head -1 $f.new | grep -q '^#!'; then mv $f.new $f; log "runner fetched via the GitHub API ($(md5sum $f | cut -c1-8))"; return 0; fi
  if curl -fsSL -m 20 "$RUNNER_RAW/games/$GAME.sh?$(date +%s)" -o $f.new && head -1 $f.new | grep -q '^#!'; then mv $f.new $f; log "runner fetched from $RUNNER_RAW ($(md5sum $f | cut -c1-8))"; return 0; fi
  rm -f $f.new; log "runner fetch failed, using the image copy ($(md5sum $f | cut -c1-8))"
}
if [ -n "$RUNNER_RAW" ] && [ "$GAME" != test ]; then fetch_runner; chmod +x /games/$GAME.sh; fi
logpump & LOGPUMP=$!
finish() { local code=${1:-0}; report log "$(jq -cn --arg id "$MATCH_ID" --arg arena "$ARENA" --arg game "$GAME" --arg tail "$(tails 2500)" '{matchId:$id,arena:$arena,game:$game,tail:$tail,final:true}')"; kill $LOGPUMP 2>/dev/null; exit $code; }
trap 'finish 143' TERM INT
log "render pod · game=$GAME match=$MATCH_ID arena=$ARENA via=$VIA ${W}x${H}@${FPS}"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | tee -a $LOG || log "no nvidia-smi"
# ---- display + encoder ----
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null   # a container restarted by RunPod inherits a stale lock from the previous run
Xvfb :99 -screen 0 ${W}x${H}x24 +extension GLX +render -noreset >/work/logs/xvfb.log 2>&1 &
for i in $(seq 1 40); do xdpyinfo -display :99 >/dev/null 2>&1 && break; sleep 0.5; done; log "display up after $((i/2)) s"
export SDL_VIDEODRIVER=x11
{ echo "vglrun: $(command -v vglrun || echo missing)"; ls /dev/nvidia* 2>/dev/null | tr "\n" " "; echo; ls /usr/lib/x86_64-linux-gnu/libnvidia-egl* /usr/lib/x86_64-linux-gnu/libEGL_nvidia* /usr/share/glvnd/egl_vendor.d/ 2>/dev/null | tr "\n" " "; echo; eglinfo -B 2>&1 | head -12; } >/work/logs/gpu.log 2>&1
if command -v vglrun >/dev/null && VGL_DISPLAY=egl vglrun -d egl glxinfo -B >/work/logs/glx.log 2>&1; then export VGL_DISPLAY=egl; RUN="vglrun -d egl"; log "GL: VirtualGL/EGL → $(grep -m1 'OpenGL renderer' /work/logs/glx.log)"; else RUN=""; log "GL: software (llvmpipe)"; export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe; fi
export RUN
if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q h264_nvenc && nvidia-smi >/dev/null 2>&1; then ENC="-c:v h264_nvenc -preset p4 -tune ll -b:v $BITRATE -maxrate $BITRATE -bufsize 2M -g $((FPS*2))"; log "encoder: nvenc"; else ENC="-c:v libx264 -preset veryfast -tune zerolatency -b:v $BITRATE -g $((FPS*2))"; log "encoder: x264"; fi
OUT="-f mpegts"; [ "$VIA" = rtmp ] && OUT="-f flv"
stream() { ffmpeg -hide_banner -loglevel warning -f x11grab -framerate $FPS -video_size ${W}x${H} -i :99 -f lavfi -i anullsrc=r=44100:cl=stereo -vf "drawtext=text='RollMarkets · $ARENA · $MATCH_ID':fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.4:x=16:y=16" $ENC -c:a aac -shortest $OUT "$SRT_URL" >>/work/logs/ffmpeg.log 2>&1 & echo $!; }
case "$GAME" in
  test) ffmpeg -hide_banner -loglevel warning -re -f lavfi -i "testsrc2=size=${W}x${H}:rate=$FPS" -f lavfi -i "sine=frequency=440" -t 900 -vf "drawtext=text='RollMarkets $ARENA $MATCH_ID %{localtime}':fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:fontsize=36:fontcolor=white:x=40:y=40" $ENC -c:a aac $OUT "$SRT_URL"; finish 0 ;;
  supertuxkart|xonotic|hedgewars|ikemen) ;;
  *) log "unknown game $GAME"; finish 2 ;;
esac
FF=$(stream); log "streaming (ffmpeg pid $FF)"
sleep 2
# the game script runs the match and prints a RESULT line (JSON) at the end
/games/$GAME.sh 2>&1 | tee /work/logs/game.log
RESULT=$(grep -m1 '^RESULT ' /work/logs/game.log | sed 's/^RESULT //')
log "match finished: ${RESULT:-no result}"
if [ -n "$RESULT" ]; then
  BODY=$(jq -cn --arg id "$MATCH_ID" --arg arena "$ARENA" --arg game "$GAME" --argjson r "$RESULT" '{matchId:$id,arena:$arena,game:$game,result:$r}' 2>/dev/null)
  [ -z "$BODY" ] && BODY=$(jq -cn --arg id "$MATCH_ID" --arg arena "$ARENA" --arg game "$GAME" --arg raw "$RESULT" '{matchId:$id,arena:$arena,game:$game,result:{ok:false,error:"unparseable RESULT",raw:$raw[0:2000]}}')
  if [ ${#BODY} -gt 30000 ]; then BODY=$(jq -c '.result.diag = ((.result.diag // "")[0:4000])' <<< "$BODY"); fi   # the engine accepts 32 KB
  log "result body ${#BODY} bytes"; report result "$BODY"
fi
sleep 3; kill $FF 2>/dev/null; wait $FF 2>/dev/null
# never exit: RunPod restarts an exited container, which would play (and report) the match a second time; the engine
# terminates the pod once it has the result, the janitor kills anything older than its limit
report log "$(jq -cn --arg id "$MATCH_ID" --arg arena "$ARENA" --arg game "$GAME" --arg tail "$(tails 2500)" '{matchId:$id,arena:$arena,game:$game,tail:$tail,final:true}')"
kill $LOGPUMP 2>/dev/null; log "idle until terminated"; sleep infinity
