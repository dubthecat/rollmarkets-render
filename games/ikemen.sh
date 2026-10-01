#!/usr/bin/env bash
# AI vs AI, best of three, with whatever open-licensed characters the image carries (IKEMEN_ASSETS tarball URL).
set -uo pipefail
export PATH="$PATH:/usr/games:/usr/local/games"
# an empty player list means "use the defaults"
[ -z "${PLAYERS:-}" ] || [ "${PLAYERS}" = "[]" ] && unset PLAYERS
# GPU diagnostics once per run
{ echo "caps=${NVIDIA_DRIVER_CAPABILITIES:-} vgl=${VGL_DISPLAY:-} RUN=${RUN:-}"; ls /dev/nvidia* 2>/dev/null | tr '\n' ' '; echo; ls /usr/lib/x86_64-linux-gnu/libnvidia-egl* /usr/share/glvnd/egl_vendor.d/ 2>/dev/null | tr '\n' ' '; echo; cat /work/logs/glx.log 2>/dev/null | head -5; } >/work/logs/gpu.log 2>&1
cd /opt/ikemen || { echo "RESULT {\"game\":\"ikemen\",\"ok\":false,\"error\":\"engine missing\"}"; exit 0; }
[ -n "${IKEMEN_ASSETS:-}" ] && curl -fsSL "$IKEMEN_ASSETS" | tar -xz -C /opt/ikemen || true
timeout 600 $RUN ./Ikemen_GO -p1.ai 8 -p2.ai 8 -rounds 3 -nosound 2>&1 | tee /work/logs/ikemen.log | tail -20
echo "RESULT {\"game\":\"ikemen\",\"ok\":false,\"error\":\"result parsing pending\"}"
