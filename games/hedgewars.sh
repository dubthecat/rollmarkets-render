#!/usr/bin/env bash
# Two AI teams on a random map. hwengine only plays a game when a FRONTEND feeds it the game config
# over its IPC socket (engine started with --internal --port N connects to 127.0.0.1:N; every message is
# one length byte + text). A tiny Python frontend below listens, sends the config when the engine asks
# ("C"), answers its pings ("?" → "!"), collects the end-of-game stats ("i…" messages) and stops at "q".
# $PLAYERS: [{name, level}] (AI level 1 strong … 5 weak)
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
PLAYERS=${PLAYERS:-'[{"name":"Hog bot rookie","level":4},{"name":"Hog bot veteran","level":2}]'}
SEED=${SEED:-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')}
HOGS=${HOGS:-2}; TURN_MS=${TURN_MS:-15000}; GAME_S=${GAME_S:-540}
export PLAYERS SEED HOGS TURN_MS GAME_S W H RUN
echo "match: teams=$(echo "$PLAYERS" | jq -r '[.[].name] | join(" vs ")') hogs=$HOGS turn=${TURN_MS}ms seed=$SEED"; echo "--- gpu diag"; cat /work/logs/gpu.log; echo "---"
mkdir -p /work/hw
# Ubuntu keeps the engine out of PATH (/usr/lib/hedgewars/bin/hwengine) and the data under /usr/share/hedgewars/Data
export PATH="$PATH:/usr/lib/hedgewars/bin:/usr/lib/games/hedgewars/bin:/usr/games"
HWENGINE=$(command -v hwengine 2>/dev/null || find /usr /opt -name hwengine -type f 2>/dev/null | head -1); export HWENGINE
DATA=""; for d in /usr/share/games/hedgewars/Data /usr/share/hedgewars/Data /usr/lib/hedgewars/Data; do [ -d "$d/Themes" ] && { DATA=$d; break; }; done
[ -z "$DATA" ] && DATA=$(find /usr /opt -type d -name Themes -path '*edgewars*' 2>/dev/null | head -1 | xargs -r dirname)
echo "engine: ${HWENGINE:-NOT FOUND} · data: ${DATA:-NOT FOUND}"; { echo "engine: ${HWENGINE:-NOT FOUND} · data: ${DATA:-NOT FOUND}"; dpkg -L hedgewars 2>/dev/null | grep -E "bin/|Data$" | head -8; } > /work/logs/hw-where.log 2>&1
[ -n "$HWENGINE" ] && "$HWENGINE" --help >/work/logs/hw-help.log 2>&1 || true
HWVER=$(dpkg-query -W -f='${Version}' hedgewars 2>/dev/null || echo unknown); echo "hedgewars package $HWVER" >> /work/logs/hw-where.log
case "$HWVER" in 1.0.*) export HW_AMMO_N=59;; 1.1*|1.2*) export HW_AMMO_N=60;; *) export HW_AMMO_N=${HW_AMMO_N:-59};; esac
cat > /work/hwfront.py <<'PY'
import json, os, socket, subprocess, sys, time, shlex
players = json.loads(os.environ['PLAYERS']); hogs = int(os.environ.get('HOGS', '3')); turn = int(os.environ.get('TURN_MS', '25000'))
seed = os.environ['SEED']; W = os.environ.get('W', '960'); H = os.environ.get('H', '540'); game_s = int(os.environ.get('GAME_S', '780'))
run = shlex.split(os.environ.get('RUN', '')); data = sys.argv[1]
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); srv.bind(('127.0.0.1', 0)); srv.listen(1); port = srv.getsockname()[1]
log = open('/work/logs/hwfront.log', 'a')
def L(*a): print(time.strftime('%H:%M:%S'), *a, file=log, flush=True)
cmd = run + [os.environ.get('HWENGINE') or 'hwengine', '--internal', '--port', str(port), '--prefix', data, '--user-prefix', '/work/hw', '--width', W, '--height', H, '--nosound', '--nomusic', '--nodampen', '--no-teamtag', '--locale', 'en.txt']
L('spawn', ' '.join(cmd))
eng = subprocess.Popen(cmd, stdout=open('/work/logs/hw.log', 'a'), stderr=subprocess.STDOUT)
srv.settimeout(90)
try: conn, _ = srv.accept()
except Exception as e: L('engine never connected', e); eng.kill(); print('RESULT ' + json.dumps({'game': 'hedgewars', 'winner': None, 'ok': False, 'error': 'engine never connected'})); sys.exit(0)
L('engine connected')
def send(*msgs):
    buf = b''
    for m in msgs: b = m.encode('utf-8'); buf += bytes([len(b)]) + b
    conn.sendall(buf)
