#!/usr/bin/env bash
# Ikemen GO (the fighter arena): AI vs AI, best of three, with the release's open-licensed Kung Fu Man characters
# (more characters/stages are fetched at runtime when IKEMEN_ASSETS is a tarball URL). The winner comes from the
# engine's own match statistics: a one-line patch of main.lua writes getGameStatsJson() right after the fight.
set -uo pipefail
export PATH="$PATH:/usr/games:/usr/local/games"
# an empty player list means "use the defaults"
[ -z "${PLAYERS:-}" ] || [ "${PLAYERS}" = "[]" ] && unset PLAYERS
mkdir -p /work/logs
{ echo "caps=${NVIDIA_DRIVER_CAPABILITIES:-} vgl=${VGL_DISPLAY:-} RUN=${RUN:-} display=${DISPLAY:-}"; nvidia-smi --query-gpu=name,memory.used --format=csv,noheader 2>/dev/null | head -1; } 2>&1 | head -c 600
echo
cd /opt/ikemen || { echo 'RESULT {"game":"ikemen","ok":false,"error":"engine missing"}'; exit 0; }
[ -x ./Ikemen_GO_Linux ] || { ls -la /opt/ikemen | head -5; echo 'RESULT {"game":"ikemen","ok":false,"error":"binary missing"}'; exit 0; }
[ -n "${IKEMEN_ASSETS:-}" ] && { curl -fsSL -m 120 "$IKEMEN_ASSETS" | tar -xz -C /opt/ikemen || echo "assets fetch failed"; }
# characters: the arena's PLAYERS [{name, char?}] pick p1/p2 by `char` when it exists on disk; otherwise the bundled KFM pair
pick() { python3 -c "
import json, os
p = json.loads(os.environ.get('PLAYERS') or '[]'); i = $1; d = '$2'
c = (p[i].get('char') if len(p) > i and isinstance(p[i], dict) else None) or ''
print(c if c and os.path.isdir('chars/' + c) else d)"; }
P1=$(pick 0 kfm); P2=$(pick 1 kfm720); [ -d "chars/$P2" ] || P2=kfm
STAGE=${IKEMEN_STAGE:-stage0}; [ -f "stages/$STAGE.def" ] || STAGE=$(ls stages/*.def | head -1 | xargs -n1 basename | sed 's/\.def$//')
# window: windowed at the capture size (defaults for everything else come from the embedded defaultConfig.ini)
mkdir -p save; printf '[Video]\nWindowWidth = %s\nWindowHeight = %s\nFullscreen = 0\nWindowCentered = 1\nVSync = 0\n' "${W:-960}" "${H:-540}" > save/config.ini
# the command-line match ends with game() then os.exit(): dump the statistics as JSON in between (idempotent patch)
grep -q 'ikemen-stats.json' external/script/main.lua || sed -i 's|^\tgame()$|\tgame()\n\tlocal __f = io.open("/work/logs/ikemen-stats.json", "w"); if __f then __f:write(getGameStatsJson()); __f:close() end|' external/script/main.lua
echo "stats hook lines: $(grep -c 'ikemen-stats.json' external/script/main.lua) · chars: $(ls chars | tr '\n' ' ')"
echo "fight: $P1 (ai ${AI1:-8}) vs $P2 (ai ${AI2:-8}) on $STAGE, best of ${ROUNDS:-3}, ${W:-960}x${H:-540}"
timeout "${IKEMEN_TIMEOUT:-600}" $RUN ./Ikemen_GO_Linux -p1 "$P1" -p2 "$P2" -p1.ai "${AI1:-8}" -p2.ai "${AI2:-8}" -p1.color 1 -p2.color 2 -rounds "${ROUNDS:-3}" -s "$STAGE" -windowed -nosound -nojoy -log /work/logs/ikemen-match.log > /work/logs/ikemen.log 2>&1
echo "engine exit $?"
echo "--- ikemen.log tail"; tail -c 2500 /work/logs/ikemen.log; echo
[ -f /work/logs/ikemen-stats.json ] && { echo "--- stats"; head -c 1500 /work/logs/ikemen-stats.json; echo; }
python3 - "$P1" "$P2" <<'PY'
import json, re, sys
p1, p2 = sys.argv[1], sys.argv[2]
res = {'game': 'ikemen', 'ok': False, 'p1': p1, 'p2': p2}
side = lambda v: 'p1' if v == 0 else 'p2' if v == 1 else 'draw'
try:
    d = json.load(open('/work/logs/ikemen-stats.json')); m = (d.get('matches') or [])[-1]
    w = m.get('wins') or [0, 0]; ws = m.get('winSide')
    winner = 'draw' if w[0] == w[1] else side(ws if ws in (0, 1) else (0 if w[0] > w[1] else 1))
    rounds = [side(r.get('winSide', r.get('winner', -1))) for r in (m.get('rounds') or [])]
    res.update(ok=True, winner=winner, wins=w, draws=m.get('draws', 0), rounds=rounds, lastRound=m.get('lastRound'), matchTime=m.get('matchTime'))
except Exception as e:
    try:   # fallback: the -log table dump
        t = open('/work/logs/ikemen-match.log').read()
        ws = re.search(r'winside"?\]?\s*=>\s*(\d+)', t, re.I)
        if ws: res.update(ok=True, winner=side(int(ws.group(1))), source='log')
        else: res['error'] = 'no stats: ' + str(e)[:80]
    except Exception as e2: res['error'] = 'no stats: ' + str(e)[:50] + ' / ' + str(e2)[:30]
print('RESULT ' + json.dumps(res))
PY