AMMO = ['93919294221991210322351110012000000002111001010111110001000', '04050405416006555465544647765766666661555101011154111111107', '00000000000002055000000400070040000000002200000006000200000', '13111103121111111231141111111111111112111111111111111111111']   # 1.0.0 defaults (59 ammo types)
n_ammo = int(os.environ.get('HW_AMMO_N', '59'))
colors = ['16711680', '255', '65280', '16776960']   # eaddteam <hash> <rgb int> <name> (QtFrontend: qcolor().rgb() & 0xffffff); different colours = different clans
def config():
    c = ['TL', 'eseed {%s}' % seed, 'e$gmflags 0', 'e$damagepct 125', 'e$turntime %d' % turn, 'e$sd_turns 6', 'e$casefreq 5', 'e$minestime 3000', 'e$minesnum 4', 'e$minedudpct 0', 'e$explosives 2', 'e$airmines 0',
         'e$healthprob 35', 'e$hcaseamount 25', 'e$worldedge 0', 'e$getawaytime 100', 'e$ropepct 100', 'e$template_filter 0', 'e$feature_size 12', 'e$mapgen 0', 'e$maze_size 0', 'etheme Nature']
    # per team, exactly as HWGame::commonConfig + HWTeam::teamGameConfig send it: ammo scheme, store, then the team and its hogs
    for i, p in enumerate(players):
        name = str(p.get('name', 'Team %d' % (i + 1)))[:30]; lvl = max(1, min(5, int(p.get('level', 3))))
        # the four ammo lines must be exactly High(TAmmoType) characters for the installed engine (Hedgewars 1.0.0 = 59,
        # QTfrontend/weapons.h AMMOLINE_DEFAULT_*); a wrong length makes eammstore fail ("Incomplete or missing ammo scheme set")
        c += ['eammloadt ' + AMMO[0][:n_ammo].ljust(n_ammo, '0'), 'eammprob ' + AMMO[1][:n_ammo].ljust(n_ammo, '0'), 'eammdelay ' + AMMO[2][:n_ammo].ljust(n_ammo, '0'), 'eammreinf ' + AMMO[3][:n_ammo].ljust(n_ammo, '1'), 'eammstore',
              'eaddteam %032x %s %s' % (i + 1, colors[i % 4], name), 'egrave Statue', 'efort Castle', 'evoicepack Default', 'eflag hedgewars']
        for h in range(hogs): c += ['eaddhh %d 100 %s %d' % (lvl, name.split(' ')[0], h + 1), 'ehat NoHat']
    c.append('!')
    return c
stats = []; result = None; ended = None; t0 = time.time(); buf = b''
conn.settimeout(5)
while time.time() - t0 < game_s and eng.poll() is None:
    try: chunk = conn.recv(65536)
    except socket.timeout: continue
    except Exception as e: L('recv error', e); break
    if not chunk: L('engine closed the socket'); break
    buf += chunk
    while buf:
        n = buf[0]
        if len(buf) < 1 + n: break
        m = buf[1:1 + n].decode('utf-8', 'replace'); buf = buf[1 + n:]
        k = m[:1]
        if k == 'C': L('config requested'); send(*config())
        elif k == '?': send('!')
        elif k == 'i': stats.append(m[1:]); L('stat', m[1:])
        elif k in ('q', 'Q'): ended = k; L('engine says', k); break
        elif k == 'E': L('ERROR', m[1:])
        elif k in ('e', 'm'): pass
        else: L('msg', m[:80])
    if ended: break
L('loop done, ended=%s, stats=%d' % (ended, len(stats)))
time.sleep(2)
try: conn.close()
except Exception: pass
try: eng.terminate(); eng.wait(10)
except Exception: eng.kill()
names = [str(p.get('name')) for p in players]; winner = None
for s in stats:
    if s[:1] == 'r':
        txt = s[1:]
        for nm in names:
            if nm in txt: winner = nm
        result = txt
if winner is None:   # the engine also writes "Console: WINNERS / <count> / <team names>" to its log
    import glob
    for f in glob.glob('/work/hw/Logs/*.log'):
        try: lines = [l.rstrip('\n') for l in open(f, errors='replace')]
        except Exception: continue
        for k, l in enumerate(lines):
            if l.endswith('Console: WINNERS'):
                for l2 in lines[k + 2:k + 4]:
                    for nm in names:
                        if l2.endswith('Console: ' + nm): winner = winner or nm
for s in stats:   # "P<colour> <kills> <TeamName>" is sent for the surviving clan's teams (rank 1)
    if winner is None and s[:1] == 'P':
        for nm in names:
            if s.endswith(' ' + nm): winner = nm
print('RESULT ' + json.dumps({'game': 'hedgewars', 'winner': winner, 'teams': names, 'ok': winner is not None, 'ended': ended, 'resultText': result, 'stats': stats[:40]}))
PY
echo "X before: $(xstate)"
timeout $((GAME_S+60)) python3 /work/hwfront.py "$DATA" 2>&1 | tee /work/logs/hwfront-out.log | grep -v '^RESULT'
echo "X after: $(xstate)"; echo "--- hw.log head"; head -30 /work/logs/hw.log; echo "--- hw.log tail"; tail -20 /work/logs/hw.log; echo "--- frontend log"; tail -30 /work/logs/hwfront.log
R=$(grep -m1 '^RESULT ' /work/logs/hwfront-out.log | sed 's/^RESULT //'); [ -z "$R" ] && R='{"game":"hedgewars","winner":null,"ok":false,"error":"frontend produced no result"}'
DIAG=$( { echo "== gpu"; cat /work/logs/gpu.log; echo "== X"; grep -E "^X (before|after)" /work/logs/game.log 2>/dev/null; echo "== where"; cat /work/logs/hw-where.log; echo "== help"; head -30 /work/logs/hw-help.log; echo "== engine log"; ls /work/hw/Logs 2>/dev/null; tail -30 /work/hw/Logs/game0.log 2>/dev/null; echo "== hw.log head"; head -40 /work/logs/hw.log; echo "== hw.log key"; grep -iE "error|fail|cannot|warn|opengl|renderer|team|win|stat" /work/logs/hw.log | tail -30; echo "== hw.log tail"; tail -20 /work/logs/hw.log; echo "== frontend"; tail -40 /work/logs/hwfront.log; } 2>/dev/null | cut -c1-220 | head -c 14000 )
echo "RESULT $(jq -cn --argjson r "$R" --arg diag "$DIAG" '$r + {diag:$diag}')"
